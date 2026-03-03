local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Knit = require(game:GetService("ReplicatedStorage").Packages.Knit)
local Enums = require(game:GetService("ReplicatedStorage").Utilities.Enums)

local ProfileStoreModule = require(script.ProfileStore)
local PlayerProfileClass = require(script.PlayerProfile)
local ReplicaService = require(script.ReplicaService)
local Config = require(script.Config)

local DataStoreService = Knit.CreateService {
	Name = "DataStoreService",
	Client = {},
}

local ProfileTemplate = require(game.ServerStorage.Data.Data_Player)
local ClassToken = ReplicaService.NewClassToken("PlayerProfile")

local PlayerStore = ProfileStoreModule.New("PlayerData", ProfileTemplate)

if RunService:IsStudio() then
	PlayerStore = PlayerStore.Mock
end

local Profiles = PlayerProfileClass.PlayerProfiles
local PlayerProfile = PlayerProfileClass.PlayerProfile

----- Private Functions -----

-- Retry parameters
local MAX_LOAD_TIME = Config.MaxLoadTimeSeconds -- seconds to wait before giving up
local INITIAL_RETRY_DELAY = Config.InitialRetryDelaySeconds -- base delay
local MAX_RETRY_DELAY = Config.MaxRetryDelaySeconds -- cap delay growth

-- Save retry parameters
local MAX_WRITE_RETRIES = Config.MaxWriteRetries
local WRITE_RETRY_BASE_DELAY = Config.WriteRetryBaseDelaySeconds -- seconds
local WRITE_RETRY_MAX_DELAY = Config.WriteRetryMaxDelaySeconds
local WRITE_DEBOUNCE_DELAY = Config.WriteDebounceDelaySeconds -- seconds to coalesce profile commits
local WRITE_IDLE_POLL_INTERVAL = Config.WriteIdlePollIntervalSeconds

local AUTO_SAVE_INTERVAL_MIN = Config.AutoSaveIntervalMinSeconds
local AUTO_SAVE_INTERVAL_MAX = Config.AutoSaveIntervalMaxSeconds
local SHUTDOWN_SAVE_TIMEOUT = Config.ShutdownSaveTimeoutSeconds
local SESSION_LOCK_TIMEOUT = Config.SessionLockTimeoutSeconds
local DEBUG_REPLICA_LOGS = Config.DebugReplicaLogs

local SessionLocks = {} -- [userId] = true when a session is active on this server
local AutoSaveTokens = {} -- [player] = token controlling the autosave loop
local ShuttingDown = false
local PendingCommits = {} -- [playerProfile] = {deadline = os.clock(), context = context}
local WriteStates = {} -- [playerProfile] = {pending = false, writing = false, context = SaveContext.ManualUpdate}
local DirtyCommitThrottle = {} -- [playerProfile] = nextAllowedCommitAt

local SaveContext = Enums.SaveContext

local function isProfileDirty(playerProfile)
	return playerProfile ~= nil and playerProfile._dirty == true
end

local function markProfileDirty(playerProfile)
	if playerProfile ~= nil then
		playerProfile._dirty = true
	end
end

local function tryClearProfileDirty(playerProfile, state)
	if playerProfile == nil then
		return
	end

	local resolvedState = state or WriteStates[playerProfile]
	if resolvedState then
		if resolvedState.pending then
			return
		end
		if resolvedState.writing then
			return
		end
	end

	if PendingCommits[playerProfile] ~= nil then
		return
	end

	playerProfile._dirty = false
end

local function retryWrite(actionName, callback, deadline)
	local attempt = 0
	local delay = WRITE_RETRY_BASE_DELAY
	local lastError
	local startTime = os.clock()

	while attempt < MAX_WRITE_RETRIES do
		if deadline and os.clock() >= deadline then
			break
		end
		attempt += 1
		local success, result = pcall(callback)
		if success then
			return true, result
		end

		lastError = result

		if attempt < MAX_WRITE_RETRIES then
			warn(string.format("[DataStoreService] %s failed (attempt %d/%d): %s", actionName, attempt, MAX_WRITE_RETRIES, tostring(result)))
			if deadline and os.clock() >= deadline then
				break
			end

			local waitTime = math.random() * delay
			if deadline then
				local timeLeft = deadline - os.clock()
				if timeLeft <= 0 then
					break
				end
				waitTime = math.min(waitTime, timeLeft)
			end

			task.wait(waitTime)
			delay = math.min(delay * 2, WRITE_RETRY_MAX_DELAY)
		end
	end

	if deadline and os.clock() >= deadline then
		lastError = lastError or string.format("Timed out after %.2f seconds", math.max(0, os.clock() - startTime))
	end

	warn(string.format("[DataStoreService] %s failed after %d attempts: %s", actionName, MAX_WRITE_RETRIES, tostring(lastError)))
	return false, lastError
