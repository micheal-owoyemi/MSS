--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileTypes = require(ReplicatedStorage.Types.ProfileTypes)
local Enums = require(ReplicatedStorage.Utilities.Enums)
local Data_EconomyDefs = require(ReplicatedStorage.Data.Data_EconomyDefs)
local ValidationUtil = require(ReplicatedStorage.Util.ValidationUtil)

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
	giveCurrency: (self: PlayerProfile, currencyName: string, amount: number) -> (),
	getCurrency: (self: PlayerProfile, currencyName: string) -> number?,
	IsActive: (self: PlayerProfile) -> boolean,
	Release: (self: PlayerProfile) -> (),
}

local PlayerProfile = {}
PlayerProfile.__index = PlayerProfile

local PlayerProfiles: {[Player]: PlayerProfile} = {}
local GOLD_KEY = Enums.Currencies.Gold

local function resolveCurrencyCap(currencyName: string): number?
	local currencyDef = Data_EconomyDefs.Currencies[currencyName]
	if currencyDef == nil then
		return nil
	end
	return currencyDef.Cap
end

local function ensureCurrenciesTable(data: ProfileData): {[string]: number}
	if typeof(data.Currencies) ~= "table" then
		data.Currencies = {}
	end

	return data.Currencies
end

function PlayerProfile:getCurrency(currencyName: string): number?
	if not self:IsActive() then
		return nil
	end

	if not ValidationUtil.isNonEmptyString(currencyName) then
		return nil
	end

	local profile = self.Profile
	if profile == nil then
		return nil
	end

	local data = profile.Data
	local currencies = data.Currencies
	if typeof(currencies) == "table" then
		local amount = currencies[currencyName]
		if typeof(amount) == "number" then
			return amount
		end
	end

	return nil
end

function PlayerProfile:giveCurrency(currencyName: string, amount: number)
	if not self:IsActive() then
		return
	end

	if not ValidationUtil.isNonEmptyString(currencyName) then
		return
	end
	if not ValidationUtil.isFiniteNumber(amount) then
		return
	end

	local currentAmount = self:getCurrency(currencyName) or 0
	local updatedAmount = currentAmount + amount
	local cap = resolveCurrencyCap(currencyName)
	if cap ~= nil then
		updatedAmount = math.clamp(updatedAmount, 0, cap)
	end

	local profile = self.Profile
	if profile ~= nil then
		local data = profile.Data
		local currencies = ensureCurrenciesTable(data)
		currencies[currencyName] = updatedAmount
	end

	if self.Replica then
		self.Replica:SetValue({"Currencies", currencyName}, updatedAmount)
	end

	self._dirty = true
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
	self:giveCurrency(GOLD_KEY, amount)
end

function PlayerProfile:getGold(): number?
	return self:getCurrency(GOLD_KEY)
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
