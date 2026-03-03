local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponData = require(ReplicatedStorage.Shared.Utilities.WeaponData)
local GameWorld = require(ReplicatedStorage.Shared.Utilities.GameWorld)
local WeaponFormation = require(ReplicatedStorage.Shared.Utilities.WeaponFormation)
local requestMobAttack = require(script.Parent.Parent.Parent.Combat.RequestMobAttack)

local weaponsFolder = GameWorld.getWeaponsFolder()
local maxClimbHeight = WeaponData.getMaxClimbHeight()
local weaponSpacing = WeaponData.getSpacing()

local offset = 2

local function absoluteDistance(pointA, pointB)
	return math.abs(math.abs(pointA) - math.abs(pointB))
end

local function playAttackAnimation(weaponInstance, mobInstance, y)
	if not weaponInstance.Animations then
		return
	end

	weaponInstance.PrimaryPart:PivotTo(mobInstance.CFrame * CFrame.Angles(-20, y, 0))
	local animations = weaponInstance.Animations
	local animationController = weaponInstance.AnimationController
	local attackAnimation = animationController:LoadAnimation(animations.Attack)

	attackAnimation:Play()
	task.wait(attackAnimation.Length)
	attackAnimation:Stop()
end

local function updateWeaponPositions(weaponFolder, mobInstance, weapon, speed, followOffset)
	if typeof(weapon) ~= "Instance" or not weapon:IsA("Model") or not weapon.PrimaryPart then
		return
	end

	local weapons, weaponIndex = WeaponFormation.getTrackedWeaponState(weaponFolder, weapon)
	if not weaponIndex then
		return
	end

	local x, z, normalizedCount = WeaponFormation.getCircleOffsets(weaponIndex, #weapons, weaponSpacing)
	local y = WeaponFormation.resolveGroundOffset(weapon, { weaponsFolder, mobInstance }, maxClimbHeight, followOffset)
	local zOffset = normalizedCount < 3 and 3 or 0

	local targetCFrame = CFrame.new(mobInstance.Position.X, 0, mobInstance.Position.Z)
		* mobInstance.CFrame.Rotation
		* CFrame.new(x, y, z + zOffset)

	weapon.PrimaryPart.CFrame = weapon.PrimaryPart.CFrame:Lerp(targetCFrame, speed)

	local distance = absoluteDistance(targetCFrame.X, weapon.PrimaryPart.CFrame.X)
	if distance >= 0.5 then
		return
	end

	local currentTick = tick()
	local lastAttackTick = weapon:GetAttribute("LastAttackTick") or 0
	if currentTick - lastAttackTick < 2 or not mobInstance then
		return
	end

	weapon:SetAttribute("LastAttackTick", currentTick)
	playAttackAnimation(weapon, mobInstance, y)
	requestMobAttack(mobInstance)
end

return function(weaponFolder, mobInstance, weapon, speed)
	updateWeaponPositions(weaponFolder, mobInstance, weapon, speed, offset)
	return speed
end
