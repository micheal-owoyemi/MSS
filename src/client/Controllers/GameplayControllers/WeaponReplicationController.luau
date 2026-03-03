local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local NetworkApi = require(ReplicatedStorage.Shared.Network.NetworkApi)
local GameWorld = require(ReplicatedStorage.Shared.Utilities.GameWorld)
local WeaponReplicationPayload = require(ReplicatedStorage.Shared.Utilities.WeaponReplicationPayload)

local WeaponPacket = NetworkApi.Packets.Weapon

local WeaponReplicationController = Knit.CreateController({
	Name = "WeaponReplicationController",
})

function WeaponReplicationController:KnitStart()
	local localPlayer = Players.LocalPlayer

	WeaponPacket.updateWeaponState.listen(function(data)
		local sourceUserId, uuid, position, orientation = WeaponReplicationPayload.parseBroadcastState(data)
		if not sourceUserId or sourceUserId == localPlayer.UserId then
			return
		end

		local playerFolder = GameWorld.getPlayerWeaponsFolder(sourceUserId, false)
		if not playerFolder then
			return
		end

		local weaponModel = playerFolder:FindFirstChild(uuid)
		if not (weaponModel and weaponModel:IsA("Model") and weaponModel.PrimaryPart) then
			return
		end

		local targetCFrame = WeaponReplicationPayload.toCFrame(position, orientation)
		weaponModel:PivotTo(weaponModel:GetPivot():Lerp(targetCFrame, 0.5))
	end)
end

return WeaponReplicationController
