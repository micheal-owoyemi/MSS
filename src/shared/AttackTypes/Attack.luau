local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkApi = require(ReplicatedStorage.Shared.Network.NetworkApi)
local GameplayPacket = NetworkApi.Packets.Gameplay

local function attack(mobInstance: Instance)
	if mobInstance then
		GameplayPacket.requestMobAttack.send({
			target = mobInstance,
		})
	end
end

return function(mobInstance: Instance)
	attack(mobInstance)
end
