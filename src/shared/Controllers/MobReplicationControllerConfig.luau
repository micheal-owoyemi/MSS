--!strict

export type Config = {
	DefaultGroundY: number,
	ModelRenderRootPath: {string},
	PositionSmoothingK: number,
	VelocitySmoothingK: number,
	PredictionLeadSeconds: number,
	MaxPredictedSpeedStudsPerSecond: number,
	MaxCatchUpSpeedStudsPerSecond: number,
	MinSmoothingAlpha: number,
	MaxSmoothingAlpha: number,
	SnapDistanceStuds: number,
	MinVelocitySampleSeconds: number,
	RenderPoseMinDistanceStuds: number,
	RenderPoseFacingDotThreshold: number,
	MaxVisualCreatesPerFrame: number,
	VisualCreateMinIntervalSeconds: number,
	VisualCreateSkipWhenFrameDtAboveSeconds: number,
	TemplatePrewarmEnabled: boolean,
	TemplatePrewarmPerStep: number,
	TemplatePrewarmStepIntervalSeconds: number,
	TemplateContentPreloadEnabled: boolean,
	DisableMobShadows: boolean,
}

local Config: Config = {
	-- MOST LIKELY TO TWEAK (visual smoothness feel)
	PositionSmoothingK = 14, -- Higher = tighter follow (less lag), lower = softer smoothing.
	VelocitySmoothingK = 10, -- How quickly estimated server velocity reacts to incoming deltas.
	PredictionLeadSeconds = 0.08, -- Extrapolation horizon to smooth sparse updates.
	MinSmoothingAlpha = 0.03, -- Lower bound so lerp still moves on very small dt.
	MaxSmoothingAlpha = 1, -- Upper bound for lerp alpha.
	SnapDistanceStuds = 45, -- If target jump exceeds this, snap instead of lerping.
	MaxPredictedSpeedStudsPerSecond = 35, -- Cap on extrapolated speed used for prediction.
	MaxCatchUpSpeedStudsPerSecond = 120, -- Cap render-step catch-up speed to avoid visible jumps.
	RenderPoseMinDistanceStuds = 0.015, -- Skip PivotTo if XZ movement is below this threshold.
	RenderPoseFacingDotThreshold = 0.9999, -- Skip PivotTo if facing change is below this dot threshold.
	MaxVisualCreatesPerFrame = 1, -- Limit new mob model creations per render frame to reduce GPU spikes.
	VisualCreateMinIntervalSeconds = 1 / 30, -- Minimum interval between successful visual creates (smooths bursty GPU load).
	VisualCreateSkipWhenFrameDtAboveSeconds = 1 / 45, -- If frame dt is above this, skip visual creation that frame to avoid compounding hitches.
	TemplatePrewarmEnabled = true, -- Pre-prepare template caches in the background to avoid first-spawn hitching.
	TemplatePrewarmPerStep = 1, -- Number of templates prepared per background prewarm step.
	TemplatePrewarmStepIntervalSeconds = 0.03, -- Delay between prewarm steps.
	TemplateContentPreloadEnabled = true, -- Preload template mesh/texture content during prewarm to reduce first-visible GPU uploads.
	DisableMobShadows = true, -- Disable CastShadow on client mob visuals to reduce GPU cost during burst spawns.
	ModelRenderRootPath = {"Game", "MobsClient"}, -- Workspace path for client-rendered mob models.

	-- RARELY TWEAK (fallback safety)
	DefaultGroundY = 3, -- Fallback Y if add packet does not include groundY.
	MinVelocitySampleSeconds = 1 / 120, -- Lower bound for velocity sample interval.
}

return table.freeze(Config)
