--!strict

local MathUtil = {}

local function clamp(value: number, minValue: number, maxValue: number): number
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function roundHalfAwayFromZero(value: number): number
	if value >= 0 then
		return math.floor(value + 0.5)
	end
	return math.ceil(value - 0.5)
end

MathUtil.clamp = clamp
MathUtil.lerp = lerp
MathUtil.roundHalfAwayFromZero = roundHalfAwayFromZero

return MathUtil
