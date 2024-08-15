-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- MODULES
local WeaponConfig = require(ReplicatedStorage.Shared.Configs.WeaponConfig)

-- VARIABLES
local rayParams = RaycastParams.new()
local rayDirection = Vector3.new(0, -500, 0)

local weaponsFolder = workspace:WaitForChild('Weapons')

-- FUNCTIONS
local function BlockCast(weapon)
    local rayResult = workspace:Blockcast(
        weapon.PrimaryPart.CFrame + Vector3.new(0, WeaponConfig.MaxClimbHeight, 0),
        weapon.PrimaryPart.Size,
        rayDirection,
        rayParams
    )

    return rayResult
end

local function UpdateWeaponPositions(weaponFolder, mobInstance, weapon, speed, offset)
    local weapons = {}
    
    for _, weapon in weaponFolder:GetChildren() do
        table.insert(weapons, weapon)
    end

    rayParams.FilterDescendantsInstances = {weaponsFolder, mobInstance}

    local numOfWeapons = #weapons
    if numOfWeapons == 1 then
        numOfWeapons = 2
    end

    local radius = WeaponConfig.Spacing * (numOfWeapons + 1) / (math.pi * 2)
    local angleStep = (math.pi * 2) / (numOfWeapons)

    for i, Weapon in weapons do
        if Weapon ~= weapon then
            continue
        end

        local angle = (i - 1) * angleStep - (math.pi)

        local X = math.sin(angle)* radius
        local Y = 0
        local Z = math.cos(angle)* radius

        local rayResult = BlockCast(Weapon)

        if rayResult then
            Y = (rayResult.Position.Y + Weapon.PrimaryPart.Size.Y/2) + offset
        end

        local zOffset = 0

        if numOfWeapons < 3 then
            zOffset = 3
        end
        local targetCFrame = CFrame.new(mobInstance.Position.X, 0, mobInstance.Position.Z) * mobInstance.CFrame.Rotation * CFrame.new(X, Y, Z + zOffset)

        Weapon.PrimaryPart.CFrame = Weapon.PrimaryPart.CFrame:Lerp(targetCFrame, speed)
    end
end

local OFFSET = 2

return function(weaponFolder, mobInstance, weapon, speed) 
    UpdateWeaponPositions(weaponFolder, mobInstance, weapon, speed, OFFSET)
    return speed
end