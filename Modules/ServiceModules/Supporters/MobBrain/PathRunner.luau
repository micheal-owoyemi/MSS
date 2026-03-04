--!strict

local PathRunner = {}

function PathRunner.moveTowards(brain: any, destination: Vector3, now: number): (boolean, string)
	local helper = brain._pathingHelper
	if helper == nil then
		brain:_MoveDirect(destination)
		return true, "DirectNoPathingHelper"
	end

	local route = helper:ComputeRoute(brain._model, destination, {
		Key = brain._pathKey,
		Token = brain._pathToken,
		RecomputeIntervalSeconds = brain._repathIntervalSeconds,
		DirectChaseDistance = brain._directChaseDistance,
		ComputeTimeoutSeconds = brain._pathComputeTimeout,
		Now = now,
	})

	if route.DirectChase then
		brain:_MoveDirect(destination)
		return true, route.Status
	end

	if route.Success and route.Waypoints ~= nil then
		if brain._humanoid ~= nil then
			local reached = helper:FollowWaypoints(brain._humanoid, route.Waypoints, brain._pathToken, brain._moveTimeoutSeconds)
			if reached then
				return true, route.Status
			end
		end
	end

	brain:_MoveDirect(destination)
	return false, route.Status
end

function PathRunner.chaseTarget(brain: any, targetPosition: Vector3, now: number): (boolean, string)
	return PathRunner.moveTowards(brain, targetPosition, now)
end

function PathRunner.returnToSpawn(brain: any, now: number): (boolean, string)
	return PathRunner.moveTowards(brain, brain._spawnOrigin, now)
end

return PathRunner
