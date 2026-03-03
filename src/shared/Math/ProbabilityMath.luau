--!strict

local MathUtil = require(script.Parent.Parent.Util.MathUtil)

local ProbabilityMath = {}

local EPSILON = 1e-6

local function weightedPick<T>(weights: {[T]: number}, roll01: number?): T?
	local total = 0
	for _, weight in pairs(weights) do
		total += math.max(weight, 0)
	end

	if total <= 0 then
		return nil
	end

	local roll = (roll01 or math.random()) * total
	local cumulative = 0
	for key, weight in pairs(weights) do
		cumulative += math.max(weight, 0)
		if roll <= cumulative then
			return key
		end
	end

	for key in pairs(weights) do
		return key
	end
	return nil
end

local function applyLuckLogitShift(probability: number, luckShift: number): number
	local p = MathUtil.clamp(probability, EPSILON, 1 - EPSILON)
	local logit = math.log(p / (1 - p))
	local shifted = logit + luckShift
	local transformed = 1 / (1 + math.exp(-shifted))
	return MathUtil.clamp(transformed, 0, 1)
end

local function rarityWeightsWithLuck(baseWeights: {[string]: number}, rarityBias: {[string]: number}, luckShift: number): {[string]: number}
	local transformed: {[string]: number} = {}
	for rarity, weight in pairs(baseWeights) do
		local bias = rarityBias[rarity] or 0
		local normalized = math.max(weight, 0)
		local pseudoProbability = normalized / (normalized + 1)
		local adjustedProbability = applyLuckLogitShift(pseudoProbability, luckShift * bias)
		transformed[rarity] = adjustedProbability
	end
	return transformed
end

local function shouldApplyPity(currentPityCount: number, threshold: number): boolean
	if threshold <= 0 then
		return false
	end
	return currentPityCount >= threshold
end

ProbabilityMath.weightedPick = weightedPick
ProbabilityMath.applyLuckLogitShift = applyLuckLogitShift
ProbabilityMath.rarityWeightsWithLuck = rarityWeightsWithLuck
ProbabilityMath.shouldApplyPity = shouldApplyPity

return ProbabilityMath
