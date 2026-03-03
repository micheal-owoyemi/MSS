local Data_Player = {
	Meta = {
		CreatedAt = 0,
		LastOnline = 0,
		TotalPlayTime = 0,
		LastDailyReset = 0,
	},

	Progression = {
		Level = 1,
		XP = 0,
	},

	Currencies = {
		Gold = 0,
	},

	Inventory = {
		Weapons = {},
	},

	Settings = {},

	Flags = {
		HasCompletedTutorial = false,
		ClaimedStarterPack = false,
	},
}

return Data_Player
