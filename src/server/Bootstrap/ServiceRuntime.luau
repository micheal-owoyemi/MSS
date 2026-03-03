local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

type ServiceModule = {
	Name: string?,
	Dependencies: { string }?,
	Init: ((self: ServiceModule, context: ServiceContext) -> ())?,
	Start: ((self: ServiceModule, context: ServiceContext) -> ())?,
	Destroy: ((self: ServiceModule) -> ())?,
}

type ServiceContext = {
	GetService: (name: string) -> ServiceModule?,
	Players: typeof(Players),
	ReplicatedStorage: typeof(ReplicatedStorage),
	ServerStorage: typeof(ServerStorage),
}

local ServiceRuntime = {}

local isStarted = false
local servicesByName: { [string]: ServiceModule } = {}
local startOrder: { ServiceModule } = {}
local serviceContext: ServiceContext = {
	GetService = function(name: string): ServiceModule?
		return servicesByName[name]
	end,
	Players = Players,
	ReplicatedStorage = ReplicatedStorage,
	ServerStorage = ServerStorage,
}

local function findServiceRoot(): Instance?
	local serviceModules = ServerStorage:FindFirstChild("ServiceModules")
	if not serviceModules then
		return nil
	end

	return serviceModules:FindFirstChild("GamePlaySystems")
end

local function collectServiceScripts(root: Instance): { ModuleScript }
	local discovered: { ModuleScript } = {}
	for _, child in root:GetChildren() do
		if child:IsA("ModuleScript") then
			table.insert(discovered, child)
		elseif child:IsA("Folder") then
			local initModule = child:FindFirstChild("init")
			if initModule and initModule:IsA("ModuleScript") then
				table.insert(discovered, initModule)
			end
		end
	end

	table.sort(discovered, function(a, b)
		local aName = a.Parent and a.Parent:IsA("Folder") and a.Parent.Name or a.Name
		local bName = b.Parent and b.Parent:IsA("Folder") and b.Parent.Name or b.Name
		return aName < bName
	end)

	return discovered
end

local function resolveServiceName(moduleScript: ModuleScript, exportedService: ServiceModule): string
	if type(exportedService.Name) == "string" and exportedService.Name ~= "" then
		return exportedService.Name
	end
	if moduleScript.Parent and moduleScript.Parent:IsA("Folder") then
		return moduleScript.Parent.Name
	end
	return moduleScript.Name
end

local function loadServices(root: Instance)
	for _, moduleScript in collectServiceScripts(root) do
		local ok, exported = pcall(require, moduleScript)
		if not ok then
			warn(string.format("[ServiceRuntime] Failed to require %s: %s", moduleScript:GetFullName(), tostring(exported)))
			continue
		end
		if type(exported) ~= "table" then
			warn(string.format("[ServiceRuntime] Module %s did not return a table service", moduleScript:GetFullName()))
			continue
		end

		local service = exported :: ServiceModule
		local serviceName = resolveServiceName(moduleScript, service)
		service.Name = serviceName

		if servicesByName[serviceName] ~= nil then
			warn(string.format("[ServiceRuntime] Duplicate service name '%s'; keeping first definition", serviceName))
			continue
		end

		servicesByName[serviceName] = service
	end
end

local function visitService(service: ServiceModule, visiting: { [string]: boolean }, visited: { [string]: boolean })
	local serviceName = service.Name or "UnknownService"
	if visited[serviceName] then
		return
	end
	if visiting[serviceName] then
		warn(string.format("[ServiceRuntime] Circular dependency detected at '%s'", serviceName))
		return
	end

	visiting[serviceName] = true
	for _, dependencyName in ipairs(service.Dependencies or {}) do
		local dependency = servicesByName[dependencyName]
		if dependency then
			visitService(dependency, visiting, visited)
		else
			warn(string.format("[ServiceRuntime] Service '%s' missing dependency '%s'", serviceName, dependencyName))
		end
	end
	visiting[serviceName] = nil

	visited[serviceName] = true
	table.insert(startOrder, service)
end

local function resolveStartOrder()
	local visited: { [string]: boolean } = {}
	local visiting: { [string]: boolean } = {}
	local names = {}
	for serviceName in pairs(servicesByName) do
		table.insert(names, serviceName)
	end
	table.sort(names)

	for _, serviceName in ipairs(names) do
		local service = servicesByName[serviceName]
		if service then
			visitService(service, visiting, visited)
		end
	end
end

local function startLifecycleMethod(service: ServiceModule, methodName: "Init" | "Start")
	local method = service[methodName]
	if type(method) ~= "function" then
		return
	end

	local ok, err = pcall(method, service, serviceContext)
	if not ok then
		warn(string.format("[ServiceRuntime] %s failed for '%s': %s", methodName, tostring(service.Name), tostring(err)))
	end
end

function ServiceRuntime.start()
	if isStarted then
		return servicesByName
	end

	local serviceRoot = findServiceRoot()
	if not serviceRoot then
		warn("[ServiceRuntime] ServerStorage.ServiceModules.GamePlaySystems was not found; no services started")
		isStarted = true
		return servicesByName
	end

	loadServices(serviceRoot)
	resolveStartOrder()

	for _, service in ipairs(startOrder) do
		startLifecycleMethod(service, "Init")
	end
	for _, service in ipairs(startOrder) do
		startLifecycleMethod(service, "Start")
	end

	isStarted = true
	return servicesByName
end

function ServiceRuntime.getService(name: string): ServiceModule?
	return servicesByName[name]
end

return ServiceRuntime
