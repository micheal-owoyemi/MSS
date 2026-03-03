local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponData = require(ReplicatedStorage.Shared.Utilities.WeaponData)
local GameWorld = require(ReplicatedStorage.Shared.Utilities.GameWorld)
local WeaponFormation = require(ReplicatedStorage.Shared.Utilities.WeaponFormation)

local weaponsFolder = GameWorld.getWeaponsFolder()
local maxClimbHeight = WeaponData.getMaxClimbHeight()
local weaponSpacing = WeaponData.getSpacing()

local offset = 5

local function updateWeaponPositions(weaponFolder, character, humanoidRootPart, weapon, speed, followOffset)
	if typeof(weapon) ~= "Instance" or not weapon:IsA("Model") or not weapon.PrimaryPart then
		return
	end

	local weapons, weaponIndex = WeaponFormation.getTrackedWeaponState(weaponFolder, weapon)
	if not weaponIndex then
		return
	end

	local x, z, normalizedCount = WeaponFormation.getArcOffsets(weaponIndex, #weapons, weaponSpacing)
	local y = WeaponFormation.resolveGroundOffset(weapon, { weaponsFolder, character }, maxClimbHeight, followOffset)
	local zOffset = normalizedCount < 3 and 3 or 0

	local targetCFrame = CFrame.new(humanoidRootPart.Position.X, 0, humanoidRootPart.Position.Z)
		* humanoidRootPart.CFrame.Rotation
		* CFrame.new(x, y, z + zOffset)

	weapon.PrimaryPart.CFrame = weapon.PrimaryPart.CFrame:Lerp(targetCFrame, speed)
	weapon.PrimaryPart.CFrame *= CFrame.new(0, math.max(math.sin(time() * 5) / 10, -1), 0)
end

return function(weaponFolder, character, humanoidRootPart, humanoid, weapon, speed)
	updateWeaponPositions(weaponFolder, character, humanoidRootPart, weapon, speed, offset)
	return speed
end
