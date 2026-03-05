--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TableUtil = require(ReplicatedStorage.Util.TableUtil)

local Data_DropTables = {
	ChestMimic = {
		RollsPerKill = 1,
		Entries = {
			{
				DefId = "HealthPotion",
				Chance = 0.08,
				MinQuantity = 1,
				MaxQuantity = 1,
			},
		},
	},
	ChestMimic2 = {
		RollsPerKill = 1,
		Entries = {
			{
				DefId = "HealthPotion",
				Chance = 0.11,
				MinQuantity = 1,
				MaxQuantity = 2,
			},
		},
	},
}

return TableUtil.deepFreeze(Data_DropTables)
