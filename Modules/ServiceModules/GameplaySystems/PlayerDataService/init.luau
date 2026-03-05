--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local TableUtil = require(ReplicatedStorage.Util.TableUtil)
local ValidationUtil = require(ReplicatedStorage.Util.ValidationUtil)
local ProfileSchema = require(ReplicatedStorage.Types.ProfileSchema)
local ProfileTypes = require(ReplicatedStorage.Types.ProfileTypes)

local Config = require(script.Config)
local SnapshotBuilder = require(script.SnapshotBuilder)

local ServiceModules = ServerStorage:WaitForChild("ServiceModules")
local SupportersFolder = ServiceModules:WaitForChild("Supporters")
local RateLimiter = require(SupportersFolder:WaitForChild("RateLimiter"))

type ProfileData = ProfileTypes.ProfileData
type PlayerProfileLike = ProfileTypes.PlayerProfileLike
type ProfileResolveReason = ProfileTypes.ProfileResolveReason

type DataStoreServiceLike = {
	GetProfileAsync: (self: DataStoreServiceLike, player: Player, timeoutSeconds: number?) -> (PlayerProfileLike?, ProfileResolveReason?),
	UpdateAsync: (self: DataStoreServiceLike, player: Player, mutator: (data: ProfileData, replica: any?) -> (), context: string?) -> boolean,
	SetAsync: (self: DataStoreServiceLike, player: Player, context: string?) -> boolean,
}

type CachedProfileRecord = {
	Player: Player,
	UserId: number,
	PlayerProfile: PlayerProfileLike,
	Data: ProfileData,
	Revision: number,
	SnapshotDirty: boolean,
	CachedSnapshot: {[string]: any}?,
	ReadOnlyDirty: boolean,
	ReadOnlyProfile: ProfileData?,
	Janitor: any,
}

local PlayerDataService = Knit.CreateService({
	Name = "PlayerDataService",
	Client = {},
})

function PlayerDataService.Client:RequestSnapshot(player: Player)
	return self.Server:_requestSnapshotInternal(player, true)
end

function PlayerDataService:KnitInit()
	self._config = Config
	self._dataStoreService = nil :: DataStoreServiceLike?
	self._serviceJanitor = Janitor.new()
	self._snapshotRateLimiter = RateLimiter.new()

	self._recordsByUserId = {} :: {[number]: CachedProfileRecord}
	self._recordsByPlayer = {} :: {[Player]: CachedProfileRecord}
	self._pendingLoadByUserId = {} :: {[number]: boolean}
	self._mutationLocksByUserId = {} :: {[number]: boolean}
end

function PlayerDataService:KnitStart()
	self._dataStoreService = Knit.GetService("DataStoreService") :: DataStoreServiceLike

	self._serviceJanitor:Add(Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			local record, reason = self:_resolveRecord(player, self._config.ProfileLoadTimeoutSeconds)
			if record == nil and player:IsDescendantOf(Players) then
				warn(string.format("[PlayerDataService] Failed to prime profile for %s: %s", player.Name, tostring(reason)))
			end
		end)
	end), "Disconnect", "PlayerAddedConnection")

	self._serviceJanitor:Add(Players.PlayerRemoving:Connect(function(player: Player)
		self:_releaseRecord(player)
	end), "Disconnect", "PlayerRemovingConnection")

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			local record, reason = self:_resolveRecord(player, self._config.ProfileLoadTimeoutSeconds)
			if record == nil and player:IsDescendantOf(Players) then
				warn(string.format("[PlayerDataService] Failed to warm existing player profile for %s: %s", player.Name, tostring(reason)))
			end
		end)
	end
end

local function copyInto(target: {[any]: any}, source: {[any]: any})
	table.clear(target)
	for key, value in pairs(source) do
		target[key] = value
	end
end

