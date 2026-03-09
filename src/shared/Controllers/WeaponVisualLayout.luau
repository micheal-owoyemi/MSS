--!strict

local WeaponVisualLayout = {}

local TAU = math.pi * 2

local function unitFromHorizontal(vector: Vector3, fallback: Vector3): Vector3
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude <= 1e-4 then
		return fallback
	end
	return horizontal.Unit
end

function WeaponVisualLayout.ComputeFollowPose(
	rootCFrame: CFrame,
	weaponIndex: number,
	weaponCount: number,
	config: {[string]: any},
	now: number,
	uidHash: number
): (Vector3, Vector3)
	local count = math.max(1, weaponCount)
	local index = math.clamp(weaponIndex, 1, count)

	local forward = unitFromHorizontal(rootCFrame.LookVector, Vector3.new(0, 0, -1))
	local right = unitFromHorizontal(rootCFrame.RightVector, Vector3.new(1, 0, 0))

	local centered = index - ((count + 1) * 0.5)
	local rowIndex = math.floor(math.abs(centered) / 2)
	local rowDirection = if centered >= 0 then 1 else -1

	local behindOffset = config.FollowDistanceBehind + rowIndex * config.FollowRowSpacing
	local lateralOffset = rowDirection * config.FollowLateralSpacing * (0.5 + (math.abs(centered) % 2))
	local bobPhase = now * config.BobFrequencyHz * TAU + uidHash * 0.11
	local bobOffset = math.sin(bobPhase) * config.BobAmplitudeStuds

	local position = rootCFrame.Position
		- (forward * behindOffset)
		+ (right * lateralOffset)
		+ Vector3.new(0, config.FollowVerticalOffset + bobOffset, 0)

	local facing = forward
	return position, facing
end

function WeaponVisualLayout.ComputeAssignedPose(
	mobPosition: Vector3,
	assignedIndex: number,
	assignedCount: number,
	config: {[string]: any},
	now: number,
	ownerOffsetRadians: number,
	uidHash: number
): (Vector3, Vector3)
	local count = math.max(1, assignedCount)
	local index = math.clamp(assignedIndex, 1, count)

	local radius = config.AssignedRingRadiusBase + ((count - 1) * config.AssignedRingRadiusPerWeapon)
	local baseAngle = ((index - 1) / count) * TAU
	local spinAngle = now * config.AssignedRingSpinRateRadians
	local jitter = (uidHash % 1000) * 0.0007
	local angle = baseAngle + spinAngle + ownerOffsetRadians + jitter

	local bobPhase = now * config.BobFrequencyHz * TAU + uidHash * 0.07
	local bobOffset = math.sin(bobPhase) * config.BobAmplitudeStuds
	local offset = Vector3.new(math.cos(angle) * radius, config.AssignedRingHeight + bobOffset, math.sin(angle) * radius)
	local position = mobPosition + offset
	local toCenter = mobPosition - position
	local facing = unitFromHorizontal(toCenter, Vector3.new(0, 0, -1))
	return position, facing
end

return table.freeze(WeaponVisualLayout)
