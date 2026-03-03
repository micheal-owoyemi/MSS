--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileTypes = require(ReplicatedStorage.Types.ProfileTypes)
local Enums = require(ReplicatedStorage.Utilities.Enums)

type ProfileData = ProfileTypes.ProfileData
type ReplicaLike = ProfileTypes.ReplicaLike
type ProfileSessionLike = ProfileTypes.ProfileSessionLike


export type PlayerProfile = {
	Profile: ProfileSessionLike?,
	Replica: ReplicaLike?,
	_player: Player,
	_dirty: boolean?,

	giveGold: (self: PlayerProfile, amount: number) -> (),
	getGold: (self: PlayerProfile) -> number?,
	IsActive: (self: PlayerProfile) -> boolean,
	Release: (self: PlayerProfile) -> (),
}

local PlayerProfile = {}
PlayerProfile.__index = PlayerProfile

local PlayerProfiles: {[Player]: PlayerProfile} = {}
local GOLD_KEY = Enums.Currencies.Gold

local function ensureCurrenciesTable(data: ProfileData): {[string]: number}
	if typeof(data.Currencies) ~= "table" then
		data.Currencies = {}
	end

	return data.Currencies
end

function PlayerProfile.new(profile: ProfileSessionLike, player: Player, replica: ReplicaLike?): PlayerProfile
	local self = setmetatable({
		Profile = profile,
		Replica = replica,
		_player = player,
		_dirty = false,
	} :: any, PlayerProfile) :: PlayerProfile

	PlayerProfiles[player] = self
	return self
end

function PlayerProfile:giveGold(amount: number)
	if not self:IsActive() then
		return
	end

	local currentGold = self:getGold() or 0
	local updatedGold = currentGold + amount
	local profile = self.Profile
	if profile ~= nil then
		local data = profile.Data
		local currencies = ensureCurrenciesTable(data)
		currencies[GOLD_KEY] = updatedGold
	end

	if self.Replica then
		self.Replica:SetValue({"Currencies", GOLD_KEY}, updatedGold)
	end
end

function PlayerProfile:getGold(): number?
	if not self:IsActive() then
		return nil
	end

	local profile = self.Profile
	if profile == nil then
		return nil
	end

	local data = profile.Data
	local currencies = data.Currencies
	if typeof(currencies) == "table" then
		local amount = currencies[GOLD_KEY]
		if typeof(amount) == "number" then
			return amount
		end
	end

	return nil
end

function PlayerProfile:IsActive(): boolean
	return PlayerProfiles[self._player] ~= nil
end

function PlayerProfile:Release()
	PlayerProfiles[self._player] = nil
end

return {
	PlayerProfiles = PlayerProfiles,
	PlayerProfile = PlayerProfile,
}
