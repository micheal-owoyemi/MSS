--!strict

export type Config = {
	StepIntervalSeconds: number,
	MaxDamagePerHit: number,
	MinDamagePerHit: number,
	DefaultRespawnDelaySeconds: number,
	RespawnFailureRetrySeconds: number,
	SpawnRootPath: {string},
	AssetsRootPath: {string},
	AttackCooldownSeconds: number,
	AttackRangeDefault: number,
	AggroLockDurationDefault: number,
	ContributionEligibilityWindowSeconds: number,
	ContributionMinDamage: number,
}

local Config: Config = {
	StepIntervalSeconds = 0.2,
	MaxDamagePerHit = 5_000_000,
	MinDamagePerHit = 0.01,
	DefaultRespawnDelaySeconds = 10,
	RespawnFailureRetrySeconds = 5,
	SpawnRootPath = {"Game", "Mobs"},
	AssetsRootPath = {"Assets", "Mobs"},
	AttackCooldownSeconds = 1.25,
	AttackRangeDefault = 10,
	AggroLockDurationDefault = 4,
	ContributionEligibilityWindowSeconds = 30,
	ContributionMinDamage = 0,
}

return table.freeze(Config)
