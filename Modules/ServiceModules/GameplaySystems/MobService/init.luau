--!strict

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local ValidationUtil = require(ReplicatedStorage.Util.ValidationUtil)
local MobDefs = require(ReplicatedStorage.Configs.MobDefs)
local ZoneDefs = require(ReplicatedStorage.Configs.ZoneDefs)

local Config = require(script.Config)
local ModelResolver = require(script.ModelResolver)
local StateSerializer = require(script.StateSerializer)
local ReplicationBuffer = require(script.ReplicationBuffer)

local ServiceModules = ServerStorage:WaitForChild("ServiceModules")
local SupportersFolder = ServiceModules:WaitForChild("Supporters")
local MobBrain = require(SupportersFolder:WaitForChild("MobBrain"))
local ZoneQueryHelper = require(SupportersFolder:WaitForChild("ZoneQueryHelper"))
local MapCollisionHelper = require(SupportersFolder:WaitForChild("MapCollisionHelper"))
local RoamBehavior = require(SupportersFolder:WaitForChild("MobBrain"):WaitForChild("RoamBehavior"))
local EMPTY_MOB_ID_LIST = table.freeze({}) :: {string}
local MODEL_SYNC_POSITION_EPSILON_SQ = 0.0004
local MODEL_SYNC_FACING_DOT_THRESHOLD = 0.99995

type ZoneServiceLike = {
	GetPlayerZone: (self: ZoneServiceLike, player: Player) -> (string?, string?),
	IsMobTargetValidForZone: (self: ZoneServiceLike, mob: any, player: Player) -> (boolean, string?),
}

type RewardServiceLike = {
	GrantMobKillRewards: (self: RewardServiceLike, mobId: string, contributionSnapshot: {[string]: any}) -> any,
}

type GameplayManagerServiceLike = {
	Now: (self: GameplayManagerServiceLike) -> number,
	RegisterSystem: (self: GameplayManagerServiceLike, name: string, system: {[string]: any}) -> (),
	UnregisterSystem: (self: GameplayManagerServiceLike, name: string) -> (),
	ScheduleAt: (self: GameplayManagerServiceLike, key: string, atTime: number, fn: () -> ()) -> (),
	Cancel: (self: GameplayManagerServiceLike, key: string) -> (),
}

type MobClientState = {
	MobId: string,
	MobDefId: string,
	ZoneId: string,
	SpawnIndex: number,
	Position: Vector3,
	PositionXZ: Vector2,
	GroundY: number,
	Facing: Vector3,
	HP: number,
	MaxHP: number,
	Alive: boolean,
	Attackable: boolean,
	BrainState: string,
	TargetUserId: number?,
	Revision: number,
}

type MobServerState = {
	SpawnOrigin: Vector3,
	PositionXZ: Vector2,
	FacingXZ: Vector2,
	GroundY: number,
	SpawnFailureCount: number,
	RoamState: "Idle" | "RoamMove",
	RoamStateUntil: number,
	RoamDestinationXZ: Vector2?,
	MoveSpeed: number,
	LastStateSyncAt: number,
	LastDamagedAt: number,
	RespawnAt: number?,
}

type MobRuntimeRecord = {
	MobId: string,
	ZoneId: string,
	SpawnIndex: number,
	MobDefId: string,
	MobDef: {[string]: any},
	Model: Model?,
	Brain: any?,
	ClientState: MobClientState,
	ServerState: MobServerState,
	Attackers: {[Player]: true},
	RespawnScheduleKey: string?,
	ResolvingDeath: boolean,
	Janitor: any,
}

local MobService = Knit.CreateService({
	Name = "MobService",
	Client = {
		MobStateDelta = Knit.CreateSignal(),
	},
})

local function resolveCharacterHumanoid(player: Player): Humanoid?
	local character = player.Character
	if character == nil then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end

	return humanoid
end

local function resolveCharacterRootPosition(player: Player): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart.Position
	end

	if character.PrimaryPart ~= nil then
		return character.PrimaryPart.Position
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant.Position
		end
	end

	return nil
end

local function resolveModelPositionAndFacing(model: Model?, fallbackPosition: Vector3, fallbackFacing: Vector3): (Vector3, Vector3)
	if model == nil then
		return fallbackPosition, fallbackFacing
	end

	local rootPart: BasePart? = nil
	if model.PrimaryPart ~= nil then
		rootPart = model.PrimaryPart
	else
		local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
			rootPart = humanoidRootPart
		end
	end

	if rootPart == nil then
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				rootPart = descendant
				break
			end
		end
	end

	if rootPart == nil then
		return fallbackPosition, fallbackFacing
	end

	local lookVector = rootPart.CFrame.LookVector
	if lookVector.Magnitude <= 1e-4 then
		lookVector = fallbackFacing
	end

	return rootPart.Position, lookVector.Unit
end

local function vector2FromVector3(value: Vector3): Vector2
	return Vector2.new(value.X, value.Z)
end

local function vector3FromXZ(positionXZ: Vector2, y: number): Vector3
	return Vector3.new(positionXZ.X, y, positionXZ.Y)
end

local function facingVector2FromVector3(value: Vector3): Vector2
	local horizontal = Vector2.new(value.X, value.Z)
	if horizontal.Magnitude <= 1e-4 then
		return Vector2.new(0, -1)
	end
	return horizontal.Unit
end

local function facingVector3FromVector2(value: Vector2): Vector3
	if value.Magnitude <= 1e-4 then
		return Vector3.new(0, 0, -1)
	end
	local unit = value.Unit
	return Vector3.new(unit.X, 0, unit.Y)
end

local function isFiniteVector2(value: Vector2): boolean
	return ValidationUtil.isFiniteNumber(value.X) and ValidationUtil.isFiniteNumber(value.Y)
end

local function sanitizeMobDef(rawMobDef: {[string]: any}, defaults: {[string]: any}): {[string]: any}
	local baseHp = tonumber(rawMobDef.BaseHP) or 1
	local damage = tonumber(rawMobDef.Damage) or 0
	local attackRange = tonumber(rawMobDef.AttackRange) or defaults.AttackRangeDefault
	local attackCooldown = tonumber(rawMobDef.AttackCooldown) or defaults.AttackCooldownSeconds
	local aggroLockDuration = tonumber(rawMobDef.AggroLockDuration) or defaults.AggroLockDurationDefault
	local respawnDelay = tonumber(rawMobDef.RespawnDelay) or defaults.DefaultRespawnDelaySeconds

	return {
		DisplayName = rawMobDef.DisplayName,
		Archetype = rawMobDef.Archetype,
		BaseHP = math.max(1, baseHp),
		Damage = math.max(0, damage),
		AttackRange = math.max(1, attackRange),
		AttackCooldown = math.max(0.1, attackCooldown),
		AggroLockDuration = math.max(1, aggroLockDuration),
		MoveSpeed = tonumber(rawMobDef.MoveSpeed) or 12,
		RespawnDelay = math.max(1, respawnDelay),
		Rewards = if typeof(rawMobDef.Rewards) == "table" then rawMobDef.Rewards else {},
		DropTableId = rawMobDef.DropTableId,
		AssetPath = rawMobDef.AssetPath,
	}
end

local function buildFallbackSpawnPointsFromBounds(
	bounds: {[string]: any},
	maxCount: number,
	insetStuds: number,
	heightOffset: number
): {Vector3}
	if typeof(bounds) ~= "table" or typeof(bounds.Min) ~= "Vector3" or typeof(bounds.Max) ~= "Vector3" then
		return {}
	end

	local minBounds: Vector3 = bounds.Min
	local maxBounds: Vector3 = bounds.Max
	local spanX = math.max(0, maxBounds.X - minBounds.X)
	local spanZ = math.max(0, maxBounds.Z - minBounds.Z)

	local insetX = math.clamp(insetStuds, 0, spanX * 0.45)
	local insetZ = math.clamp(insetStuds, 0, spanZ * 0.45)
	local y = minBounds.Y + heightOffset
	local centerX = (minBounds.X + maxBounds.X) * 0.5
	local centerZ = (minBounds.Z + maxBounds.Z) * 0.5

	local candidates = {
		Vector3.new(centerX, y, centerZ),
		Vector3.new(minBounds.X + insetX, y, minBounds.Z + insetZ),
		Vector3.new(maxBounds.X - insetX, y, maxBounds.Z - insetZ),
		Vector3.new(minBounds.X + insetX, y, maxBounds.Z - insetZ),
		Vector3.new(maxBounds.X - insetX, y, minBounds.Z + insetZ),
	}

	local output: {Vector3} = {}
	local seen: {[string]: true} = {}
	for _, point in ipairs(candidates) do
		local key = string.format("%.3f|%.3f|%.3f", point.X, point.Y, point.Z)
		if seen[key] == nil then
			seen[key] = true
			table.insert(output, point)
			if #output >= maxCount then
				break
			end
		end
	end

	return output
end

