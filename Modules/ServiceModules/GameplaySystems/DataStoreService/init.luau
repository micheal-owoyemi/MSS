local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Enums = require(ReplicatedStorage.Utilities.Enums)
local ProfileSchema = require(ReplicatedStorage.Types.ProfileSchema)

local ProfileStoreModule = require(script.ProfileStore)
local PlayerProfileClass = require(script.PlayerProfile)
local ReplicaService = require(script.ReplicaService)
local Config = require(script.Config)
local ServiceModules = ServerStorage:WaitForChild("ServiceModules")
local SupportersFolder = ServiceModules:WaitForChild("Supporters")
local DataStoreAdapter = require(SupportersFolder:WaitForChild("DataStoreAdapter"))

local DataStoreService = Knit.CreateService {
	Name = "DataStoreService",
	Client = {},
}

local ProfileTemplate = ProfileSchema.getTemplate()
local ClassToken = ReplicaService.NewClassToken("PlayerProfile")

local PlayerStore = ProfileStoreModule.New("PlayerData", ProfileTemplate)
if RunService:IsStudio() then
	PlayerStore = PlayerStore.Mock
end

local Profiles = PlayerProfileClass.PlayerProfiles
local PlayerProfile = PlayerProfileClass.PlayerProfile

local MAX_LOAD_TIME = Config.MaxLoadTimeSeconds
local INITIAL_RETRY_DELAY = Config.InitialRetryDelaySeconds
local MAX_RETRY_DELAY = Config.MaxRetryDelaySeconds
local AUTO_SAVE_INTERVAL_MIN = Config.AutoSaveIntervalMinSeconds
local AUTO_SAVE_INTERVAL_MAX = Config.AutoSaveIntervalMaxSeconds
local SHUTDOWN_SAVE_TIMEOUT = Config.ShutdownSaveTimeoutSeconds
local SESSION_LOCK_TIMEOUT = Config.SessionLockTimeoutSeconds
local WRITE_RETRY_MAX_DELAY = Config.WriteRetryMaxDelaySeconds
local DEBUG_REPLICA_LOGS = Config.DebugReplicaLogs

local SaveContext = Enums.SaveContext

local SessionLocks = {} -- [userId] = true when a session is active on this server
local AutoSaveTokens = {} -- [player] = token controlling autosave loop
local PlayerJanitors = {} -- [player] = Janitor
local DirtyCommitThrottle = {} -- [userId] = nextAllowedCommitAt

local ServiceJanitor = Janitor.new()
local StoreAdapter = DataStoreAdapter.new(Config)

local ShuttingDown = false

local function clearSessionLock(player: Player)
	SessionLocks[player.UserId] = nil
end

local function stopAutoSave(player: Player)
	AutoSaveTokens[player] = nil
end

local function getPlayerJanitor(player: Player)
	local janitor = PlayerJanitors[player]
	if janitor ~= nil then
		return janitor
	end

	janitor = Janitor.new()
	PlayerJanitors[player] = janitor

	janitor:Add(function()
		stopAutoSave(player)
		clearSessionLock(player)
		StoreAdapter:UnregisterProfile(player.UserId)
		DirtyCommitThrottle[player.UserId] = nil
	end, true, "PlayerSessionCleanup")

	return janitor
end

local function cleanupPlayerJanitor(player: Player)
	local janitor = PlayerJanitors[player]
	if janitor == nil then
		return
	end

	janitor:Cleanup()
	PlayerJanitors[player] = nil
end

local function validateAndMigrateProfileData(profile, player: Player)
	local migratedData, migrationsApplied = ProfileSchema.migrateInPlace(profile.Data, os.time())
	local isValid, reason = ProfileSchema.validate(migratedData)
	if not isValid then
		warn(string.format("[DataStoreService] Invalid profile data for %s: %s. Replacing with defaults.", player.Name, tostring(reason)))
		migratedData = ProfileSchema.createDefault(os.time())
	elseif migrationsApplied > 0 then
		warn(string.format("[DataStoreService] Applied %d schema migration(s) for %s.", migrationsApplied, player.Name))
	end
	profile.Data = migratedData
end

local function isProfileDirty(playerProfile)
	return playerProfile ~= nil and playerProfile._dirty == true
end

local function markProfileDirty(playerProfile)
	if playerProfile ~= nil then
		playerProfile._dirty = true
	end
end

local function clearProfileDirty(playerProfile)
	if playerProfile ~= nil then
		playerProfile._dirty = false
	end
end

local function queueCommit(player: Player, context: string): boolean
	local playerProfile = Profiles[player]
	if playerProfile == nil then
		return false
	end

	markProfileDirty(playerProfile)

	local ok, err = StoreAdapter:QueueSave(player.UserId, context)
	if not ok and err ~= nil then
		warn(string.format("[DataStoreService] QueueSave failed for %s (%s): %s", player.Name, context, tostring(err)))
	end

	return ok