end

local function commitUpdateAsync(playerProfile, context)
	local profile = playerProfile and playerProfile.Profile
	if profile == nil or profile:IsActive() ~= true then
		return false
	end

	local success = retryWrite("ProfileSave", function()
		profile:Save()
		return true
	end)
	if not success then
		warn(string.format("[DataStoreService] Profile save failed (%s)", context or "Unknown"))
	end
	return success
end

local function commitSetAsync(playerProfile, context, deadline)
	local profile = playerProfile and playerProfile.Profile
	if profile == nil or profile:IsActive() ~= true then
		return false
	end

	local success = retryWrite("ProfileSave", function()
		profile:Save()
		return true
	end, deadline)
	if not success then
		warn(string.format("[DataStoreService] Profile save failed (%s)", context or "Unknown"))
	end
	return success
end

local function waitForWriteIdle(playerProfile, deadline)
	local state = WriteStates[playerProfile]
	while state ~= nil and state.writing do
		if deadline and os.clock() >= deadline then
			return false
		end
		task.wait(WRITE_IDLE_POLL_INTERVAL)
		state = WriteStates[playerProfile]
	end
	return true
end

local function clearWriteState(playerProfile)
	local state = WriteStates[playerProfile]
	if state ~= nil then
		state.cancelled = true
		state.pending = false
		state.writing = false
	end
	WriteStates[playerProfile] = nil
	PendingCommits[playerProfile] = nil
	DirtyCommitThrottle[playerProfile] = nil
end

local function runWriteLoop(playerProfile, state)
	while true do
		if state.cancelled then
			state.writing = false
			WriteStates[playerProfile] = nil
			return
		end
		state.pending = false

		local profile = playerProfile.Profile
		if profile == nil or profile:IsActive() ~= true then
			state.writing = false
			WriteStates[playerProfile] = nil
			return
		end

		local context = state.context or SaveContext.ManualUpdate
		local success = commitUpdateAsync(playerProfile, context)
		if not success then
			task.wait(WRITE_RETRY_BASE_DELAY)
		else
			tryClearProfileDirty(playerProfile, state)
		end

		if not state.pending then
			break
		end
	end

	state.writing = false
	if state.pending then
		state.writing = true
		task.spawn(runWriteLoop, playerProfile, state)
	else
		tryClearProfileDirty(playerProfile, state)
		WriteStates[playerProfile] = nil
	end
end

local function scheduleWrite(playerProfile, context)
	local state = WriteStates[playerProfile]
	if state == nil then
		state = {
			pending = false,
			writing = false,
			context = context or SaveContext.ManualUpdate,
			cancelled = false,
			lastLogTime = 0,
		}
		WriteStates[playerProfile] = state
	elseif context ~= nil then
		state.context = context
	end

	if state.context == nil then
		state.context = SaveContext.ManualUpdate
	end

	state.pending = true

	if not state.writing then
		state.writing = true
		task.spawn(runWriteLoop, playerProfile, state)
	else
		local now = os.clock()
		if now - (state.lastLogTime or 0) >= 30 then
			state.lastLogTime = now
			local profile = playerProfile.Profile
			local key = profile and profile.Key or "[unknown]"
			warn(string.format("[DataStoreService] Coalescing commit for key %s (%s)", tostring(key), tostring(state.context)))
		end
	end

	return true
end

