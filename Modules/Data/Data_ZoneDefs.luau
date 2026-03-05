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

		},
		TeleportPoints = {
			Default = {},
		},
		Bounds = {
		},
	},
}

return TableUtil.deepFreeze(Data_ZoneDefs)
