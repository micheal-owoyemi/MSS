--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TableUtil = require(ReplicatedStorage.Util.TableUtil)

local Data_MobDefs = {
	ChestMimic = {
		DisplayName = "Chest Mimic",
		Archetype = "Melee",
		BaseHP = 100,
		Damage = 1,
		AttackRange = 10,
		AttackCooldown = 1.2,
		AggroLockDuration = 4,
		MoveSpeed = 12,
		RespawnDelay = 10,
		DropTableId = "ChestMimic",
		Rewards = {
			Gold = 10,
			Gems = 0,
		},
	},
	ChestMimic2 = {
		DisplayName = "Chest Mimic 2",
		Archetype = "Melee",
		BaseHP = 100,
		Damage = 1,
		AttackRange = 11,
		AttackCooldown = 1.15,
		AggroLockDuration = 4,
		MoveSpeed = 13,
		RespawnDelay = 10,
		DropTableId = "ChestMimic2",
		Rewards = {
			Gold = 10,
			Gems = 0,
		},
	},
}

return TableUtil.deepFreeze(Data_MobDefs)