function PlayerDataService:_isActiveRecord(record: CachedProfileRecord?): boolean
	if record == nil then
		return false
	end
	if not record.Player:IsDescendantOf(Players) then
		return false
	end

	local playerProfile = record.PlayerProfile
	local profileSession = playerProfile and playerProfile.Profile
	if profileSession == nil or typeof(profileSession.IsActive) ~= "function" then
		return false
	end

	if profileSession:IsActive() ~= true then
		return false
	end
	if typeof(profileSession.Data) ~= "table" then
		return false
	end

	return true
end

function PlayerDataService:_markRecordDirty(record: CachedProfileRecord)
	record.Revision += 1
	record.SnapshotDirty = true
	record.ReadOnlyDirty = true
end

function PlayerDataService:_syncRecordData(record: CachedProfileRecord)
	local playerProfile = record.PlayerProfile
	if playerProfile == nil then
		return
	end

	local profileSession = playerProfile.Profile
	if profileSession ~= nil and typeof(profileSession.Data) == "table" then
		record.Data = profileSession.Data :: ProfileData
	end
end

function PlayerDataService:_buildReadOnlyProfile(record: CachedProfileRecord): ProfileData
	local copy = TableUtil.deepCopy(record.Data)
	record.ReadOnlyProfile = TableUtil.deepFreeze(copy)
	record.ReadOnlyDirty = false
	return record.ReadOnlyProfile :: ProfileData
end

function PlayerDataService:_getReadOnlyProfile(record: CachedProfileRecord): ProfileData
	if record.ReadOnlyDirty or record.ReadOnlyProfile == nil then
		return self:_buildReadOnlyProfile(record)
	end

	return record.ReadOnlyProfile
end

function PlayerDataService:_buildSnapshot(record: CachedProfileRecord): {[string]: any}
	local snapshot = SnapshotBuilder.build(record.Data, record.Revision, os.time())
	record.CachedSnapshot = TableUtil.deepFreeze(snapshot)
	record.SnapshotDirty = false
	return record.CachedSnapshot :: {[string]: any}
end

function PlayerDataService:_getSnapshot(record: CachedProfileRecord): {[string]: any}
	if record.SnapshotDirty or record.CachedSnapshot == nil then
		return self:_buildSnapshot(record)
	end

	return record.CachedSnapshot
end

function PlayerDataService:_createRecord(player: Player, playerProfile: PlayerProfileLike): CachedProfileRecord?
	local profileSession = playerProfile.Profile
	if profileSession == nil or typeof(profileSession.Data) ~= "table" then
		return nil
	end

	local existing = self._recordsByUserId[player.UserId]
	if existing ~= nil then
		existing.Player = player
		existing.PlayerProfile = playerProfile
		existing.Data = profileSession.Data :: ProfileData
		existing.ReadOnlyDirty = true
		existing.SnapshotDirty = true
		self._recordsByPlayer[player] = existing
		return existing
	end

	local recordJanitor = Janitor.new()
	local newRecord: CachedProfileRecord = {
		Player = player,
		UserId = player.UserId,
		PlayerProfile = playerProfile,
		Data = profileSession.Data :: ProfileData,
		Revision = 1,
		SnapshotDirty = true,
		CachedSnapshot = nil,
		ReadOnlyDirty = true,
		ReadOnlyProfile = nil,
		Janitor = recordJanitor,
	}

	recordJanitor:Add(function()
		if self._recordsByUserId[player.UserId] == newRecord then
			self._recordsByUserId[player.UserId] = nil
		end
		if self._recordsByPlayer[player] == newRecord then
			self._recordsByPlayer[player] = nil
		end
		self._pendingLoadByUserId[player.UserId] = nil
		self._mutationLocksByUserId[player.UserId] = nil
	end)

	self._recordsByUserId[player.UserId] = newRecord
	self._recordsByPlayer[player] = newRecord
	return newRecord
end

function PlayerDataService:_releaseRecord(player: Player)
	local record = self._recordsByPlayer[player]
	if record == nil then
		self._pendingLoadByUserId[player.UserId] = nil
		self._mutationLocksByUserId[player.UserId] = nil
		return
	end

	record.Janitor:Cleanup()
