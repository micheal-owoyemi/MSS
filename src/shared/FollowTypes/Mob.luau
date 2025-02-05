-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local TweenService = game:GetService('TweenService')

-- MODULES
local WeaponConfig = require(ReplicatedStorage.Shared.Configs.WeaponConfig)
local Attack = require(ReplicatedStorage.Shared.AttackTypes.Attack)

-- VARIABLES
local rayParams = RaycastParams.new()
local rayDirection = Vector3.new(0, -500, 0)

local weaponsFolder = workspace:WaitForChild('Game'):WaitForChild('Weapons')

local distance
local lastTick = tick()

-- REMOTES

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

local function absDistance(pointA, pointB)
    return math.abs(math.abs(pointA) - math.abs(pointB))
end

local function playAttackAnimation(weaponInstance, mobInstance, X, Y, Z, zOffset) 
    if not weaponInstance.Animations then return end


    weaponInstance.PrimaryPart:PivotTo(mobInstance.CFrame * CFrame.Angles(-20, Y, 0))
    local animations = weaponInstance.Animations
    local animationController = weaponInstance.AnimationController

    local attackAnimation = animationController:LoadAnimation(animations.Attack)

    attackAnimation:Play()
    task.wait(attackAnimation.Length)
    attackAnimation:Stop()
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

        

        distance = absDistance(targetCFrame.X,  Weapon.PrimaryPart.CFrame.X)

        if distance < 0.5 then
            local currentTick = tick()
            
            if currentTick - lastTick >= 2 and mobInstance then
                lastTick = tick()
                playAttackAnimation(Weapon, mobInstance, X, Y, Z, zOffset)
                Attack(mobInstance)
            end
        end
    end
end




local OFFSET = 2

return function(weaponFolder, mobInstance, weapon, speed) 
    UpdateWeaponPositions(weaponFolder, mobInstance, weapon, speed, OFFSET)
    return speed
end