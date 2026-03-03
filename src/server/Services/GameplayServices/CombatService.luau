local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local NetworkApi = require(ReplicatedStorage.Shared.Network.NetworkApi)
local PacketSubscription = require(ReplicatedStorage.Shared.Utilities.PacketSubscription)

local DataCombat = require(script.Parent.Parent.Parent.Config.Data_Combat)
local ClientRequestGate = require(script.Parent.Support.ClientRequestGate)
local RequestValidation = require(script.Parent.Support.RequestValidation)

local GameplayPacket = NetworkApi.Packets.Gameplay

local CombatService = Knit.CreateService({
	Name = "CombatService",
	Client = {},
})

local ACTION_COOLDOWNS = {
	AttackMob = tonumber(DataCombat.AttackCooldownSeconds) or 0.2,
}

function CombatService:KnitInit()
	self._dataStoreService = Knit.GetService("DataStoreService")
	self._mobService = Knit.GetService("MobService")
	self._gameplayManagerService = Knit.GetService("GameplayManagerService")
	self._cooldownsByUserId = {}
	self._rateLimiter = RateLimiter.NewRateLimiter(tonumber(DataCombat.AttackRateLimitPerSecond) or 10)
	self._attackQueueByUserId = {}
	self._maxQueueSize = math.max(1, tonumber(DataCombat.MaxQueuedAttacksPerPlayer) or 8)
	self._maxProcessedPerTick = math.max(1, tonumber(DataCombat.MaxProcessedAttacksPerTick) or 2)
	self._unsubscribeAttackPacket = nil
end

function CombatService:KnitStart()
	if not (self._dataStoreService and self._mobService and self._gameplayManagerService) then
		warn("[CombatService] Missing service dependencies")
		return
	end

	self._unsubscribeAttackPacket = PacketSubscription.listen(GameplayPacket.requestMobAttack, function(data, player)
		self:_onAttackRequest(player, data)
	end)

	self._gameplayManagerService:RegisterSystem(self.Name, self)
end

function CombatService:OnPlayerRemoving(player: Player)
	self._cooldownsByUserId[player.UserId] = nil
	self._attackQueueByUserId[player.UserId] = nil
	self._rateLimiter:CleanSource(player)
end

function CombatService:_enqueueAttack(userId: number, targetPart: BasePart)
	local queue = self._attackQueueByUserId[userId]
	if type(queue) ~= "table" then
		queue = {}
		self._attackQueueByUserId[userId] = queue
	end

	queue[#queue + 1] = targetPart
	while #queue > self._maxQueueSize do
		table.remove(queue, 1)
	end
end

function CombatService:_onAttackRequest(player: Player, data: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	if type(data) ~= "table" then
		return
	end

	if not self._rateLimiter:CheckRate(player) then
		return
	end

	if not ClientRequestGate.allow(self._cooldownsByUserId, player.UserId, "AttackMob", ACTION_COOLDOWNS) then
		return
	end

	local target = data.target
	local valid, _, targetPart = RequestValidation.validateAttackTarget(player, target, DataCombat.MaxAttackDistance)
	if not valid or not targetPart then
		return
	end

	self:_enqueueAttack(player.UserId, targetPart)
end

function CombatService:OnTick()
	for userId, queue in pairs(self._attackQueueByUserId) do
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			self._attackQueueByUserId[userId] = nil
			continue
		end
		if type(queue) ~= "table" or #queue == 0 then
			continue
		end

		local equippedWeapons = self._dataStoreService:GetEquippedWeapons(player)
		if next(equippedWeapons) == nil then
			table.clear(queue)
			continue
		end

		local processed = 0
		while #queue > 0 and processed < self._maxProcessedPerTick do
			local targetPart = table.remove(queue, 1)
			if targetPart and targetPart.Parent then
				local valid, _, verifiedTarget = RequestValidation.validateAttackTarget(
					player,
					targetPart,
					DataCombat.MaxAttackDistance
				)
				if valid and verifiedTarget then
					self._mobService:AttackMob(player, verifiedTarget, equippedWeapons)
				end
			end
			processed += 1
		end
	end
end

function CombatService:Destroy()
	if self._unsubscribeAttackPacket then
		self._unsubscribeAttackPacket()
		self._unsubscribeAttackPacket = nil
	end
end

return CombatService
