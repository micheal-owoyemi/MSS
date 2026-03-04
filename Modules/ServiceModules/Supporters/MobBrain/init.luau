--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Janitor = require(ReplicatedStorage.Packages.Janitor)

local PathingHelper = require(script.Parent.PathingHelper)
local ZoneQueryHelper = require(script.Parent.ZoneQueryHelper)

local TargetSelector = require(script.TargetSelector)
local PathRunner = require(script.PathRunner)
local AttackState = require(script.AttackState)
local ReturnState = require(script.ReturnState)
local DeathState = require(script.DeathState)
local ContributionTrackerAdapter = require(script.ContributionTrackerAdapter)

export type MobState = "Idle" | "Chase" | "Attack" | "Return" | "Dead"

local MobBrain = {}
MobBrain.__index = MobBrain

local DEFAULTS = {
	AttackRange = 10,
	AttackCooldown = 1,
	AggroLockDuration = 8,
	RepathIntervalSeconds = 0.35,
	DirectChaseDistance = 14,
	PathComputeTimeout = 2,
	MoveTimeoutSeconds = 1.25,
	ReturnThreshold = 4,
	ZonePadding = 0,
}

local function resolveHumanoid(model: Model): Humanoid?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Humanoid") then
			return descendant
		end
	end

	return nil
end

local function resolveRoot(model: Model): BasePart?
	if model.PrimaryPart ~= nil then
		return model.PrimaryPart
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

function MobBrain.new(params: {
	MobId: string,
	Model: Model,
	SpawnOrigin: Vector3?,
	AllowedZoneId: string?,
	AttackRange: number?,
	AttackCooldown: number?,
	AggroLockDuration: number?,
	RepathIntervalSeconds: number?,
	DirectChaseDistance: number?,
	PathComputeTimeout: number?,
	MoveTimeoutSeconds: number?,
	ReturnThreshold: number?,
	ZonePadding: number?,
	TargetValidator: ((brain: any, player: Player) -> boolean)?,
	AttackExecutor: ((brain: any, player: Player, now: number) -> boolean?)?,
	OnStateChanged: ((brain: any, previousState: MobState, newState: MobState) -> ())?,
	OnDeath: ((brain: any, now: number) -> ())?,
	PathingHelper: any?,
	ZoneQueryHelper: any?,
	ContributionConfig: {[string]: any}?,
}): any
	assert(params ~= nil, "MobBrain params are required")	
	assert(params.Model ~= nil, "MobBrain requires params.Model")

	local model = params.Model
	local root = resolveRoot(model)
	assert(root ~= nil, "MobBrain requires a model with a root part")

	local ownPathingHelper = params.PathingHelper == nil
	local pathingHelper = if params.PathingHelper ~= nil then params.PathingHelper else PathingHelper.new()

	local spawnOrigin = if typeof(params.SpawnOrigin) == "Vector3" then params.SpawnOrigin else root.Position

	local self = setmetatable({
		_mobId = params.MobId or model.Name,
		_model = model,
		_humanoid = resolveHumanoid(model),
		_root = root,
		_spawnOrigin = spawnOrigin,
		_allowedZoneId = params.AllowedZoneId,
		_zonePadding = if typeof(params.ZonePadding) == "number" then params.ZonePadding else DEFAULTS.ZonePadding,
		_targetValidator = params.TargetValidator,
		_attackExecutor = params.AttackExecutor,
		_onStateChanged = params.OnStateChanged,
		_onDeath = params.OnDeath,
		_state = "Idle" :: MobState,
		_attackers = {} :: {[Player]: true},
		_currentTarget = nil :: Player?,
		_aggroLockUntil = 0,
		_nextAttackAt = 0,
		_deadAt = nil,
		_attackRange = if typeof(params.AttackRange) == "number" then params.AttackRange else DEFAULTS.AttackRange,
		_attackCooldown = if typeof(params.AttackCooldown) == "number" then params.AttackCooldown else DEFAULTS.AttackCooldown,
		_aggroLockDuration = if typeof(params.AggroLockDuration) == "number" then params.AggroLockDuration else DEFAULTS.AggroLockDuration,
		_repathIntervalSeconds = if typeof(params.RepathIntervalSeconds) == "number" then params.RepathIntervalSeconds else DEFAULTS.RepathIntervalSeconds,
		_directChaseDistance = if typeof(params.DirectChaseDistance) == "number" then params.DirectChaseDistance else DEFAULTS.DirectChaseDistance,
		_pathComputeTimeout = if typeof(params.PathComputeTimeout) == "number" then params.PathComputeTimeout else DEFAULTS.PathComputeTimeout,
		_moveTimeoutSeconds = if typeof(params.MoveTimeoutSeconds) == "number" then params.MoveTimeoutSeconds else DEFAULTS.MoveTimeoutSeconds,
		_returnThreshold = if typeof(params.ReturnThreshold) == "number" then params.ReturnThreshold else DEFAULTS.ReturnThreshold,
		_pathingHelper = pathingHelper,
		_zoneQueryHelper = params.ZoneQueryHelper or ZoneQueryHelper,
		_ownsPathingHelper = ownPathingHelper,
		_pathToken = pathingHelper:CreateCancelToken(),
		_pathKey = string.format("Mob:%s", params.MobId or model.Name),
		_contributionTracker = ContributionTrackerAdapter.new(params.ContributionConfig),
		_janitor = Janitor.new(),
		_destroyed = false,
	}, MobBrain)

	self._janitor:Add(Players.PlayerRemoving:Connect(function(player: Player)
		self:RemoveAttacker(player)
	end), "Disconnect", "PlayerRemovingConnection")

	return self
end

