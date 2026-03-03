local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local DataHandler = require(ServerScriptService.Server.DataHandler)
local DataPlayer = require(script.Parent.Parent.Parent.Config.Data_Player)

local DataStoreService = Knit.CreateService({
	Name = "DataStoreService",
	Client = {},
})

function DataStoreService:GetProfile(player: Player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end

	return DataHandler:getProfileAsync(player)
end

function DataStoreService:GetWeapons(player: Player): { [string]: any }
	local profile = self:GetProfile(player)
	if not profile then
		return {}
	end

	local weapons = profile:getWeapons()
	if type(weapons) ~= "table" then
		return {}
	end

	return weapons
end

function DataStoreService:GetEquippedWeapons(player: Player): { [string]: any }
	local profile = self:GetProfile(player)
	if not profile then
		return {}
	end

	local weapons = profile:getEquippedWeapons()
	if type(weapons) ~= "table" then
		return {}
	end

	return weapons
end

function DataStoreService:EnsureStarterWeapon(player: Player)
	local profile = self:GetProfile(player)
	if not profile then
		return
	end

	local existingWeapons = profile:getWeapons()
	if type(existingWeapons) ~= "table" or next(existingWeapons) == nil then
		profile:addWeapon(DataPlayer.StarterWeapon)
	end
end

return DataStoreService
