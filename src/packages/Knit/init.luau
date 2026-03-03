local RunService = game:GetService("RunService")

local Knit = {}

local servicesByName = {}
local controllersByName = {}

local hasStarted = false

local createRejectedPromise

local function createResolvedPromise(value)
	local promise = {}

	function promise:andThen(callback)
		if type(callback) ~= "function" then
			return self
		end

		local ok, result = pcall(callback, value)
		if ok then
			return createResolvedPromise(result)
		end
		return createRejectedPromise(result)
	end

	function promise:catch()
		return self
	end

	return promise
end

createRejectedPromise = function(errorValue)
	local promise = {}

	function promise:andThen()
		return self
	end

	function promise:catch(callback)
		if type(callback) == "function" then
			callback(errorValue)
		end
		return self
	end

	return promise
end

local function createRegistryError(kind: string, name: any)
	return string.format("[Knit] Duplicate %s registered: %s", kind, tostring(name))
end

local function registerByName(registry: { [string]: any }, kind: string, definition: { [string]: any })
	if type(definition) ~= "table" then
		error(string.format("[Knit] %s definition must be a table", kind))
	end

	local name = definition.Name
	if type(name) ~= "string" or name == "" then
		error(string.format("[Knit] %s is missing a valid Name", kind))
	end

	if registry[name] then
		error(createRegistryError(kind, name))
	end

	registry[name] = definition
	return definition
end

local function collectModules(root: Instance, suffix: string): { ModuleScript }
	local modules = {}

	local function scan(node: Instance)
		for _, child in ipairs(node:GetChildren()) do
			if child:IsA("ModuleScript") and child.Name:sub(-#suffix) == suffix then
				table.insert(modules, child)
			elseif child:IsA("Folder") then
				scan(child)
			end
		end
	end

	scan(root)
	table.sort(modules, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)

	return modules
end

local function requireModules(root: Instance, suffix: string)
	for _, moduleScript in ipairs(collectModules(root, suffix)) do
		local ok, err = pcall(require, moduleScript)
		if not ok then
			error(string.format("[Knit] Failed to require %s: %s", moduleScript:GetFullName(), tostring(err)))
		end
	end
end

local function sortedRegistryValues(registry: { [string]: any }): { any }
	local names = {}
	for name in pairs(registry) do
		table.insert(names, name)
	end

	table.sort(names)

	local ordered = {}
	for _, name in ipairs(names) do
		table.insert(ordered, registry[name])
	end

	return ordered
end

local function callLifecycle(registry: { [string]: any }, methodName: string)
	for _, object in ipairs(sortedRegistryValues(registry)) do
		local method = object[methodName]
		if type(method) == "function" then
			local ok, err = pcall(method, object)
			if not ok then
				error(string.format("[Knit] %s failed for '%s': %s", methodName, tostring(object.Name), tostring(err)))
			end
		end
	end
end

function Knit.CreateService(serviceDefinition: { [string]: any })
	if RunService:IsClient() then
		error("[Knit] CreateService can only be used on the server")
	end

	serviceDefinition.Client = type(serviceDefinition.Client) == "table" and serviceDefinition.Client or {}
	return registerByName(servicesByName, "service", serviceDefinition)
end

function Knit.CreateController(controllerDefinition: { [string]: any })
	if RunService:IsServer() then
		error("[Knit] CreateController can only be used on the client")
	end

	return registerByName(controllersByName, "controller", controllerDefinition)
end

function Knit.AddServices(serviceRoot: Instance)
	if RunService:IsClient() then
		return
	end

	requireModules(serviceRoot, "Service")
end

function Knit.AddControllers(controllerRoot: Instance)
	if RunService:IsServer() then
		return
	end

	requireModules(controllerRoot, "Controller")
end

function Knit.GetService(name: string)
	return servicesByName[name]
end

function Knit.GetController(name: string)
	return controllersByName[name]
end

function Knit.Start()
	if hasStarted then
		return createResolvedPromise()
	end

	local ok, startError = pcall(function()
		if RunService:IsServer() then
			callLifecycle(servicesByName, "KnitInit")
			callLifecycle(servicesByName, "KnitStart")
		else
			callLifecycle(controllersByName, "KnitInit")
			callLifecycle(controllersByName, "KnitStart")
		end
	end)

	if not ok then
		return createRejectedPromise(startError)
	end

	hasStarted = true
	return createResolvedPromise()
end

return Knit