local function buildGridSpawnPointsFromBounds(
	bounds: {[string]: any},
	maxCount: number,
	insetStuds: number,
	heightOffset: number
): {Vector3}
	if typeof(bounds) ~= "table" or typeof(bounds.Min) ~= "Vector3" or typeof(bounds.Max) ~= "Vector3" then
		return {}
	end

	local count = math.max(0, math.floor(maxCount))
	if count <= 0 then
		return {}
	end

	local minimum: Vector3 = bounds.Min
	local maximum: Vector3 = bounds.Max
	local spanX = math.max(0, maximum.X - minimum.X)
	local spanZ = math.max(0, maximum.Z - minimum.Z)
	local insetX = math.clamp(insetStuds, 0, spanX * 0.45)
	local insetZ = math.clamp(insetStuds, 0, spanZ * 0.45)
	local minX = minimum.X + insetX
	local maxX = maximum.X - insetX
	local minZ = minimum.Z + insetZ
	local maxZ = maximum.Z - insetZ
	local y = minimum.Y + heightOffset

	if minX > maxX then
		local centerX = (minimum.X + maximum.X) * 0.5
		minX = centerX
		maxX = centerX
	end
	if minZ > maxZ then
		local centerZ = (minimum.Z + maximum.Z) * 0.5
		minZ = centerZ
		maxZ = centerZ
	end

	local columns = math.max(1, math.ceil(math.sqrt(count)))
	local rows = math.max(1, math.ceil(count / columns))
	local stepX = if columns > 1 then (maxX - minX) / (columns - 1) else 0
	local stepZ = if rows > 1 then (maxZ - minZ) / (rows - 1) else 0

	local output: {Vector3} = table.create(count)
	for row = 0, rows - 1 do
		for col = 0, columns - 1 do
			if #output >= count then
				break
			end
			local x = minX + (stepX * col)
			local z = minZ + (stepZ * row)
			table.insert(output, Vector3.new(x, y, z))
		end
		if #output >= count then
			break
		end
	end

	return output
end

function MobService:KnitInit()
	self._config = Config
	self._mobDefs = MobDefs
	self._zoneDefs = ZoneDefs
	self._zoneService = nil :: ZoneServiceLike?
	self._rewardService = nil :: RewardServiceLike?
	self._gameplayManager = nil :: GameplayManagerServiceLike?
	self._gameplaySystemName = "MobServiceRuntime"

	self._mobContainer = nil :: Instance?
	self._mobById = {} :: {[string]: MobRuntimeRecord}
	self._mobIdsByZone = {} :: {[string]: {[string]: true}}
	self._sortedMobIdsCacheByZone = {} :: {[string]: {string}}
	self._sortedMobIdsDirtyByZone = {} :: {[string]: true}
	self._attackerMobIdsByUserId = {} :: {[number]: {[string]: true}}
	self._activePlayers = {} :: {[Player]: true}

	self._simulationAccumulator = 0
	self._replicationAccumulator = 0
	self._positionThresholdSquared = Config.PositionChangeThresholdStuds * Config.PositionChangeThresholdStuds
	self._zonePopulationRefreshIntervalSeconds = math.max(0.05, Config.ZonePopulationRefreshIntervalSeconds)
	self._maxCombatSyncStepStuds = math.max(0, Config.MaxCombatSyncStepStuds)
	self._roamMinTravelDistanceStuds = math.max(0, Config.RoamMinTravelDistanceStuds)
	self._roamMinTravelDistanceStudsSq = self._roamMinTravelDistanceStuds * self._roamMinTravelDistanceStuds
	self._roamMaxTravelDistanceStuds = math.max(self._roamMinTravelDistanceStuds, Config.RoamMaxTravelDistanceStuds)
	self._roamTravelScoreDistanceStuds = math.max(1, self._roamMaxTravelDistanceStuds)
	self._roamTravelScoreDistanceStudsInv = 1 / self._roamTravelScoreDistanceStuds
	self._roamDesiredPeerDistance = math.max(1, Config.RoamSeparationRadius * 2)
	self._roamDestinationSampleAttempts = math.max(1, math.floor(Config.RoamDestinationSampleAttempts))
	self._roamLocalDestinationBias = math.clamp(Config.RoamLocalDestinationBias, 0, 1)
	self._warnedNoSpawnPointsByZone = {} :: {[string]: true}
	self._spawnQueue = {} :: {[number]: MobRuntimeRecord}
	self._spawnQueueHead = 1
	self._spawnQueueTail = 0
	self._spawnQueueByMobId = {} :: {[string]: true}
	self._zonePopulationById = {} :: {[string]: number}
	self._lastZonePopulationRefreshAt = 0
	self._zoneAliveCacheScratch = {} :: {[string]: {string}}

	self._serviceJanitor = Janitor.new()
	self._rng = Random.new()
	self._serializeAddCallback = function(mobId: string)
		return self:_serializeMobAddState(mobId)
	end
	self._serializeUpdateCallback = function(mobId: string)
		return self:_serializeMobUpdateState(mobId)
	end
	self._replicationBuffer = ReplicationBuffer.new({
		MaxAddsPerFlushPerPlayer = Config.MaxAddsPerFlushPerPlayer,
		MaxUpdatesPerFlushPerPlayer = Config.MaxUpdatesPerFlushPerPlayer,
		MaxRemovesPerFlushPerPlayer = Config.MaxRemovesPerFlushPerPlayer,
		MaxTotalMobEntriesPerFlush = Config.MaxTotalMobEntriesPerFlush,
	})
end

function MobService:KnitStart()
	self._zoneService = Knit.GetService("ZoneService") :: ZoneServiceLike
	self._rewardService = Knit.GetService("RewardService") :: RewardServiceLike
	self._gameplayManager = Knit.GetService("GameplayManagerService") :: GameplayManagerServiceLike
	self._mobContainer = ModelResolver.ResolveSpawnContainer(Workspace, self._config.SpawnRootPath)

	local zoneIds = {}
	for zoneId in pairs(self._zoneDefs) do
		table.insert(zoneIds, zoneId)
	end
	table.sort(zoneIds)
	MapCollisionHelper.WarmZones(zoneIds)

	local okInit, initErr = pcall(function()
		self:_initializeSpawnSlots()
	end)
	if not okInit then
		warn(string.format("[MobService] Initialize spawn slots failed: %s", tostring(initErr)))
	end

	local gameplayManager = self._gameplayManager
	if gameplayManager == nil then
		error("[MobService] GameplayManagerService is required")
	end

	gameplayManager:RegisterSystem(self._gameplaySystemName, {
		OnTick = function(_: any, now: number, dt: number)
			self:StepMobSimulation(now, dt)
			self:FlushReplicationBuffers(now, dt)
		end,
		OnPlayerAdded = function(_: any, player: Player)
			self:_onPlayerAdded(player)
		end,
		OnPlayerRemoving = function(_: any, player: Player)
			self:_onPlayerRemoving(player)
		end,
		})
end

function MobService:_onPlayerAdded(player: Player)
	self._activePlayers[player] = true
	self._replicationBuffer:ResetPlayer(player.UserId)
	self._lastZonePopulationRefreshAt = 0
end

function MobService:_onPlayerRemoving(player: Player)
	self._activePlayers[player] = nil
	self:_clearPlayerAsAttacker(player)
	self._replicationBuffer:ResetPlayer(player.UserId)
	self._lastZonePopulationRefreshAt = 0
end

function MobService:_respawnScheduleKey(mobId: string): string
	return string.format("mob_respawn_%s", mobId)
end

function MobService:_enqueueSpawn(record: MobRuntimeRecord)
	if record.Janitor == nil then
		return
	end
	if self._spawnQueueByMobId[record.MobId] == true then
		return
	end

	self._spawnQueueTail += 1
	self._spawnQueue[self._spawnQueueTail] = record
	self._spawnQueueByMobId[record.MobId] = true
end

function MobService:_dequeueSpawn(): MobRuntimeRecord?
	if self._spawnQueueHead > self._spawnQueueTail then
		self._spawnQueueHead = 1
		self._spawnQueueTail = 0
		return nil
	end

	local index = self._spawnQueueHead
	local record = self._spawnQueue[index]
	self._spawnQueue[index] = nil
	self._spawnQueueHead += 1

	if self._spawnQueueHead > self._spawnQueueTail then
		self._spawnQueueHead = 1
		self._spawnQueueTail = 0
	end

	if record ~= nil then
		self._spawnQueueByMobId[record.MobId] = nil
	end
	return record
end

