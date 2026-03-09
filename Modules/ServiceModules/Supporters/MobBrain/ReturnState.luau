--!strict

local PathRunner = require(script.Parent.PathRunner)

local ReturnState = {}

function ReturnState.update(brain: any, now: number)
	PathRunner.returnToSpawn(brain, now)

	local currentPosition = brain:_GetPosition()
	local delta = currentPosition - brain._spawnOrigin
	if delta:Dot(delta) <= (brain._returnThreshold * brain._returnThreshold) then
		brain:_Transition("Idle")
	end
end

return ReturnState
