--!strict

local Players = game:GetService("Players")
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

type ZoneServiceLike = {
	GetPlayerZone: (self: ZoneServiceLike, player: Player) -> (string?, string?),
	IsMobTargetValidForZone: (self: ZoneServiceLike, mob: any, player: Player) -> (boolean, string?),
}

type RewardServiceLike = {
	GrantMobKillRewards: (self: RewardServiceLike, mobId: string, contributionSnapshot: {[string]: any}) -> any,
}

type GameplayManagerServiceLike = {
	RegisterSystem: (self: GameplayManagerServiceLike, name: string, system: {[string]: any}) -> (),
	UnregisterSystem: (self: GameplayManagerServiceLike, name: string) -> (),
}

type MobClientState = {
	MobId: string,
	MobDefId: string,
	ZoneId: string,
	SpawnIndex: number,
	Position: Vector3,
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
	RespawnToken: {[string]: any}?,
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
	self._attackerMobIdsByUserId = {} :: {[number]: {[string]: true}}

	self._simulationAccumulator = 0
	self._replicationAccumulator = 0
	self._positionThresholdSquared = Config.PositionChangeThresholdStuds * Config.PositionChangeThresholdStuds
	self._warnedNoSpawnPointsByZone = {} :: {[string]: true}

	self._serviceJanitor = Janitor.new()
	self._rng = Random.new()
	self._replicationBuffer = ReplicationBuffer.new({
		MaxAddsPerFlushPerPlayer = Config.MaxAddsPerFlushPerPlayer,
		MaxUpdatesPerFlushPerPlayer = Config.MaxUpdatesPerFlushPerPlayer,
		MaxRemovesPerFlushPerPlayer = Config.MaxRemovesPerFlushPerPlayer,
		MaxTotalMobEntriesPerFlush = Config.MaxTotalMobEntriesPerFlush,
	})

	print("Mob Service Init")
end

function MobService:KnitStart()
	self._zoneService = Knit.GetService("ZoneService") :: ZoneServiceLike
	self._rewardService = Knit.GetService("RewardService") :: RewardServiceLike
	self._gameplayManager = Knit.GetService("GameplayManagerService") :: GameplayManagerServiceLike
	self._mobContainer = ModelResolver.ResolveSpawnContainer(Workspace, self._config.SpawnRootPath)

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
	self._replicationBuffer:ResetPlayer(player.UserId)
end

function MobService:_onPlayerRemoving(player: Player)
	self:_clearPlayerAsAttacker(player)
	self._replicationBuffer:ResetPlayer(player.UserId)
end

function MobService:_registerMobInZone(zoneId: string, mobId: string)
	local zoneSet = self._mobIdsByZone[zoneId]
	if zoneSet == nil then
		zoneSet = {}
		self._mobIdsByZone[zoneId] = zoneSet
	end
	zoneSet[mobId] = true
end

function MobService:_unregisterMobFromZone(zoneId: string, mobId: string)
	local zoneSet = self._mobIdsByZone[zoneId]
	if zoneSet == nil then
		return
	end
	zoneSet[mobId] = nil
	if next(zoneSet) == nil then
		self._mobIdsByZone[zoneId] = nil
	end
end

function MobService:_newClientState(mobId: string, zoneId: string, spawnIndex: number, spawnOrigin: Vector3): MobClientState
	return {
		MobId = mobId,
		MobDefId = "",
		ZoneId = zoneId,
		SpawnIndex = spawnIndex,
		Position = spawnOrigin,
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

function MobService:_syncStateFromModelAndBrain(record: MobRuntimeRecord, now: number)
	local clientState = record.ClientState
	local changed = false

	local nextPosition, nextFacing = resolveModelPositionAndFacing(record.Model, clientState.Position, clientState.Facing)
	if (nextPosition - clientState.Position).Magnitude^2 > self._positionThresholdSquared then
		clientState.Position = nextPosition
		changed = true
	end
	if self:_isFacingDifferent(clientState.Facing, nextFacing) then
		clientState.Facing = nextFacing
		changed = true
	end

	local brain = record.Brain
	if brain ~= nil then
		local brainState = brain:GetState()
		if brainState ~= clientState.BrainState then
			clientState.BrainState = brainState
			changed = true
		end

		local targetPlayer = brain:GetCurrentTarget()
		local targetUserId = if targetPlayer ~= nil then targetPlayer.UserId else nil
		if targetUserId ~= clientState.TargetUserId then
			clientState.TargetUserId = targetUserId
			changed = true
		end
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

	local nextPosition, nextFacing = resolveModelPositionAndFacing(record.Model, clientState.Position, clientState.Facing)
	if (nextPosition - clientState.Position).Magnitude^2 > self._positionThresholdSquared then
		clientState.Position = nextPosition
		changed = true
	end
	if self:_isFacingDifferent(clientState.Facing, nextFacing) then
		clientState.Facing = nextFacing
		changed = true
	end

	if changed then
		self:_bumpRevision(record)
	end
end

function MobService:_applyDeathState(record: MobRuntimeRecord)
	local clientState = record.ClientState
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

	if changed then
		self:_bumpRevision(record)
	end
end

function MobService:_resolveSpawnOriginsForZone(zoneId: string, zoneDef: {[string]: any}?): {Vector3}
	local spawnOrigins = {}
	if typeof(zoneDef) == "table" and typeof(zoneDef.SpawnPoints) == "table" then
		for _, spawnOrigin in ipairs(zoneDef.SpawnPoints) do
			if typeof(spawnOrigin) == "Vector3" then
				table.insert(spawnOrigins, spawnOrigin)
			end
		end
	end

	if #spawnOrigins > 0 then
		return spawnOrigins
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

	local fallbackOrigins = buildFallbackSpawnPointsFromBounds(
		markerBounds,
		math.max(1, self._config.FallbackSpawnPointsPerZone),
		math.max(0, self._config.FallbackSpawnInsetStuds),
		self._config.FallbackSpawnHeightOffset
	)
	if #fallbackOrigins == 0 then
		if self._warnedNoSpawnPointsByZone[zoneId] == nil then
			self._warnedNoSpawnPointsByZone[zoneId] = true
			warn(string.format("[MobService] Unable to build fallback spawn points for zone '%s'", zoneId))
		end
		return spawnOrigins
	end

	return fallbackOrigins
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
								LastStateSyncAt = 0,
								LastDamagedAt = 0,
								RespawnAt = nil,
							},
							Attackers = {},
							RespawnToken = nil,
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
							self._mobById[mobId] = nil
						end)

						self._mobById[mobId] = record
						self:_registerMobInZone(zoneId, mobId)

						local spawned, spawnReason = self:_spawnMob(record)
						if not spawned then
							warn(string.format("[MobService] Initial spawn failed for %s: %s", mobId, tostring(spawnReason)))
							self:_scheduleRespawn(record, self._config.RespawnFailureRetrySeconds)
						end
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
		record.ServerState.SpawnOrigin
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
	local token = record.RespawnToken
	if token ~= nil then
		token.Cancelled = true
		record.RespawnToken = nil
	end
