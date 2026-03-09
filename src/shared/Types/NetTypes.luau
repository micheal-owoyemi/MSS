--!strict

local NetTypes = {}

export type AttackRequest = {
	MobId: string,
	Mode: "Single" | "Double",
}

export type EquipRequest = {
	Slot: string,
	ItemId: string,
}

export type UnlockRequest = {
	ZoneId: string,
}

export type TeleportRequest = {
	ZoneId: string,
	TeleportId: string,
}

export type TradeOfferRequest = {
	TradeId: string?,
	ToUserId: number,
	ItemIds: {string},
	CurrencyOffer: {[string]: number},
}

export type ClaimRequest = {
	ClaimType: string,
	ClaimId: string,
}

export type RedeemRequest = {
	Code: string,
}

export type GiftRequest = {
	RecipientUserId: number,
	ItemIds: {string},
	Message: string?,
}

export type NetResponse = {
	Success: boolean,
	Error: string?,
	Data: any?,
}

export type RequestAction =
	"Attack"
	| "Equip"
	| "Unlock"
	| "Teleport"
	| "TradeOffer"
	| "TradeAccept"
	| "TradeDecline"
	| "Gift"
	| "Claim"
	| "Redeem"

NetTypes.RequestActions = table.freeze({
	Attack = "Attack",
	Equip = "Equip",
	Unlock = "Unlock",
	Teleport = "Teleport",
	TradeOffer = "TradeOffer",
	TradeAccept = "TradeAccept",
	TradeDecline = "TradeDecline",
	Gift = "Gift",
	Claim = "Claim",
	Redeem = "Redeem",
})

return NetTypes
