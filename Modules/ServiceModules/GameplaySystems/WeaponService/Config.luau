--!strict

export type Config = {
	AttackActionName: string,
	EquipActionName: string,
	MaxMobIdLength: number,
	MaxWeaponUidLength: number,
	MaxSlotLength: number,
	WeaponStateFlushIntervalSeconds: number,
	EquipmentRefreshIntervalSeconds: number,
	SlotPriority: {string},
	DefaultCadencePerSecond: number,
	DefaultBaseDps: number,
	DefaultRangeStuds: number,
	DamageMultiplier: number,
	RangePaddingStuds: number,
	AttackCatchUpLimitPerTick: number,
}

local Config: Config = {
	AttackActionName = "Attack",
	EquipActionName = "Equip",
	MaxMobIdLength = 80,
	MaxWeaponUidLength = 120,
	MaxSlotLength = 80,
	WeaponStateFlushIntervalSeconds = 0.1,
	EquipmentRefreshIntervalSeconds = 0.5,
	SlotPriority = {"PrimaryWeapon", "SecondaryWeapon", "TertiaryWeapon", "QuaternaryWeapon"},
	DefaultCadencePerSecond = 1,
	DefaultBaseDps = 1,
	DefaultRangeStuds = 12,
	DamageMultiplier = 1,
	RangePaddingStuds = 3,
	AttackCatchUpLimitPerTick = 2,
}

return table.freeze(Config)
