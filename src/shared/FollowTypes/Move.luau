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

local function UpdateWeaponPositions(weaponFolder, character, humanoidRootPart, humanoid, weapon, speed, offset)
    local weapons = {}
    
    for _, weapon in weaponFolder:GetChildren() do
        table.insert(weapons, weapon)
    end

    rayParams.FilterDescendantsInstances = {weaponsFolder, character}

    local radius = WeaponConfig.Spacing * (#weapons - 1) / math.pi
    local angleStep = math.pi / (#weapons - 1)

    for i, Weapon in weapons do
        if Weapon ~= weapon then
            continue
        end

        local angle = (i - 1) * angleStep - (math.pi/2)

        local X = math.sin(angle)* radius
        local Y = 0
        local Z = math.cos(angle)* radius

        local rayResult = BlockCast(Weapon)

        if rayResult then
            Y = (rayResult.Position.Y + Weapon.PrimaryPart.Size.Y/2) + offset
        end

        local targetCFrame = CFrame.new(humanoidRootPart.Position.X, 0, humanoidRootPart.Position.Z) * humanoidRootPart.CFrame.Rotation * CFrame.new(X, Y, Z)

        Weapon.PrimaryPart.CFrame = Weapon.PrimaryPart.CFrame:Lerp(targetCFrame, speed)
    end
end

local OFFSET = 0

return function(weaponFolder, character, humanoidRootPart, humanoid, weapon, speed) 
    UpdateWeaponPositions(weaponFolder, character, humanoidRootPart, humanoid, weapon, speed, OFFSET)
    return speed
end