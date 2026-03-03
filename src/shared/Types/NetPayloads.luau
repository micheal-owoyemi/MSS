--!strict

local CoreTypes = require(script.Parent.CoreTypes)
local NetTypes = require(script.Parent.NetTypes)

local NetPayloads = {}

type Currency = CoreTypes.Currency
type Timestamp = CoreTypes.Timestamp

export type CurrencyName = "Gold"
export type CurrencySnapshot = {
	Gold: Currency,
}

export type CurrencySnapshotPayload = {
	kind: "snapshot",
	values: CurrencySnapshot,
	timestamp: Timestamp,
}

export type CurrencyDeltaPayload = {
	kind: "delta",
	currency: CurrencyName,
	amount: Currency,
	timestamp: Timestamp,
}

export type CurrencyUpdatePayload = CurrencySnapshotPayload | CurrencyDeltaPayload
export type RequestAction = NetTypes.RequestAction

return NetPayloads