end

function PlayerDataService:_waitForPendingLoad(userId: number, timeoutSeconds: number): boolean
	local deadline = os.clock() + timeoutSeconds
	while self._pendingLoadByUserId[userId] do
		if os.clock() >= deadline then
			return false
		end
		task.wait(self._config.PendingLoadPollIntervalSeconds)
	end
	return true
end

function PlayerDataService:_resolveRecord(player: Player, timeoutSeconds: number?): (CachedProfileRecord?, string?)
	if not ValidationUtil.isPlayer(player) then
		return nil, "InvalidPlayer"
	end

	local waitSeconds = timeoutSeconds
	if typeof(waitSeconds) ~= "number" or waitSeconds <= 0 then
		waitSeconds = self._config.ProfileLoadTimeoutSeconds
	end

	local userId = player.UserId
	local cached = self._recordsByUserId[userId]
	if self:_isActiveRecord(cached) then
		self:_syncRecordData(cached :: CachedProfileRecord)
		return cached, nil
	end

	if not self:_waitForPendingLoad(userId, waitSeconds) then
		return nil, "ProfileLoadTimeout"
	end

	cached = self._recordsByUserId[userId]
	if self:_isActiveRecord(cached) then
		self:_syncRecordData(cached :: CachedProfileRecord)
		return cached, nil
	end

	if player:IsDescendantOf(Players) == false then
		return nil, "ProfileUnavailable"
	end

	local dataStoreService = self._dataStoreService
	if dataStoreService == nil then
		return nil, "ServiceUnavailable"
	end

	self._pendingLoadByUserId[userId] = true
	local ok, playerProfileOrError, resolveReason = pcall(function()
		return dataStoreService:GetProfileAsync(player, waitSeconds)
	end)
	self._pendingLoadByUserId[userId] = nil

	if not ok then
		warn(string.format("[PlayerDataService] GetProfileAsync exception for %s (%d): %s", player.Name, userId, tostring(playerProfileOrError)))
		return nil, "ProfileUnavailable"
	end

	local playerProfile = playerProfileOrError :: PlayerProfileLike?
	if playerProfile == nil then
		return nil, (resolveReason :: string?) or "ProfileUnavailable"
	end

	local record = self:_createRecord(player, playerProfile)
	if record == nil then
		return nil, "ProfileUnavailable"
	end

	return record, nil
end

function PlayerDataService:_acquireMutationLock(userId: number): boolean
	local deadline = os.clock() + self._config.MutationLockTimeoutSeconds
	while self._mutationLocksByUserId[userId] do
		if os.clock() >= deadline then
			return false
		end
		task.wait(self._config.MutationLockPollIntervalSeconds)
	end

	self._mutationLocksByUserId[userId] = true
	return true
end

function PlayerDataService:_releaseMutationLock(userId: number)
	self._mutationLocksByUserId[userId] = nil
end

function PlayerDataService:GetProfile(player: Player): (ProfileData?, string?)
	local record, reason = self:_resolveRecord(player, self._config.ProfileLoadTimeoutSeconds)
	if record == nil then
		return nil, reason
	end

	self:_syncRecordData(record)
	return self:_getReadOnlyProfile(record), nil
end

function PlayerDataService:_requestSnapshotInternal(player: Player, enforceRateLimit: boolean): ({[string]: any}?, string?)
	if not ValidationUtil.isPlayer(player) then
		return nil, "InvalidPlayer"
	end

	if enforceRateLimit then
		local limiter = self._snapshotRateLimiter
		if limiter ~= nil and limiter:Consume(player, self._config.SnapshotActionName) == false then
			return nil, "RateLimited"
		end
	end

	local record, reason = self:_resolveRecord(player, self._config.ProfileLoadTimeoutSeconds)
	if record == nil then
		return nil, reason
	end

	self:_syncRecordData(record)
	return self:_getSnapshot(record), nil
end

