-- Data_Mobs.lua
-- Shared mob definitions and global mob-spawn settings.

local Data_Mobs = {
	Zones = {
		["Castle"] = {
			Mobs = {
				["Chest Mimic"] = {
					Name = "Chest Mimic",
					ParentZone = "Castle",
					ModelTemplate = "ChestMimic",
					DefaultHealth = 100,
					HealthValue = 100,
					AttackValue = 1,
					CoinValue = 10,
					GemValue = 0,
					Weight = 60,
					CanBeEngaged = false,
				},
				["Chest Mimic 2"] = {
					Name = "Chest Mimic 2",
					ParentZone = "Castle",
					ModelTemplate = "ChestMimic2",
					DefaultHealth = 100,
					HealthValue = 100,
					AttackValue = 1,
					CoinValue = 10,
					GemValue = 0,
					Weight = 40,
					CanBeEngaged = false,
				},
			},
		},
	},
	Settings = {
		SpawnIntervals = 10,
		MinimumDistance = 100,
		MobCursor = "rbxassetid://139652821759028",
		DisengageCursor = "rbxassetid://100382422313044",
		Icons = {
			AlarmedIcon = "rbxassetid://111847898662707",
			TargetIcon = "rbxassetid://79817429248444",
			DeathIcon = "rbxassetid://108877701366175",
			VictoryIcon = "rbxassetid://87187170692394",
		},
	},
}

return Data_Mobs
