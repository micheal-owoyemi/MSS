-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')
local TweenService = game:GetService('TweenService')

-- MODULES
local Trove = require(ReplicatedStorage.Shared.Trove)

local CoinDrop = require(ReplicatedStorage:WaitForChild('Shared').Classes.CoinDrop)

-- VARIABLES
local VFX = ReplicatedStorage.Shared.Assets:WaitForChild('VFX')

local RemoteEvents = ReplicatedStorage.Shared.RemoteEvents

local CoinDropRE = RemoteEvents:WaitForChild('CoinDrop')
local MobDeathFXRE = RemoteEvents.MobDeathFX
local AttackMobRE = RemoteEvents.AttackMobFX

local Player = Players.LocalPlayer

-- FUNCTIONS

-- COIN DROP FX
local function onCoinDropInvoke(mobModelCFrame, individualReward)
    CoinDrop.spawn(mobModelCFrame, individualReward, Player)
end

-- MOB DEATH EXPLOSION

local function onMobDeath(mobPosition)
    local mobExplosionInstance = ReplicatedStorage.Shared:WaitForChild('Assets').VFX.MobExplosion:Clone()
    mobExplosionInstance.Parent = workspace:WaitForChild('Game'):WaitForChild('FX')
    
    local newTrove = Trove.new()
    newTrove.Add(newTrove, mobExplosionInstance)

    mobExplosionInstance.Position = Vector3.new(mobPosition.X, 2, mobPosition.Z)
    local fxAttachment = mobExplosionInstance:WaitForChild('Main')

    for _, particle in fxAttachment:GetChildren() do
        particle:Emit(particle:GetAttribute("EmitCount"))
    end

    task.wait(4)

    mobExplosionInstance:Destroy()
end

local function onMobAttack(mobPosition)
    local mobAttackImpactInstance = ReplicatedStorage.Shared:WaitForChild('Assets').VFX.MobAttackImpact:Clone()
    mobAttackImpactInstance.Parent = workspace:WaitForChild('Game'):WaitForChild('FX')

    local newTrove = Trove.new()
    newTrove.Add(newTrove, mobAttackImpactInstance)

    mobAttackImpactInstance.Position = mobPosition

    local fxAttachment = mobAttackImpactInstance:WaitForChild('Main')

    for _, particle in fxAttachment:GetChildren() do
        particle:Emit(particle:GetAttribute('EmitCount'))
    end

    task.wait(1)

    mobAttackImpactInstance:Destroy()
end

AttackMobRE.OnClientEvent:Connect(onMobAttack)
CoinDropRE.OnClientEvent:Connect(onCoinDropInvoke)
MobDeathFXRE.OnClientEvent:Connect(onMobDeath)