--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TableUtil = require(ReplicatedStorage.Util.TableUtil)

local Data_WeaponDefs = {
	RustySword = {
		DisplayName = "Wooden Sword",
		BaseDPS = 1,
		Cadence = 1,
		Rarity = "Common",
		VisualAssetId = 0,
		ZoneTier = 1,
		SellValue = 5,
		CaseEligibility = {"StarterCase"},
	},
}

return TableUtil.deepFreeze(Data_WeaponDefs)
