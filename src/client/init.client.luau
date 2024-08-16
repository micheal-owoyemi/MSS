
-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local Players = game:GetService('Players')
local UserInputService = game:GetService('UserInputService')

-- MODULE(S)
local ReplicaController = require(ReplicatedStorage.Shared.ReplicaController)
ReplicaController.RequestData() -- INIT ONCE FOR ENTIRE CLIENT

local WeaponClass = require(ReplicatedStorage.Shared.Classes.Weapon)
local MobClass = require(ReplicatedStorage.Shared.Classes.Weapon)

-- VARIABLES
local Player = Players.LocalPlayer


-- FUNCTIONS
ReplicaController.ReplicaOfClassCreated('PlayerProfile', function(Replica)
    local isLocal = Replica.Tags.Player == Player
    local replicaData = Replica.Data

    if isLocal then 
        print('[Client Init] Initial Replica Data: ', replicaData)
        -- Grabs init replicaData, spawns weapons for it
        for UUID, weapon in pairs(replicaData.Weapons) do
            WeaponClass.new(weapon.weaponType, weapon.weaponName, weapon.equipped, Player)
        end

        Replica:ListenToChange({'Weapons'}, function(new_value, old_value)
            print('[Client Init] Data Has Been Changed, New Replica Data: ', new_value)
            -- When changed, does it again
            for UUID, weapon in pairs(new_value) do
                WeaponClass.new(weapon.weaponType, weapon.weaponName, weapon.equipped, Player)
                
            end
            -- Create comparison function to see what changed, then reflect as such
        end)
    end
end)