local function queueCommit(playerProfile, context)
	if playerProfile == nil then
		return false
	end

	local profile = playerProfile.Profile
	if profile == nil or profile:IsActive() ~= true then
		return false
	end

	markProfileDirty(playerProfile)

	local now = os.clock()
	local entry = PendingCommits[playerProfile]
	if entry == nil then
		entry = {
			deadline = now + WRITE_DEBOUNCE_DELAY,
			context = context or SaveContext.ManualUpdate,
		}
		PendingCommits[playerProfile] = entry

		task.spawn(function()
			while PendingCommits[playerProfile] == entry do
				local waitTime = entry.deadline - os.clock()
				if waitTime <= 0 then
					break
				end
				task.wait(waitTime)
			end

			if PendingCommits[playerProfile] ~= entry then
				return
			end

			PendingCommits[playerProfile] = nil
			scheduleWrite(playerProfile, entry.context)
		end)
	else
		entry.deadline = now + WRITE_DEBOUNCE_DELAY
		entry.context = context or entry.context
	end

	return true
end

local function flushPendingCommit(playerProfile, context)
	local entry = PendingCommits[playerProfile]
	if entry == nil then
		return false
	end

	PendingCommits[playerProfile] = nil
	scheduleWrite(playerProfile, context or entry.context)
	return true
end

local function stopAutoSave(player)
	AutoSaveTokens[player] = nil
end

local function startAutoSave(player)
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

			if not flushPendingCommit(currentProfile, SaveContext.AutoSave) then
				scheduleWrite(currentProfile, SaveContext.AutoSave)
			end
            
		end
	end)
end

local function clearSessionLock(player)
	SessionLocks[player.UserId] = nil
end

local function saveProfileForPlayer(player, useSet, context)
	local playerProfile = Profiles[player]
	if playerProfile == nil then
		return false
	end

	if useSet == true then
		flushPendingCommit(playerProfile, context)
		waitForWriteIdle(playerProfile, os.clock() + WRITE_RETRY_MAX_DELAY)
		local success = commitSetAsync(playerProfile, context)
		if success then
			tryClearProfileDirty(playerProfile, nil)
		end
		return success
	else
		return queueCommit(playerProfile, context)
	end
end

local function startSessionWithRetry(player)
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
		task.wait(math.random() * maxDelay) -- full jitter
	end

	return nil
end

local function PlayerAdded(player)
	if ShuttingDown then
		if player:IsDescendantOf(Players) == true then
			player:Kick()
		end
		return
	end

	-- Prevent concurrent sessions for the same userId inside this server.
	local lockWaitStart = os.clock()
	while SessionLocks[player.UserId] ~= nil do
		if player:IsDescendantOf(Players) == false then
			return
		end
		if os.clock() - lockWaitStart >= SESSION_LOCK_TIMEOUT then
			warn(string.format(
				"[DataStoreService] Session lock timeout for %s (UserId %d)",
				player.Name,
				player.UserId
			))
			if player:IsDescendantOf(Players) == true then
				player:Kick("Session lock timeout - Please rejoin")
			end
			return
		end
		task.wait(0.1)
	end

	SessionLocks[player.UserId] = true

	local profile = startSessionWithRetry(player)
	if profile ~= nil then
		profile:AddUserId(player.UserId)
		profile:Reconcile()

		profile.OnSessionEnd:Connect(function()
			stopAutoSave(player)
			clearSessionLock(player)

			local playerProfile = Profiles[player]
			if playerProfile then
				flushPendingCommit(playerProfile, SaveContext.ManualUpdate)
				waitForWriteIdle(playerProfile, os.clock() + WRITE_RETRY_MAX_DELAY)
				playerProfile:Release()
				clearWriteState(playerProfile)
			end

			if player:IsDescendantOf(Players) == true then
				player:Kick("Profile session end - Please rejoin")
			end
		end)

		if player:IsDescendantOf(Players) == true then
			local replica = ReplicaService.NewReplica({
				ClassToken = ClassToken,
				Tags = { Player = player },
				Data = profile.Data,
				Replication = "All",
			})

			if DEBUG_REPLICA_LOGS then
				print("[DataStoreService] Replica data for", player.Name, replica.Data)
			end

			-- PlayerProfile.new is expected to populate Profiles[player] internally (same as your original).
			PlayerProfile.new(profile, player, replica)
			startAutoSave(player)
		else
			profile:EndSession()
			clearSessionLock(player)
		end
	else
		clearSessionLock(player)
		if player:IsDescendantOf(Players) == true then
			player:Kick("Profile load fail - Please rejoin")
		end
	end
