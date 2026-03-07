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
	SpawnMaxOperationsPerSimulationStep: number,
	ZonePopulationRefreshIntervalSeconds: number,
	SpawnCollisionRadius: number,
	SpawnCollisionHeight: number,
	SpawnMinSeparationStuds: number,
	SpawnMinSeparationFloorStuds: number,
	SpawnSeparationRelaxPerFailureStuds: number,
	SpawnSeparationRelaxStartFailures: number,
	SpawnIgnoreSeparationAfterFailures: number,
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
	RoamLocalDestinationBias: number,
	RoamMinTravelDistanceStuds: number,
	RoamMaxTravelDistanceStuds: number,
	RoamCollisionRadius: number,
	RoamCollisionHeight: number,
	RoamSeparationRadius: number,
	RoamSeparationWeight: number,
	MobGroundOffset: number,
	DebugReplicateZoneIdInUpdate: boolean,
	DebugSpawnProgressEnabled: boolean,
	DebugSpawnProgressIntervalSeconds: number,
	DebugClientRenderReportEnabled: boolean,
	DebugClientRenderReportIntervalSeconds: number,
}

local Config: Config = {
	-- MOST LIKELY TO TWEAK (movement feel / smoothness)
	SimulationStepIntervalSeconds = 1/60, -- Server sim step size. Lower = smoother (e.g. 1/30 or 1/60).
	ReplicationFlushIntervalSeconds = 0.2, -- How often mob deltas are flushed to clients.
	ReplicationDistanceLimitStuds = 0, -- 0 disables distance culling; replicate all mobs in the player's current zone.
	RoamSpeedMultiplier = 0.5, -- Global multiplier for roam speed (applied to MobDefs.MoveSpeed).
	RoamMinSpeedStudsPerSecond = 1, -- Floor speed after multiplier.
	RoamIdleMinSeconds = 10, -- Minimum idle duration before choosing a roam destination.
	RoamIdleMaxSeconds = 30, -- Maximum idle duration before choosing a roam destination.
	RoamMoveDurationMinSeconds = 5, -- Minimum time roaming before forcing idle again.
	RoamMoveDurationMaxSeconds = 10, -- Maximum time roaming before forcing idle again.
	RoamArrivalDistanceStuds = 1.5, -- Consider destination reached within this radius.
	RoamLocalDestinationBias = 0.75, -- Chance to sample a destination around current position instead of zone-wide random.
	RoamMinTravelDistanceStuds = 10, -- Minimum distance for a new roam destination from current position.
	RoamMaxTravelDistanceStuds = 42, -- Maximum preferred local roam hop distance before falling back to zone-wide sampling.
	RoamSeparationRadius = 10, -- Nearby-mob separation influence radius while roaming.
	RoamSeparationWeight = 1.15, -- Strength of separation steering.

	-- OFTEN TWEAKED (spawn density / roam collision behavior)
	DefaultMaxMobsPerZone = 3, -- Fallback max mobs when zone data does not provide MaxMobs.
	SpawnSampleAttemptsPerMob = 48, -- Spawn sampling attempts when validating a spawn position.
	SpawnMaxOperationsPerSimulationStep = 1, -- Max spawn/respawn attempts processed per simulation step.
	ZonePopulationRefreshIntervalSeconds = 0.2, -- How often zone player-presence is refreshed for spawn gating.
	SpawnMinSeparationStuds = 25, -- Minimum spawn spacing between mobs.
	SpawnMinSeparationFloorStuds = 0, -- Lowest possible spacing after repeated spawn failures.
	SpawnSeparationRelaxPerFailureStuds = 2.5, -- Spacing reduction per failed attempt (after relax start).
	SpawnSeparationRelaxStartFailures = 2, -- Number of failures before spacing relaxation starts.
	SpawnIgnoreSeparationAfterFailures = 8, -- At/after this many failures, separation no longer blocks spawn.
	SpawnZoneInsetStuds = 4, -- Inset from zone edge while sampling spawn points.
	SpawnCollisionRadius = 2.5, -- Spawn collision check radius.
	SpawnCollisionHeight = 6, -- Spawn collision check height.
	RoamDestinationSampleAttempts = 20, -- Destination sampling attempts each roam cycle (higher = less clustering, more CPU).
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
	DebugSpawnProgressEnabled = true, -- Temporary: print zone spawn progression counters on server.
	DebugSpawnProgressIntervalSeconds = 1, -- Seconds between spawn debug counter prints.
	DebugClientRenderReportEnabled = true, -- Accept and print client render parity reports.
	DebugClientRenderReportIntervalSeconds = 1, -- Server-side print throttle per player for client render reports.
}

return table.freeze(Config)
