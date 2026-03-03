local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataNetwork = require(ReplicatedStorage.Shared.Data.Data_Network)
local SystemBinder = require(script.Parent.Shared.SystemBinder)

local WeaponService = {
	Name = "WeaponService",
	Dependencies = { "NetworkService", "DataStoreService", "GamePlayManagerService" },
}

local function resolveWeaponsFolder(): Folder?
	local gameFolder = Workspace:FindFirstChild("Game")
	if not (gameFolder and gameFolder:IsA("Folder")) then
		return nil
	end

	local weaponsFolder = gameFolder:FindFirstChild("Weapons")
	if not (weaponsFolder and weaponsFolder:IsA("Folder")) then
		weaponsFolder = Instance.new("Folder")
		weaponsFolder.Name = "Weapons"
		weaponsFolder.Parent = gameFolder
	end

	return weaponsFolder
end

function WeaponService:Init(context)
	self._networkService = context.GetService("NetworkService")
	self._dataStoreService = context.GetService("DataStoreService")
	self._managerService = context.GetService("GamePlayManagerService")
	self._weaponsFolder = nil
end

function WeaponService:Start()
	if not self._networkService or not self._dataStoreService then
		warn("[WeaponService] Missing dependencies")
		return
	end

	self._weaponsFolder = resolveWeaponsFolder()

	local getWeaponsRemote = self._networkService:GetRemoteFunction(DataNetwork.RemoteFunctions.GetWeapons)
	if getWeaponsRemote then
		getWeaponsRemote.OnServerInvoke = function(player: Player)
			return self._dataStoreService:GetWeapons(player)
		end
	end

	SystemBinder.registerManagedSystem(self._managerService, self.Name, self)
end

function WeaponService:OnPlayerAdded(player: Player)
	self:_bootstrapPlayer(player)
end

function WeaponService:OnPlayerRemoving(player: Player)
	self:_teardownPlayer(player)
end

function WeaponService:_bootstrapPlayer(player: Player)
	self._dataStoreService:EnsureStarterWeapon(player)

	local weaponsFolder = self._weaponsFolder
	if not weaponsFolder then
		return
	end

	local playerFolderName = tostring(player.UserId)
	local playerFolder = weaponsFolder:FindFirstChild(playerFolderName)
	if not playerFolder then
		playerFolder = Instance.new("Folder")
		playerFolder.Name = playerFolderName
		playerFolder.Parent = weaponsFolder
	end
end

function WeaponService:_teardownPlayer(player: Player)
	local weaponsFolder = self._weaponsFolder
	if not weaponsFolder then
		return
	end

	local playerFolder = weaponsFolder:FindFirstChild(tostring(player.UserId))
	if playerFolder then
		playerFolder:Destroy()
	end
end

return WeaponService
