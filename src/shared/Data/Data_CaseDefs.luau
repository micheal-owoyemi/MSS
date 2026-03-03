--!strict

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local Data_CaseDefs = {
	StarterCase = {
		Cost = 25,
		CurrencyType = "Gold",
		RarityWeights = {
			Common = 70,
			Uncommon = 25,
			Rare = 5,
		},
		PityRules = {
			RollsUntilGuaranteed = 25,
			GuaranteedRarity = "Rare",
		},
		CandidateLootPool = {
			Common = {"RustySword"},
			Uncommon = {"KnightBlade"},
			Rare = {"RoyalClaymore"},
		},
	},
	CastleCase = {
		Cost = 150,
		CurrencyType = "Gold",
		RarityWeights = {
			Uncommon = 65,
			Rare = 28,
			Epic = 7,
		},
		PityRules = {
			RollsUntilGuaranteed = 40,
			GuaranteedRarity = "Epic",
		},
		CandidateLootPool = {
			Uncommon = {"KnightBlade"},
			Rare = {"RoyalClaymore"},
			Epic = {},
		},
	},
}

return TableUtil.deepFreeze(Data_CaseDefs)
