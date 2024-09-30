-- SERVICES / LIBRARIES -- 

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local ByteNet = require(ReplicatedStorage.Shared.ByteNet)


-- PACKET DEFINITION --
return ByteNet.defineNamespace("WeaponReplication", function()
    return {
        updateWeaponState = ByteNet.definePacket({
            value = ByteNet.struct{
                id = ByteNet.int32,
                uuid = ByteNet.string,
                position = ByteNet.vec3,
                orientation = ByteNet.vec3
            },

            reliabilityType = 'unreliable'
        })
        
    }
end)


--[[
-- FUNCTIONS -- 


function WeaponPacket.onClientUpdate(callback)
    WeaponReplication.updateWeaponState.listen(callback)
end -- Event handler for server-side weapon state updates from clients

function WeaponPacket.onServerUpdate(callback)
    WeaponReplication.updateWeaponState.listen(callback)
end -- Event handler for client-side weapon updates from server

return WeaponReplication]]