end

function MobService:_scheduleRespawn(record: MobRuntimeRecord, delaySeconds: number)
	self:_cancelRespawn(record)

	local resolvedDelay = math.max(0.1, delaySeconds)
	local token = {
		Cancelled = false,
	}
	record.RespawnToken = token
	record.ServerState.RespawnAt = os.clock() + resolvedDelay

	task.delay(resolvedDelay, function()
		if token.Cancelled then
			return
		end
		if record.Janitor == nil then
			return
		end

		record.RespawnToken = nil
		local spawned, reason = self:_spawnMob(record)
		if not spawned then
			warn(string.format("[MobService] Respawn failed for %s: %s", record.MobId, tostring(reason)))
			self:_scheduleRespawn(record, self._config.RespawnFailureRetrySeconds)
		end
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

function MobService:StepMobSimulation(now: number, dt: number)
	self._simulationAccumulator += math.max(dt, 0)
	local stepInterval = self._config.SimulationStepIntervalSeconds
	local steps = 0

	while self._simulationAccumulator >= stepInterval and steps < self._config.MaxSimulationStepsPerTick do
		self._simulationAccumulator -= stepInterval
		local stepNow = now - self._simulationAccumulator

		for _, record in pairs(self._mobById) do
			if record.ClientState.Alive and record.Brain ~= nil then
				local ok, err = pcall(function()
					record.Brain:Step(stepNow)
				end)
				if not ok then
					warn(string.format("[MobService] Brain step failed for %s: %s", record.MobId, tostring(err)))
				end

				self:_syncStateFromModelAndBrain(record, stepNow)
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
	return StateSerializer.SerializeAdd(record.ClientState)
end

function MobService:_serializeMobUpdateState(mobId: string): {[string]: any}?
	local record = self._mobById[mobId]
	if record == nil then
		return nil
	end
	return StateSerializer.SerializeUpdate(record.ClientState)
end

function MobService:_getRelevantMobIdsForPlayer(player: Player): {string}
	local zoneId: string? = nil
	local zoneService = self._zoneService
	if zoneService ~= nil then
		local resolvedZoneId = zoneService:GetPlayerZone(player)
		if ValidationUtil.isNonEmptyString(resolvedZoneId) then
			zoneId = resolvedZoneId
		end
	end

	if zoneId == nil then
		return {}
	end

	local zoneSet = self._mobIdsByZone[zoneId]
	if zoneSet == nil then
		return {}
	end

	local distanceLimit = self._config.ReplicationDistanceLimitStuds
	local playerPosition = if distanceLimit > 0 then resolveCharacterRootPosition(player) else nil
	local limitSquared = distanceLimit * distanceLimit

	local mobIds = {}
	for mobId in pairs(zoneSet) do
		local record = self._mobById[mobId]
		if record ~= nil then
			if playerPosition ~= nil and distanceLimit > 0 then
				if (record.ClientState.Position - playerPosition).Magnitude^2 <= limitSquared then
					table.insert(mobIds, mobId)
				end
			else
				table.insert(mobIds, mobId)
			end
		end
	end

	table.sort(mobIds)
	return mobIds
end

function MobService:FlushReplicationBuffers(now: number, dt: number)
	self._replicationAccumulator += math.max(dt, 0)
	local flushInterval = self._config.ReplicationFlushIntervalSeconds
	if self._replicationAccumulator < flushInterval then
		return
	end

	while self._replicationAccumulator >= flushInterval do
		self._replicationAccumulator -= flushInterval

		for _, player in ipairs(Players:GetPlayers()) do
			local relevantMobIds = self:_getRelevantMobIdsForPlayer(player)
			local packet = self._replicationBuffer:BuildPacketForPlayer(
				player.UserId,
				now,
				relevantMobIds,
				function(mobId: string)
					return self:_serializeMobAddState(mobId)
				end,
				function(mobId: string)
					return self:_serializeMobUpdateState(mobId)
				end
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

	table.clear(self._mobById)
	table.clear(self._mobIdsByZone)
	table.clear(self._attackerMobIdsByUserId)
end

return MobService
