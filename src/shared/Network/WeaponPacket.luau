local WeaponPacket = {}
WeaponPacket.__index = WeaponPacket

-- SERVICES / LIBRARIES -- 

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local ByteNet = require(ReplicatedStorage.Shared.ByteNet)


-- PACKET DEFINITION --
local WeaponReplication = ByteNet.defineNamespace("WeaponReplication", function()
    return {
        updateWeaponState = ByteNet.definePacket({
            value = ByteNet.struct{
                id = ByteNet.int32,
                uuid = ByteNet.string,
                cframe = ByteNet.cframe,
            },

            reliabilityType = 'unreliable'
        })
        
    }
end)

-- FUNCTIONS -- 
function WeaponPacket.broadcastUpdate(player, id, uuid, cframe)
    WeaponReplication.updateWeaponState.sendToAllExcept({
        id = id,
        uuid = uuid,
        cframe = cframe
    }, player)
end -- Broadcast weapon update to all clients except sender

function WeaponPacket.onClientUpdate(callback)
    WeaponReplication.updateWeaponState.listen(callback)
end -- Event handler for server-side weapon state updates from clients

function WeaponPacket.onServerUpdate(callback)
    WeaponReplication.updateWeaponState.listen(callback)
end -- Event handler for client-side weapon updates from server

return WeaponPacket