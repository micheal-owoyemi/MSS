local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ControllerRuntime = {}

local controllersByName: { [string]: any } = {}
local hasStartedAll = false

local function getControllersFolder(): Instance
	return ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Controllers")
end

function ControllerRuntime.startController(controllerName: string): boolean
	if controllersByName[controllerName] ~= nil then
		return true
	end

	local controllersFolder = getControllersFolder()
	local moduleScript = controllersFolder:FindFirstChild(controllerName)
	if not (moduleScript and moduleScript:IsA("ModuleScript")) then
		warn(string.format("[ControllerRuntime] Missing controller module '%s'", controllerName))
		return false
	end

	local ok, controllerOrError = pcall(require, moduleScript)
	if not ok then
		warn(string.format("[ControllerRuntime] Failed to load '%s': %s", controllerName, tostring(controllerOrError)))
		return false
	end

	local controller = controllerOrError
	local controllerType = type(controller)
	if controllerType == "table" and type(controller.Start) == "function" then
		local startOk, startError = pcall(controller.Start, controller)
		if not startOk then
			warn(string.format("[ControllerRuntime] Failed to start '%s': %s", controllerName, tostring(startError)))
			return false
		end
	elseif controllerType == "function" then
		local startOk, startError = pcall(controller)
		if not startOk then
			warn(string.format("[ControllerRuntime] Failed to run '%s': %s", controllerName, tostring(startError)))
			return false
		end
	else
		warn(string.format("[ControllerRuntime] Controller '%s' has unsupported export type '%s'", controllerName, controllerType))
		return false
	end

	controllersByName[controllerName] = controller
	return true
end

function ControllerRuntime.startAll()
	if hasStartedAll then
		return controllersByName
	end

	local controllersFolder = getControllersFolder()
	local manifestModule = controllersFolder:FindFirstChild("Manifest")
	if not (manifestModule and manifestModule:IsA("ModuleScript")) then
		warn("[ControllerRuntime] Shared.Controllers.Manifest is missing")
		hasStartedAll = true
		return controllersByName
	end

	local ok, manifest = pcall(require, manifestModule)
	if not ok or type(manifest) ~= "table" then
		warn("[ControllerRuntime] Manifest failed to load")
		hasStartedAll = true
		return controllersByName
	end

	for _, controllerName in ipairs(manifest) do
		if type(controllerName) == "string" then
			ControllerRuntime.startController(controllerName)
		end
	end

	hasStartedAll = true
	return controllersByName
end

return ControllerRuntime
