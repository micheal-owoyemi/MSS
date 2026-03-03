--!strict

local ItemTypes = require(script.Parent.ItemTypes)

local InventoryTypes = {}

export type InventoryItem = ItemTypes.BaseItem
export type WeaponItem = ItemTypes.WeaponItem
export type StackableItem = ItemTypes.StackableItem
export type ConsumableItem = ItemTypes.ConsumableItem
export type GiftPayload = ItemTypes.GiftPayload
export type TradeOffer = ItemTypes.TradeOffer

return InventoryTypes
