local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local NetworkApi = require(ReplicatedStorage.Shared.Network.NetworkApi)
local PacketSubscription = require(ReplicatedStorage.Shared.Utilities.PacketSubscription)
local WeaponReplicationPayload = require(ReplicatedStorage.Shared.Utilities.WeaponReplicationPayload)

local WeaponPacket = NetworkApi.Packets.Weapon

local WeaponReplicationService = Knit.CreateService({
	Name = "WeaponReplicationService",
	Client = {},
})

function WeaponReplicationService:KnitInit()
	self._gameplayManagerService = Knit.GetService("GameplayManagerService")
	self._weaponStates = {}
	self._unsubscribeWeaponPacket = nil
end

function WeaponReplicationService:KnitStart()
	self._unsubscribeWeaponPacket = PacketSubscription.listen(WeaponPacket.updateWeaponState, function(data, player)
		self:_onWeaponStateUpdate(data, player)
	end)

	if self._gameplayManagerService then
		self._gameplayManagerService:RegisterSystem(self.Name, self)
	end
end

function WeaponReplicationService:OnPlayerRemoving(player: Player)
	self._weaponStates[player.UserId] = nil
end

function WeaponReplicationService:_onWeaponStateUpdate(data: any, player: Player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	local uuid, position, orientation = WeaponReplicationPayload.parseState(data)
	if not (uuid and position and orientation) then
		return
	end

	local userId = player.UserId
	self._weaponStates[userId] = self._weaponStates[userId] or {}
	self._weaponStates[userId][uuid] = {
		position = position,
		orientation = orientation,
	}

	local payload = WeaponReplicationPayload.create(userId, uuid, position, orientation)
	if payload then
		WeaponPacket.updateWeaponState.sendToAllExcept(payload, player)
	end
end

function WeaponReplicationService:Destroy()
	if self._unsubscribeWeaponPacket then
		self._unsubscribeWeaponPacket()
		self._unsubscribeWeaponPacket = nil
	end
end

return WeaponReplicationService
