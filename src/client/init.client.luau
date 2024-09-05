
-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

-- MODULE(S)
local ReplicaController = require(ReplicatedStorage.Shared.ReplicaController)
ReplicaController.RequestData() -- INIT ONCE FOR ENTIRE CLIENT

local WeaponClass = require(ReplicatedStorage.Shared.Classes.Weapon)
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

    print(replicaData)
    
   --[[ if isLocal then 
        -- Grabs init replicaData, spawns weapons for it
        for UUID, weapon in pairs(replicaData.Weapons) do
            local weaponInstance = WeaponClass.new(weapon.weaponType, weapon.weaponName, weapon.equipped, Player)
            table.insert(Weapons, weaponInstance)
        end

        local coinCountUI = Player:WaitForChild('PlayerGui'):WaitForChild('CurrencyCounter').Frame.TextLabel
        coinCountUI.Text = replicaData.Coins


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

        Replica:ListenToChange({'Coins'}, function(new_value, old_value)

            if new_value > old_value then
                local diff = new_value - old_value
                coinCountUI.Text = ('+ '..diff)

                task.wait(2)
                
                coinCountUI.Text = new_value
            end
        end)
    end]]
end)



-- RE to disengage player weapons on target death
local function onMobDeath(mobInstance)
    for _, weapon in Weapons do
        weapon:disengageMob(mobInstance)
    end
end

MobDeathRE.OnClientEvent:Connect(onMobDeath)