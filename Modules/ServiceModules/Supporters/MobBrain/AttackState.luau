--!strict

local AttackState = {}

function AttackState.update(brain: any, now: number): boolean
	local target = brain._currentTarget
	if target == nil then
		return false
	end

	if now < brain._nextAttackAt then
		return false
	end

	brain._nextAttackAt = now + brain._attackCooldown
	local executor = brain._attackExecutor
	if executor == nil then
		return true
	end

	local ok, result = pcall(executor, brain, target, now)
	if not ok then
		warn(string.format("[MobBrain:%s] Attack executor error: %s", tostring(brain._mobId), tostring(result)))
		return false
	end

	if result == false then
		return false
	end

	return true
end

return AttackState
