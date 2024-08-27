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

function CoinDrop.spawn(originCFrame, coinAmount, Player)
    local coinObject = ReplicatedStorage.Shared:WaitForChild('Assets').VFX.CoinDrop:Clone()

    local coinInstances = coinAmount / 10
    local coinInstanceTable = {}

    for i = 0, coinInstances do
        local coin = coinObject:Clone()
        coin.CFrame = originCFrame
        coin.Parent = workspace:WaitForChild('Coin Spawn')

        local randomX = {math.random(-10, -2), math.random(2, 10)}
        local randomZ = {math.random(-10, -2), math.random(2, 10)}

        local velocity = Vector3.new(randomX[math.random(1, 10)], math.random(50, 100), randomZ[math.random(1, 10)])

        coin.AssemblyLinearVelocity = velocity

        table.insert(coinInstanceTable, coin)
    end

    task.wait()

    for _, coin in coinInstanceTable do
        CoinDrop.goToPlayer(Player, coin)
    end
end

function CoinDrop.goToPlayer(Player, coinInstance)
    local character = Player.Character or Player.CharacterAdded:Wait()
    local humanoidRootPart = character:WaitForChild('HumanoidRootPart')
    local magnitude = (humanoidRootPart.Position - coinInstance.Position).Magnitude

    if coinInstance:IsA('Part') and coinInstance.Name == 'CoinDrop' then
        coinInstance.CanCollide = false

        local tweenInfo = TweenInfo.new(magnitude*0.01, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, false, 0)

        local tween = TweenService:Create(coinInstance, tweenInfo, {Position = humanoidRootPart.Position})
        tween:Play()

        tween.Completed:Connect(function()
            local newTrove = Trove.new()
            newTrove.Add(newTrove, coinInstance)
            coinInstance:Destroy()
        end)
        task.wait()
    end
end

return CoinDrop

-- SCALE THIS OUT OMGGGG