-- SERVICES --
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

-- MODULES --
local WeaponPacket = require(ReplicatedStorage.Shared.Network.WeaponPacket)

-- VARIABLES -- 
local Player = Players.LocalPlayer
local ServerWeapons = workspace:WaitForChild('Weapons')
local PlayerWeapons = {}

-- FUNCTIONS --
WeaponPacket.onServerUpdate(function(data)
    local weaponInstance = ServerWeapons[Players:GetNameFromUserIdAsync(data.id).Name][data.uuid]
    if weaponInstance then
        weaponInstance.PrimaryPart:Lerp(data.cframe, 0.5)
    end
end)

local function sendWeaponUpdate(id, uuid, cframe)
    local data = {
        id = id,
        uuid = uuid,
        cframe = cframe
    }
    
    WeaponPacket.onServerUpdate(data)
end
