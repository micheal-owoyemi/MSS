--!strict

local ValidationUtil = require(script.Parent.Parent.Util.ValidationUtil)

local RemoteSchemas = {}

export type ValidationResult = {
	ok: boolean,
	errorCode: string?,
	sanitizedPayload: any?,
}

local MAX_STRING_LENGTH = 64
local MAX_ITEMS_PER_PAYLOAD = 50

local function isShortString(value: any): boolean
	return ValidationUtil.isNonEmptyString(value) and string.len(value) <= MAX_STRING_LENGTH
end

local function normalizeStringArray(value: any): ({string}?, string?)
	if not ValidationUtil.isArray(value) then
		return nil, "InvalidArray"
	end

	if #value > MAX_ITEMS_PER_PAYLOAD then
		return nil, "ArrayTooLarge"
	end

	local out = table.create(#value)
	for index, entry in ipairs(value) do
		if not isShortString(entry) then
			return nil, "InvalidArrayEntry"
		end
		out[index] = entry
	end

	return out, nil
end

local function validateAttack(payload: any): ValidationResult
	if typeof(payload) ~= "table" then
		return {ok = false, errorCode = "InvalidPayload"}
	end

	local mobId = payload.MobId
	if mobId == nil then
		mobId = payload.TargetMobId -- Backward compatibility for earlier payload shape.
	end
	if not isShortString(mobId) then
		return {ok = false, errorCode = "InvalidMobId"}
	end

	local mode = payload.Mode
	if mode == nil then
		mode = payload.ClickType -- Backward compatibility for alternate naming.
	end
	if mode == nil then
		mode = "Single"
	end
	if mode ~= "Single" and mode ~= "Double" then
		return {ok = false, errorCode = "InvalidAttackMode"}
	end

	return {
		ok = true,
		sanitizedPayload = {
			MobId = mobId,
			Mode = mode,
		},
	}
end

local function validateEquip(payload: any): ValidationResult
	if typeof(payload) ~= "table" then
		return {ok = false, errorCode = "InvalidPayload"}
	end
	if not isShortString(payload.Slot) then
		return {ok = false, errorCode = "InvalidSlot"}
	end
	if not isShortString(payload.ItemId) then
		return {ok = false, errorCode = "InvalidItemId"}
	end

	return {
		ok = true,
		sanitizedPayload = {
			Slot = payload.Slot,
			ItemId = payload.ItemId,
		},
	}
end

local function validateUnlock(payload: any): ValidationResult
	if typeof(payload) ~= "table" or not isShortString(payload.ZoneId) then
		return {ok = false, errorCode = "InvalidZoneId"}
	end

	return {
		ok = true,
		sanitizedPayload = {
			ZoneId = payload.ZoneId,
		},
	}
end

local function validateTeleport(payload: any): ValidationResult
	if typeof(payload) ~= "table" then
		return {ok = false, errorCode = "InvalidPayload"}
	end
	if not isShortString(payload.ZoneId) then
		return {ok = false, errorCode = "InvalidZoneId"}
	end
	if not isShortString(payload.TeleportId) then
		return {ok = false, errorCode = "InvalidTeleportId"}
	end

	return {
		ok = true,
		sanitizedPayload = {
			ZoneId = payload.ZoneId,
			TeleportId = payload.TeleportId,
		},
	}
end

local function validateTrade(payload: any): ValidationResult
	if typeof(payload) ~= "table" then
		return {ok = false, errorCode = "InvalidPayload"}
	end
	if not ValidationUtil.isFiniteNumber(payload.ToUserId) then
		return {ok = false, errorCode = "InvalidToUserId"}
	end

	local itemIds, itemErr = normalizeStringArray(payload.ItemIds)
	if itemIds == nil then
		return {ok = false, errorCode = itemErr}
	end

	local currencyOffer = payload.CurrencyOffer
	if typeof(currencyOffer) ~= "table" then
		currencyOffer = {}
	end

	for currencyName, amount in pairs(currencyOffer) do
		if not isShortString(currencyName) then
			return {ok = false, errorCode = "InvalidCurrencyName"}
		end
		if not ValidationUtil.isFiniteNumber(amount) then
			return {ok = false, errorCode = "InvalidCurrencyAmount"}
		end
	end

	return {
		ok = true,
		sanitizedPayload = {
			TradeId = if isShortString(payload.TradeId) then payload.TradeId else nil,
			ToUserId = payload.ToUserId,
			ItemIds = itemIds,
			CurrencyOffer = currencyOffer,
		},
	}
end

local function validateGift(payload: any): ValidationResult
	if typeof(payload) ~= "table" then
		return {ok = false, errorCode = "InvalidPayload"}
	end
	if not ValidationUtil.isFiniteNumber(payload.RecipientUserId) then
		return {ok = false, errorCode = "InvalidRecipientUserId"}
	end

	local itemIds, itemErr = normalizeStringArray(payload.ItemIds)
	if itemIds == nil then
		return {ok = false, errorCode = itemErr}
	end

	if payload.Message ~= nil and (typeof(payload.Message) ~= "string" or string.len(payload.Message) > 120) then
		return {ok = false, errorCode = "InvalidGiftMessage"}
	end

	return {
		ok = true,
		sanitizedPayload = {
			RecipientUserId = payload.RecipientUserId,
			ItemIds = itemIds,
			Message = payload.Message,
		},
	}
end

local function validateClaim(payload: any): ValidationResult
	if typeof(payload) ~= "table" then
		return {ok = false, errorCode = "InvalidPayload"}
	end
	if not isShortString(payload.ClaimType) then
		return {ok = false, errorCode = "InvalidClaimType"}
	end
	if not isShortString(payload.ClaimId) then
		return {ok = false, errorCode = "InvalidClaimId"}
	end

	return {
		ok = true,
		sanitizedPayload = {
			ClaimType = payload.ClaimType,
			ClaimId = payload.ClaimId,
		},
	}
end

local function validateRedeem(payload: any): ValidationResult
	if typeof(payload) ~= "table" or not isShortString(payload.Code) then
		return {ok = false, errorCode = "InvalidCode"}
	end

	return {
		ok = true,
		sanitizedPayload = {
			Code = string.upper(payload.Code),
		},
	}
end

local VALIDATORS: {[string]: (payload: any) -> ValidationResult} = {
	Attack = validateAttack,
	Equip = validateEquip,
	Unlock = validateUnlock,
	Teleport = validateTeleport,
	Trade = validateTrade,
	Gift = validateGift,
	Claim = validateClaim,
	Redeem = validateRedeem,
}

local function validate(actionName: string, payload: any): ValidationResult
	local validator = VALIDATORS[actionName]
	if validator == nil then
		return {ok = false, errorCode = "UnknownAction"}
	end
	return validator(payload)
end

RemoteSchemas.validate = validate
RemoteSchemas.validators = VALIDATORS

return RemoteSchemas
