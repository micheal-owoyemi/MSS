--!strict

local ValidationUtil = require(script.Parent.Parent.Util.ValidationUtil)

local ItemTypes = {}

export type ItemType = "Weapon" | "Stackable" | "Consumable" | "Gift"
export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type BaseItem = {
	Uid: string,
	DefId: string,
	Type: ItemType,
	DisplayName: string,
	Rarity: Rarity,
	Quantity: number,
	CreatedAt: number,
}

export type WeaponItem = BaseItem & {
	Type: "Weapon",
	WeaponDefId: string,
	Level: number,
	RolledStats: {[string]: number},
	IsTradable: boolean,
}

export type StackableItem = BaseItem & {
	Type: "Stackable",
	StackKey: string,
	MaxStack: number,
}

export type ConsumableItem = BaseItem & {
	Type: "Consumable",
	EffectId: string,
	DurationSeconds: number,
}

export type GiftPayload = {
	GiftId: string,
	SenderUserId: number,
	RecipientUserId: number,
	Items: {BaseItem},
	Message: string?,
	CreatedAt: number,
	ExpiresAt: number,
}

export type TradeOffer = {
	OfferId: string,
	FromUserId: number,
	ToUserId: number,
	Items: {BaseItem},
	Currencies: {[string]: number},
	CreatedAt: number,
	ExpiresAt: number,
}

local ITEM_TYPES: {[string]: ItemType} = table.freeze({
	Weapon = "Weapon",
	Stackable = "Stackable",
	Consumable = "Consumable",
	Gift = "Gift",
})

local function isValidItemType(rawType: any): boolean
	return typeof(rawType) == "string" and ITEM_TYPES[rawType] ~= nil
end

local function isValidBaseItem(raw: any): boolean
	if typeof(raw) ~= "table" then
		return false
	end

	if not ValidationUtil.isNonEmptyString(raw.Uid) then
		return false
	end
	if not ValidationUtil.isNonEmptyString(raw.DefId) then
		return false
	end
	local itemType = raw.ItemType
	if itemType == nil then
		itemType = raw.Type
	end
	if not isValidItemType(itemType) then
		return false
	end
	if not ValidationUtil.isNonEmptyString(raw.DisplayName) then
		return false
	end
	if not ValidationUtil.isNonEmptyString(raw.Rarity) then
		return false
	end
	if not ValidationUtil.isFiniteNumber(raw.Quantity) or raw.Quantity < 0 then
		return false
	end
	if not ValidationUtil.isFiniteNumber(raw.CreatedAt) then
		return false
	end

	return true
end

local function sanitizeQuantity(rawQuantity: any, fallback: number): number
	local quantity = tonumber(rawQuantity)
	if not ValidationUtil.isFiniteNumber(quantity) then
		return fallback
	end
	return math.max(0, math.floor(quantity :: number))
end

ItemTypes.ItemTypes = ITEM_TYPES
ItemTypes.isValidItemType = isValidItemType
ItemTypes.isValidBaseItem = isValidBaseItem
ItemTypes.sanitizeQuantity = sanitizeQuantity

return ItemTypes
