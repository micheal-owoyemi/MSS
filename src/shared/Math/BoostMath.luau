--!strict

local MathUtil = require(script.Parent.Parent.Util.MathUtil)

local BoostMath = {}

local function saturatingMultiplier(multipliers: {number}, cap: number, saturation: number?): number
	local sumBonus = 0
	for _, multiplier in ipairs(multipliers) do
		sumBonus += math.max(multiplier - 1, 0)
	end

	if sumBonus <= 0 then
		return 1
	end

	local capBonus = math.max(cap - 1, 0)
	if capBonus <= 0 then
		return 1
	end

	local k = math.max(saturation or 1.2, 0.001)
	local effectiveBonus = capBonus * (1 - math.exp(-sumBonus / k))
	return MathUtil.clamp(1 + effectiveBonus, 1, cap)
end

local function cappedStackCount(stacks: number, cap: number): number
	return math.floor(MathUtil.clamp(stacks, 0, cap))
end

local function diminishingReturns(baseValue: number, factor: number, stacks: number): number
	local value = baseValue
	local attenuation = math.max(factor, 0)
	for _ = 2, math.max(stacks, 1) do
		value += baseValue * attenuation
		attenuation *= factor
	end
	return value
end

BoostMath.saturatingMultiplier = saturatingMultiplier
BoostMath.cappedStackCount = cappedStackCount
BoostMath.diminishingReturns = diminishingReturns

return BoostMath
