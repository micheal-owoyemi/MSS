-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

-- MODULE(S)

-- VARIABLES
local Player = Players.LocalPlayer

local RemoteEvents = ReplicatedStorage.Shared.RemoteEvents

local MobDeathRE = RemoteEvents:WaitForChild('MobDeath')


-- FUNCTIONS

-- RE to disengage player weapons on target death
local function onMobDeath(mobInstance, Weapons)
    for _, weapon in Weapons do
        weapon:disengageMob(mobInstance)
    end
end

