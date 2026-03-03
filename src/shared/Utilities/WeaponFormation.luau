local Workspace = game:GetService("Workspace")

local WeaponFormation = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local rayDirection = Vector3.new(0, -500, 0)

local function collectWeapons(weaponFolder: Instance): { Model }
	local weapons = {}

	for _, child in ipairs(weaponFolder:GetChildren()) do
		if child:IsA("Model") and child.PrimaryPart then
			table.insert(weapons, child)
		end
	end

	table.sort(weapons, function(a, b)
		return a.Name < b.Name
	end)

	return weapons
end

function WeaponFormation.getTrackedWeaponState(weaponFolder: Instance, trackedWeapon: Model): ({ Model }, number?)
	if typeof(weaponFolder) ~= "Instance" or typeof(trackedWeapon) ~= "Instance" then
		return {}, nil
	end

	local weapons = collectWeapons(weaponFolder)
	local trackedIndex = table.find(weapons, trackedWeapon)

	return weapons, trackedIndex
end

function WeaponFormation.resolveGroundOffset(
	weapon: Model,
	filterInstances: { Instance },
	maxClimbHeight: number,
	offset: number
): number
	local primaryPart = weapon.PrimaryPart
	if not primaryPart then
		return 0
	end

	rayParams.FilterDescendantsInstances = filterInstances

	local rayResult = Workspace:Blockcast(
		primaryPart.CFrame + Vector3.new(0, maxClimbHeight, 0),
		primaryPart.Size,
		rayDirection,
		rayParams
	)

	if not rayResult then
		return 0
	end

	return (rayResult.Position.Y + primaryPart.Size.Y / 2) + offset
end

local function normalizeWeaponCount(numWeapons: number): number
	if numWeapons <= 1 then
		return 2
	end
	return numWeapons
end

function WeaponFormation.getArcOffsets(index: number, numWeapons: number, spacing: number): (number, number, number)
	local normalizedCount = normalizeWeaponCount(numWeapons)
	local radius = spacing * (normalizedCount - 1) / math.pi
	local angleStep = math.pi / (normalizedCount - 1)
	local angle = (index - 1) * angleStep - (math.pi / 2)

	return math.sin(angle) * radius, math.cos(angle) * radius, normalizedCount
end

function WeaponFormation.getCircleOffsets(index: number, numWeapons: number, spacing: number): (number, number, number)
	local normalizedCount = normalizeWeaponCount(numWeapons)
	local radius = spacing * (normalizedCount + 1) / (math.pi * 2)
	local angleStep = (math.pi * 2) / normalizedCount
	local angle = (index - 1) * angleStep - math.pi

	return math.sin(angle) * radius, math.cos(angle) * radius, normalizedCount
end

return WeaponFormation
