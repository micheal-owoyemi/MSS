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

local Player = Players.LocalPlayer

-- FUNCTIONS

-- COIN DROP FX
local function onCoinDropInvoke(mobModelCFrame, individualReward)
    CoinDrop.spawn(mobModelCFrame, individualReward, Player)
end

-- MOB DEATH EXPLOSION

local function onMobDeath(mobPosition)
    local mobExplosionInstance = VFX:WaitForChild('MobExplosion')
    
    local newTrove = Trove.new()
    newTrove.Add(newTrove, mobExplosionInstance)

    mobExplosionInstance.Position = mobPosition
    local fxAttachment = mobExplosionInstance:WaitForChild('Main')

    for _, particle in fxAttachment:GetChildren() do
        particle:Emit(particle:GetAttribute("EmitCount"))
    end

    task.wait(4)

    mobExplosionInstance:Destroy()
end

CoinDropRE.OnClientEvent:Connect(onCoinDropInvoke)
MobDeathFXRE.OnClientEvent:Connect(onMobDeath)