end

local function PlayerRemoving(player)
	stopAutoSave(player)

	local playerProfile = Profiles[player]
	if playerProfile ~= nil then
		flushPendingCommit(playerProfile, SaveContext.ManualUpdate)
		waitForWriteIdle(playerProfile, os.clock() + WRITE_RETRY_MAX_DELAY)
		local profileSession = playerProfile.Profile
		if profileSession ~= nil and profileSession:IsActive() == true then
			profileSession:EndSession()
		else
			playerProfile:Release()
			clearWriteState(playerProfile)
		end
	end

	clearSessionLock(player)
end

local function shutdownSavePlayer(player, deadline)
	local playerProfile = Profiles[player]
	if playerProfile == nil then
		clearSessionLock(player)
		return true
	end

	if deadline and os.clock() >= deadline then
		warn(string.format("[DataStoreService] Shutdown timeout reached before saving %s", player.Name))
		local profileSession = playerProfile.Profile
		if profileSession ~= nil and profileSession:IsActive() == true then
			profileSession:EndSession()
		else
			playerProfile:Release()
		end
		clearSessionLock(player)
		return false
	end

	flushPendingCommit(playerProfile, SaveContext.Shutdown)
	waitForWriteIdle(playerProfile, deadline)
	local success = commitSetAsync(playerProfile, SaveContext.Shutdown, deadline)
	local profileSession = playerProfile.Profile
	if profileSession ~= nil and profileSession:IsActive() == true then
		profileSession:EndSession()
	else
		playerProfile:Release()
	end

	clearWriteState(playerProfile)
	clearSessionLock(player)
	return success
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
			if deadline and os.clock() >= deadline then
				break
			end
			local success = shutdownSavePlayer(player, deadline)
			if not success and deadline and os.clock() >= deadline then
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

----- Public API (Server) -----

function DataStoreService:GetProfileAsync(player, timeoutSeconds)
	local profile = Profiles[player]
	if profile ~= nil then
		return profile
	end

	local waitSeconds = timeoutSeconds
	if typeof(waitSeconds) ~= "number" or waitSeconds <= 0 then
		waitSeconds = MAX_LOAD_TIME
	end

	local deadline = os.clock() + waitSeconds

	while profile == nil and player:IsDescendantOf(Players) == true do
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

function DataStoreService:UpdateAsync(player, mutator, context)
	local playerProfile = Profiles[player]
	if playerProfile == nil then
		return false
	end

	if typeof(mutator) == "function" then
		mutator(playerProfile.Profile.Data, playerProfile.Replica)
	end

	return queueCommit(playerProfile, context or SaveContext.ManualUpdate)
end

function DataStoreService:MarkDirty(player, context)
	local playerProfile = Profiles[player]
	if playerProfile == nil then
		return false
	end

	return queueCommit(playerProfile, context or SaveContext.ManualUpdate)
end

function DataStoreService:MarkDirtyThrottled(player, context, minIntervalSeconds)
	local playerProfile = Profiles[player]
	if playerProfile == nil then
		return false
	end

	local resolvedContext = context or SaveContext.ManualUpdate
	local intervalSeconds = tonumber(minIntervalSeconds) or 0
	if intervalSeconds <= 0 then
		return queueCommit(playerProfile, resolvedContext)
	end

	markProfileDirty(playerProfile)

	local now = os.clock()
	local nextAllowed = tonumber(DirtyCommitThrottle[playerProfile]) or 0
	if now < nextAllowed then
		return true
	end

	DirtyCommitThrottle[playerProfile] = now + intervalSeconds
	return queueCommit(playerProfile, resolvedContext)
end

function DataStoreService:SetAsync(player, context)
	return saveProfileForPlayer(player, true, context or SaveContext.ManualSet)
end

----- Knit Lifecycle -----

function DataStoreService:KnitInit()
	print("DataStoreService Init")
	bindToClose()
end

function DataStoreService:KnitStart()
	print("DataStoreService Started")

	-- In case Players joined before Knit started:
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(PlayerAdded, player)
	end

	Players.PlayerAdded:Connect(PlayerAdded)
	Players.PlayerRemoving:Connect(PlayerRemoving)
end

return DataStoreService