end

local function flushCommit(player: Player, context: string, deadline: number?): boolean
	local playerProfile = Profiles[player]
	if playerProfile == nil then
		return false
	end

	local ok, err = StoreAdapter:FlushSave(player.UserId, context, deadline)
	if ok then
		clearProfileDirty(playerProfile)
		return true
	end

	warn(string.format("[DataStoreService] FlushSave failed for %s (%s): %s", player.Name, context, tostring(err)))
	return false
end

local function waitForWriteIdle(player: Player, deadline: number?): boolean
	return StoreAdapter:WaitForIdle(player.UserId, deadline)
end

local function startAutoSave(player: Player)
	local token = {}
	AutoSaveTokens[player] = token

	task.spawn(function()
		while AutoSaveTokens[player] == token and player:IsDescendantOf(Players) do
			local waitSeconds = math.random(AUTO_SAVE_INTERVAL_MIN, AUTO_SAVE_INTERVAL_MAX)
			task.wait(waitSeconds)

			if AutoSaveTokens[player] ~= token then
				break
			end

			local currentProfile = Profiles[player]
			if currentProfile == nil then
				break
			end

			if not isProfileDirty(currentProfile) then
				continue
			end

			queueCommit(player, SaveContext.AutoSave)
		end
	end)
end

local function startSessionWithRetry(player: Player)
	if ShuttingDown then
		return nil
	end

	local startTime = os.clock()
	local attempt = 0
	local sessionKey = "Player_" .. player.UserId

	while player:IsDescendantOf(Players) and ShuttingDown == false do
		local profile = PlayerStore:StartSessionAsync(sessionKey, {
			Cancel = function()
				return ShuttingDown or player:IsDescendantOf(Players) == false
			end,
		})
		if profile ~= nil then
			return profile
		end

		if os.clock() - startTime >= MAX_LOAD_TIME then
			return nil
		end

		attempt += 1
		local maxDelay = math.min(MAX_RETRY_DELAY, INITIAL_RETRY_DELAY * (2 ^ attempt))
		task.wait(math.random() * maxDelay)
	end

	return nil
end

local function releasePlayerProfile(player: Player)
	local playerProfile = Profiles[player]
	if playerProfile ~= nil then
		playerProfile:Release()
	end

	StoreAdapter:UnregisterProfile(player.UserId)
	clearSessionLock(player)
	cleanupPlayerJanitor(player)
end

local function PlayerAdded(player: Player)
	if ShuttingDown then
		if player:IsDescendantOf(Players) then
			player:Kick()
		end
		return
	end

	local lockWaitStart = os.clock()
	while SessionLocks[player.UserId] ~= nil do
		if player:IsDescendantOf(Players) == false then
			return
		end
		if os.clock() - lockWaitStart >= SESSION_LOCK_TIMEOUT then
			warn(string.format("[DataStoreService] Session lock timeout for %s (UserId %d)", player.Name, player.UserId))
			if player:IsDescendantOf(Players) then
				player:Kick("Session lock timeout - Please rejoin")
			end
			return
		end
		task.wait(0.1)
	end

	SessionLocks[player.UserId] = true

	local profile = startSessionWithRetry(player)
	if profile == nil then
		clearSessionLock(player)
		cleanupPlayerJanitor(player)
		if player:IsDescendantOf(Players) then
			player:Kick("Profile load fail - Please rejoin")
		end
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	validateAndMigrateProfileData(profile, player)

	local playerJanitor = getPlayerJanitor(player)
	playerJanitor:Add(profile.OnSessionEnd:Connect(function()
		stopAutoSave(player)
		releasePlayerProfile(player)
		if player:IsDescendantOf(Players) then
			player:Kick("Profile session end - Please rejoin")
		end
	end), "Disconnect", "ProfileSessionEndConnection")

	if player:IsDescendantOf(Players) == false then
		profile:EndSession()
		releasePlayerProfile(player)
		return
	end

	local replica = ReplicaService.NewReplica({
		ClassToken = ClassToken,
		Tags = { Player = player },
		Data = profile.Data,
		Replication = player,
	})

	if DEBUG_REPLICA_LOGS then
		print("[DataStoreService] Replica data for", player.Name, replica.Data)
	end

	PlayerProfile.new(profile, player, replica)
	StoreAdapter:RegisterProfile(player.UserId, profile)
	startAutoSave(player)
end

local function PlayerRemoving(player: Player)
	stopAutoSave(player)

	local playerProfile = Profiles[player]
	if playerProfile ~= nil then
		flushCommit(player, SaveContext.ManualUpdate, os.clock() + WRITE_RETRY_MAX_DELAY)
		waitForWriteIdle(player, os.clock() + WRITE_RETRY_MAX_DELAY)

		local profileSession = playerProfile.Profile
		if profileSession ~= nil and profileSession:IsActive() then
			profileSession:EndSession()
		else
			releasePlayerProfile(player)
		end
	else
		releasePlayerProfile(player)
	end
