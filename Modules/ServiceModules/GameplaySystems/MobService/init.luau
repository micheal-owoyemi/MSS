--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local ValidationUtil = require(ReplicatedStorage.Util.ValidationUtil)
local MobDefs = require(ReplicatedStorage.Configs.MobDefs)
local ZoneDefs = require(ReplicatedStorage.Configs.ZoneDefs)

local Config = require(script.Config)
local ModelResolver = require(script.ModelResolver)

local ServerStorage = game:GetService("ServerStorage")
local ServiceModules = ServerStorage:WaitForChild("ServiceModules")
local SupportersFolder = ServiceModules:WaitForChild("Supporters")
local MobBrain = require(SupportersFolder:WaitForChild("MobBrain"))

type ZoneServiceLike = {
	IsMobTargetValidForZone: (self: ZoneServiceLike, mob: any, player: Player) -> (boolean, string?),
}

type RewardServiceLike = {
	GrantMobKillRewards: (self: RewardServiceLike, mobId: string, contributionSnapshot: {[string]: any}) -> any,
}

type SpawnSlot = {
	ZoneId: string,
	SpawnIndex: number,
	SpawnOrigin: Vector3,
}

type MobRuntimeRecord = {
	MobId: string,
	ZoneId: string,
	SpawnIndex: number,
	SpawnOrigin: Vector3,
	MobDefId: string,
	MobDef: {[string]: any},
	Model: Model?,
	Brain: any?,
	Alive: boolean,
	Attackable: boolean,
	Health: number,
	MaxHealth: number,
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
	if humanoid == nil then
		return nil
	end

	if humanoid.Health <= 0 then
		return nil
	end

	return humanoid
end

local function resolveModelPosition(model: Model?, fallback: Vector3): Vector3
	if model == nil then
		return fallback
	end

	if model.PrimaryPart ~= nil then
		return model.PrimaryPart.Position
	end

	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart.Position
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant.Position
		end
	end

	return fallback
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

function MobService:KnitInit()
	self._config = Config
	self._zoneDefs = ZoneDefs
	self._mobDefs = MobDefs
	self._zoneService = nil :: ZoneServiceLike?
	self._rewardService = nil :: RewardServiceLike?
	self._serviceJanitor = Janitor.new()
	self._mobContainer = nil :: Instance?
	self._mobById = {} :: {[string]: MobRuntimeRecord}
	self._spawnSlotsByMobId = {} :: {[string]: SpawnSlot}
	self._attackerMobIdsByUserId = {} :: {[number]: {[string]: true}}
	self._accumulator = 0
	self._rng = Random.new()
end

function MobService:KnitStart()
	local okZone, zoneService = pcall(function()
		return Knit.GetService("ZoneService")
	end)
	if okZone then
		self._zoneService = zoneService :: ZoneServiceLike
	end

	local okReward, rewardService = pcall(function()
		return Knit.GetService("RewardService")
	end)
	if okReward then
		self._rewardService = rewardService :: RewardServiceLike
	else
		warn(string.format("[MobService] RewardService unavailable at start: %s", tostring(rewardService)))
	end

	self._mobContainer = ModelResolver.ResolveSpawnContainer(Workspace, self._config.SpawnRootPath)

	self._serviceJanitor:Add(Players.PlayerRemoving:Connect(function(player: Player)
		self:_clearPlayerAsAttacker(player)
	end), "Disconnect", "PlayerRemovingConnection")

	self._serviceJanitor:Add(RunService.Heartbeat:Connect(function(dt: number)
		self:_onHeartbeat(dt)
	end), "Disconnect", "HeartbeatConnection")

	self:_initializeSpawnSlots()
end

function MobService:_emitMobDelta(payload: {[string]: any})
	self.Client.MobStateDelta:FireAll(payload)
end

function MobService:_initializeSpawnSlots()
	for zoneId, zoneDef in pairs(self._zoneDefs) do
		if typeof(zoneDef) == "table" and typeof(zoneDef.SpawnPoints) == "table" then
			for spawnIndex, spawnOrigin in ipairs(zoneDef.SpawnPoints) do
				if typeof(spawnOrigin) == "Vector3" then
					local mobId = string.format("%s:%d", zoneId, spawnIndex)
					if self._mobById[mobId] == nil then
						local recordJanitor = Janitor.new()
						local record: MobRuntimeRecord = {
							MobId = mobId,
							ZoneId = zoneId,
							SpawnIndex = spawnIndex,
							SpawnOrigin = spawnOrigin,
							MobDefId = "",
							MobDef = {},
							Model = nil,
							Brain = nil,
							Alive = false,
							Attackable = false,
							Health = 0,
							MaxHealth = 0,
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
							self._mobById[mobId] = nil
							self._spawnSlotsByMobId[mobId] = nil
						end)

						self._mobById[mobId] = record
						self._spawnSlotsByMobId[mobId] = {
							ZoneId = zoneId,
							SpawnIndex = spawnIndex,
							SpawnOrigin = spawnOrigin,
						}

						local spawned, spawnReason = self:_spawnMob(record)
						if not spawned then
							warn(string.format("[MobService] Initial spawn failed for %s: %s", mobId, tostring(spawnReason)))
							self:_scheduleRespawn(record, self._config.RespawnFailureRetrySeconds)
						end
					end
				end
			end
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

	local model, rootPart = ModelResolver.CloneMobModel(template, self._mobContainer, record.MobId, record.ZoneId, mobDefId, record.SpawnOrigin)
	if model == nil or rootPart == nil then
		if model ~= nil then
			model:Destroy()
		end
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
	record.MaxHealth = mobDef.BaseHP
	record.Health = mobDef.BaseHP
	record.Alive = true
	record.Attackable = true
	record.ResolvingDeath = false

	record.Brain = MobBrain.new({
		MobId = record.MobId,
		Model = model,
		SpawnOrigin = record.SpawnOrigin,
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
		OnStateChanged = function(_: any, previousState: string, newState: string)
			self:_emitMobDelta({
				Type = "StateChanged",
				MobId = record.MobId,
				PreviousState = previousState,
				State = newState,
			})
		end,
		OnDeath = function(_: any, now: number)
			self:_resolveMobDeath(record, nil, "MobBrainDeath", now)
		end,
		ContributionConfig = {
			EligibilityWindowSeconds = self._config.ContributionEligibilityWindowSeconds,
			MinDamage = self._config.ContributionMinDamage,
		},
	})

	self:_emitMobDelta({
		Type = "Spawned",
		MobId = record.MobId,
		ZoneId = record.ZoneId,
		MobDefId = record.MobDefId,
		Model = record.Model,
		Health = record.Health,
		MaxHealth = record.MaxHealth,
		Attackable = true,
		Alive = true,
	})

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

	self:_emitMobDelta({
		Type = "RespawnScheduled",
		MobId = record.MobId,
		RespawnAt = os.clock() + resolvedDelay,
	})

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

function MobService:_resolveMobDeath(record: MobRuntimeRecord, killerPlayer: Player?, reason: string, now: number?)
	if record.Alive == false or record.ResolvingDeath then
		return
	end

	record.ResolvingDeath = true
	record.Alive = false
	record.Attackable = false
	record.Health = 0

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

	self:_emitMobDelta({
		Type = "Died",
		MobId = record.MobId,
		Reason = reason,
		KilledByUserId = killerUserId,
		Model = record.Model,
		Alive = false,
	})

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
	if record.Alive == false or record.Attackable == false then
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
			Position = resolveModelPosition(record.Model, record.SpawnOrigin),
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

	if humanoid.Health <= 0 then
		self:_emitMobDelta({
			Type = "Victory",
			MobId = record.MobId,
			TargetUserId = player.UserId,
		})
	end

	return true
end

function MobService:_onHeartbeat(dt: number)
	self._accumulator += dt
	if self._accumulator < self._config.StepIntervalSeconds then
		return
	end

	local now = os.clock()
	self._accumulator = 0
	for _, record in pairs(self._mobById) do
		if record.Alive and record.Brain ~= nil then
			local ok, err = pcall(function()
				record.Brain:Step(now)
			end)
			if not ok then
				warn(string.format("[MobService] Brain step failed for %s: %s", record.MobId, tostring(err)))
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
	if record.Alive == false then
		return false, "MobDead"
	end
	if record.Attackable == false then
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
	if not record.Alive or not record.Attackable then
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
	if not record.Alive or not record.Attackable then
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

	record.Health = math.max(0, record.Health - numericAmount)

	self:_emitMobDelta({
		Type = "HealthChanged",
		MobId = record.MobId,
		Health = record.Health,
		MaxHealth = record.MaxHealth,
		LastHitByUserId = player.UserId,
		Damage = numericAmount,
	})

	if record.Health <= 0 then
		self:_resolveMobDeath(record, player, "DamageDepleted", os.clock())
	end

	return true, nil
end

function MobService:Destroy()
	if self._serviceJanitor ~= nil then
		self._serviceJanitor:Cleanup()
	end

	for _, record in pairs(self._mobById) do
		record.Janitor:Cleanup()
	end

	table.clear(self._mobById)
	table.clear(self._spawnSlotsByMobId)
	table.clear(self._attackerMobIdsByUserId)
end

return MobService