function MobService:_processSpawnQueue(_now: number)
	local hasActiveZone = false
	for _, count in pairs(self._zonePopulationById) do
		if count > 0 then
			hasActiveZone = true
			break
		end
	end
	if not hasActiveZone then
		return
	end

	local maxOps = math.max(1, self._config.SpawnMaxOperationsPerSimulationStep)
	local queueSize = math.max(0, self._spawnQueueTail - self._spawnQueueHead + 1)
	local attempts = 0
	local processed = 0
	local maxAttempts = math.max(queueSize, maxOps)

	while processed < maxOps and attempts < maxAttempts do
		local record = self:_dequeueSpawn()
		if record == nil then
			break
		end
		attempts += 1
		if record.Janitor == nil then
			continue
		end
		if self._mobById[record.MobId] ~= record then
			continue
		end
		if record.ClientState.Alive == true then
			continue
		end
		if (self._zonePopulationById[record.ZoneId] or 0) <= 0 then
			self:_enqueueSpawn(record)
			continue
		end

		processed += 1
		local spawned, spawnReason = self:_spawnMob(record)
		if not spawned then
			record.ServerState.SpawnFailureCount += 1
			warn(string.format("[MobService] Spawn failed for %s: %s", record.MobId, tostring(spawnReason)))
			self:_scheduleRespawn(record, self._config.RespawnFailureRetrySeconds)
		end
	end
end

function MobService:_refreshZonePopulation(now: number)
	local refreshInterval = self._zonePopulationRefreshIntervalSeconds
	if (now - self._lastZonePopulationRefreshAt) < refreshInterval then
		return
	end

	self._lastZonePopulationRefreshAt = now
	table.clear(self._zonePopulationById)

	local zoneService = self._zoneService
	if zoneService == nil then
		return
	end

	for player in pairs(self._activePlayers) do
		local zoneId, _ = zoneService:GetPlayerZone(player)
		if ValidationUtil.isNonEmptyString(zoneId) then
			local key = zoneId :: string
			self._zonePopulationById[key] = (self._zonePopulationById[key] or 0) + 1
		end
	end
end

function MobService:_registerMobInZone(zoneId: string, mobId: string)
	local zoneSet = self._mobIdsByZone[zoneId]
	if zoneSet == nil then
		zoneSet = {}
		self._mobIdsByZone[zoneId] = zoneSet
	end
	zoneSet[mobId] = true
	self._sortedMobIdsDirtyByZone[zoneId] = true
end

function MobService:_unregisterMobFromZone(zoneId: string, mobId: string)
	local zoneSet = self._mobIdsByZone[zoneId]
	if zoneSet == nil then
		return
	end
	zoneSet[mobId] = nil
	if next(zoneSet) == nil then
		self._mobIdsByZone[zoneId] = nil
		self._sortedMobIdsCacheByZone[zoneId] = nil
		self._sortedMobIdsDirtyByZone[zoneId] = nil
		return
	end
	self._sortedMobIdsDirtyByZone[zoneId] = true
end

function MobService:_getSortedMobIdsForZone(zoneId: string): {string}
	local cached = self._sortedMobIdsCacheByZone[zoneId]
	if cached ~= nil and self._sortedMobIdsDirtyByZone[zoneId] ~= true then
		return cached
	end

	local zoneSet = self._mobIdsByZone[zoneId]
	if zoneSet == nil then
		local empty = {}
		self._sortedMobIdsCacheByZone[zoneId] = empty
		self._sortedMobIdsDirtyByZone[zoneId] = nil
		return empty
	end

	local sorted = {}
	for mobId in pairs(zoneSet) do
		table.insert(sorted, mobId)
	end
	table.sort(sorted)

	self._sortedMobIdsCacheByZone[zoneId] = sorted
	self._sortedMobIdsDirtyByZone[zoneId] = nil
	return sorted
end

function MobService:_resolveReplicationZoneIdForPlayer(player: Player): string?
	local zoneId: string? = nil
	local zoneService = self._zoneService
	if zoneService ~= nil then
		local resolvedZoneId = zoneService:GetPlayerZone(player)
		if ValidationUtil.isNonEmptyString(resolvedZoneId) then
			zoneId = resolvedZoneId
		end
	end
	return zoneId
end

