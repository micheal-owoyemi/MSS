local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkApi = require(ReplicatedStorage.Shared.Network.NetworkApi)
local WeaponPacket = NetworkApi.Packets.Weapon

local WeaponReplicationController = {
	_started = false,
}

local function orientationToCFrame(orientation: Vector3): CFrame
	return CFrame.Angles(
		math.rad(orientation.X),
		math.rad(orientation.Y),
		math.rad(orientation.Z)
	)
end

local function resolvePlayerWeaponFolder(serverWeapons: Folder, userId: number): Instance?
	local byUserId = serverWeapons:FindFirstChild(tostring(userId))
	if byUserId then
		return byUserId
	end

	local ok, playerNameOrError = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if not ok then
		return nil
	end

	return serverWeapons:FindFirstChild(playerNameOrError)
end

function WeaponReplicationController:Start()
	if self._started then
		return
	end

	self._started = true

	local serverWeapons = workspace:WaitForChild("Game"):WaitForChild("Weapons")
	local localPlayer = Players.LocalPlayer

	WeaponPacket.updateWeaponState.listen(function(data)
		if type(data) ~= "table" then
			return
		end

		local sourceUserId = tonumber(data.id)
		if not sourceUserId or sourceUserId == localPlayer.UserId then
			return
		end

		local uuid = type(data.uuid) == "string" and data.uuid or nil
		local position = typeof(data.position) == "Vector3" and data.position or nil
		local orientation = typeof(data.orientation) == "Vector3" and data.orientation or nil
		if not (uuid and position and orientation) then
			return
		end

		local playerFolder = resolvePlayerWeaponFolder(serverWeapons, sourceUserId)
		if not playerFolder then
			return
		end

		local weaponModel = playerFolder:FindFirstChild(uuid)
		if not (weaponModel and weaponModel:IsA("Model") and weaponModel.PrimaryPart) then
			return
		end

		local targetCFrame = CFrame.new(position) * orientationToCFrame(orientation)
		weaponModel:PivotTo(weaponModel:GetPivot():Lerp(targetCFrame, 0.5))
	end)
end

return WeaponReplicationController