end

local function shutdownSavePlayer(player: Player, deadline: number): boolean
	local playerProfile = Profiles[player]
	if playerProfile == nil then
		releasePlayerProfile(player)
		return true
	end

	if os.clock() >= deadline then
		warn(string.format("[DataStoreService] Shutdown timeout reached before saving %s", player.Name))
		local profileSession = playerProfile.Profile
		if profileSession ~= nil and profileSession:IsActive() then
			profileSession:EndSession()
		else
			releasePlayerProfile(player)
		end
		return false
	end

	flushCommit(player, SaveContext.Shutdown, deadline)
	waitForWriteIdle(player, deadline)

	local profileSession = playerProfile.Profile
	if profileSession ~= nil and profileSession:IsActive() then
		profileSession:EndSession()
	else
		releasePlayerProfile(player)
	end

	return true
end

local function bindToClose()
	game:BindToClose(function()
		if RunService:IsStudio() then
			return
		end

		ShuttingDown = true
		local deadline = os.clock() + SHUTDOWN_SAVE_TIMEOUT
		local players = Players:GetPlayers()

		for _, player in ipairs(players) do
			stopAutoSave(player)
		end

		for _, player in ipairs(players) do
			if os.clock() >= deadline then
				break
			end
			local success = shutdownSavePlayer(player, deadline)
			if not success and os.clock() >= deadline then
				break
			end
		end

		if table.clear then
			table.clear(SessionLocks)
		else
			for userId in pairs(SessionLocks) do
				SessionLocks[userId] = nil
			end
		end
	end)
end

function DataStoreService:GetProfileAsync(player: Player, timeoutSeconds: number?)
	local profile = Profiles[player]
	if profile ~= nil then
		return profile
	end

	local waitSeconds = timeoutSeconds
	if typeof(waitSeconds) ~= "number" or waitSeconds <= 0 then
		waitSeconds = MAX_LOAD_TIME
	end

	local deadline = os.clock() + waitSeconds
	while profile == nil and player:IsDescendantOf(Players) do
		if os.clock() >= deadline then
			return nil, "ProfileLoadTimeout"
		end
		task.wait()
		profile = Profiles[player]
	end

	if profile == nil then
		return nil, "ProfileUnavailable"
	end

	return profile
end

function DataStoreService:UpdateAsync(player: Player, mutator, context: string?)
	local playerProfile = Profiles[player]
	if playerProfile == nil then
		return false
	end

	if typeof(mutator) == "function" then
		local ok, err = pcall(mutator, playerProfile.Profile.Data, playerProfile.Replica)
		if not ok then
			warn(string.format("[DataStoreService] UpdateAsync mutator failed for %s: %s", player.Name, tostring(err)))
			return false
		end
	end

	return queueCommit(player, context or SaveContext.ManualUpdate)
end

function DataStoreService:MarkDirty(player: Player, context: string?)
	return queueCommit(player, context or SaveContext.ManualUpdate)
end

function DataStoreService:MarkDirtyThrottled(player: Player, context: string?, minIntervalSeconds: number?)
	local playerProfile = Profiles[player]
	if playerProfile == nil then
		return false
	end

	local resolvedContext = context or SaveContext.ManualUpdate
	local intervalSeconds = tonumber(minIntervalSeconds) or 0
	if intervalSeconds <= 0 then
		return queueCommit(player, resolvedContext)
	end

	markProfileDirty(playerProfile)

	local now = os.clock()
	local nextAllowed = tonumber(DirtyCommitThrottle[player.UserId]) or 0
	if now < nextAllowed then
		return true
	end

	DirtyCommitThrottle[player.UserId] = now + intervalSeconds
	return queueCommit(player, resolvedContext)
end

function DataStoreService:SetAsync(player: Player, context: string?)
	return flushCommit(player, context or SaveContext.ManualSet, os.clock() + WRITE_RETRY_MAX_DELAY)
end

function DataStoreService:KnitInit()
	print("DataStoreService Init")
	bindToClose()
end

function DataStoreService:KnitStart()
	print("DataStoreService Started")

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(PlayerAdded, player)
	end

	ServiceJanitor:Add(Players.PlayerAdded:Connect(PlayerAdded), "Disconnect", "PlayerAddedConnection")
	ServiceJanitor:Add(Players.PlayerRemoving:Connect(PlayerRemoving), "Disconnect", "PlayerRemovingConnection")
end

function DataStoreService:Destroy()
	ServiceJanitor:Cleanup()
	for player in pairs(PlayerJanitors) do
		cleanupPlayerJanitor(player)
	end
	StoreAdapter:Destroy()
end

return DataStoreService
