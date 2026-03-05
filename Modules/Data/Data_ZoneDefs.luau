--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TableUtil = require(ReplicatedStorage.Util.TableUtil)

local Data_ZoneDefs = {
	Castle = {
		DisplayName = "Castle",
		UnlockRequirement = {
			Currency = "Gold",
			Amount = 0,
		},
		MobSpawnTable = {
			{MobId = "ChestMimic", Weight = 60},
			{MobId = "ChestMimic2", Weight = 40},
		},
		SpawnPoints = {
			Vector3.new(24, 5, 20),
			Vector3.new(-18, 5, 14),
			Vector3.new(7, 5, -16),
		},
		TeleportPoints = {
			Default = Vector3.new(0, 5, 0),
		},
		Bounds = {
			Min = Vector3.new(-256, 0, -256),
			Max = Vector3.new(256, 256, 256),
		},
	},
}

return TableUtil.deepFreeze(Data_ZoneDefs)
