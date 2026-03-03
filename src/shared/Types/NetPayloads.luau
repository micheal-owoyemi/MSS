--!strict

local CoreTypes = require(script.Parent.CoreTypes)

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

return NetPayloads
