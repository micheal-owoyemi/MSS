
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

local HelperFunctions = require(ReplicatedStorage.Shared.HelperFunctions.HelperFunctions)

-- VARIABLES
local Player = Players.LocalPlayer
local RemoteEvents = ReplicatedStorage.Shared.RemoteEvents

local Weapons = {}

local MobDeathRE = RemoteEvents:WaitForChild('MobDeath')

-- FUNCTIONS
ReplicaController.ReplicaOfClassCreated('PlayerProfile', function(Replica)
    local isLocal = Replica.Tags.Player == Player
    local replicaData = Replica.Data

    if isLocal then 
        -- Grabs init replicaData, spawns weapons for it
        for UUID, weapon in pairs(replicaData.Weapons) do
            local weaponInstance = WeaponClass.new(weapon.weaponType, weapon.weaponName, weapon.equipped, Player)
            table.insert(Weapons, weaponInstance)
        end

        Replica:ListenToChange({'Weapons'}, function(new_value, old_value)
            print('[Client Init] Data Has Been Changed, New Replica Data: ', new_value)
            -- When changed, does it again

            local additions, deletions = HelperFunctions.compareTables(new_value, old_value)
            
           -- for i, weapon in (deletions) do
            --    weapon:despawn()
            --    Weapons[i] = nil    
           -- end

            for i, weapon in (additions) do
                local weaponInstance = WeaponClass.new(weapon.weaponType, weapon.weaponName, weapon.equipped, Player)
                table.insert(Weapons, weaponInstance)
            end
            -- Create comparison function to see what changed, then reflect as such
        end)
    end
end)


local function onMobDeath(mobInstance)
    for _, weapon in Weapons do
        weapon:disengageMob(mobInstance)
    end
end

MobDeathRE.OnClientEvent:Connect(onMobDeath)