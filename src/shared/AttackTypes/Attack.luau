-- basically you would tell the server when they move to a mob to start attacking then on the server you could check their equipped swords and start applying damage on the mob

--[[

    Play animation everytime damage is dealt
    Keep track of damage dealt

]]


-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RemoteEvents = ReplicatedStorage.Shared.RemoteEvents

-- MODULES

-- VARIABLES
local attackMobRE = RemoteEvents:WaitForChild('AttackMob')

local function attack(mobInstance)
    if mobInstance then
        attackMobRE:FireServer(mobInstance)
    end
end

return function(mobInstance)
    attack(mobInstance)
end
