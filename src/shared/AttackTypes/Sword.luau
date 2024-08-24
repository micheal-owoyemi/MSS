-- basically you would tell the server when they move to a mob to start attacking then on the server you could check their equipped swords and start applying damage on the mob

--[[

    Check if destination has been reached
    Deal damage per cooldown
    Play animation everytime damage is dealt
    Keep track of damage dealt

]]

local Sword

-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- MODULES
local WeaponConfig = require(ReplicatedStorage.Shared.Configs.MobConfig)
-- VARIABLES

local function attack()

    print('yea')

    wait(10)
end

return function()
    attack()
end
