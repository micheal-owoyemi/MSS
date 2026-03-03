local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local NetworkApi = require(ReplicatedStorage.Shared.Network.NetworkApi)
local GameplayPacket = NetworkApi.Packets.Gameplay

local DataCombat = require(ServerStorage.Data.Data_Combat)
local ClientRequestGate = require(script.Parent.Shared.ClientRequestGate)
local RequestValidation = require(script.Parent.Shared.RequestValidation)
local SystemBinder = require(script.Parent.Shared.SystemBinder)

local CombatService = {
	Name = "CombatService",
	Dependencies = { "DataStoreService", "MobService", "GamePlayManagerService" },
}

local ACTION_COOLDOWNS = {
	AttackMob = tonumber(DataCombat.AttackCooldownSeconds) or 0.2,
}

function CombatService:Init(context)
	self._dataStoreService = context.GetService("DataStoreService")
	self._mobService = context.GetService("MobService")
	self._managerService = context.GetService("GamePlayManagerService")
	self._cooldownsByUserId = {}
	self._rateLimiter = RateLimiter.NewRateLimiter(tonumber(DataCombat.AttackRateLimitPerSecond) or 10)
	self._attackQueueByUserId = {}
	self._maxQueueSize = math.max(1, tonumber(DataCombat.MaxQueuedAttacksPerPlayer) or 8)
	self._maxProcessedPerTick = math.max(1, tonumber(DataCombat.MaxProcessedAttacksPerTick) or 2)
	self._connections = {}
	self._attackPacketListener = nil
end

function CombatService:Start()
	if not (self._dataStoreService and self._mobService) then
		warn("[CombatService] Missing dependencies")
		return
	end

	self._attackPacketListener = function(data, player)
		self:_onAttackRequest(player, data)
	end
	GameplayPacket.requestMobAttack.listen(self._attackPacketListener)

	table.insert(self._connections, Players.PlayerRemoving:Connect(function(player)
		self._cooldownsByUserId[player.UserId] = nil
		self._attackQueueByUserId[player.UserId] = nil
		self._rateLimiter:CleanSource(player)
	end))

	SystemBinder.registerManagedSystem(self._managerService, self.Name, self)
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
	if self._attackPacketListener then
		local listeners = GameplayPacket.requestMobAttack.getListeners()
		local index = table.find(listeners, self._attackPacketListener)
		if index then
			table.remove(listeners, index)
		end
		self._attackPacketListener = nil
	end

	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
end

return CombatService