function MobService:_buildAliveMobIdsForZone(zoneId: string): {string}
	local sortedZoneMobIds = self:_getSortedMobIdsForZone(zoneId)
	if #sortedZoneMobIds == 0 then
		return EMPTY_MOB_ID_LIST
	end

	local mobIds = table.create(#sortedZoneMobIds)
	for _, mobId in ipairs(sortedZoneMobIds) do
		local record = self._mobById[mobId]
		if record ~= nil and record.ClientState.Alive == true then
			table.insert(mobIds, mobId)
		end
	end

	return mobIds
end

function MobService:_newClientState(mobId: string, zoneId: string, spawnIndex: number, spawnOrigin: Vector3): MobClientState
	local positionXZ = vector2FromVector3(spawnOrigin)
	return {
		MobId = mobId,
		MobDefId = "",
		ZoneId = zoneId,
		SpawnIndex = spawnIndex,
		Position = spawnOrigin,
		PositionXZ = positionXZ,
		GroundY = spawnOrigin.Y,
		Facing = Vector3.new(0, 0, -1),
		HP = 0,
		MaxHP = 0,
		Alive = false,
		Attackable = false,
		BrainState = "Idle",
		TargetUserId = nil,
		Revision = 0,
	}
end

function MobService:_bumpRevision(record: MobRuntimeRecord)
	record.ClientState.Revision += 1
end

function MobService:_isFacingDifferent(currentFacing: Vector3, nextFacing: Vector3): boolean
	return currentFacing:Dot(nextFacing) < self._config.FacingDotThreshold
end

function MobService:_hasAttackers(record: MobRuntimeRecord): boolean
	return next(record.Attackers) ~= nil
end

function MobService:_setAuthoritativePosition(
	record: MobRuntimeRecord,
	position: Vector3,
	facing: Vector3?
): boolean
	local serverState = record.ServerState
	local clientState = record.ClientState
	local changed = false
	local positionXZ = vector2FromVector3(position)
	local serverDelta = positionXZ - serverState.PositionXZ

	if serverDelta:Dot(serverDelta) > 1e-8 then
		serverState.PositionXZ = positionXZ
		changed = true
	end
	if math.abs(position.Y - serverState.GroundY) > 1e-4 then
		serverState.GroundY = position.Y
		changed = true
	end

	local positionDelta = position - clientState.Position
	if positionDelta:Dot(positionDelta) > self._positionThresholdSquared then
		clientState.Position = position
		changed = true
	end
	local clientDeltaXZ = positionXZ - clientState.PositionXZ
	if clientDeltaXZ:Dot(clientDeltaXZ) > 1e-8 then
		clientState.PositionXZ = positionXZ
		changed = true
	end
	if math.abs(position.Y - clientState.GroundY) > 1e-4 then
		clientState.GroundY = position.Y
		changed = true
	end

	if facing ~= nil then
		local nextFacing = if facing.Magnitude <= 1e-4 then clientState.Facing else facing.Unit
		if self:_isFacingDifferent(clientState.Facing, nextFacing) then
			clientState.Facing = nextFacing
			serverState.FacingXZ = facingVector2FromVector3(nextFacing)
			changed = true
		end
	end

	return changed
end

function MobService:_syncModelToAuthoritative(record: MobRuntimeRecord)
	local model = record.Model
	if model == nil then
		return
	end

	local clientState = record.ClientState
	local targetPosition = clientState.Position
	local facing = if clientState.Facing.Magnitude <= 1e-4 then Vector3.new(0, 0, -1) else clientState.Facing.Unit
	local currentPivot = model:GetPivot()
	local positionDelta = currentPivot.Position - targetPosition
	if positionDelta:Dot(positionDelta) <= MODEL_SYNC_POSITION_EPSILON_SQ then
		if currentPivot.LookVector:Dot(facing) >= MODEL_SYNC_FACING_DOT_THRESHOLD then
			return
		end
	end

	model:PivotTo(CFrame.lookAt(targetPosition, targetPosition + facing))
end

function MobService:_syncStateFromModelAndBrain(record: MobRuntimeRecord, now: number)
	local clientState = record.ClientState
	local serverState = record.ServerState
	local changed = false
	local currentTargetPlayer: Player? = nil

	local brain = record.Brain
	if brain ~= nil then
		local brainState = brain:GetState()
		currentTargetPlayer = brain:GetCurrentTarget()
		if currentTargetPlayer ~= nil and brainState ~= "Dead" then
			brainState = "Engaged"
		end

		if brainState ~= clientState.BrainState then
			clientState.BrainState = brainState
			changed = true
		end

		local targetUserId = if currentTargetPlayer ~= nil then currentTargetPlayer.UserId else nil
		if targetUserId ~= clientState.TargetUserId then
			clientState.TargetUserId = targetUserId
			changed = true
		end
	end

	local combatAuthority = self:_hasAttackers(record) and currentTargetPlayer ~= nil
	if combatAuthority then
		local nextPosition, nextFacing = resolveModelPositionAndFacing(
			record.Model,
			vector3FromXZ(serverState.PositionXZ, serverState.GroundY),
			clientState.Facing
		)
		local fallbackXZ = serverState.PositionXZ
		local candidateXZ = vector2FromVector3(nextPosition)
		if not isFiniteVector2(candidateXZ) then
			candidateXZ = fallbackXZ
		end

		local clampXZToZone = ZoneQueryHelper.ClampXZToZone
		if typeof(clampXZToZone) == "function" then
			local clampedXZ = clampXZToZone(candidateXZ, record.ZoneId, 0)
			if clampedXZ ~= nil then
				candidateXZ = clampedXZ
			end
		end

		local maxStep = self._maxCombatSyncStepStuds
		if maxStep > 0 then
			local delta = candidateXZ - fallbackXZ
			local distance = delta.Magnitude
			if distance > maxStep and distance > 1e-4 then
				candidateXZ = fallbackXZ + (delta.Unit * maxStep)
			end
		end

		-- Server proxy roots are non-collidable; keep combat authority constrained to the
		-- zone ground plane so assignment/chase cannot drag replicated visuals underground.
		nextPosition = vector3FromXZ(candidateXZ, serverState.GroundY)
		if self:_setAuthoritativePosition(record, nextPosition, nextFacing) then
			changed = true
		end
		self:_syncModelToAuthoritative(record)
	else
		local authoritativePosition = vector3FromXZ(serverState.PositionXZ, serverState.GroundY)
		if self:_setAuthoritativePosition(record, authoritativePosition, facingVector3FromVector2(serverState.FacingXZ)) then
			changed = true
		end
		self:_syncModelToAuthoritative(record)
	end

	if changed then
		self:_bumpRevision(record)
	end

	record.ServerState.LastStateSyncAt = now
end

function MobService:_setHealth(record: MobRuntimeRecord, nextHealth: number): boolean
	local clientState = record.ClientState
	local clamped = math.clamp(nextHealth, 0, clientState.MaxHP)
	if clamped == clientState.HP then
		return false
	end

	clientState.HP = clamped
	record.ServerState.LastDamagedAt = os.clock()
	self:_bumpRevision(record)
	return true
end

function MobService:_applySpawnState(record: MobRuntimeRecord, mobDefId: string, mobDef: {[string]: any})
	local clientState = record.ClientState
	local serverState = record.ServerState
	local changed = false

	if clientState.MobDefId ~= mobDefId then
		clientState.MobDefId = mobDefId
		changed = true
	end

	if clientState.MaxHP ~= mobDef.BaseHP then
		clientState.MaxHP = mobDef.BaseHP
		changed = true
	end
	if clientState.HP ~= mobDef.BaseHP then
		clientState.HP = mobDef.BaseHP
		changed = true
	end
	if clientState.Alive ~= true then
		clientState.Alive = true
		changed = true
	end
	if clientState.Attackable ~= true then
		clientState.Attackable = true
		changed = true
	end
	if clientState.BrainState ~= "Idle" then
		clientState.BrainState = "Idle"
		changed = true
	end
	if clientState.TargetUserId ~= nil then
		clientState.TargetUserId = nil
		changed = true
	end

	local spawnPosition = vector3FromXZ(serverState.PositionXZ, serverState.GroundY)
	local spawnFacing = facingVector3FromVector2(serverState.FacingXZ)
	if self:_setAuthoritativePosition(record, spawnPosition, spawnFacing) then
		changed = true
	end

	if changed then
		self:_bumpRevision(record)
	end
end

function MobService:_applyDeathState(record: MobRuntimeRecord)
	local clientState = record.ClientState
	local serverState = record.ServerState
	local changed = false

	if clientState.HP ~= 0 then
		clientState.HP = 0
		changed = true
	end
	if clientState.Alive ~= false then
		clientState.Alive = false
		changed = true
	end
	if clientState.Attackable ~= false then
		clientState.Attackable = false
		changed = true
	end
	if clientState.BrainState ~= "Dead" then
		clientState.BrainState = "Dead"
		changed = true
	end
	if clientState.TargetUserId ~= nil then
		clientState.TargetUserId = nil
		changed = true
	end
	serverState.RoamDestinationXZ = nil
	serverState.RoamState = "Idle"

	if changed then
		self:_bumpRevision(record)
	end
end

function MobService:_resolveZoneGroundY(zoneId: string, fallbackY: number): number
	local getZoneGroundY = ZoneQueryHelper.GetZoneGroundY
	if typeof(getZoneGroundY) == "function" then
		local groundY = getZoneGroundY(zoneId, true)
		if ValidationUtil.isFiniteNumber(groundY) then
			return (groundY :: number) + self._config.MobGroundOffset
		end
	end
	return fallbackY
end

function MobService:_isPositionInsideZone(zoneId: string, position: Vector3): boolean
	local pointXZ = vector2FromVector3(position)
	local isPointXZInZone = ZoneQueryHelper.IsPointXZInZone
	if typeof(isPointXZInZone) == "function" then
		return isPointXZInZone(pointXZ, zoneId, self._config.ZoneContainmentPadding)
	end
	return ZoneQueryHelper.IsPointInZone(position, zoneId, self._config.ZoneContainmentPadding)
end

function MobService:_isPositionTooCloseToMob(
	zoneId: string,
	position: Vector3,
	minimumDistance: number,
	ignoreMobId: string?,
	pendingPositions: {Vector3}?
): boolean
	local minDistanceSq = minimumDistance * minimumDistance
	local zoneSet = self._mobIdsByZone[zoneId]
	if zoneSet ~= nil then
		for mobId in pairs(zoneSet) do
			if mobId ~= ignoreMobId then
				local otherRecord = self._mobById[mobId]
				if otherRecord ~= nil and otherRecord.ClientState.Alive == true then
					local otherPosition = vector3FromXZ(otherRecord.ServerState.PositionXZ, otherRecord.ServerState.GroundY)
					local delta = position - otherPosition
					local distanceSq = (delta.X * delta.X) + (delta.Z * delta.Z)
					if distanceSq < minDistanceSq then
						return true
					end
				end
			end
		end
	end

	if pendingPositions ~= nil then
		for _, pendingPosition in ipairs(pendingPositions) do
			local delta = position - pendingPosition
			local distanceSq = (delta.X * delta.X) + (delta.Z * delta.Z)
			if distanceSq < minDistanceSq then
				return true
			end
		end
	end

	return false
end

function MobService:_isPositionBlocked(zoneId: string, position: Vector3, radius: number, height: number): boolean
	return MapCollisionHelper.IsPositionObstructed(zoneId, position, radius, height)
end

function MobService:_resolveDynamicSpawnSeparation(record: MobRuntimeRecord): number
	local baseSeparation = math.max(0, tonumber(self._config.SpawnMinSeparationStuds) or 0)
	local failureCount = math.max(0, math.floor(tonumber(record.ServerState.SpawnFailureCount) or 0))
	local ignoreAfter = math.max(0, math.floor(tonumber(self._config.SpawnIgnoreSeparationAfterFailures) or 0))
	if ignoreAfter > 0 and failureCount >= ignoreAfter then
		return 0
	end

	local relaxStart = math.max(0, math.floor(tonumber(self._config.SpawnSeparationRelaxStartFailures) or 0))
	local relaxPerFailure = math.max(0, tonumber(self._config.SpawnSeparationRelaxPerFailureStuds) or 0)
	local floorSeparation = math.max(0, tonumber(self._config.SpawnMinSeparationFloorStuds) or 0)
	local relaxedFailures = math.max(0, failureCount - relaxStart + 1)
	local resolved = baseSeparation - (relaxedFailures * relaxPerFailure)
	return math.max(floorSeparation, resolved)
end

function MobService:_isSpawnPositionValid(
	zoneId: string,
	position: Vector3,
	minimumSeparation: number,
	ignoreMobId: string?,
	pendingPositions: {Vector3}?
): boolean
	if not self:_isPositionInsideZone(zoneId, position) then
		return false
	end
	if self:_isPositionBlocked(zoneId, position, self._config.SpawnCollisionRadius, self._config.SpawnCollisionHeight) then
		return false
	end
	if self:_isPositionTooCloseToMob(zoneId, position, minimumSeparation, ignoreMobId, pendingPositions) then
		return false
	end
	return true
end

function MobService:_sampleSpawnPositionForZone(
	zoneId: string,
	groundY: number,
	minimumSeparation: number,
	ignoreMobId: string?,
	pendingPositions: {Vector3}?
): Vector3?
	local samplePointInZone = ZoneQueryHelper.SampleRandomPointXZInZone
	for _ = 1, self._config.SpawnSampleAttemptsPerMob do
		local sampledXZ: Vector2? = nil
		if typeof(samplePointInZone) == "function" then
			sampledXZ = samplePointInZone(zoneId, self._rng, self._config.SpawnZoneInsetStuds)
		end
		if sampledXZ ~= nil then
			local candidate = vector3FromXZ(sampledXZ, groundY)
			if self:_isSpawnPositionValid(zoneId, candidate, minimumSeparation, ignoreMobId, pendingPositions) then
				return candidate
			end
		end
	end
	return nil
end

function MobService:_resolveSpawnOriginsForZone(zoneId: string, zoneDef: {[string]: any}?): {Vector3}
	local maxMobs = self._config.DefaultMaxMobsPerZone
	if typeof(zoneDef) == "table" and ValidationUtil.isFiniteNumber(zoneDef.MaxMobs) then
		maxMobs = math.max(0, math.floor(zoneDef.MaxMobs))
	end
	if maxMobs <= 0 then
		return {}
	end

	local spawnOrigins = table.create(maxMobs) :: {Vector3}
	local seenByKey: {[string]: true} = {}
	local groundY = self:_resolveZoneGroundY(zoneId, self._config.FallbackSpawnHeightOffset)

	local function addOrigin(point: Vector3, allowDuplicate: boolean?)
		if #spawnOrigins >= maxMobs then
			return
		end
		local normalized = Vector3.new(point.X, groundY, point.Z)
		if allowDuplicate ~= true then
			local key = string.format("%.2f|%.2f", normalized.X, normalized.Z)
			if seenByKey[key] == true then
				return
			end
			seenByKey[key] = true
		end
		table.insert(spawnOrigins, normalized)
	end

	if typeof(zoneDef) == "table" and typeof(zoneDef.SpawnPoints) == "table" then
		for _, spawnOrigin in ipairs(zoneDef.SpawnPoints) do
			if #spawnOrigins >= maxMobs then
				break
			end
			if typeof(spawnOrigin) == "Vector3" then
				addOrigin(spawnOrigin, false)
			end
		end
	end

	local markerBounds: {[string]: any}? = nil
	local getMarkerExactBounds = ZoneQueryHelper.GetMarkerExactBounds
	if typeof(getMarkerExactBounds) == "function" then
		markerBounds = getMarkerExactBounds(zoneId, true)
	end
	if markerBounds == nil then
		local getZoneBounds = ZoneQueryHelper.GetZoneBounds
		if typeof(getZoneBounds) == "function" then
			markerBounds = getZoneBounds(zoneId, true)
		end
	end
	if markerBounds == nil then
		if self._warnedNoSpawnPointsByZone[zoneId] == nil then
			self._warnedNoSpawnPointsByZone[zoneId] = true
			warn(string.format("[MobService] No spawn origins for zone '%s' (no SpawnPoints and no zone bounds)", zoneId))
		end
		return spawnOrigins
	end

	local gridOrigins = buildGridSpawnPointsFromBounds(
		markerBounds,
		maxMobs,
		math.max(0, self._config.FallbackSpawnInsetStuds),
		self._config.FallbackSpawnHeightOffset
	)
	for _, origin in ipairs(gridOrigins) do
		addOrigin(origin, true)
		if #spawnOrigins >= maxMobs then
			break
		end
	end

	if #spawnOrigins == 0 then
		local fallbackOrigins = buildFallbackSpawnPointsFromBounds(
			markerBounds,
			math.max(1, math.min(maxMobs, self._config.FallbackSpawnPointsPerZone)),
			math.max(0, self._config.FallbackSpawnInsetStuds),
			self._config.FallbackSpawnHeightOffset
		)
		for _, origin in ipairs(fallbackOrigins) do
			addOrigin(origin, true)
			if #spawnOrigins >= maxMobs then
				break
			end
		end
	end

	if #spawnOrigins < maxMobs then
		local samplePointInZone = ZoneQueryHelper.SampleRandomPointXZInZone
		if typeof(samplePointInZone) == "function" then
			local remaining = maxMobs - #spawnOrigins
			local attempts = math.max(remaining * 3, remaining)
			for _ = 1, attempts do
				local sampledXZ = samplePointInZone(zoneId, self._rng, self._config.SpawnZoneInsetStuds)
				if sampledXZ ~= nil then
					addOrigin(vector3FromXZ(sampledXZ, groundY), true)
					if #spawnOrigins >= maxMobs then
						break
					end
				end
			end
		end
	end

	if #spawnOrigins == 0 and self._warnedNoSpawnPointsByZone[zoneId] == nil then
		self._warnedNoSpawnPointsByZone[zoneId] = true
		warn(string.format("[MobService] Unable to resolve valid spawn points for zone '%s'", zoneId))
	end

	return spawnOrigins
end

function MobService:_initializeSpawnSlots()
	for zoneId, zoneDef in pairs(self._zoneDefs) do
		local okZone, zoneErr = pcall(function()
			local spawnOrigins = self:_resolveSpawnOriginsForZone(zoneId, zoneDef)
			for spawnIndex, spawnOrigin in ipairs(spawnOrigins) do
				if typeof(spawnOrigin) == "Vector3" then
					local mobId = string.format("%s:%d", zoneId, spawnIndex)
					if self._mobById[mobId] == nil then
						local recordJanitor = Janitor.new()
						local record: MobRuntimeRecord = {
							MobId = mobId,
							ZoneId = zoneId,
							SpawnIndex = spawnIndex,
							MobDefId = "",
							MobDef = {},
							Model = nil,
							Brain = nil,
								ClientState = self:_newClientState(mobId, zoneId, spawnIndex, spawnOrigin),
								ServerState = {
									SpawnOrigin = spawnOrigin,
									PositionXZ = vector2FromVector3(spawnOrigin),
									FacingXZ = Vector2.new(0, -1),
									GroundY = spawnOrigin.Y,
									SpawnFailureCount = 0,
									RoamState = "Idle",
									RoamStateUntil = 0,
									RoamDestinationXZ = nil,
									MoveSpeed = 0,
									LastStateSyncAt = 0,
									LastDamagedAt = 0,
									RespawnAt = nil,
								},
							Attackers = {},
							RespawnScheduleKey = nil,
							ResolvingDeath = false,
							Janitor = recordJanitor,
						}

						recordJanitor:Add(function()
							self:_cancelRespawn(record)
							if record.Brain ~= nil then
								record.Brain:Destroy()
								record.Brain = nil
							end
							if record.Model ~= nil then
								record.Model:Destroy()
								record.Model = nil
							end
							self:_clearAllAttackers(record)
							self:_unregisterMobFromZone(record.ZoneId, record.MobId)
							self._spawnQueueByMobId[record.MobId] = nil
							self._mobById[mobId] = nil
						end)

						self._mobById[mobId] = record
						self:_registerMobInZone(zoneId, mobId)
						self:_enqueueSpawn(record)
					end
				end
			end
		end)
		if not okZone then
			warn(string.format("[MobService] Failed to initialize zone '%s': %s", tostring(zoneId), tostring(zoneErr)))
		end
	end
end

function MobService:_pickMobDefIdForZone(zoneId: string): string?
	local zoneDef = self._zoneDefs[zoneId]
	if typeof(zoneDef) ~= "table" then
		return nil
	end

	local spawnTable = zoneDef.MobSpawnTable
	if typeof(spawnTable) ~= "table" then
		return nil
	end

	local totalWeight = 0
	for _, entry in ipairs(spawnTable) do
		if typeof(entry) == "table" and ValidationUtil.isNonEmptyString(entry.MobId) then
			local weight = tonumber(entry.Weight) or 0
			if weight > 0 then
				totalWeight += weight
			end
		end
	end

	if totalWeight <= 0 then
		return nil
	end

	local roll = self._rng:NextNumber() * totalWeight
	local cumulative = 0
	for _, entry in ipairs(spawnTable) do
		if typeof(entry) == "table" and ValidationUtil.isNonEmptyString(entry.MobId) then
			local weight = tonumber(entry.Weight) or 0
			if weight > 0 then
				cumulative += weight
				if roll <= cumulative then
					return entry.MobId
				end
			end
		end
	end

	for _, entry in ipairs(spawnTable) do
		if typeof(entry) == "table" and ValidationUtil.isNonEmptyString(entry.MobId) then
			return entry.MobId
		end
	end

	return nil
end

function MobService:_spawnMob(record: MobRuntimeRecord): (boolean, string?)
	if self._mobContainer == nil then
		return false, "MobContainerUnavailable"
	end

	self:_cancelRespawn(record)
	self:_clearAllAttackers(record)

	if record.Brain ~= nil then
		record.Brain:Destroy()
		record.Brain = nil
	end

	if record.Model ~= nil then
		record.Model:Destroy()
		record.Model = nil
	end

	local mobDefId = self:_pickMobDefIdForZone(record.ZoneId)
	if not ValidationUtil.isNonEmptyString(mobDefId) then
		return false, "NoSpawnCandidates"
	end

	local rawMobDef = self._mobDefs[mobDefId]
	if typeof(rawMobDef) ~= "table" then
		return false, "UnknownMobDef"
	end

	local mobDef = sanitizeMobDef(rawMobDef, self._config)
	local spawnPosition = record.ServerState.SpawnOrigin
	local minimumSeparation = self:_resolveDynamicSpawnSeparation(record)
	if not self:_isSpawnPositionValid(
		record.ZoneId,
		spawnPosition,
		minimumSeparation,
		record.MobId,
		nil
	) then
		local groundY = self:_resolveZoneGroundY(record.ZoneId, spawnPosition.Y)
		local sampledSpawn = self:_sampleSpawnPositionForZone(
			record.ZoneId,
			groundY,
			minimumSeparation,
			record.MobId,
			nil
		)
		if sampledSpawn ~= nil then
			spawnPosition = sampledSpawn
		end
	end

	record.ServerState.SpawnOrigin = spawnPosition
	record.ServerState.PositionXZ = vector2FromVector3(spawnPosition)
	record.ServerState.GroundY = spawnPosition.Y
	record.ServerState.FacingXZ = Vector2.new(0, -1)
	record.ServerState.RoamState = "Idle"
	record.ServerState.RoamStateUntil = 0
	record.ServerState.RoamDestinationXZ = nil
	record.ServerState.MoveSpeed = math.max(
		self._config.RoamMinSpeedStudsPerSecond,
		(tonumber(mobDef.MoveSpeed) or 12) * self._config.RoamSpeedMultiplier
	)

	local template = ModelResolver.ResolveMobTemplate(ReplicatedStorage, self._config.AssetsRootPath, record.ZoneId, mobDefId, mobDef)
	if template == nil then
		return false, "MissingMobTemplate"
	end

	local model, _ = ModelResolver.CloneMobModel(
		template,
		self._mobContainer,
		record.MobId,
		record.ZoneId,
		mobDefId,
		spawnPosition
	)
	if model == nil then
		return false, "InvalidMobModel"
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid.WalkSpeed = tonumber(mobDef.MoveSpeed) or humanoid.WalkSpeed
		humanoid.Health = mobDef.BaseHP
		humanoid.MaxHealth = mobDef.BaseHP
	end

	record.MobDefId = mobDefId
	record.MobDef = mobDef
	record.Model = model
	record.ResolvingDeath = false
	record.ServerState.RespawnAt = nil
	record.ServerState.SpawnFailureCount = 0

	record.Brain = MobBrain.new({
		MobId = record.MobId,
		Model = model,
		SpawnOrigin = record.ServerState.SpawnOrigin,
		AllowedZoneId = record.ZoneId,
		AttackRange = mobDef.AttackRange,
		AttackCooldown = mobDef.AttackCooldown,
		AggroLockDuration = mobDef.AggroLockDuration,
		TargetValidator = function(_: any, player: Player): boolean
			return self:_isMobTargetValid(record, player)
		end,
		AttackExecutor = function(_: any, player: Player, now: number): boolean
			return self:_executeMobAttack(record, player, now)
		end,
		OnStateChanged = function(_: any)
			self:_syncStateFromModelAndBrain(record, os.clock())
		end,
		OnDeath = function(_: any, now: number)
			self:_resolveMobDeath(record, nil, "MobBrainDeath", now)
		end,
		ContributionConfig = {
			EligibilityWindowSeconds = self._config.ContributionEligibilityWindowSeconds,
			MinDamage = self._config.ContributionMinDamage,
		},
	})

	self:_applySpawnState(record, mobDefId, mobDef)
	self:_syncStateFromModelAndBrain(record, os.clock())
	return true, nil
end

function MobService:_cancelRespawn(record: MobRuntimeRecord)
	local scheduleKey = record.RespawnScheduleKey
	if scheduleKey ~= nil then
		local gameplayManager = self._gameplayManager
		if gameplayManager ~= nil then
			pcall(function()
				gameplayManager:Cancel(scheduleKey)
			end)
		end
		record.RespawnScheduleKey = nil
	end
	record.ServerState.RespawnAt = nil
end

function MobService:_scheduleRespawn(record: MobRuntimeRecord, delaySeconds: number)
	self:_cancelRespawn(record)

	local resolvedDelay = math.max(0.1, delaySeconds)
	local gameplayManager = self._gameplayManager
	local now = if gameplayManager ~= nil then gameplayManager:Now() else os.clock()
	local dueAt = now + resolvedDelay
	record.ServerState.RespawnAt = dueAt

	local scheduleKey = self:_respawnScheduleKey(record.MobId)
	record.RespawnScheduleKey = scheduleKey

	if gameplayManager == nil then
		task.delay(resolvedDelay, function()
			if record.RespawnScheduleKey ~= scheduleKey then
				return
			end
			record.RespawnScheduleKey = nil
			record.ServerState.RespawnAt = nil
			self:_enqueueSpawn(record)
		end)
		return
	end

	gameplayManager:ScheduleAt(scheduleKey, dueAt, function()
		if record.RespawnScheduleKey ~= scheduleKey then
			return
		end
		record.RespawnScheduleKey = nil
		record.ServerState.RespawnAt = nil
		self:_enqueueSpawn(record)
	end)
end

function MobService:_buildContributionSnapshot(record: MobRuntimeRecord, killedByUserId: number?, now: number): {[string]: any}
	local eligible = {}
	local brain = record.Brain
	if brain ~= nil then
		for _, entry in ipairs(brain:GetEligibleContributors(now)) do
			if typeof(entry) == "table" then
				table.insert(eligible, {
					UserId = tonumber(entry.UserId) or 0,
					Damage = tonumber(entry.Damage) or 0,
					LastContributionAt = tonumber(entry.LastContributionAt) or now,
				})
			end
		end
	end

	return {
		MobId = record.MobId,
		MobDefId = record.MobDefId,
		MobDef = record.MobDef,
		ZoneId = record.ZoneId,
		KilledAt = now,
		KilledByUserId = killedByUserId,
		Eligible = eligible,
	}
end

function MobService:_resolveMobDeath(record: MobRuntimeRecord, killerPlayer: Player?, _reason: string, now: number?)
	if record.ClientState.Alive == false or record.ResolvingDeath then
		return
	end

	record.ResolvingDeath = true
	self:_applyDeathState(record)

	local timestamp = if ValidationUtil.isFiniteNumber(now) then now else os.clock()

	if record.Brain ~= nil then
		record.Brain:MarkDead(timestamp)
	end

	local killerUserId = if killerPlayer ~= nil then killerPlayer.UserId else nil
	local contributionSnapshot = self:_buildContributionSnapshot(record, killerUserId, timestamp)

	local rewardService = self._rewardService
	if rewardService ~= nil then
		local ok, err = pcall(function()
			rewardService:GrantMobKillRewards(record.MobId, contributionSnapshot)
		end)
		if not ok then
			warn(string.format("[MobService] Reward grant failed for %s: %s", record.MobId, tostring(err)))
		end
	end

	self:_clearAllAttackers(record)

	if record.Brain ~= nil then
		record.Brain:Destroy()
		record.Brain = nil
	end

	if record.Model ~= nil then
		record.Model:Destroy()
		record.Model = nil
	end

	local respawnDelay = tonumber(record.MobDef.RespawnDelay) or self._config.DefaultRespawnDelaySeconds
	record.ResolvingDeath = false
	self:_scheduleRespawn(record, respawnDelay)
end

function MobService:_clearAllAttackers(record: MobRuntimeRecord)
	for player in pairs(record.Attackers) do
		if record.Brain ~= nil then
			record.Brain:RemoveAttacker(player)
		end

		local userBucket = self._attackerMobIdsByUserId[player.UserId]
		if userBucket ~= nil then
			userBucket[record.MobId] = nil
			if next(userBucket) == nil then
				self._attackerMobIdsByUserId[player.UserId] = nil
			end
		end
	end

	table.clear(record.Attackers)
end

function MobService:_clearPlayerAsAttacker(player: Player)
	local mobIds = self._attackerMobIdsByUserId[player.UserId]
	if mobIds == nil then
		return
	end

	for mobId in pairs(mobIds) do
		local record = self._mobById[mobId]
		if record ~= nil then
			record.Attackers[player] = nil
			if record.Brain ~= nil then
				record.Brain:RemoveAttacker(player)
			end
		end
	end

	self._attackerMobIdsByUserId[player.UserId] = nil
end

function MobService:_isMobTargetValid(record: MobRuntimeRecord, player: Player): boolean
	if record.ClientState.Alive == false or record.ClientState.Attackable == false then
		return false
	end
	if not ValidationUtil.isPlayer(player) then
		return false
	end
	if resolveCharacterHumanoid(player) == nil then
		return false
	end

	local zoneService = self._zoneService
	if zoneService ~= nil then
		local mobProxy = {
			AllowedZoneId = record.ZoneId,
			Position = record.ClientState.Position,
		}
		local valid = zoneService:IsMobTargetValidForZone(mobProxy, player)
		if not valid then
			return false
		end
	end

	return true
end

function MobService:_executeMobAttack(record: MobRuntimeRecord, player: Player, _now: number): boolean
	if self._config.AllowMobAttacksOnPlayers ~= true then
		return true
	end

	if not self:_isMobTargetValid(record, player) then
		return false
	end

	local humanoid = resolveCharacterHumanoid(player)
	if humanoid == nil then
		return false
	end

	local damage = tonumber(record.MobDef.Damage) or 0
	if damage <= 0 then
		return true
	end

	humanoid:TakeDamage(damage)
	return true
end

function MobService:_isRoamStepPositionValid(record: MobRuntimeRecord, candidateXZ: Vector2): boolean
	local zoneId = record.ZoneId
	local isPointXZInZone = ZoneQueryHelper.IsPointXZInZone
	if typeof(isPointXZInZone) == "function" then
		if not isPointXZInZone(candidateXZ, zoneId, self._config.ZoneContainmentPadding) then
			return false
		end
	else
		local worldPositionFallback = vector3FromXZ(candidateXZ, record.ServerState.GroundY)
		if not self:_isPositionInsideZone(zoneId, worldPositionFallback) then
			return false
		end
	end

	local worldPosition = vector3FromXZ(candidateXZ, record.ServerState.GroundY)
	if self:_isPositionBlocked(zoneId, worldPosition, self._config.RoamCollisionRadius, self._config.RoamCollisionHeight) then
		return false
	end

	return true
end

function MobService:_isRoamDestinationValid(record: MobRuntimeRecord, currentXZ: Vector2, candidateXZ: Vector2): boolean
	local minTravelDistance = self._roamMinTravelDistanceStuds
	if minTravelDistance > 0 then
		local travelDelta = candidateXZ - currentXZ
		if travelDelta:Dot(travelDelta) < self._roamMinTravelDistanceStudsSq then
			return false
		end
	end

	if not self:_isRoamStepPositionValid(record, candidateXZ) then
		return false
	end

	local worldPosition = vector3FromXZ(candidateXZ, record.ServerState.GroundY)
	return not self:_isPositionTooCloseToMob(
		record.ZoneId,
		worldPosition,
		self._config.RoamSeparationRadius,
		record.MobId,
		nil
	)
end

function MobService:_getNearestAliveMobDistanceXZ(record: MobRuntimeRecord, candidateXZ: Vector2): number
	local zoneSet = self._mobIdsByZone[record.ZoneId]
	if zoneSet == nil then
		return math.huge
	end

	local nearestDistanceSq = math.huge
	for mobId in pairs(zoneSet) do
		if mobId ~= record.MobId then
			local otherRecord = self._mobById[mobId]
			if otherRecord ~= nil and otherRecord.ClientState.Alive == true then
				local delta = candidateXZ - otherRecord.ServerState.PositionXZ
				local distanceSq = delta:Dot(delta)
				if distanceSq > 1e-6 and distanceSq < nearestDistanceSq then
					nearestDistanceSq = distanceSq
				end
			end
		end
	end

	if nearestDistanceSq == math.huge then
		return math.huge
	end

	return math.sqrt(nearestDistanceSq)
end

function MobService:_sampleLocalRoamDestinationXZ(record: MobRuntimeRecord, currentXZ: Vector2): Vector2?
	local minTravel = self._roamMinTravelDistanceStuds
	local maxTravel = self._roamMaxTravelDistanceStuds
	if maxTravel <= 0 then
		return nil
	end

	local angle = self._rng:NextNumber(0, math.pi * 2)
	local distance = self._rng:NextNumber(minTravel, maxTravel)
	local offset = Vector2.new(math.cos(angle), math.sin(angle)) * distance
	local candidate = currentXZ + offset

	local clampXZToZone = ZoneQueryHelper.ClampXZToZone
	if typeof(clampXZToZone) == "function" then
		return clampXZToZone(candidate, record.ZoneId, self._config.RoamDestinationInsetStuds)
	end

	return candidate
end

function MobService:_scoreRoamDestinationXZ(record: MobRuntimeRecord, currentXZ: Vector2, candidateXZ: Vector2): number
	local travelDistance = (candidateXZ - currentXZ).Magnitude
	local travelScore = math.clamp(travelDistance * self._roamTravelScoreDistanceStudsInv, 0, 1)

	local nearestMobDistance = self:_getNearestAliveMobDistanceXZ(record, candidateXZ)
	local peerSpacingScore = math.clamp(nearestMobDistance / self._roamDesiredPeerDistance, 0, 1.5)

	local randomNoise = self._rng:NextNumber(0, 0.2)
	return (peerSpacingScore * 1.5) + (travelScore * 0.75) + randomNoise
end

function MobService:_sampleRoamDestinationXZ(record: MobRuntimeRecord, currentXZ: Vector2): Vector2?
	local samplePointInZone = ZoneQueryHelper.SampleRandomPointXZInZone
	local attemptCount = self._roamDestinationSampleAttempts
	local localBias = self._roamLocalDestinationBias

	local bestCandidate: Vector2? = nil
	local bestScore = -math.huge

	for _ = 1, attemptCount do
		local candidateXZ: Vector2? = nil
		if self._rng:NextNumber() <= localBias then
			candidateXZ = self:_sampleLocalRoamDestinationXZ(record, currentXZ)
		end
		if candidateXZ == nil and typeof(samplePointInZone) == "function" then
			candidateXZ = samplePointInZone(record.ZoneId, self._rng, self._config.RoamDestinationInsetStuds)
		end

		if candidateXZ ~= nil and self:_isRoamDestinationValid(record, currentXZ, candidateXZ) then
			local score = self:_scoreRoamDestinationXZ(record, currentXZ, candidateXZ)
			if score > bestScore then
				bestScore = score
				bestCandidate = candidateXZ
			end
		end
	end

	return bestCandidate
end

function MobService:_getLocalSeparationOffsetXZ(record: MobRuntimeRecord, currentXZ: Vector2): Vector2?
	local separationRadius = self._config.RoamSeparationRadius
	if separationRadius <= 0 then
		return nil
	end

	local zoneSet = self._mobIdsByZone[record.ZoneId]
	if zoneSet == nil then
		return nil
	end

	local radiusSq = separationRadius * separationRadius
	local push = Vector2.zero
	for mobId in pairs(zoneSet) do
		if mobId ~= record.MobId then
			local otherRecord = self._mobById[mobId]
			if otherRecord ~= nil and otherRecord.ClientState.Alive == true then
				local delta = currentXZ - otherRecord.ServerState.PositionXZ
				local distSq = delta:Dot(delta)
				if distSq > 1e-6 and distSq < radiusSq then
					local distance = math.sqrt(distSq)
					local strength = (separationRadius - distance) / separationRadius
					push += (delta / distance) * strength
				end
			end
		end
	end

	local pushSq = push:Dot(push)
	if pushSq <= 1e-8 then
		return nil
	end

	local weight = math.max(0, self._config.RoamSeparationWeight)
	if weight <= 0 then
		return nil
	end

	return push * (weight / math.sqrt(pushSq))
end

function MobService:_stepRoam(record: MobRuntimeRecord, now: number, dt: number)
	local serverState = record.ServerState
	local runtime = {
		State = serverState.RoamState,
		StateUntil = serverState.RoamStateUntil,
		DestinationXZ = serverState.RoamDestinationXZ,
		FacingXZ = serverState.FacingXZ,
		Speed = serverState.MoveSpeed,
	}

	local result = RoamBehavior.Step({
		Now = now,
		Dt = dt,
		Runtime = runtime,
		PositionXZ = serverState.PositionXZ,
		IdleDurationMin = self._config.RoamIdleMinSeconds,
		IdleDurationMax = self._config.RoamIdleMaxSeconds,
		MoveDurationMin = self._config.RoamMoveDurationMinSeconds,
		MoveDurationMax = self._config.RoamMoveDurationMaxSeconds,
		ArriveDistance = self._config.RoamArrivalDistanceStuds,
		Rng = self._rng,
		SampleDestination = function(currentXZ: Vector2)
			return self:_sampleRoamDestinationXZ(record, currentXZ)
		end,
		IsValidPosition = function(candidateXZ: Vector2)
			return self:_isRoamStepPositionValid(record, candidateXZ)
		end,
		GetSeparationOffset = function(currentXZ: Vector2)
			return self:_getLocalSeparationOffsetXZ(record, currentXZ)
		end,
	})

	serverState.RoamState = result.State
	serverState.RoamStateUntil = result.StateUntil
	serverState.RoamDestinationXZ = result.DestinationXZ
	serverState.PositionXZ = result.PositionXZ
	serverState.FacingXZ = result.FacingXZ

	local changed = false
	local clientState = record.ClientState
	if clientState.BrainState ~= result.State then
		clientState.BrainState = result.State
		changed = true
	end
	if clientState.TargetUserId ~= nil then
		clientState.TargetUserId = nil
		changed = true
	end

	local worldPosition = vector3FromXZ(result.PositionXZ, serverState.GroundY)
	if self:_setAuthoritativePosition(record, worldPosition, facingVector3FromVector2(result.FacingXZ)) then
		changed = true
	end

	if changed then
		self:_bumpRevision(record)
	end

	self:_syncModelToAuthoritative(record)
	serverState.LastStateSyncAt = now
end

function MobService:StepMobSimulation(now: number, dt: number)
	self._simulationAccumulator += math.max(dt, 0)
	local stepInterval = self._config.SimulationStepIntervalSeconds
	local steps = 0
	if next(self._activePlayers) == nil then
		if self._simulationAccumulator > stepInterval then
			self._simulationAccumulator = stepInterval
		end
		return
	end

	while self._simulationAccumulator >= stepInterval and steps < self._config.MaxSimulationStepsPerTick do
		self._simulationAccumulator -= stepInterval
		local stepNow = now - self._simulationAccumulator
		self:_refreshZonePopulation(stepNow)
		self:_processSpawnQueue(stepNow)

		for _, record in pairs(self._mobById) do
			if record.ClientState.Alive then
				if self:_hasAttackers(record) and record.Brain ~= nil then
					local ok, err = pcall(function()
						record.Brain:Step(stepNow, stepInterval)
					end)
					if not ok then
						warn(string.format("[MobService] Brain step failed for %s: %s", record.MobId, tostring(err)))
					end

					self:_syncStateFromModelAndBrain(record, stepNow)
				else
					self:_stepRoam(record, stepNow, stepInterval)
				end
			end
		end

		steps += 1
	end

	if self._simulationAccumulator > stepInterval then
		self._simulationAccumulator = stepInterval
	end
end

function MobService:_serializeMobAddState(mobId: string): {[string]: any}?
	local record = self._mobById[mobId]
	if record == nil then
		return nil
	end
	if record.ClientState.Alive ~= true then
		return nil
	end
	if not ValidationUtil.isNonEmptyString(record.ClientState.MobDefId) then
		return nil
	end
	return StateSerializer.SerializeAdd(record.ClientState)
end

function MobService:_serializeMobUpdateState(mobId: string): {[string]: any}?
	local record = self._mobById[mobId]
	if record == nil then
		return nil
	end
	if record.ClientState.Alive ~= true then
		return nil
	end
	if not ValidationUtil.isNonEmptyString(record.ClientState.MobDefId) then
		return nil
	end
	return StateSerializer.SerializeUpdate(record.ClientState)
end

function MobService:_getRelevantMobIdsForPlayer(
	player: Player,
	aliveMobIdsByZone: {[string]: {string}}?
): {string}
	local zoneId = self:_resolveReplicationZoneIdForPlayer(player)
	if zoneId == nil then
		return EMPTY_MOB_ID_LIST
	end

	local distanceLimit = self._config.ReplicationDistanceLimitStuds
	if distanceLimit <= 0 then
		if aliveMobIdsByZone ~= nil then
			local cachedAlive = aliveMobIdsByZone[zoneId]
			if cachedAlive ~= nil then
				return cachedAlive
			end
			local builtAlive = self:_buildAliveMobIdsForZone(zoneId)
			aliveMobIdsByZone[zoneId] = builtAlive
			return builtAlive
		end
		return self:_buildAliveMobIdsForZone(zoneId)
	end

	local sortedZoneMobIds = self:_getSortedMobIdsForZone(zoneId)
	if #sortedZoneMobIds == 0 then
		return EMPTY_MOB_ID_LIST
	end

	local playerPosition = if distanceLimit > 0 then resolveCharacterRootPosition(player) else nil
	local limitSquared = distanceLimit * distanceLimit

	local mobIds = table.create(#sortedZoneMobIds)
	for _, mobId in ipairs(sortedZoneMobIds) do
		local record = self._mobById[mobId]
		if record ~= nil and record.ClientState.Alive == true then
			if playerPosition ~= nil and distanceLimit > 0 then
				local delta = record.ClientState.Position - playerPosition
				if delta:Dot(delta) <= limitSquared then
					table.insert(mobIds, mobId)
				end
			else
				table.insert(mobIds, mobId)
			end
		end
	end

	return mobIds
end

function MobService:FlushReplicationBuffers(now: number, dt: number)
	if next(self._activePlayers) == nil then
		self._replicationAccumulator = 0
		return
	end

	self._replicationAccumulator += math.max(dt, 0)
	local flushInterval = self._config.ReplicationFlushIntervalSeconds
	if self._replicationAccumulator < flushInterval then
		return
	end

	while self._replicationAccumulator >= flushInterval do
		self._replicationAccumulator -= flushInterval
		local zoneAliveCache = self._zoneAliveCacheScratch
		table.clear(zoneAliveCache)

		for player in pairs(self._activePlayers) do
			local relevantMobIds = self:_getRelevantMobIdsForPlayer(player, zoneAliveCache)
			local packet = self._replicationBuffer:BuildPacketForPlayer(
				player.UserId,
				now,
				relevantMobIds,
				self._serializeAddCallback,
				self._serializeUpdateCallback
			)
			if packet ~= nil then
				self.Client.MobStateDelta:Fire(player, packet)
			end
		end
	end
end

function MobService:GetMobById(mobId: string): MobRuntimeRecord?
	if not ValidationUtil.isNonEmptyString(mobId) then
		return nil
	end
	return self._mobById[mobId]
end

function MobService:IsMobAttackable(mobId: string): (boolean, string?)
	local record = self:GetMobById(mobId)
	if record == nil then
		return false, "MobNotFound"
	end
	if record.ClientState.Alive == false then
		return false, "MobDead"
	end
	if record.ClientState.Attackable == false then
		return false, "MobNotAttackable"
	end
	return true, nil
end

function MobService:RegisterAttacker(mobId: string, player: Player): (boolean, string?)
	if not ValidationUtil.isPlayer(player) then
		return false, "InvalidPlayer"
	end

	local record = self:GetMobById(mobId)
	if record == nil then
		return false, "MobNotFound"
	end
	if not record.ClientState.Alive or not record.ClientState.Attackable then
		return false, "MobNotAttackable"
	end
	if not self:_isMobTargetValid(record, player) then
		return false, "InvalidTargetForZone"
	end

	record.Attackers[player] = true

	local bucket = self._attackerMobIdsByUserId[player.UserId]
	if bucket == nil then
		bucket = {}
		self._attackerMobIdsByUserId[player.UserId] = bucket
	end
	bucket[mobId] = true

	if record.Brain ~= nil then
		record.Brain:AddAttacker(player)
		self:_syncStateFromModelAndBrain(record, os.clock())
	end

	return true, nil
end

function MobService:UnregisterAttacker(mobId: string, player: Player): (boolean, string?)
	if not ValidationUtil.isPlayer(player) then
		return false, "InvalidPlayer"
	end

	local record = self:GetMobById(mobId)
	if record == nil then
		return false, "MobNotFound"
	end

	record.Attackers[player] = nil
	local bucket = self._attackerMobIdsByUserId[player.UserId]
	if bucket ~= nil then
		bucket[mobId] = nil
		if next(bucket) == nil then
			self._attackerMobIdsByUserId[player.UserId] = nil
		end
	end

	if record.Brain ~= nil then
		record.Brain:RemoveAttacker(player)
		self:_syncStateFromModelAndBrain(record, os.clock())
	end

	return true, nil
end

function MobService:ApplyDamage(mobId: string, player: Player, amount: number, _sourceMeta: any): (boolean, string?)
	if not ValidationUtil.isPlayer(player) then
		return false, "InvalidPlayer"
	end

	local numericAmount = tonumber(amount)
	if not ValidationUtil.isFiniteNumber(numericAmount) then
		return false, "InvalidDamageAmount"
	end
	if numericAmount < self._config.MinDamagePerHit then
		return false, "DamageTooLow"
	end
	if numericAmount > self._config.MaxDamagePerHit then
		return false, "DamageTooHigh"
	end

	local record = self:GetMobById(mobId)
	if record == nil then
		return false, "MobNotFound"
	end
	if not record.ClientState.Alive or not record.ClientState.Attackable then
		return false, "MobNotAttackable"
	end
	if not self:_isMobTargetValid(record, player) then
		return false, "InvalidTargetForZone"
	end

	local registered = self:RegisterAttacker(mobId, player)
	if not registered then
		return false, "UnableToRegisterAttacker"
	end

	if record.Brain ~= nil then
		record.Brain:AddDamage(player.UserId, numericAmount, os.clock())
	end

	self:_setHealth(record, record.ClientState.HP - numericAmount)

	if record.ClientState.HP <= 0 then
		self:_resolveMobDeath(record, player, "DamageDepleted", os.clock())
	end

	return true, nil
end

function MobService:Destroy()
	local gameplayManager = self._gameplayManager
	if gameplayManager ~= nil then
		pcall(function()
			gameplayManager:UnregisterSystem(self._gameplaySystemName)
		end)
	end

	if self._serviceJanitor ~= nil then
		self._serviceJanitor:Cleanup()
	end

	for _, record in pairs(self._mobById) do
		record.Janitor:Cleanup()
	end

	if self._replicationBuffer ~= nil then
		self._replicationBuffer:Destroy()
	end
	MapCollisionHelper.ResetAll()

	table.clear(self._mobById)
	table.clear(self._mobIdsByZone)
	table.clear(self._sortedMobIdsCacheByZone)
	table.clear(self._sortedMobIdsDirtyByZone)
	table.clear(self._attackerMobIdsByUserId)
	table.clear(self._activePlayers)
	table.clear(self._spawnQueue)
	table.clear(self._spawnQueueByMobId)
	table.clear(self._zonePopulationById)
	table.clear(self._zoneAliveCacheScratch)
	self._spawnQueueHead = 1
	self._spawnQueueTail = 0
	self._lastZonePopulationRefreshAt = 0
end

return MobService
