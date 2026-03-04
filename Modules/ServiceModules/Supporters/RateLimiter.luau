--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local MathUtil = require(ReplicatedStorage.Util.MathUtil)
local RequestPolicy = require(ReplicatedStorage.Net.RequestPolicy)

type RequestLimit = {
	Burst: number,
	BurstWindowSeconds: number,
	Sustain: number,
	SustainWindowSeconds: number,
}

type BucketState = {
	BurstTokens: number,
	SustainTokens: number,
	BurstUpdatedAt: number,
	SustainUpdatedAt: number,
}

type UserActionState = {[string]: BucketState}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

local function refill(tokens: number, maxTokens: number, elapsed: number, windowSeconds: number): number
	if elapsed <= 0 or windowSeconds <= 0 then
		return tokens
	end

	local refillRate = maxTokens / windowSeconds
	return MathUtil.clamp(tokens + elapsed * refillRate, 0, maxTokens)
end

local function resolveUserId(playerOrUserId: Player | number): number?
	if typeof(playerOrUserId) == "Instance" then
		local player = playerOrUserId :: Player
		if player:IsA("Player") then
			return player.UserId
		end
		return nil
	end

	if typeof(playerOrUserId) == "number" and playerOrUserId > 0 then
		return playerOrUserId
	end

	return nil
end

function RateLimiter.new(policyResolver: ((actionName: string) -> RequestLimit)?): any
	local self = setmetatable({
		_policyResolver = policyResolver or RequestPolicy.get,
		_stateByUser = {} :: {[number]: UserActionState},
		_janitor = Janitor.new(),
	}, RateLimiter)

	self._janitor:Add(Players.PlayerRemoving:Connect(function(player: Player)
		self:ClearPlayer(player)
	end), "Disconnect", "PlayerRemovingConnection")

	return self
end

function RateLimiter:_getLimits(actionName: string): RequestLimit
	local limits = self._policyResolver(actionName)
	return limits
end

function RateLimiter:_consumeByUserId(userId: number, actionName: string, now: number): boolean
	local limits = self:_getLimits(actionName)
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
			BurstUpdatedAt = now,
			SustainUpdatedAt = now,
		}
		stateByAction[actionName] = state
	end

	state.BurstTokens = refill(state.BurstTokens, limits.Burst, now - state.BurstUpdatedAt, limits.BurstWindowSeconds)
	state.SustainTokens = refill(state.SustainTokens, limits.Sustain, now - state.SustainUpdatedAt, limits.SustainWindowSeconds)
	state.BurstUpdatedAt = now
	state.SustainUpdatedAt = now

	if state.BurstTokens < 1 or state.SustainTokens < 1 then
		return false
	end

	state.BurstTokens -= 1
	state.SustainTokens -= 1
	return true
end

function RateLimiter:Consume(playerOrUserId: Player | number, actionName: string): boolean
	if typeof(actionName) ~= "string" or actionName == "" then
		return false
	end

	local userId = resolveUserId(playerOrUserId)
	if userId == nil then
		return false
	end

	return self:_consumeByUserId(userId, actionName, os.clock())
end

function RateLimiter:GetRemaining(playerOrUserId: Player | number, actionName: string): {Burst: number, Sustain: number}
	local userId = resolveUserId(playerOrUserId)
	local limits = self:_getLimits(actionName)
	if userId == nil then
		return {
			Burst = 0,
			Sustain = 0,
		}
	end

	local stateByAction = self._stateByUser[userId]
	local state = if stateByAction then stateByAction[actionName] else nil
	if state == nil then
		return {
			Burst = limits.Burst,
			Sustain = limits.Sustain,
		}
	end

	local now = os.clock()
	local burstTokens = refill(state.BurstTokens, limits.Burst, now - state.BurstUpdatedAt, limits.BurstWindowSeconds)
	local sustainTokens = refill(state.SustainTokens, limits.Sustain, now - state.SustainUpdatedAt, limits.SustainWindowSeconds)

	return {
		Burst = burstTokens,
		Sustain = sustainTokens,
	}
end

function RateLimiter:ClearUser(userId: number)
	if typeof(userId) ~= "number" then
		return
	end
	self._stateByUser[userId] = nil
end

function RateLimiter:ClearPlayer(playerOrUserId: Player | number)
	local userId = resolveUserId(playerOrUserId)
	if userId == nil then
		return
	end
	self:ClearUser(userId)
end

function RateLimiter:Destroy()
	if self._janitor then
		self._janitor:Cleanup()
	end
	if self._stateByUser then
		table.clear(self._stateByUser)
	end
end

return RateLimiter
