-- SERVICES --
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

-- MODULES --
local WeaponPacket = require(ReplicatedStorage.Shared.Network.WeaponPacket)

-- VARIABLES --
local WeaponStates = {}

-- FUNCTIONS -- 

local function broadcastUpdate(id, uuid, position, orientation) -- Broadcast weapon update to all clients except sender
    if not id or not uuid or not position or not orientation then return end

    WeaponPacket.updateWeaponState.sendToAllExcept({
        id = id,
        uuid = uuid,
        position = position,
        orientation = orientation
    }, Players:GetPlayerByUserId(id))
end 


local function updateWeaponStateOnServer(id, uuid, position, orientation) -- Update Weapon States on Server Table
    if not id or not uuid or not position or not orientation then return end

    WeaponStates[id] = WeaponStates[id] or {}
    WeaponStates[id][uuid] = {
        position  = position,
        orientation = orientation
    }

    broadcastUpdate(id, uuid, position, orientation)
end 

WeaponPacket.updateWeaponState.listen(function(data, player) -- Listen for when a packet is sent from Client(s)
    updateWeaponStateOnServer(player.UserId, data.uuid, data.position, data.orientation)
end)

Players.PlayerRemoving:Connect(function(player) -- Removes from table when player leaves
    WeaponStates[player.UserId] = nil
end) 