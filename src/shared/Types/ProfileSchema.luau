--!strict

local TableUtil = require(script.Parent.Parent.Util.TableUtil)
local ValidationUtil = require(script.Parent.Parent.Util.ValidationUtil)

local ProfileSchema = {}

export type CurrencyMap = {[string]: number}

export type ProgressionRecord = {
	Level: number,
	XP: number,
}

export type InventoryRecord = {
	Weapons: {[string]: any},
	Stackables: {[string]: number},
	Consumables: {[string]: number},
	Gifts: {[string]: any},
}

export type ProfileData = {
	Meta: {
		SchemaVersion: number,
		CreatedAt: number,
		LastOnline: number,
		TotalPlayTime: number,
		LastDailyReset: number,
	},
	Progression: ProgressionRecord,
	Currencies: CurrencyMap,
	Inventory: InventoryRecord,
	EquippedSlots: {[string]: string},
	UnlockedZones: {[string]: boolean},
	Boosts: {[string]: {Multiplier: number, ExpiresAt: number, Stacks: number}},
	QuestProgress: {[string]: {Progress: number, Claimed: boolean, UpdatedAt: number}},
	Stats: {
		TotalKills: number,
		TotalDeaths: number,
		TotalDamageDealt: number,
		TotalDamageTaken: number,
	},
	TransactionHistory: {{
		Id: string,
		Kind: string,
		Currency: string,
		Amount: number,
		At: number,
	}},
	Settings: {[string]: any},
	Flags: {
		HasCompletedTutorial: boolean,
		ClaimedStarterPack: boolean,
	},
}

local CURRENT_SCHEMA_VERSION = 2
local MAX_TRANSACTION_HISTORY = 50

local DEFAULT_PROFILE_TEMPLATE: ProfileData = {
	Meta = {
		SchemaVersion = CURRENT_SCHEMA_VERSION,
		CreatedAt = 0,
		LastOnline = 0,
		TotalPlayTime = 0,
		LastDailyReset = 0,
	},
	Progression = {
		Level = 1,
		XP = 0,
	},
	Currencies = {
		Gold = 0,
		Gems = 0,
	},
	Inventory = {
		Weapons = {},
		Stackables = {},
		Consumables = {},
		Gifts = {},
	},
	EquippedSlots = {
		PrimaryWeapon = "",
		SecondaryWeapon = "",
	},
	UnlockedZones = {
		Starter = true,
	},
	Boosts = {},
	QuestProgress = {},
	Stats = {
		TotalKills = 0,
		TotalDeaths = 0,
		TotalDamageDealt = 0,
		TotalDamageTaken = 0,
	},
	TransactionHistory = {},
	Settings = {},
	Flags = {
		HasCompletedTutorial = false,
		ClaimedStarterPack = false,
	},
}

local function sanitizeNumber(rawValue: any, fallback: number, minValue: number?, maxValue: number?): number
	local value = tonumber(rawValue)
	if not ValidationUtil.isFiniteNumber(value) then
		value = fallback
	end

	if minValue ~= nil and value < minValue then
		value = minValue
	end
	if maxValue ~= nil and value > maxValue then
		value = maxValue
	end

	return value :: number
end

local function ensureTable(container: {[string]: any}, key: string): {[string]: any}
	local value = container[key]
	if typeof(value) ~= "table" then
		value = {}
		container[key] = value
	end

	return value
end

local function sanitizeCurrencyMap(currencies: {[string]: any})
	currencies.Gold = sanitizeNumber(currencies.Gold, 0, 0, nil)
	currencies.Gems = sanitizeNumber(currencies.Gems, 0, 0, nil)
end

local function sanitizeProgression(progression: {[string]: any})
	progression.Level = sanitizeNumber(progression.Level, 1, 1, nil)
	progression.XP = sanitizeNumber(progression.XP, 0, 0, nil)
end

local function sanitizeInventory(inventory: {[string]: any})
	if typeof(inventory.Weapons) ~= "table" then
		inventory.Weapons = {}
	end
	if typeof(inventory.Stackables) ~= "table" then
		inventory.Stackables = {}
	end
	if typeof(inventory.Consumables) ~= "table" then
		inventory.Consumables = {}
	end
	if typeof(inventory.Gifts) ~= "table" then
		inventory.Gifts = {}
	end
end

local function sanitizeStats(stats: {[string]: any})
	stats.TotalKills = sanitizeNumber(stats.TotalKills, 0, 0, nil)
	stats.TotalDeaths = sanitizeNumber(stats.TotalDeaths, 0, 0, nil)
	stats.TotalDamageDealt = sanitizeNumber(stats.TotalDamageDealt, 0, 0, nil)
	stats.TotalDamageTaken = sanitizeNumber(stats.TotalDamageTaken, 0, 0, nil)
end

local function sanitizeMeta(meta: {[string]: any}, now: number?)
	local serverNow = sanitizeNumber(now, os.time(), 0, nil)
	meta.CreatedAt = sanitizeNumber(meta.CreatedAt, serverNow, 0, nil)
	meta.LastOnline = sanitizeNumber(meta.LastOnline, serverNow, 0, nil)
	meta.TotalPlayTime = sanitizeNumber(meta.TotalPlayTime, 0, 0, nil)
	meta.LastDailyReset = sanitizeNumber(meta.LastDailyReset, serverNow, 0, nil)
	meta.SchemaVersion = CURRENT_SCHEMA_VERSION
