--!strict

export type Config = {
	SimulationStepIntervalSeconds: number,
	ReplicationFlushIntervalSeconds: number,
	MaxSimulationStepsPerTick: number,
	PositionChangeThresholdStuds: number,
	FacingDotThreshold: number,
	ReplicationDistanceLimitStuds: number,
	MaxAddsPerFlushPerPlayer: number,
	MaxUpdatesPerFlushPerPlayer: number,
	MaxRemovesPerFlushPerPlayer: number,
	MaxTotalMobEntriesPerFlush: number,
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
	FallbackSpawnPointsPerZone: number,
	FallbackSpawnInsetStuds: number,
	FallbackSpawnHeightOffset: number,
	DefaultMaxMobsPerZone: number,
	SpawnSampleAttemptsPerMob: number,
	SpawnCollisionRadius: number,
	SpawnCollisionHeight: number,
	SpawnMinSeparationStuds: number,
	SpawnZoneInsetStuds: number,
	ZoneContainmentPadding: number,
	RoamIdleMinSeconds: number,
	RoamIdleMaxSeconds: number,
	RoamMoveDurationMinSeconds: number,
	RoamMoveDurationMaxSeconds: number,
	RoamSpeedMultiplier: number,
	RoamMinSpeedStudsPerSecond: number,
	RoamArrivalDistanceStuds: number,
	RoamDestinationSampleAttempts: number,
	RoamDestinationInsetStuds: number,
	RoamCollisionRadius: number,
	RoamCollisionHeight: number,
	RoamSeparationRadius: number,
	RoamSeparationWeight: number,
	MobGroundOffset: number,
	DebugReplicateZoneIdInUpdate: boolean,
}

local Config: Config = {
	-- MOST LIKELY TO TWEAK (movement feel / smoothness)
	SimulationStepIntervalSeconds = 1/60, -- Server sim step size. Lower = smoother (e.g. 1/30 or 1/60).
	ReplicationFlushIntervalSeconds = 0.2, -- How often mob deltas are flushed to clients.
	ReplicationDistanceLimitStuds = 280, -- Max distance for a player to receive mob updates.
	RoamSpeedMultiplier = 0.5, -- Global multiplier for roam speed (applied to MobDefs.MoveSpeed).
	RoamMinSpeedStudsPerSecond = 1, -- Floor speed after multiplier.
	RoamIdleMinSeconds = 10, -- Minimum idle duration before choosing a roam destination.
	RoamIdleMaxSeconds = 30, -- Maximum idle duration before choosing a roam destination.
	RoamMoveDurationMinSeconds = 5, -- Minimum time roaming before forcing idle again.
	RoamMoveDurationMaxSeconds = 10, -- Maximum time roaming before forcing idle again.
	RoamArrivalDistanceStuds = 1.5, -- Consider destination reached within this radius.
	RoamSeparationRadius = 6, -- Nearby-mob separation influence radius while roaming.
	RoamSeparationWeight = 0.75, -- Strength of separation steering.

	-- OFTEN TWEAKED (spawn density / roam collision behavior)
	DefaultMaxMobsPerZone = 3, -- Fallback max mobs when zone data does not provide MaxMobs.
	SpawnSampleAttemptsPerMob = 30, -- Spawn sampling attempts per slot.
	SpawnMinSeparationStuds = 7, -- Minimum spawn spacing between mobs.
	SpawnZoneInsetStuds = 4, -- Inset from zone edge while sampling spawn points.
	SpawnCollisionRadius = 2.5, -- Spawn collision check radius.
	SpawnCollisionHeight = 6, -- Spawn collision check height.
	RoamDestinationSampleAttempts = 10, -- Destination sampling attempts each roam cycle.
	RoamDestinationInsetStuds = 4, -- Inset from zone edge while sampling roam destinations.
	RoamCollisionRadius = 2.25, -- Roam step collision check radius.
	RoamCollisionHeight = 6, -- Roam step collision check height.
	ZoneContainmentPadding = 0, -- Extra bounds padding for zone containment checks.

	-- RARELY TWEAKED (network budgets / safety / combat guards)
	MaxSimulationStepsPerTick = 3, -- Caps catch-up sim loops in a single manager tick.
	MaxAddsPerFlushPerPlayer = 20, -- Per-flush cap on newly visible mobs per player.
	MaxUpdatesPerFlushPerPlayer = 30, -- Per-flush cap on update entries per player.
	MaxRemovesPerFlushPerPlayer = 30, -- Per-flush cap on remove entries per player.
	MaxTotalMobEntriesPerFlush = 50, -- Hard ceiling per packet build.
	PositionChangeThresholdStuds = 0.2, -- Threshold for position-change revision bumps.
	FacingDotThreshold = 0.999, -- Facing-change sensitivity (dot product threshold).
	MinDamagePerHit = 0.01, -- Reject damage below this amount.
	MaxDamagePerHit = 5_000_000, -- Reject damage above this amount.
	ContributionEligibilityWindowSeconds = 30, -- Contribution timeout window.
	ContributionMinDamage = 0, -- Minimum cumulative contribution to be eligible.
	AttackCooldownSeconds = 1.25, -- Fallback attack cooldown if def missing.
	AttackRangeDefault = 10, -- Fallback attack range if def missing.
	AggroLockDurationDefault = 4, -- Fallback aggro lock duration if def missing.
	DefaultRespawnDelaySeconds = 10, -- Fallback respawn delay.
	RespawnFailureRetrySeconds = 5, -- Retry delay when spawn fails.

	-- PATHS / FALLBACKS (infrastructure)
	SpawnRootPath = {"Game", "Mobs"}, -- Workspace path for server proxy mob models.
	AssetsRootPath = {"Assets", "Mobs"}, -- ReplicatedStorage path for mob templates.
	FallbackSpawnPointsPerZone = 3, -- Fallback point count when sampling cannot resolve.
	FallbackSpawnInsetStuds = 8, -- Fallback point inset from zone bounds.
	FallbackSpawnHeightOffset = 3, -- Fallback Y offset if zone ground cannot be resolved.
	MobGroundOffset = 0, -- Offset applied above zone ground plane for mob simulation Y.

	-- DEBUG / DEV
	DebugReplicateZoneIdInUpdate = false, -- Include zone id in update deltas for debug.
}

return table.freeze(Config)