function PlayerDataService:RequestSnapshot(player: Player): ({[string]: any}?, string?)
	return self:_requestSnapshotInternal(player, false)
end

function PlayerDataService:MutateProfile(player: Player, transformFn: (profileData: ProfileData, replica: any?) -> any, contextTag: string?): (boolean, string?)
	if not ValidationUtil.isPlayer(player) then
		return false, "InvalidPlayer"
	end

	if typeof(transformFn) ~= "function" then
		return false, "InvalidTransform"
	end

	local record, reason = self:_resolveRecord(player, self._config.ProfileLoadTimeoutSeconds)
	if record == nil then
		return false, reason
	end

	local userId = record.UserId
	if not self:_acquireMutationLock(userId) then
		return false, "MutationLockTimeout"
	end

	local mutationError: string? = nil
	local mutationContext = string.format("%s:%s", self._config.MutationContextPrefix, contextTag or "Unknown")

	local dataStoreService = self._dataStoreService
	if dataStoreService == nil then
		self:_releaseMutationLock(userId)
		return false, "ServiceUnavailable"
	end

	local success = dataStoreService:UpdateAsync(player, function(profileData: ProfileData, replica: any?)
		local rollbackCopy = TableUtil.deepCopy(profileData)

		local transformOk, transformResult = pcall(transformFn, profileData, replica)
		if not transformOk then
			copyInto(profileData :: {[any]: any}, rollbackCopy)
			mutationError = "TransformError"
			error(tostring(transformResult))
		end

		if transformResult ~= nil then
			if typeof(transformResult) ~= "table" then
				copyInto(profileData :: {[any]: any}, rollbackCopy)
				mutationError = "TransformReturnedNonTable"
				error("Transform must return nil or table")
			end
			if transformResult ~= profileData then
				copyInto(profileData :: {[any]: any}, transformResult :: {[any]: any})
			end
		end

		local migratedData = ProfileSchema.migrateInPlace(profileData, os.time())
		if migratedData ~= profileData then
			copyInto(profileData :: {[any]: any}, migratedData :: {[any]: any})
		end

		local isValid, schemaReason = ProfileSchema.validate(profileData)
		if not isValid then
			copyInto(profileData :: {[any]: any}, rollbackCopy)
			mutationError = string.format("SchemaValidationFailed:%s", tostring(schemaReason))
			error(mutationError)
		end
	end, mutationContext)

	self:_releaseMutationLock(userId)

	if not success then
		return false, mutationError or "UpdateFailed"
	end

	self:_syncRecordData(record)
	self:_markRecordDirty(record)
	return true, nil
end

function PlayerDataService:ForceSave(player: Player): (boolean, string?)
	if not ValidationUtil.isPlayer(player) then
		return false, "InvalidPlayer"
	end

	local record, reason = self:_resolveRecord(player, self._config.ProfileLoadTimeoutSeconds)
	if record == nil then
		return false, reason
	end

	local userId = record.UserId
	if not self:_acquireMutationLock(userId) then
		return false, "MutationLockTimeout"
	end

	local dataStoreService = self._dataStoreService
	if dataStoreService == nil then
		self:_releaseMutationLock(userId)
		return false, "ServiceUnavailable"
	end

	local success = dataStoreService:SetAsync(player, self._config.ForceSaveContextTag)
	self:_releaseMutationLock(userId)

	if not success then
		return false, "ForceSaveFailed"
	end

	self:_syncRecordData(record)
	return true, nil
end

function PlayerDataService:Destroy()
	if self._snapshotRateLimiter ~= nil then
		self._snapshotRateLimiter:Destroy()
	end

	if self._serviceJanitor ~= nil then
		self._serviceJanitor:Cleanup()
	end

	for _, record in pairs(self._recordsByUserId) do
		record.Janitor:Cleanup()
	end

	table.clear(self._recordsByUserId)
	table.clear(self._recordsByPlayer)
	table.clear(self._pendingLoadByUserId)
	table.clear(self._mutationLocksByUserId)
end

return PlayerDataService
