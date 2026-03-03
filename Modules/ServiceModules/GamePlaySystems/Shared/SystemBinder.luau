local SystemBinder = {}

function SystemBinder.registerManagedSystem(managerService, systemName: string, system: any)
	if type(system) ~= "table" then
		return false
	end
	if type(systemName) ~= "string" or systemName == "" then
		return false
	end
	if type(managerService) ~= "table" or type(managerService.RegisterSystem) ~= "function" then
		return false
	end

	local hasManagedCallbacks = type(system.OnTick) == "function"
		or type(system.OnPlayerAdded) == "function"
		or type(system.OnPlayerRemoving) == "function"
		or type(system.OnStart) == "function"

	if not hasManagedCallbacks then
		return false
	end

	managerService:RegisterSystem(systemName, system)
	return true
end

return SystemBinder
