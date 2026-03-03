local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataNetwork = require(ReplicatedStorage.Shared.Data.Data_Network)
local GameplayPacket = require(ReplicatedStorage.Shared.Network.GameplayPacket)
local WeaponPacket = require(ReplicatedStorage.Shared.Network.WeaponPacket)

local NetworkApi = {}

NetworkApi.Packets = {
	Gameplay = GameplayPacket,
	Weapon = WeaponPacket,
}

function NetworkApi.getRemoteFunctionsFolder(): Folder
	return ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RemoteFunctions") :: Folder
end

function NetworkApi.getRemoteFunction(name: string): RemoteFunction?
	local remoteFunctions = NetworkApi.getRemoteFunctionsFolder()
	local resolvedName = DataNetwork.RemoteFunctions[name] or name
	local remoteFunction = remoteFunctions:FindFirstChild(resolvedName)
	if remoteFunction and remoteFunction:IsA("RemoteFunction") then
		return remoteFunction
	end

	return nil
end

function NetworkApi.waitForRemoteFunction(name: string): RemoteFunction
	local remoteFunctions = NetworkApi.getRemoteFunctionsFolder()
	local resolvedName = DataNetwork.RemoteFunctions[name] or name
	return remoteFunctions:WaitForChild(resolvedName) :: RemoteFunction
end

return NetworkApi
