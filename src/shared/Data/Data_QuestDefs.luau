--!strict

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local Data_QuestDefs = {
	Daily_CastleKills = {
		Objective = {
			Type = "KillMob",
			TargetId = "ChestMimic",
			RequiredCount = 10,
		},
		ResetCadence = "Daily",
		Rewards = {
			Gold = 100,
			Gems = 1,
		},
		ClaimRequirements = {
			MustCompleteObjective = true,
		},
	},
	Daily_OpenCases = {
		Objective = {
			Type = "OpenCase",
			TargetId = "StarterCase",
			RequiredCount = 3,
		},
		ResetCadence = "Daily",
		Rewards = {
			Gold = 75,
			Gems = 1,
		},
		ClaimRequirements = {
			MustCompleteObjective = true,
		},
	},
}

return TableUtil.deepFreeze(Data_QuestDefs)
