--!strict

local MathUtil = require(script.Parent.Parent.Util.MathUtil)

local CombatMath = {}

local function cadenceToInterval(cadencePerSecond: number): number
	if cadencePerSecond <= 0 then
		return math.huge
	end
	return 1 / cadencePerSecond
end

local function computeDamage(baseDps: number, cadencePerSecond: number, damageMultiplier: number?, flatBonus: number?): number
	if baseDps <= 0 or cadencePerSecond <= 0 then
		return 0
	end

	local multiplier = if damageMultiplier ~= nil then math.max(damageMultiplier, 0) else 1
	local bonus = flatBonus or 0
	local damagePerHit = (baseDps / cadencePerSecond) * multiplier + bonus
	return math.max(damagePerHit, 0)
end

local function isWithinRange(attackerPosition: Vector3, targetPosition: Vector3, maxRange: number, rangePadding: number?): boolean
	if maxRange <= 0 then
		return false
	end

	local padding = rangePadding or 0
	local distance = (targetPosition - attackerPosition).Magnitude
	return distance <= math.max(maxRange + padding, 0)
end

local function contributionWeight(totalDamage: number, encounterDuration: number, focusTime: number?): number
	if totalDamage <= 0 then
		return 0
	end

	local duration = math.max(encounterDuration, 0.001)
	local damagePerSecond = totalDamage / duration
	local participation = 1
	if focusTime ~= nil and focusTime > 0 then
		participation = MathUtil.clamp(focusTime / duration, 0, 1)
	end

	return damagePerSecond * (0.5 + 0.5 * participation)
end

CombatMath.cadenceToInterval = cadenceToInterval
CombatMath.computeDamage = computeDamage
CombatMath.isWithinRange = isWithinRange
CombatMath.contributionWeight = contributionWeight

return CombatMath
