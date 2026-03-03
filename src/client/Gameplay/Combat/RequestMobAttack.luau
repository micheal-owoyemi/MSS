local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkApi = require(ReplicatedStorage.Shared.Network.NetworkApi)
local GameplayPacket = NetworkApi.Packets.Gameplay

return function(mobInstance: Instance)
	if mobInstance then
		GameplayPacket.requestMobAttack.send({
			target = mobInstance,
		})
	end
end
