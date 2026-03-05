--!strict

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local RequestPolicy = {}

export type RequestLimit = {
	Burst: number,
	BurstWindowSeconds: number,
	Sustain: number,
	SustainWindowSeconds: number,
}

local ACTION_LIMITS: {[string]: RequestLimit} = {
	Attack = {
		Burst = 12,
		BurstWindowSeconds = 1,
		Sustain = 120,
		SustainWindowSeconds = 10,
	},
	Equip = {
		Burst = 6,
		BurstWindowSeconds = 1,
		Sustain = 30,
		SustainWindowSeconds = 10,
	},
	Unlock = {
		Burst = 2,
		BurstWindowSeconds = 2,
		Sustain = 8,
		SustainWindowSeconds = 30,
	},
	Teleport = {
		Burst = 2,
		BurstWindowSeconds = 2,
		Sustain = 10,
		SustainWindowSeconds = 30,
	},
	TradeOffer = {
		Burst = 4,
		BurstWindowSeconds = 2,
		Sustain = 20,
		SustainWindowSeconds = 20,
	},
	Gift = {
		Burst = 2,
		BurstWindowSeconds = 2,
		Sustain = 12,
		SustainWindowSeconds = 30,
	},
	Claim = {
		Burst = 3,
		BurstWindowSeconds = 2,
		Sustain = 15,
		SustainWindowSeconds = 30,
	},
	Redeem = {
		Burst = 1,
		BurstWindowSeconds = 2,
		Sustain = 6,
		SustainWindowSeconds = 30,
	},
	RequestSnapshot = {
		Burst = 3,
		BurstWindowSeconds = 1,
		Sustain = 18,
		SustainWindowSeconds = 10,
	},
	ReplicaSignal = {
		Burst = 30,
		BurstWindowSeconds = 1,
		Sustain = 180,
		SustainWindowSeconds = 10,
	},
}

local DEFAULT_LIMIT: RequestLimit = {
	Burst = 2,
	BurstWindowSeconds = 1,
	Sustain = 10,
	SustainWindowSeconds = 10,
}

local function get(actionName: string): RequestLimit
	local policy = ACTION_LIMITS[actionName]
	if policy ~= nil then
		return policy
	end
	return DEFAULT_LIMIT
end

RequestPolicy.ActionLimits = TableUtil.deepFreeze(ACTION_LIMITS)
RequestPolicy.DefaultLimit = DEFAULT_LIMIT
RequestPolicy.get = get

return RequestPolicy
