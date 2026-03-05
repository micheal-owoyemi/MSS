--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ValidationUtil = require(ReplicatedStorage.Util.ValidationUtil)

local SnapshotBuilder = {}

local MAX_KEY_LENGTH = 64

local function isSafeKey(key: any): boolean
	return typeof(key) == "string" and key ~= "" and #key <= MAX_KEY_LENGTH
end

local function safeNumber(value: any, fallback: number, minValue: number?): number
	local resolved = tonumber(value)
	if not ValidationUtil.isFiniteNumber(resolved) then
		resolved = fallback
	end
	if minValue ~= nil and (resolved :: number) < minValue then
		resolved = minValue
	end
	return resolved :: number
end

local function safeString(value: any, fallback: string): string
	if typeof(value) == "string" then
		return value
	end
	return fallback
end

local function copyNumberMap(input: any): {[string]: number}
	local out: {[string]: number} = {}
	if typeof(input) ~= "table" then
		return out
	end

	for key, value in pairs(input) do
		if isSafeKey(key) and ValidationUtil.isFiniteNumber(value) then
			out[key] = value
		end
	end

	return out
end

local function copyBooleanMap(input: any): {[string]: boolean}
	local out: {[string]: boolean} = {}
	if typeof(input) ~= "table" then
		return out
	end

	for key, value in pairs(input) do
		if isSafeKey(key) and value == true then
			out[key] = true
		end
	end

	return out
end

local function copyStringMap(input: any): {[string]: string}
	local out: {[string]: string} = {}
	if typeof(input) ~= "table" then
		return out
	end

	for key, value in pairs(input) do
		if isSafeKey(key) and typeof(value) == "string" then
			out[key] = value
		end
	end

	return out
end

local function sanitizeWeapons(input: any): {[string]: any}
	local out = {}
	if typeof(input) ~= "table" then
		return out
	end

	for itemId, weaponRecord in pairs(input) do
		if isSafeKey(itemId) and typeof(weaponRecord) == "table" then
			local rolledStats = copyNumberMap(weaponRecord.RolledStats)
			out[itemId] = {
				ItemId = safeString(weaponRecord.ItemId, itemId),
				WeaponDefId = safeString(weaponRecord.WeaponDefId, ""),
				DisplayName = safeString(weaponRecord.DisplayName, ""),
				Rarity = safeString(weaponRecord.Rarity, "Common"),
				Level = safeNumber(weaponRecord.Level, 1, 1),
				Quantity = safeNumber(weaponRecord.Quantity, 1, 0),
				CreatedAt = safeNumber(weaponRecord.CreatedAt, 0, 0),
				IsTradable = weaponRecord.IsTradable == true,
				RolledStats = rolledStats,
			}
		end
	end

	return out
end

local function sanitizeGifts(input: any): {[string]: any}
	local out = {}
	if typeof(input) ~= "table" then
		return out
	end

	for giftId, giftRecord in pairs(input) do
		if isSafeKey(giftId) and typeof(giftRecord) == "table" then
			out[giftId] = {
				GiftId = safeString(giftRecord.GiftId, giftId),
				SenderUserId = safeNumber(giftRecord.SenderUserId, 0, 0),
				CreatedAt = safeNumber(giftRecord.CreatedAt, 0, 0),
				ExpiresAt = safeNumber(giftRecord.ExpiresAt, 0, 0),
				Message = if typeof(giftRecord.Message) == "string" then giftRecord.Message else nil,
				ItemCount = if ValidationUtil.isArray(giftRecord.Items) then #giftRecord.Items else 0,
			}
		end
	end

	return out
end

local function sanitizeBoosts(input: any): {[string]: {Multiplier: number, ExpiresAt: number, Stacks: number}}
	local out = {}
	if typeof(input) ~= "table" then
		return out
	end

	for boostId, boostRecord in pairs(input) do
		if isSafeKey(boostId) and typeof(boostRecord) == "table" then
			out[boostId] = {
				Multiplier = safeNumber(boostRecord.Multiplier, 1, 0),
				ExpiresAt = safeNumber(boostRecord.ExpiresAt, 0, 0),
				Stacks = safeNumber(boostRecord.Stacks, 0, 0),
			}
		end
	end

	return out
end

local function sanitizeQuestProgress(input: any): {[string]: {Progress: number, Claimed: boolean, UpdatedAt: number}}
	local out = {}
	if typeof(input) ~= "table" then
		return out
	end

	for questId, questRecord in pairs(input) do
		if isSafeKey(questId) and typeof(questRecord) == "table" then
			out[questId] = {
				Progress = safeNumber(questRecord.Progress, 0, 0),
				Claimed = questRecord.Claimed == true,
				UpdatedAt = safeNumber(questRecord.UpdatedAt, 0, 0),
			}
		end
	end

	return out
end

function SnapshotBuilder.build(profileData: any, revision: number, snapshotAt: number): {[string]: any}
	local data = if typeof(profileData) == "table" then profileData else {}

	local meta = if typeof(data.Meta) == "table" then data.Meta else {}
	local progression = if typeof(data.Progression) == "table" then data.Progression else {}
	local inventory = if typeof(data.Inventory) == "table" then data.Inventory else {}
	local stats = if typeof(data.Stats) == "table" then data.Stats else {}
	local flags = if typeof(data.Flags) == "table" then data.Flags else {}

	return {
		Snapshot = {
			Revision = revision,
			GeneratedAt = snapshotAt,
			SchemaVersion = safeNumber(meta.SchemaVersion, 0, 0),
		},
		Meta = {
			CreatedAt = safeNumber(meta.CreatedAt, 0, 0),
			LastOnline = safeNumber(meta.LastOnline, 0, 0),
			TotalPlayTime = safeNumber(meta.TotalPlayTime, 0, 0),
			LastDailyReset = safeNumber(meta.LastDailyReset, 0, 0),
		},
		Progression = {
			Level = safeNumber(progression.Level, 1, 1),
			XP = safeNumber(progression.XP, 0, 0),
		},
		Currencies = copyNumberMap(data.Currencies),
		Inventory = {
			Weapons = sanitizeWeapons(inventory.Weapons),
			Stackables = copyNumberMap(inventory.Stackables),
			Consumables = copyNumberMap(inventory.Consumables),
			Gifts = sanitizeGifts(inventory.Gifts),
		},
		EquippedSlots = copyStringMap(data.EquippedSlots),
		UnlockedZones = copyBooleanMap(data.UnlockedZones),
		Boosts = sanitizeBoosts(data.Boosts),
		QuestProgress = sanitizeQuestProgress(data.QuestProgress),
		Stats = {
			TotalKills = safeNumber(stats.TotalKills, 0, 0),
			TotalDeaths = safeNumber(stats.TotalDeaths, 0, 0),
			TotalDamageDealt = safeNumber(stats.TotalDamageDealt, 0, 0),
			TotalDamageTaken = safeNumber(stats.TotalDamageTaken, 0, 0),
		},
		Flags = {
			HasCompletedTutorial = flags.HasCompletedTutorial == true,
			ClaimedStarterPack = flags.ClaimedStarterPack == true,
		},
	}
end

return SnapshotBuilder
