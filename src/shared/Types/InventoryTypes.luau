--!strict

local CoreTypes = require(script.Parent.CoreTypes)

local InventoryTypes = {}

type Currency = CoreTypes.Currency

export type InventoryItem = {
    id: string,
    quantity: number,
}

return InventoryTypes
