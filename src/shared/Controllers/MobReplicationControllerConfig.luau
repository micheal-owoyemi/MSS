--!strict

export type Config = {
	SphereSize: number,
	RenderHeightOffset: number,
	DefaultGroundY: number,
	PositionSmoothingK: number,
	MinSmoothingAlpha: number,
	MaxSmoothingAlpha: number,
	SnapDistanceStuds: number,
}

local Config: Config = {
	-- MOST LIKELY TO TWEAK (visual smoothness feel)
	PositionSmoothingK = 12, -- Higher = tighter follow (less lag), lower = softer smoothing.
	MinSmoothingAlpha = 0.03, -- Lower bound so lerp still moves on very small dt.
	MaxSmoothingAlpha = 1, -- Upper bound for lerp alpha; keep at 1 unless debugging.
	SnapDistanceStuds = 45, -- If target jump exceeds this, snap instead of lerping.

	-- SOMETIMES TWEAK (debug visuals)
	RenderHeightOffset = 2, -- How high the debug sphere sits above groundY.
	SphereSize = 4, -- Debug sphere size.

	-- RARELY TWEAK (fallback safety)
	DefaultGroundY = 3, -- Fallback Y if add packet does not include groundY.
}

return table.freeze(Config)
