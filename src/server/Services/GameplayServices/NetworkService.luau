local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local DataNetwork = require(ReplicatedStorage.Shared.Data.Data_Network)

local NetworkService = Knit.CreateService({
	Name = "NetworkService",
	Client = {},
})

local function ensureInstance(parent: Instance, className: string, name: string): Instance
	local instance = parent:FindFirstChild(name)
	if instance and not instance:IsA(className) then
		instance:Destroy()
		instance = nil
	end

	if not instance then
		instance = Instance.new(className)
		instance.Name = name
		instance.Parent = parent
	end

	return instance
end

function NetworkService:KnitStart()
	local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
	local remoteFunctionsFolder = ensureInstance(sharedFolder, "Folder", "RemoteFunctions")

	for _, remoteName in pairs(DataNetwork.RemoteFunctions) do
		ensureInstance(remoteFunctionsFolder, "RemoteFunction", remoteName)
	end

	self._remoteFunctions = remoteFunctionsFolder
end

function NetworkService:GetRemoteFunction(functionName: string): RemoteFunction?
	local remoteFunctions = self._remoteFunctions
	if not remoteFunctions then
		return nil
	end

	local resolvedName = DataNetwork.RemoteFunctions[functionName] or functionName
	local remoteFunction = remoteFunctions:FindFirstChild(resolvedName)
	if remoteFunction and remoteFunction:IsA("RemoteFunction") then
		return remoteFunction
	end

	return nil
end

return NetworkService
