--!strict

local RequestPolicy = require(script.Parent.Parent.Net.RequestPolicy)
local MathUtil = require(script.Parent.Parent.Util.MathUtil)

local RequestRateLimiter = {}
RequestRateLimiter.__index = RequestRateLimiter

type BucketState = {
	BurstTokens: number,
	SustainTokens: number,
	BurstUpdatedAt: number,
	SustainUpdatedAt: number,
}

type UserActionState = {[string]: BucketState}

export type RequestRateLimiter = {
	_stateByUser: {[number]: UserActionState},
	Allow: (self: RequestRateLimiter, userId: number, actionName: string, now: number?) -> boolean,
	ClearUser: (self: RequestRateLimiter, userId: number) -> (),
	Destroy: (self: RequestRateLimiter) -> (),
}

local function refill(tokens: number, maxTokens: number, elapsed: number, windowSeconds: number): number
	if elapsed <= 0 or windowSeconds <= 0 then
		return tokens
	end

	local refillRate = maxTokens / windowSeconds
	return MathUtil.clamp(tokens + elapsed * refillRate, 0, maxTokens)
end

function RequestRateLimiter.new(): RequestRateLimiter
	local self = setmetatable({
		_stateByUser = {},
	}, RequestRateLimiter)

	return self
end

function RequestRateLimiter:Allow(userId: number, actionName: string, now: number?): boolean
	local timestamp = now or os.clock()
	local limits = RequestPolicy.get(actionName)

	local stateByAction = self._stateByUser[userId]
	if stateByAction == nil then
		stateByAction = {}
		self._stateByUser[userId] = stateByAction
	end

	local state = stateByAction[actionName]
	if state == nil then
		state = {
			BurstTokens = limits.Burst,
			SustainTokens = limits.Sustain,
			BurstUpdatedAt = timestamp,
			SustainUpdatedAt = timestamp,
		}
		stateByAction[actionName] = state
	end

	state.BurstTokens = refill(state.BurstTokens, limits.Burst, timestamp - state.BurstUpdatedAt, limits.BurstWindowSeconds)
	state.SustainTokens = refill(state.SustainTokens, limits.Sustain, timestamp - state.SustainUpdatedAt, limits.SustainWindowSeconds)
	state.BurstUpdatedAt = timestamp
	state.SustainUpdatedAt = timestamp

	if state.BurstTokens < 1 or state.SustainTokens < 1 then
		return false
	end

	state.BurstTokens -= 1
	state.SustainTokens -= 1
	return true
end

function RequestRateLimiter:ClearUser(userId: number)
	self._stateByUser[userId] = nil
end

function RequestRateLimiter:Destroy()
	self._stateByUser = {}
end

return RequestRateLimiter
