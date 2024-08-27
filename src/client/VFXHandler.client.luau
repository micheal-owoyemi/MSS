-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

-- MODULES
local CoinDrop = require(ReplicatedStorage:WaitForChild('Shared').Classes.CoinDrop)

-- VARIABLES
local RemoteEvents = ReplicatedStorage.Shared.RemoteEvents

local CoinDropRE = RemoteEvents:WaitForChild('CoinDrop')
local MobDeathRE = RemoteEvents.MobDeath

local Player = Players.LocalPlayer

-- FUNCTIONS

local function onCoinDropInvoke (mobModelCFrame, individualReward)
    CoinDrop.spawn(mobModelCFrame, individualReward, Player)
end



CoinDropRE.OnClientEvent:Connect(onCoinDropInvoke)