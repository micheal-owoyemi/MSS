local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkApi = require(ReplicatedStorage.Shared.Network.NetworkApi)
local WeaponPacket = NetworkApi.Packets.Weapon

local WeaponReplicationService = {
	Name = "WeaponReplicationService",
}

function WeaponReplicationService:Init()
	self._weaponStates = {}
end

function WeaponReplicationService:Start()
	WeaponPacket.updateWeaponState.listen(function(data, player)
		self:_onWeaponStateUpdate(data, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._weaponStates[player.UserId] = nil
	end)
end

function WeaponReplicationService:_onWeaponStateUpdate(data: any, player: Player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	if type(data) ~= "table" then
		return
	end

	local uuid = type(data.uuid) == "string" and data.uuid or nil
	local position = typeof(data.position) == "Vector3" and data.position or nil
	local orientation = typeof(data.orientation) == "Vector3" and data.orientation or nil

	if not (uuid and position and orientation) then
		return
	end

	local userId = player.UserId
	self._weaponStates[userId] = self._weaponStates[userId] or {}
	self._weaponStates[userId][uuid] = {
		position = position,
		orientation = orientation,
	}

	WeaponPacket.updateWeaponState.sendToAllExcept({
		id = userId,
		uuid = uuid,
		position = position,
		orientation = orientation,
	}, player)
end

return WeaponReplicationService
