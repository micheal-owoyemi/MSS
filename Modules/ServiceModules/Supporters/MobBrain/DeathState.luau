--!strict

local DeathState = {}

function DeathState.enter(brain: any, now: number)
	brain._deadAt = now
	brain._currentTarget = nil
	table.clear(brain._attackers)
	if brain._pathingHelper then
		brain._pathingHelper:Cancel(brain._pathToken)
		brain._pathToken = brain._pathingHelper:CreateCancelToken()
	end

	local onDeath = brain._onDeath
	if onDeath ~= nil then
		local ok, err = pcall(onDeath, brain, now)
		if not ok then
			warn(string.format("[MobBrain:%s] onDeath callback error: %s", tostring(brain._mobId), tostring(err)))
		end
	end
end

return DeathState
