--!strict

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local Data_WeaponDefs = {
	RustySword = {
		DisplayName = "Rusty Sword",
		BaseDPS = 6,
		Cadence = 1,
		Rarity = "Common",
		Range = 12,
		VisualAssetId = 0,
		ZoneTier = 1,
		SellValue = 5,
		CaseEligibility = {"StarterCase"},
	},
	KnightBlade = {
		DisplayName = "Knight Blade",
		BaseDPS = 12,
		Cadence = 1.1,
		Rarity = "Uncommon",
		Range = 13,
		VisualAssetId = 0,
		ZoneTier = 1,
		SellValue = 18,
		CaseEligibility = {"StarterCase", "CastleCase"},
	},
	RoyalClaymore = {
		DisplayName = "Royal Claymore",
		BaseDPS = 20,
		Cadence = 0.95,
		Rarity = "Rare",
		Range = 15,
		VisualAssetId = 0,
		ZoneTier = 2,
		SellValue = 60,
		CaseEligibility = {"CastleCase"},
	},
}

return TableUtil.deepFreeze(Data_WeaponDefs)
