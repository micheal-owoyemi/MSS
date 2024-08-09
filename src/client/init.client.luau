-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

-- MODULE(S)
local ReplicaController = require(ReplicatedStorage.Shared.ReplicaController)
ReplicaController.RequestData() -- INIT ONCE FOR ENTIRE CLIENT

-- VARIABLES
local Player = Players.LocalPlayer

-- FUNCTIONS
ReplicaController.ReplicaOfClassCreated('PlayerProfile', function(Replica)
    local isLocal = Replica.Tags.Player == Player
    --local replicaData = Replica.Data

    if isLocal then 
        print(Replica.Data)
        Replica:ListenToNewKey({'Weapons'}, function(new_value, new_key)
            -- Opt for listenToChange
            print(new_key, new_value)
        end)
    end
end)
