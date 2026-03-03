-- Data_Mobs.lua
-- Shared mob definitions and global mob-spawn settings.

local Data_Mobs = {
	Zones = {
		["Castle"] = {
			Mobs = {
				["Chest Mimic"] = {
					Name = "Chest Mimic",
					HealthValue = 100,
					AttackValue = 1,
					CoinValue = 10,
					GemValue = 1,
					Weight = 60,
				},
				["Chest Mimic 2"] = {
					Name = "Chest Mimic 2",
					HealthValue = 100,
					AttackValue = 1,
					CoinValue = 10,
					GemValue = 1,
					Weight = 40,
				},
			},
		},
	},
	Settings = {
		SpawnIntervals = 10,
		MinimumDistance = 100,
		MobCursor = "rbxassetid://139652821759028",
		DisengageCursor = "rbxassetid://100382422313044",
	},
}

return Data_Mobs
