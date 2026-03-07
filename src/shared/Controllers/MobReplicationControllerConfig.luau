--!strict

export type Config = {
	SphereSize: number,
	RenderHeightOffset: number,
	DefaultGroundY: number,
	RenderDebugSpheres: boolean,
	ModelRenderRootPath: {string},
	SphereRenderRootPath: {string},
	PositionSmoothingK: number,
	VelocitySmoothingK: number,
	PredictionLeadSeconds: number,
	MaxPredictedSpeedStudsPerSecond: number,
	MaxCatchUpSpeedStudsPerSecond: number,
	MinSmoothingAlpha: number,
	MaxSmoothingAlpha: number,
	SnapDistanceStuds: number,
	MinVelocitySampleSeconds: number,
	MaxVisualCreatesPerFrame: number,
	ServerProxyRootPath: {string},
	DebugCompareMobsEnabled: boolean,
	DebugCompareIntervalSeconds: number,
}

local Config: Config = {
	-- MOST LIKELY TO TWEAK (render mode)
	RenderDebugSpheres = false, -- false = render asset models, true = render debug spheres.

	-- MOST LIKELY TO TWEAK (visual smoothness feel)
	PositionSmoothingK = 14, -- Higher = tighter follow (less lag), lower = softer smoothing.
	VelocitySmoothingK = 10, -- How quickly estimated server velocity reacts to incoming deltas.
	PredictionLeadSeconds = 0.08, -- Extrapolation horizon to smooth sparse updates.
	MinSmoothingAlpha = 0.03, -- Lower bound so lerp still moves on very small dt.
	MaxSmoothingAlpha = 1, -- Upper bound for lerp alpha; keep at 1 unless debugging.
	SnapDistanceStuds = 45, -- If target jump exceeds this, snap instead of lerping.
	MaxPredictedSpeedStudsPerSecond = 35, -- Cap on extrapolated speed used for prediction.
	MaxCatchUpSpeedStudsPerSecond = 120, -- Cap render-step catch-up speed to avoid visible jumps.
	MaxVisualCreatesPerFrame = 1, -- Limit new mob model creations per render frame to reduce GPU spikes.
	DebugCompareMobsEnabled = true, -- Print proxy vs client-render counts and reconcile missing visuals.
	DebugCompareIntervalSeconds = 1, -- Interval for client-side compare/reconcile debug.

	-- SOMETIMES TWEAK (debug visuals)
	RenderHeightOffset = 2, -- How high the debug sphere sits above groundY.
	SphereSize = 4, -- Debug sphere size.
	ModelRenderRootPath = {"Game", "MobsClient"}, -- Workspace path for client-rendered mob models.
	SphereRenderRootPath = {"Game", "MobDebugSpheres"}, -- Workspace path for debug spheres.
	ServerProxyRootPath = {"Game", "Mobs"}, -- Workspace path for authoritative server proxy mob models.

	-- RARELY TWEAK (fallback safety)
	DefaultGroundY = 3, -- Fallback Y if add packet does not include groundY.
	MinVelocitySampleSeconds = 1 / 120, -- Lower bound for velocity sample interval.
}

return table.freeze(Config)
