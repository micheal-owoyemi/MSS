--!strict

export type RoamStateName = "Idle" | "RoamMove"

export type RoamRuntimeState = {
	State: RoamStateName,
	StateUntil: number,
	DestinationXZ: Vector2?,
	FacingXZ: Vector2,
	Speed: number,
}

export type RoamStepResult = {
	PositionXZ: Vector2,
	State: RoamStateName,
	StateUntil: number,
	DestinationXZ: Vector2?,
	FacingXZ: Vector2,
	Moved: boolean,
	StateChanged: boolean,
}

type RoamStepParams = {
	Now: number,
	Dt: number,
	Runtime: RoamRuntimeState,
	PositionXZ: Vector2,
	IdleDurationMin: number,
	IdleDurationMax: number,
	MoveDurationMin: number,
	MoveDurationMax: number,
	ArriveDistance: number,
	Rng: Random,
	SampleDestination: (currentXZ: Vector2) -> Vector2?,
	IsValidPosition: (candidateXZ: Vector2) -> boolean,
	GetSeparationOffset: ((currentXZ: Vector2) -> Vector2?)?,
}

local RoamBehavior = {}

local function randomDuration(rng: Random, minimum: number, maximum: number): number
	local minDuration = math.max(0.05, minimum)
	local maxDuration = math.max(minDuration, maximum)
	return rng:NextNumber(minDuration, maxDuration)
end

local function enterIdle(runtime: RoamRuntimeState, now: number, rng: Random, idleMin: number, idleMax: number)
	runtime.State = "Idle"
	runtime.DestinationXZ = nil
	runtime.StateUntil = now + randomDuration(rng, idleMin, idleMax)
end

local function enterRoamMove(
	runtime: RoamRuntimeState,
	now: number,
	rng: Random,
	moveMin: number,
	moveMax: number,
	destinationXZ: Vector2
)
	runtime.State = "RoamMove"
	runtime.DestinationXZ = destinationXZ
	runtime.StateUntil = now + randomDuration(rng, moveMin, moveMax)
end

local function normalizeOrFallback(input: Vector2, fallback: Vector2): Vector2
	local magnitude = input.Magnitude
	if magnitude <= 1e-6 then
		return fallback
	end
	return input / magnitude
end

function RoamBehavior.Step(params: RoamStepParams): RoamStepResult
	local now = params.Now
	local dt = math.max(0, params.Dt)
	local runtime = params.Runtime
	local currentXZ = params.PositionXZ
	local rng = params.Rng
	local idleMin = params.IdleDurationMin
	local idleMax = params.IdleDurationMax
	local moveMin = params.MoveDurationMin
	local moveMax = params.MoveDurationMax
	local arriveDistance = math.max(0.25, params.ArriveDistance)

	local moved = false
	local stateChanged = false

	if runtime.State ~= "Idle" and runtime.State ~= "RoamMove" then
		enterIdle(runtime, now, rng, idleMin, idleMax)
		stateChanged = true
	end

	if runtime.State == "Idle" then
		if now >= runtime.StateUntil then
			local destination = params.SampleDestination(currentXZ)
			if destination ~= nil then
				enterRoamMove(runtime, now, rng, moveMin, moveMax, destination)
				stateChanged = true
			else
				enterIdle(runtime, now, rng, idleMin, idleMax)
			end
		end
	else
		if now >= runtime.StateUntil then
			enterIdle(runtime, now, rng, idleMin, idleMax)
			stateChanged = true
		end

		local destination = runtime.DestinationXZ
		if destination == nil then
			enterIdle(runtime, now, rng, idleMin, idleMax)
			stateChanged = true
		else
			local toDestination = destination - currentXZ
			local distanceToDestination = toDestination.Magnitude
			if distanceToDestination <= arriveDistance then
				enterIdle(runtime, now, rng, idleMin, idleMax)
				stateChanged = true
			else
				local direction = normalizeOrFallback(toDestination, runtime.FacingXZ)
				local getSeparationOffset = params.GetSeparationOffset
				if getSeparationOffset ~= nil then
					local separation = getSeparationOffset(currentXZ)
					if separation ~= nil and separation.Magnitude > 1e-4 then
						direction = normalizeOrFallback(direction + separation, direction)
					end
				end

					local moveDistance = math.min(distanceToDestination, math.max(0, runtime.Speed) * dt)
					if moveDistance > 0 then
						local nextXZ = currentXZ + (direction * moveDistance)
						if params.IsValidPosition(nextXZ) then
							currentXZ = nextXZ
							moved = true
							runtime.FacingXZ = direction
						else
							local replacementDestination = params.SampleDestination(currentXZ)
							if replacementDestination ~= nil then
								enterRoamMove(runtime, now, rng, moveMin, moveMax, replacementDestination)
								stateChanged = true
							else
								enterIdle(runtime, now, rng, idleMin, idleMax)
								stateChanged = true
							end
						end
					end

					if runtime.State == "RoamMove" and runtime.DestinationXZ ~= nil then
					local remainingDistance = (runtime.DestinationXZ - currentXZ).Magnitude
					if remainingDistance <= arriveDistance then
						enterIdle(runtime, now, rng, idleMin, idleMax)
						stateChanged = true
					end
				end
			end
		end
	end

	return {
		PositionXZ = currentXZ,
		State = runtime.State,
		StateUntil = runtime.StateUntil,
		DestinationXZ = runtime.DestinationXZ,
		FacingXZ = runtime.FacingXZ,
		Moved = moved,
		StateChanged = stateChanged,
	}
end

return RoamBehavior
