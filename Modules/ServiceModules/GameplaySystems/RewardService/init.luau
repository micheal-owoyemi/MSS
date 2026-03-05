--!strict

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local ValidationUtil = require(ReplicatedStorage.Util.ValidationUtil)
local RewardMath = require(ReplicatedStorage.Math.RewardMath)
local EconomyDefs = require(ReplicatedStorage.Configs.EconomyDefs)
local DropTables = require(ReplicatedStorage.Configs.DropTables)

local Config = require(script.Config)

type PlayerDataServiceLike = {
	MutateProfile: (self: PlayerDataServiceLike, player: Player, transformFn: (profileData: {[string]: any}, replica: any?) -> any, contextTag: string?) -> (boolean, string?),
}

type InventoryServiceLike = {
	AddItem: (self: InventoryServiceLike, player: Player, itemRecord: {[string]: any}) -> (boolean, string?),
}

type BoostServiceLike = {
	GetCurrencyPayoutMultiplier: ((self: BoostServiceLike, player: Player, currencyId: string) -> number)?,
	GetDropRateMultiplier: ((self: BoostServiceLike, player: Player) -> number)?,
}

type ContributionEntry = {
	UserId: number,
	Damage: number,
	LastContributionAt: number,
}

type ContributionSnapshot = {
	MobId: string,
	MobDefId: string,
	MobDef: {[string]: any}?,
	ZoneId: string,
	Eligible: {ContributionEntry}?,
	KilledAt: number?,
}

type CurrencyGrant = {
	UserId: number,
	CurrencyId: string,
	Amount: number,
	Reason: string,
}

type DropRollEntry = {
	DefId: string,
	Quantity: number,
}

type MobKillRewardResult = {
	CurrencyGrants: {CurrencyGrant},
	DropsByUserId: {[number]: {DropRollEntry}},
}

local RewardService = Knit.CreateService({
	Name = "RewardService",
	Client = {},
})

function RewardService:KnitInit()
	self._config = Config
	self._playerDataService = nil :: PlayerDataServiceLike?
	self._inventoryService = nil :: InventoryServiceLike?
	self._boostService = nil :: BoostServiceLike?
	self._economyDefs = EconomyDefs
	self._dropTables = DropTables
	self._serviceJanitor = Janitor.new()
	self._rng = Random.new()
end

function RewardService:KnitStart()
	self._playerDataService = Knit.GetService("PlayerDataService") :: PlayerDataServiceLike

	local okInventory, inventoryService = pcall(function()
		return Knit.GetService("InventoryService")
	end)
	if okInventory then
		self._inventoryService = inventoryService :: InventoryServiceLike
	end

	local okBoost, boostService = pcall(function()
		return Knit.GetService("BoostService")
	end)
	if okBoost then
		self._boostService = boostService :: BoostServiceLike
	end
end

local function clampFinitePositive(value: any, fallback: number): number
	local numeric = tonumber(value)
	if not ValidationUtil.isFiniteNumber(numeric) then
		return fallback
	end
	if numeric <= 0 then
		return fallback
	end
	return numeric
end

local function isValidCurrencyId(currencyId: any): boolean
	return ValidationUtil.isNonEmptyString(currencyId)
end

