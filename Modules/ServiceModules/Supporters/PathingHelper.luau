--!strict

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Janitor = require(ReplicatedStorage.Packages.Janitor)

type CancelToken = {
	Version: number,
	Cancelled: boolean,
}

local DEFAULTS = {
	DirectChaseDistance = 14,
	RecomputeIntervalSeconds = 0.35,
	ComputeTimeoutSeconds = 2,
	MoveTimeoutSeconds = 1.25,
}

local PathingHelper = {}
PathingHelper.__index = PathingHelper

local function getModelRoot(model: Model): BasePart?
	local primaryPart = model.PrimaryPart
	if primaryPart ~= nil then
		return primaryPart
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

function PathingHelper.new(config: {[string]: any}?): any
	local resolved = {}
	for key, defaultValue in pairs(DEFAULTS) do
		local value = if config then config[key] else nil
		if typeof(value) == "number" and value > 0 then
			resolved[key] = value
		else
			resolved[key] = defaultValue
		end
	end

	local self = setmetatable({
		_config = resolved,
		_lastComputeAtByKey = {} :: {[string]: number},
		_janitor = Janitor.new(),
	}, PathingHelper)

	return self
end

function PathingHelper:CreateCancelToken(): CancelToken
	return {
		Version = 1,
		Cancelled = false,
	}
end

function PathingHelper:Cancel(token: CancelToken?)
	if token == nil then
		return
	end
	token.Cancelled = true
	token.Version += 1
end

function PathingHelper:ShouldRecompute(key: string, now: number?, minIntervalSeconds: number?): boolean
	local current = if typeof(now) == "number" then now else os.clock()
	local minimum = if typeof(minIntervalSeconds) == "number" and minIntervalSeconds > 0 then minIntervalSeconds else self._config.RecomputeIntervalSeconds
	local last = self._lastComputeAtByKey[key]
	if last ~= nil and current - last < minimum then
		return false
	end

	self._lastComputeAtByKey[key] = current
	return true
end

local function moveToWithTimeout(humanoid: Humanoid, destination: Vector3, timeoutSeconds: number, token: CancelToken?): boolean
	humanoid:MoveTo(destination)

	local reached = false
	local succeeded = false
	local connection = humanoid.MoveToFinished:Connect(function(moveSucceeded: boolean)
		reached = true
		succeeded = moveSucceeded
	end)

	local deadline = os.clock() + timeoutSeconds
	while reached == false do
		if token ~= nil and token.Cancelled then
			connection:Disconnect()
			return false
		end
		if os.clock() >= deadline then
			connection:Disconnect()
			return false
		end
		task.wait()
	end

	connection:Disconnect()
	return succeeded
end

function PathingHelper:FollowWaypoints(humanoid: Humanoid, waypoints: {PathWaypoint}, token: CancelToken?, timeoutSeconds: number?): boolean
	local timeout = if typeof(timeoutSeconds) == "number" and timeoutSeconds > 0 then timeoutSeconds else self._config.MoveTimeoutSeconds

	for _, waypoint in ipairs(waypoints) do
		if token ~= nil and token.Cancelled then
			return false
		end

		if waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end

		if not moveToWithTimeout(humanoid, waypoint.Position, timeout, token) then
			return false
		end
	end

	return true
end

function PathingHelper:ComputeRoute(model: Model, destination: Vector3, options: {[string]: any}?): {
	Success: boolean,
	DirectChase: boolean,
	UsedPathfinding: boolean,
	Status: string,
	Waypoints: {PathWaypoint}?,
}
	if model == nil or typeof(destination) ~= "Vector3" then
		return {
			Success = false,
			DirectChase = false,
			UsedPathfinding = false,
			Status = "InvalidArguments",
			Waypoints = nil,
		}
	end

	local token = if options then options.Token else nil
	if token ~= nil and token.Cancelled then
		return {
			Success = false,
			DirectChase = false,
			UsedPathfinding = false,
			Status = "Cancelled",
			Waypoints = nil,
		}
	end

	local root = getModelRoot(model)
	if root == nil then
		return {
			Success = false,
			DirectChase = false,
			UsedPathfinding = false,
			Status = "MissingRoot",
			Waypoints = nil,
		}
	end

	local current = os.clock()
	local recomputeKey = if options and typeof(options.Key) == "string" then options.Key else nil
	if recomputeKey ~= nil then
		local minInterval = if options then options.RecomputeIntervalSeconds else nil
		if not self:ShouldRecompute(recomputeKey, current, minInterval) then
			return {
				Success = false,
				DirectChase = false,
				UsedPathfinding = false,
				Status = "RecomputeThrottled",
				Waypoints = nil,
			}
		end
	end

	local directDistance = if options and typeof(options.DirectChaseDistance) == "number" then options.DirectChaseDistance else self._config.DirectChaseDistance
	if (destination - root.Position).Magnitude <= directDistance then
		return {
			Success = true,
			DirectChase = true,
			UsedPathfinding = false,
			Status = "DirectChase",
			Waypoints = nil,
		}
	end

	local pathParams = if options and typeof(options.AgentParams) == "table" then options.AgentParams else nil
	local path = PathfindingService:CreatePath(pathParams)

	local finished = false
	local computeOk = false
	local computeError: string? = nil

	task.spawn(function()
		local ok, err = pcall(function()
			path:ComputeAsync(root.Position, destination)
		end)
		computeOk = ok
		if not ok then
			computeError = tostring(err)
		end
		finished = true
	end)

	local timeout = if options and typeof(options.ComputeTimeoutSeconds) == "number" then options.ComputeTimeoutSeconds else self._config.ComputeTimeoutSeconds
	local deadline = os.clock() + timeout
	while finished == false do
		if token ~= nil and token.Cancelled then
			path:Destroy()
			return {
				Success = false,
				DirectChase = false,
				UsedPathfinding = true,
				Status = "Cancelled",
				Waypoints = nil,
			}
		end
		if os.clock() >= deadline then
			path:Destroy()
			return {
				Success = false,
				DirectChase = false,
				UsedPathfinding = true,
				Status = "ComputeTimeout",
				Waypoints = nil,
			}
		end
		task.wait()
	end

	if not computeOk then
		path:Destroy()
		return {
			Success = false,
			DirectChase = false,
			UsedPathfinding = true,
			Status = "ComputeFailed:" .. tostring(computeError),
			Waypoints = nil,
		}
	end

	if path.Status ~= Enum.PathStatus.Success then
		path:Destroy()
		return {
			Success = false,
			DirectChase = false,
			UsedPathfinding = true,
			Status = "PathStatus:" .. tostring(path.Status),
			Waypoints = nil,
		}
	end

	local waypoints = path:GetWaypoints()
	path:Destroy()

	if #waypoints == 0 then
		return {
			Success = false,
			DirectChase = false,
			UsedPathfinding = true,
			Status = "NoWaypoints",
			Waypoints = nil,
		}
	end

	return {
		Success = true,
		DirectChase = false,
		UsedPathfinding = true,
		Status = "PathSuccess",
		Waypoints = waypoints,
	}
end

function PathingHelper:Destroy()
	table.clear(self._lastComputeAtByKey)
	self._janitor:Cleanup()
end

return PathingHelper
