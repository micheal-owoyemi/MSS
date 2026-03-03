local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ReplicaController = require(ReplicatedStorage.Shared.ReplicaController)
local HelperFunctions = require(ReplicatedStorage.Shared.HelperFunctions.HelperFunctions)
local WeaponClass = require(ReplicatedStorage.Shared.Classes.Weapon)
local NetworkApi = require(ReplicatedStorage.Shared.Network.NetworkApi)
local GameplayPacket = NetworkApi.Packets.Gameplay

local ProfileController = {
	_started = false,
	_localPlayer = Players.LocalPlayer,
	weaponsByUuid = {},
}

local function getCoinLabel(player: Player): TextLabel?
	local playerGui = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui", 10)
	if not playerGui then
		return nil
	end

	local main = playerGui:FindFirstChild("Main")
	if not main then
		return nil
	end

	local currencyCounter = main:FindFirstChild("CurrencyCounter")
	if not currencyCounter then
		return nil
	end

	local frame = currencyCounter:FindFirstChild("Frame")
	if not frame then
		return nil
	end

	local textLabel = frame:FindFirstChild("TextLabel")
	if textLabel and textLabel:IsA("TextLabel") then
		return textLabel
	end

	return nil
end

function ProfileController:_spawnWeapon(uuid: string, weaponData: { [string]: any })
	if self.weaponsByUuid[uuid] then
		return
	end
	if type(weaponData) ~= "table" then
		return
	end

	local weaponType = weaponData.weaponType
	local weaponName = weaponData.weaponName
	local equipped = weaponData.equipped == true
	if type(weaponType) ~= "string" or type(weaponName) ~= "string" then
		return
	end

	local ok, weaponOrError = pcall(function()
		return WeaponClass.new(uuid, weaponType, weaponName, equipped, self._localPlayer)
	end)
	if not ok then
		warn(string.format("[ProfileController] Failed to spawn weapon '%s': %s", uuid, tostring(weaponOrError)))
		return
	end

	self.weaponsByUuid[uuid] = weaponOrError
end

function ProfileController:_removeWeapon(uuid: string)
	local weapon = self.weaponsByUuid[uuid]
	if not weapon then
		return
	end

	if type(weapon.despawn) == "function" then
		weapon:despawn()
	end
	self.weaponsByUuid[uuid] = nil
end

function ProfileController:_syncWeapons(newWeapons: { [string]: any }, oldWeapons: { [string]: any })
	local additions, deletions = HelperFunctions.compareTables(newWeapons, oldWeapons)

	for uuid, weaponData in pairs(additions) do
		self:_spawnWeapon(uuid, weaponData)
	end

	for uuid in pairs(deletions) do
		self:_removeWeapon(uuid)
	end
end

function ProfileController:_hydrateWeapons(weapons: { [string]: any })
	for uuid, weaponData in pairs(weapons) do
		self:_spawnWeapon(uuid, weaponData)
	end
end

function ProfileController:_bindReplicaEvents()
	ReplicaController.ReplicaOfClassCreated("PlayerProfile", function(replica)
		local isLocalReplica = replica.Tags.Player == self._localPlayer
		if not isLocalReplica then
			return
		end

		local replicaData = replica.Data
		local initialWeapons = type(replicaData.Weapons) == "table" and replicaData.Weapons or {}
		local coinLabel = getCoinLabel(self._localPlayer)

		self:_hydrateWeapons(initialWeapons)

		if coinLabel then
			coinLabel.Text = tostring(replicaData.Coins or 0)
		end

		replica:ListenToChange({ "Weapons" }, function(newValue, oldValue)
			local nextWeapons = type(newValue) == "table" and newValue or {}
			local previousWeapons = type(oldValue) == "table" and oldValue or {}
			self:_syncWeapons(nextWeapons, previousWeapons)
		end)

		replica:ListenToChange({ "Coins" }, function(newValue, oldValue)
			if not coinLabel then
				return
			end

			local nextValue = tonumber(newValue) or 0
			local previousValue = tonumber(oldValue) or 0
			if nextValue > previousValue then
				coinLabel.Text = "+ " .. tostring(nextValue - previousValue)
				task.delay(2, function()
					if coinLabel.Parent then
						coinLabel.Text = tostring(nextValue)
					end
				end)
			else
				coinLabel.Text = tostring(nextValue)
			end
		end)
	end)
end

function ProfileController:_bindMobDeath()
	GameplayPacket.mobDeath.listen(function(data)
		if type(data) ~= "table" then
			return
		end
		local mobMeshPart = data.mob
		if typeof(mobMeshPart) ~= "Instance" then
			return
		end
		for _, weapon in pairs(self.weaponsByUuid) do
			if type(weapon.disengageMob) == "function" then
				weapon:disengageMob(mobMeshPart)
			end
		end
	end)
end

function ProfileController:Start()
	if self._started then
		return
	end

	self._started = true
	ReplicaController.RequestData()
	self:_bindReplicaEvents()
	self:_bindMobDeath()
end

return ProfileController
