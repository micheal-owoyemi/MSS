local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameWorld = require(ReplicatedStorage.Shared.Utilities.GameWorld)

local WeaponService = Knit.CreateService({
	Name = "WeaponService",
	Client = {},
})

function WeaponService:KnitInit()
	self._networkService = Knit.GetService("NetworkService")
	self._dataStoreService = Knit.GetService("DataStoreService")
	self._gameplayManagerService = Knit.GetService("GameplayManagerService")
end

function WeaponService:KnitStart()
	if not self._networkService or not self._dataStoreService then
		warn("[WeaponService] Missing service dependencies")
		return
	end

	GameWorld.getWeaponsFolder(true)

	local getWeaponsRemote = self._networkService:GetRemoteFunction("GetWeapons")
	if getWeaponsRemote then
		getWeaponsRemote.OnServerInvoke = function(player: Player)
			return self._dataStoreService:GetWeapons(player)
		end
	end

	if self._gameplayManagerService then
		self._gameplayManagerService:RegisterSystem(self.Name, self)
	end
end

function WeaponService:OnPlayerAdded(player: Player)
	self:_bootstrapPlayer(player)
end

function WeaponService:OnPlayerRemoving(player: Player)
	self:_teardownPlayer(player)
end

function WeaponService:_bootstrapPlayer(player: Player)
	self._dataStoreService:EnsureStarterWeapon(player)
	GameWorld.getPlayerWeaponsFolder(player.UserId, true)
end

function WeaponService:_teardownPlayer(player: Player)
	local playerFolder = GameWorld.getPlayerWeaponsFolder(player.UserId, false)
	if playerFolder then
		playerFolder:Destroy()
	end
end

return WeaponService
