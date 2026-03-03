--!strict

local ValidationUtil = require(script.Parent.Parent.Util.ValidationUtil)

local ItemTypes = {}

export type ItemKind = "Weapon" | "Stackable" | "Consumable" | "Gift"
export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type BaseItem = {
	ItemId: string,
	Kind: ItemKind,
	DisplayName: string,
	Rarity: Rarity,
	Quantity: number,
	CreatedAt: number,
}

export type WeaponItem = BaseItem & {
	Kind: "Weapon",
	WeaponDefId: string,
	Level: number,
	RolledStats: {[string]: number},
	IsTradable: boolean,
}

export type StackableItem = BaseItem & {
	Kind: "Stackable",
	StackKey: string,
	MaxStack: number,
}

export type ConsumableItem = BaseItem & {
	Kind: "Consumable",
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

local ITEM_KINDS = table.freeze({
	Weapon = "Weapon",
	Stackable = "Stackable",
	Consumable = "Consumable",
	Gift = "Gift",
})

local function isValidBaseItem(raw: any): boolean
	if typeof(raw) ~= "table" then
		return false
	end

	if not ValidationUtil.isNonEmptyString(raw.ItemId) then
		return false
	end
	if not ValidationUtil.isNonEmptyString(raw.Kind) then
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

ItemTypes.ItemKinds = ITEM_KINDS
ItemTypes.isValidBaseItem = isValidBaseItem

return ItemTypes