local function shallowCopyList<T>(source: {T}?): {T}
	if source == nil then
		return {}
	end

	local out = table.create(#source)
	for index, value in ipairs(source) do
		out[index] = value
	end
	return out
end

function RewardService:_resolveCurrencyMultiplier(player: Player, currencyId: string): number
	local boostService = self._boostService
	if boostService ~= nil and typeof(boostService.GetCurrencyPayoutMultiplier) == "function" then
		local ok, result = pcall(boostService.GetCurrencyPayoutMultiplier, boostService, player, currencyId)
		if ok and ValidationUtil.isFiniteNumber(result) then
			return math.max(result :: number, 0)
		end
	end

	return 1
end

function RewardService:_resolveDropRateMultiplier(player: Player): number
	local boostService = self._boostService
	if boostService ~= nil and typeof(boostService.GetDropRateMultiplier) == "function" then
		local ok, result = pcall(boostService.GetDropRateMultiplier, boostService, player)
		if ok and ValidationUtil.isFiniteNumber(result) then
			return math.max(result :: number, 0)
		end
	end

	return 1
end

function RewardService:_sanitizeReason(reason: string?): string
	local fallback = self._config.DefaultRewardReason
	if not ValidationUtil.isNonEmptyString(reason) then
		return fallback
	end

	local maxLength = self._config.MaxReasonLength
	if string.len(reason :: string) <= maxLength then
		return reason :: string
	end

	return string.sub(reason :: string, 1, maxLength)
end

function RewardService:_appendTransactionHistory(profileData: {[string]: any}, currencyId: string, amount: number, reason: string)
	if typeof(profileData.TransactionHistory) ~= "table" then
		profileData.TransactionHistory = {}
	end

	local history = profileData.TransactionHistory
	table.insert(history, {
		Id = HttpService:GenerateGUID(false),
		Kind = reason,
		Currency = currencyId,
		Amount = amount,
		At = os.time(),
	})

	local maxEntries = self._config.MaxTransactionHistoryEntries
	local overflow = #history - maxEntries
	if overflow > 0 then
		for _ = 1, overflow do
			table.remove(history, 1)
		end
	end
end

function RewardService:GrantCurrency(player: Player, currencyId: string, amount: number, reason: string?): (boolean, string?)
	if not ValidationUtil.isPlayer(player) then
		return false, "InvalidPlayer"
	end
	if not isValidCurrencyId(currencyId) then
		return false, "InvalidCurrencyId"
	end

	local rawAmount = tonumber(amount)
	if not ValidationUtil.isFiniteNumber(rawAmount) or rawAmount <= 0 then
		return false, "InvalidAmount"
	end

	local economyDefs = self._economyDefs
	local currencies = if typeof(economyDefs) == "table" then economyDefs.Currencies else nil
	local currencyDef = if typeof(currencies) == "table" then currencies[currencyId] else nil
	if typeof(currencyDef) ~= "table" then
		return false, "UnknownCurrency"
	end

	local roundedAmount = RewardMath.roundReward(rawAmount :: number)
	if roundedAmount <= 0 then
		return true, nil
	end

	local sanitizedReason = self:_sanitizeReason(reason)
	local contextTag = string.format("%s:GrantCurrency:%s", self._config.MutationContextPrefix, sanitizedReason)

	local playerDataService = self._playerDataService
	if playerDataService == nil then
		return false, "PlayerDataServiceUnavailable"
	end

	local success, mutateReason = playerDataService:MutateProfile(player, function(profileData)
		if typeof(profileData.Currencies) ~= "table" then
			profileData.Currencies = {}
		end

		local profileCurrencies = profileData.Currencies
		local currentAmount = tonumber(profileCurrencies[currencyId]) or 0
		local nextAmount = currentAmount + roundedAmount

		local cap = tonumber(currencyDef.Cap)
		if ValidationUtil.isFiniteNumber(cap) and cap >= 0 then
			nextAmount = math.min(nextAmount, cap :: number)
		end

		profileCurrencies[currencyId] = nextAmount

		local grantedAmount = math.max(0, nextAmount - currentAmount)
		if grantedAmount > 0 then
			self:_appendTransactionHistory(profileData, currencyId, grantedAmount, sanitizedReason)
		end
	end, contextTag)

	if not success then
		return false, mutateReason or "GrantCurrencyFailed"
	end

	return true, nil
end

function RewardService:_buildEligibleEntries(contributionSnapshot: ContributionSnapshot): {ContributionEntry}
	local sourceEntries = shallowCopyList(contributionSnapshot.Eligible)
	if #sourceEntries == 0 then
		return sourceEntries
	end

	local totalDamage = 0
	for _, entry in ipairs(sourceEntries) do
		local damage = tonumber(entry.Damage) or 0
		if damage > 0 then
			totalDamage += damage
		end
	end

	if totalDamage <= 0 then
		return {}
	end

	local minShare = math.max(0, self._config.MinContributionShare)
	if minShare <= 0 then
		return sourceEntries
	end

	local filtered = {}
	for _, entry in ipairs(sourceEntries) do
		local damage = tonumber(entry.Damage) or 0
		if damage > 0 and (damage / totalDamage) >= minShare then
			table.insert(filtered, entry)
		end
	end

	if #filtered == 0 then
		table.sort(sourceEntries, function(a, b)
			if a.Damage == b.Damage then
				return a.UserId < b.UserId
			end
			return a.Damage > b.Damage
		end)
		filtered[1] = sourceEntries[1]
	end

	return filtered
end

function RewardService:RollDrops(mobDef: {[string]: any}, contributionSnapshot: ContributionSnapshot): {[number]: {DropRollEntry}}
	if typeof(mobDef) ~= "table" or typeof(contributionSnapshot) ~= "table" then
		return {}
	end

	local dropTableId = mobDef.DropTableId
	if not ValidationUtil.isNonEmptyString(dropTableId) then
		dropTableId = contributionSnapshot.MobDefId
	end
	if not ValidationUtil.isNonEmptyString(dropTableId) then
		return {}
	end

	local dropTable = self._dropTables[dropTableId]
	if typeof(dropTable) ~= "table" then
		return {}
	end

	local entries = dropTable.Entries
	if typeof(entries) ~= "table" or #entries == 0 then
		return {}
	end

	local rollsPerKill = math.floor(clampFinitePositive(dropTable.RollsPerKill, 1))
	rollsPerKill = math.clamp(rollsPerKill, 1, self._config.DropRollsHardCap)

	local eligible = self:_buildEligibleEntries(contributionSnapshot)
	local dropsByUserId: {[number]: {DropRollEntry}} = {}
	local inventoryService = self._inventoryService

	for _, contributor in ipairs(eligible) do
		local player = Players:GetPlayerByUserId(contributor.UserId)
		if player ~= nil then
			local luckMultiplier = self:_resolveDropRateMultiplier(player)
			for _ = 1, rollsPerKill do
				for _, dropEntry in ipairs(entries) do
					if typeof(dropEntry) == "table" and ValidationUtil.isNonEmptyString(dropEntry.DefId) then
						local baseChance = math.clamp(clampFinitePositive(dropEntry.Chance, 0), 0, 1)
						if baseChance > 0 then
							local scaledChance = math.clamp(baseChance * luckMultiplier, 0, self._config.MaxDropChancePerEntry)
							if self._rng:NextNumber() <= scaledChance then
								local minQuantity = math.max(1, math.floor(clampFinitePositive(dropEntry.MinQuantity, 1)))
								local maxQuantity = math.max(minQuantity, math.floor(clampFinitePositive(dropEntry.MaxQuantity, minQuantity)))
								local quantity = self._rng:NextInteger(minQuantity, maxQuantity)

								if dropsByUserId[contributor.UserId] == nil then
									dropsByUserId[contributor.UserId] = {}
								end
								table.insert(dropsByUserId[contributor.UserId], {
									DefId = dropEntry.DefId,
									Quantity = quantity,
								})

								if inventoryService ~= nil then
									local okAdd, addErr = pcall(function()
										inventoryService:AddItem(player, {
											DefId = dropEntry.DefId,
											Quantity = quantity,
										})
									end)
									if not okAdd then
										warn(string.format("[RewardService] Failed to grant drop %s x%d to %s(%d): %s", dropEntry.DefId, quantity, player.Name, player.UserId, tostring(addErr)))
									end
								end
							end
						end
					end
				end
			end
		end
	end

	return dropsByUserId
end

function RewardService:GrantMobKillRewards(mobId: string, contributionSnapshot: ContributionSnapshot): MobKillRewardResult
	local result: MobKillRewardResult = {
		CurrencyGrants = {},
		DropsByUserId = {},
	}

	if not ValidationUtil.isNonEmptyString(mobId) then
		return result
	end
	if typeof(contributionSnapshot) ~= "table" then
		return result
	end

	local mobDef = contributionSnapshot.MobDef
	if typeof(mobDef) ~= "table" then
		return result
	end

	local eligible = self:_buildEligibleEntries(contributionSnapshot)
	if #eligible == 0 then
		return result
	end

	local weights = table.create(#eligible)
	for index, entry in ipairs(eligible) do
		weights[index] = math.max(tonumber(entry.Damage) or 0, 0)
	end

	local rewardsTable = mobDef.Rewards
	if typeof(rewardsTable) == "table" then
		for currencyId, rewardAmount in pairs(rewardsTable) do
			if isValidCurrencyId(currencyId) and ValidationUtil.isFiniteNumber(rewardAmount) and rewardAmount > 0 then
				local baseShares = RewardMath.deterministicSplit(math.floor(rewardAmount), weights)
				for index, entry in ipairs(eligible) do
					local baseAmount = baseShares[index] or 0
					if baseAmount > 0 then
						local player = Players:GetPlayerByUserId(entry.UserId)
						if player ~= nil then
							local multiplier = self:_resolveCurrencyMultiplier(player, currencyId)
							local boosted = RewardMath.applyBoostPayout(baseAmount, multiplier, self._config.MaxCurrencyGrantPerKill)
							local finalAmount = RewardMath.roundReward(boosted)
							if finalAmount > 0 then
								local reason = string.format("MobKill:%s", mobId)
								local granted = self:GrantCurrency(player, currencyId, finalAmount, reason)
								if granted then
									table.insert(result.CurrencyGrants, {
										UserId = entry.UserId,
										CurrencyId = currencyId,
										Amount = finalAmount,
										Reason = reason,
									})
								end
							end
						end
					end
				end
			end
		end
	end

	result.DropsByUserId = self:RollDrops(mobDef, contributionSnapshot)
	return result
end

function RewardService:Destroy()
	if self._serviceJanitor ~= nil then
		self._serviceJanitor:Cleanup()
	end
end

return RewardService
