--!strict

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local Data_EconomyDefs = {
	Currencies = {
		Gold = {
			Cap = 10_000_000,
		},
		Gems = {
			Cap = 1_000_000,
		},
	},
	ZonePrices = {
		Starter = 0,
		Castle = 100,
		CastleDungeon = 1_000,
	},
	BoostCaps = {
		Damage = 3,
		DropRate = 2,
		GoldGain = 4,
	},
	SellMultipliers = {
		Common = 1,
		Uncommon = 1.25,
		Rare = 1.6,
		Epic = 2.25,
		Legendary = 3.5,
		Mythic = 5,
	},
	PremiumCatalog = {
		SmallGoldPack = 0,
		MediumGoldPack = 0,
		LargeGoldPack = 0,
		StarterBundle = 0,
	},
}

return TableUtil.deepFreeze(Data_EconomyDefs)
