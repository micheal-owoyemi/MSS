-- SERVICES --
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

-- MODULES --
local WeaponPacket = require(ReplicatedStorage.Shared.Network.WeaponPacket)

-- VARIABLES --
local WeaponStates = {}

-- FUNCTIONS -- 
local function updateWeaponStateOnServer(id, uuid, newCframe)
    WeaponStates[id] = WeaponStates[id] or {}
    
    WeaponStates[id][uuid] = {
        cframe = newCframe
    }
    
    WeaponPacket.broadcastUpdate(id, uuid, newCframe)
end -- Broadcast update to all players


WeaponPacket.onClientUpdate(function(player, data)
    updateWeaponStateOnServer(player.UserId, data.uuid, data.cframe)
end) -- Event listener for client weapon state updates


Players.PlayerRemoving:Connect(function(player)
    WeaponStates[player.UserId] = nil
end) -- Clean up on player leave