-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

-- MODULE(S)
local ReplicaController = require(ReplicatedStorage.Shared.ReplicaController)

ReplicaController.RequestData() -- INIT ONCE FOR ENTIRE CLIENT

-- VARIABLES
local Player = Players.LocalPlayer
local playerGUI = Player:WaitForChild('PlayerGui')
local screenGUI = playerGUI:WaitForChild('ScreenGui')
local frame = screenGUI:WaitForChild('Frame')

-- FUNCTIONS

ReplicaController.ReplicaOfClassCreated('PlayerProfile', function(Replica)
    local isLocal = Replica.Tags.Player == Player
    local replicaData = Replica.Data

    if isLocal then 
        frame.TextLabel.Text = replicaData.Coins

        Replica:ListenToChange({'Coins'}, function(new_value, old_value)
            frame.TextLabel.Text = new_value
        end)
    end
end)