end

local function sanitizeTransactionHistory(data: {[string]: any})
	if not ValidationUtil.isArray(data.TransactionHistory) then
		data.TransactionHistory = {}
		return
	end

	local history = data.TransactionHistory
	local sanitized = {}
	for _, entry in ipairs(history) do
		if typeof(entry) == "table" then
			local id = entry.Id
			local kind = entry.Kind
			local currency = entry.Currency
			local amount = entry.Amount
			local at = entry.At

			if ValidationUtil.isNonEmptyString(id)
				and ValidationUtil.isNonEmptyString(kind)
				and ValidationUtil.isNonEmptyString(currency)
				and ValidationUtil.isFiniteNumber(amount)
				and ValidationUtil.isFiniteNumber(at)
			then
				table.insert(sanitized, {
					Id = id,
					Kind = kind,
					Currency = currency,
					Amount = amount,
					At = at,
				})
			end
		end
	end

	if #sanitized > MAX_TRANSACTION_HISTORY then
		local trimmed = {}
		local startIndex = #sanitized - MAX_TRANSACTION_HISTORY + 1
		for index = startIndex, #sanitized do
			table.insert(trimmed, sanitized[index])
		end
		sanitized = trimmed
	end

	data.TransactionHistory = sanitized
end

local function migrateInPlace(rawProfile: any, now: number?): (ProfileData, number)
	local profileData: {[string]: any}
	if typeof(rawProfile) ~= "table" then
		profileData = TableUtil.deepCopy(DEFAULT_PROFILE_TEMPLATE)
	else
		profileData = rawProfile
	end

	local meta = ensureTable(profileData, "Meta")
	local previousVersion = sanitizeNumber(meta.SchemaVersion, 1, 1, CURRENT_SCHEMA_VERSION)
	local migrationsApplied = 0

	profileData.Progression = ensureTable(profileData, "Progression")
	profileData.Currencies = ensureTable(profileData, "Currencies")
	profileData.Inventory = ensureTable(profileData, "Inventory")
	profileData.EquippedSlots = ensureTable(profileData, "EquippedSlots")
	profileData.UnlockedZones = ensureTable(profileData, "UnlockedZones")
	profileData.Boosts = ensureTable(profileData, "Boosts")
	profileData.QuestProgress = ensureTable(profileData, "QuestProgress")
	profileData.Stats = ensureTable(profileData, "Stats")
	profileData.Settings = ensureTable(profileData, "Settings")
	profileData.Flags = ensureTable(profileData, "Flags")

	if typeof(profileData.TransactionHistory) ~= "table" then
		profileData.TransactionHistory = {}
	end

	if previousVersion < 2 then
		migrationsApplied += 1
	end

	sanitizeMeta(meta, now)
	sanitizeProgression(profileData.Progression)
	sanitizeCurrencyMap(profileData.Currencies)
	sanitizeInventory(profileData.Inventory)
	sanitizeStats(profileData.Stats)
	sanitizeTransactionHistory(profileData)

	profileData.Flags.HasCompletedTutorial = profileData.Flags.HasCompletedTutorial == true
	profileData.Flags.ClaimedStarterPack = profileData.Flags.ClaimedStarterPack == true

	if next(profileData.UnlockedZones) == nil then
		profileData.UnlockedZones.Starter = true
	end

	return profileData :: ProfileData, migrationsApplied
end

local function createDefault(now: number?): ProfileData
	local profileData = TableUtil.deepCopy(DEFAULT_PROFILE_TEMPLATE)
	migrateInPlace(profileData, now)
	return profileData
end

local function validate(profileData: any): (boolean, string?)
	if typeof(profileData) ~= "table" then
		return false, "ProfileNotTable"
	end

	if typeof(profileData.Meta) ~= "table" then
		return false, "MissingMeta"
	end
	if tonumber(profileData.Meta.SchemaVersion) ~= CURRENT_SCHEMA_VERSION then
		return false, "SchemaVersionMismatch"
	end
	if typeof(profileData.Currencies) ~= "table" then
		return false, "MissingCurrencies"
	end
	if not ValidationUtil.isFiniteNumber(profileData.Currencies.Gold) then
		return false, "InvalidGold"
	end
	if not ValidationUtil.isFiniteNumber(profileData.Currencies.Gems) then
		return false, "InvalidGems"
	end
	if typeof(profileData.Inventory) ~= "table" then
		return false, "MissingInventory"
	end
	if typeof(profileData.EquippedSlots) ~= "table" then
		return false, "MissingEquippedSlots"
	end
	if typeof(profileData.UnlockedZones) ~= "table" then
		return false, "MissingUnlockedZones"
	end
	if typeof(profileData.Boosts) ~= "table" then
		return false, "MissingBoosts"
	end
	if typeof(profileData.QuestProgress) ~= "table" then
		return false, "MissingQuestProgress"
	end
	if typeof(profileData.Stats) ~= "table" then
		return false, "MissingStats"
	end

	return true, nil
end

local function getTemplate(): ProfileData
	return createDefault(0)
end

ProfileSchema.CurrentVersion = CURRENT_SCHEMA_VERSION
ProfileSchema.DefaultTemplate = DEFAULT_PROFILE_TEMPLATE
ProfileSchema.createDefault = createDefault
ProfileSchema.getTemplate = getTemplate
ProfileSchema.migrateInPlace = migrateInPlace
ProfileSchema.validate = validate

return ProfileSchema
