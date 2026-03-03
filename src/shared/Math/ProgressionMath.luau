--!strict

local MathUtil = require(script.Parent.Parent.Util.MathUtil)

local ProgressionMath = {}

local function logistic(x: number, midpoint: number, steepness: number): number
	return 1 / (1 + math.exp(-steepness * (x - midpoint)))
end

local function zoneCost(level: number, params: {
	BaseCost: number,
	EarlyLinear: number,
	LateLinear: number,
	LateQuadratic: number,
	Midpoint: number,
	Steepness: number,
}?): number
	local p = params or {
		BaseCost = 50,
		EarlyLinear = 35,
		LateLinear = 120,
		LateQuadratic = 4,
		Midpoint = 20,
		Steepness = 0.18,
	}

	local n = math.max(level, 1)
	local blend = logistic(n, p.Midpoint, p.Steepness)
	local linearRate = MathUtil.lerp(p.EarlyLinear, p.LateLinear, blend)
	local quadraticRate = p.LateQuadratic * blend

	return math.floor(p.BaseCost + linearRate * n + quadraticRate * (n * n))
end

local function xpForLevel(level: number): number
	local n = math.max(level, 1)
	local blend = logistic(n, 15, 0.22)
	local early = 40 + (12 * n)
	local late = 120 + (25 * n) + (2 * n * n)
	return math.floor(MathUtil.lerp(early, late, blend))
end

local function totalXpToReach(level: number): number
	local total = 0
	for currentLevel = 1, math.max(level - 1, 0) do
		total += xpForLevel(currentLevel)
	end
	return total
end

ProgressionMath.zoneCost = zoneCost
ProgressionMath.xpForLevel = xpForLevel
ProgressionMath.totalXpToReach = totalXpToReach

return ProgressionMath
