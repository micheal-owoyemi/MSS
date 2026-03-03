--!strict

local MathUtil = require(script.Parent.Parent.Util.MathUtil)

local RewardMath = {}

local function deterministicSplit(totalAmount: number, weights: {number}): {number}
	local clampedTotal = math.max(totalAmount, 0)
	if #weights == 0 or clampedTotal == 0 then
		return table.create(#weights, 0)
	end

	local totalWeight = 0
	for _, weight in ipairs(weights) do
		totalWeight += math.max(weight, 0)
	end
	if totalWeight <= 0 then
		return table.create(#weights, 0)
	end

	local base = table.create(#weights, 0)
	local remainderPool = {}
	local spent = 0

	for index, weight in ipairs(weights) do
		local share = (clampedTotal * math.max(weight, 0)) / totalWeight
		local floored = math.floor(share)
		base[index] = floored
		spent += floored
		table.insert(remainderPool, {
			Index = index,
			Remainder = share - floored,
		})
	end

	table.sort(remainderPool, function(a, b)
		if a.Remainder == b.Remainder then
			return a.Index < b.Index
		end
		return a.Remainder > b.Remainder
	end)

	local remaining = clampedTotal - spent
	for i = 1, remaining do
		local slot = remainderPool[((i - 1) % #remainderPool) + 1]
		base[slot.Index] += 1
	end

	return base
end

local function scaleReward(baseValue: number, zoneMultiplier: number?, difficultyMultiplier: number?): number
	local zone = zoneMultiplier or 1
	local difficulty = difficultyMultiplier or 1
	return math.max(baseValue, 0) * math.max(zone, 0) * math.max(difficulty, 0)
end

local function applyBoostPayout(baseValue: number, boostMultiplier: number?, cap: number?): number
	local boost = boostMultiplier or 1
	local hardCap = cap or math.huge
	return math.min(baseValue * math.max(boost, 0), hardCap)
end

local function roundReward(value: number): number
	return math.max(MathUtil.roundHalfAwayFromZero(value), 0)
end

RewardMath.deterministicSplit = deterministicSplit
RewardMath.scaleReward = scaleReward
RewardMath.applyBoostPayout = applyBoostPayout
RewardMath.roundReward = roundReward

return RewardMath
