-- SERVICES --
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

-- MODULES --
local WeaponPacket = require(ReplicatedStorage.Shared.Network.WeaponPacket)
local WeaponClass = require(ReplicatedStorage.Shared.Classes.Weapon)

-- VARIABLES -- 
local Player = Players.LocalPlayer
local ServerWeapons = workspace:WaitForChild('Weapons')
local PlayerWeapons = {}

-- FUNCTIONS --

--[[WeaponPacket.onServerUpdate(function(data)
    local weaponInstance = ServerWeapons[Players:GetNameFromUserIdAsync(data.id).Name][data.uuid]
    if weaponInstance then
        weaponInstance.PrimaryPart:Lerp(data.cframe, 0.5)
    end
end)]]

WeaponPacket.updateWeaponState.listen(function(data)
    print(`server says { data }`)
end)
