local CoinDrop = {}

-- SERVICES
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService('TweenService')

-- MODULES
local PID = require(ReplicatedStorage.Shared.PID)
local Trove = require(ReplicatedStorage.Shared.Trove)

-- VARIABLES
local coinDictionary = {}

-- FUNCTIONS

function CoinDrop.spawnMob(originCFrame, coinObject, coinAmount)
    local coinInstances = coinAmount / 10

    for i = 0, coinInstances do
        local coin = coinObject:Clone()
        coin.CFrame = originCFrame
        coin.Parent = workspace:WaitForChild('Coin Drops')

        local randomX = {math.random(-10, -2), math.random(2, 10)}
        local randomZ = {math.random(-10, -2), math.random(2, 10)}

        local velocity = Vector3.new(randomX[math.random(1, 2)], math.random(50, 60), randomZ[math.random(1, 2)])

        coin.AssemblyLinearVelocity = velocity
        
    end
end

function CoinDrop.goToPlayer(Player)
    
end

return CoinDrop

-- SCALE THIS OUT OMGGGG