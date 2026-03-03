local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage.Shared.ByteNet)

return ByteNet.defineNamespace("Gameplay", function()
	return {
		requestMobAttack = ByteNet.definePacket({
			value = ByteNet.struct({
				target = ByteNet.inst,
			}),
			reliabilityType = "reliable",
		}),
		mobDeath = ByteNet.definePacket({
			value = ByteNet.struct({
				mob = ByteNet.inst,
			}),
			reliabilityType = "reliable",
		}),
		mobDeathFX = ByteNet.definePacket({
			value = ByteNet.struct({
				position = ByteNet.vec3,
			}),
			reliabilityType = "reliable",
		}),
		mobAttackFX = ByteNet.definePacket({
			value = ByteNet.struct({
				position = ByteNet.vec3,
			}),
			reliabilityType = "unreliable",
		}),
		coinDrop = ByteNet.definePacket({
			value = ByteNet.struct({
				origin = ByteNet.cframe,
				reward = ByteNet.float32,
			}),
			reliabilityType = "reliable",
		}),
	}
end)