function MobBrain:_Transition(nextState: MobState)
	if self._state == nextState then
		return
	end

	local previous = self._state
	self._state = nextState

	if self._onStateChanged ~= nil then
		local ok, err = pcall(self._onStateChanged, self, previous, nextState)
		if not ok then
			warn(string.format("[MobBrain:%s] state callback error: %s", tostring(self._mobId), tostring(err)))
		end
	end
end

function MobBrain:_GetPosition(): Vector3
	local root = resolveRoot(self._model)
	if root ~= nil then
		self._root = root
		return root.Position
	end
	return self._spawnOrigin
end

function MobBrain:_MoveDirect(destination: Vector3)
	if self._humanoid ~= nil then
		self._humanoid:MoveTo(destination)
	end
end

function MobBrain:_IsTargetValid(player: Player?): boolean
	if player == nil then
		return false
	end
	if not player:IsDescendantOf(Players) then
		return false
	end

	local character = player.Character
	if character == nil then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return false
	end

	if self._allowedZoneId ~= nil and self._zoneQueryHelper ~= nil then
		local inZone = self._zoneQueryHelper.IsPlayerWithinAllowedZone(player, self._allowedZoneId, self._zonePadding)
		if not inZone then
			return false
		end
	end

	if self._targetValidator ~= nil then
		local ok, result = pcall(self._targetValidator, self, player)
		if not ok then
			warn(string.format("[MobBrain:%s] target validator error: %s", tostring(self._mobId), tostring(result)))
			return false
		end
		if result == false then
			return false
		end
	end

	return true
end

function MobBrain:_GetTargetPosition(player: Player): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	if character.PrimaryPart ~= nil then
		return character.PrimaryPart.Position
	end
	return nil
end

function MobBrain:_SelectTarget(now: number): Player?
	local selected = TargetSelector.selectTarget({
		Attackers = self._attackers,
		CurrentTarget = self._currentTarget,
		Now = now,
		AggroLockUntil = self._aggroLockUntil,
		IsValidTarget = function(player: Player)
			return self:_IsTargetValid(player)
		end,
	})

	if selected ~= self._currentTarget then
		self._currentTarget = selected
		if selected ~= nil then
			self._aggroLockUntil = now + self._aggroLockDuration
		else
			self._aggroLockUntil = 0
		end
	end

	return selected
end

function MobBrain:GetState(): MobState
	return self._state
end

function MobBrain:GetCurrentTarget(): Player?
	return self._currentTarget
end

function MobBrain:AddAttacker(player: Player)
	if self._destroyed then
		return
	end
	if not self:_IsTargetValid(player) then
		return
	end
	self._attackers[player] = true
end

function MobBrain:RemoveAttacker(player: Player)
	self._attackers[player] = nil
	if self._currentTarget == player then
		self._currentTarget = nil
		self._aggroLockUntil = 0
	end
end

function MobBrain:AddDamage(userId: number, amount: number, now: number?)
	self._contributionTracker:AddDamage(userId, amount, now)
end

function MobBrain:GetEligibleContributors(now: number?)
	return self._contributionTracker:GetEligibleContributors(now)
end

function MobBrain:BuildPayoutShares(totalPool: number, now: number?)
	return self._contributionTracker:BuildPayoutShares(totalPool, now)
end

function MobBrain:MarkDead(now: number?)
	if self._destroyed then
		return
	end
	if self._state == "Dead" then
		return
	end

	local currentNow = if typeof(now) == "number" then now else os.clock()
	self:_Transition("Dead")
	DeathState.enter(self, currentNow)
end

function MobBrain:ResetForRespawn(spawnOrigin: Vector3?)
	if self._destroyed then
		return
	end

	if typeof(spawnOrigin) == "Vector3" then
		self._spawnOrigin = spawnOrigin
	end

	self._currentTarget = nil
	self._aggroLockUntil = 0
	self._nextAttackAt = 0
	self._deadAt = nil
	table.clear(self._attackers)
	self._contributionTracker:Reset()
	if self._pathingHelper then
		self._pathingHelper:Cancel(self._pathToken)
		self._pathToken = self._pathingHelper:CreateCancelToken()
	end
	self:_Transition("Idle")
end

function MobBrain:Step(now: number?)
	if self._destroyed then
		return
	end

	local currentNow = if typeof(now) == "number" then now else os.clock()
	if self._state == "Dead" then
		return
	end

	if self._humanoid ~= nil and self._humanoid.Health <= 0 then
		self:MarkDead(currentNow)
		return
	end

	local target = self._currentTarget
	if not self:_IsTargetValid(target) then
		target = self:_SelectTarget(currentNow)
	end

	if target ~= nil then
		local targetPosition = self:_GetTargetPosition(target)
		if targetPosition == nil then
			self:RemoveAttacker(target)
			return
		end

		local distance = (targetPosition - self:_GetPosition()).Magnitude
		if distance <= self._attackRange then
			self:_Transition("Attack")
			AttackState.update(self, currentNow)
			return
		end

		self:_Transition("Chase")
		PathRunner.chaseTarget(self, targetPosition, currentNow)
		return
	end

	local distanceFromSpawn = (self:_GetPosition() - self._spawnOrigin).Magnitude
	if distanceFromSpawn > self._returnThreshold then
		self:_Transition("Return")
		ReturnState.update(self, currentNow)
		return
	end

	self:_Transition("Idle")
end

function MobBrain:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true

	if self._pathingHelper ~= nil then
		self._pathingHelper:Cancel(self._pathToken)
		if self._ownsPathingHelper then
			self._pathingHelper:Destroy()
		end
	end

	self._contributionTracker:Destroy()
	self._janitor:Cleanup()
	table.clear(self._attackers)
	self._currentTarget = nil
	self._state = "Dead"
end

return MobBrain
