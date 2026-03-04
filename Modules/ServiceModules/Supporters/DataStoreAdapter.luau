--!strict

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local ValidationUtil = require(ReplicatedStorage.Util.ValidationUtil)

type ProfileSessionLike = {
	Data: any,
	IsActive: (self: ProfileSessionLike) -> boolean,
	Save: (self: ProfileSessionLike) -> (),
	Key: string?,
}

type AdapterConfig = {
	MaxWriteRetries: number?,
	WriteRetryBaseDelaySeconds: number?,
	WriteRetryMaxDelaySeconds: number?,
	WriteDebounceDelaySeconds: number?,
	WriteIdlePollIntervalSeconds: number?,
	DataStoreBudgetPollIntervalSeconds: number?,
	SerializationDepthLimit: number?,
}

type SaveState = {
	UserId: number,
	Profile: ProfileSessionLike?,
	Pending: boolean,
	Writing: boolean,
	RunnerActive: boolean,
	Cancelled: boolean,
	RunId: number,
	NextWriteAt: number,
	Context: string,
	LastError: string?,
	Janitor: any,
}

local DEFAULTS = {
	MaxWriteRetries = 6,
	WriteRetryBaseDelaySeconds = 1,
	WriteRetryMaxDelaySeconds = 8,
	WriteDebounceDelaySeconds = 5,
	WriteIdlePollIntervalSeconds = 0.1,
	DataStoreBudgetPollIntervalSeconds = 0.25,
	SerializationDepthLimit = 64,
}

local DataStoreAdapter = {}
DataStoreAdapter.__index = DataStoreAdapter

local function normalizeConfig(raw: AdapterConfig?): {[string]: number}
	local resolved = {}
	for key, defaultValue in pairs(DEFAULTS) do
		local rawValue = if raw ~= nil then (raw :: any)[key] else nil
		if typeof(rawValue) == "number" and rawValue > 0 then
			resolved[key] = rawValue
		else
			resolved[key] = defaultValue
		end
	end
	return resolved
end

local function isSupportedKeyType(key: any): boolean
	local keyType = typeof(key)
	if keyType == "string" then
		return true
	end
	if keyType == "number" then
		if not ValidationUtil.isFiniteNumber(key) then
			return false
		end
		return key % 1 == 0
	end
	return false
end

local function validateSerializableValue(value: any, depth: number, maxDepth: number, seen: {[any]: boolean}): (boolean, string?)
	if depth > maxDepth then
		return false, "DepthLimitExceeded"
	end

	local valueType = typeof(value)
	if valueType == "nil" or valueType == "boolean" or valueType == "string" then
		return true, nil
	end

	if valueType == "number" then
		if ValidationUtil.isFiniteNumber(value) then
			return true, nil
		end
		return false, "NonFiniteNumber"
	end

	if valueType ~= "table" then
		return false, "UnsupportedType:" .. valueType
	end

	if seen[value] then
		return false, "CyclicReference"
	end

	seen[value] = true
	for key, child in pairs(value) do
		if not isSupportedKeyType(key) then
			seen[value] = nil
			return false, "UnsupportedKeyType"
		end

		local ok, err = validateSerializableValue(child, depth + 1, maxDepth, seen)
		if not ok then
			seen[value] = nil
			return false, err
		end
	end
	seen[value] = nil

	return true, nil
end

function DataStoreAdapter.new(config: AdapterConfig?): any
	local resolvedConfig = normalizeConfig(config)

	local self = setmetatable({
		_config = resolvedConfig,
		_states = {} :: {[number]: SaveState},
		_destroyed = false,
		_janitor = Janitor.new(),
	}, DataStoreAdapter)

	return self
end

function DataStoreAdapter:_isProfileActive(profile: ProfileSessionLike?): boolean
	if profile == nil then
		return false
	end
	if typeof(profile.IsActive) ~= "function" then
		return false
	end
	return profile:IsActive()
end

function DataStoreAdapter:_newState(userId: number): SaveState
	return {
		UserId = userId,
		Profile = nil,
		Pending = false,
		Writing = false,
		RunnerActive = false,
		Cancelled = false,
		RunId = 0,
		NextWriteAt = 0,
		Context = "Unknown",
		LastError = nil,
		Janitor = Janitor.new(),
	}
end

function DataStoreAdapter:_getState(userId: number): SaveState
	local state = self._states[userId]
	if state == nil then
		state = self:_newState(userId)
		self._states[userId] = state
	end
	return state
end

function DataStoreAdapter:RegisterProfile(userId: number, profile: ProfileSessionLike)
	local state = self:_getState(userId)
	state.Profile = profile
	state.Pending = false
	state.Writing = false
	state.Cancelled = false
	state.RunId += 1
	state.LastError = nil
end

function DataStoreAdapter:UnregisterProfile(userId: number)
	local state = self._states[userId]
	if state == nil then
		return
	end

	state.Cancelled = true
	state.Pending = false
	state.Profile = nil
	state.RunId += 1
	state.Janitor:Cleanup()

	self._states[userId] = nil
end

function DataStoreAdapter:LoadProfile(userId: number): (any?, string?)
	local state = self._states[userId]
	if state == nil then
		return nil, "ProfileNotRegistered"
	end

	local profile = state.Profile
	if not self:_isProfileActive(profile) then
		return nil, "ProfileInactive"
	end

	return profile.Data, nil
end

function DataStoreAdapter:_waitForBudget(deadline: number?): boolean
	while true do
		local ok, budget = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
		end)

		if not ok then
			return true
		end

		if budget > 0 then
			return true
		end

		if deadline ~= nil and os.clock() >= deadline then
			return false
		end

		task.wait(self._config.DataStoreBudgetPollIntervalSeconds)
	end
end

function DataStoreAdapter:_writeWithRetry(state: SaveState, deadline: number?): (boolean, string?)
	local profile = state.Profile
	if not self:_isProfileActive(profile) then
		return false, "ProfileInactive"
	end

	local okData, dataErr = validateSerializableValue(profile.Data, 0, self._config.SerializationDepthLimit, {})
	if not okData then
		return false, "SerializationError:" .. tostring(dataErr)
	end

	local attempt = 0
	local delay = self._config.WriteRetryBaseDelaySeconds
	local lastError: string? = nil

	while attempt < self._config.MaxWriteRetries do
		if deadline ~= nil and os.clock() >= deadline then
			break
		end

		attempt += 1

		if not self:_waitForBudget(deadline) then
			lastError = "DataStoreBudgetTimeout"
			break
		end

		local ok, err = pcall(function()
			profile:Save()
		end)
		if ok then
			return true, nil
		end

		lastError = tostring(err)
		if attempt < self._config.MaxWriteRetries then
			local waitTime = math.random() * delay
			if deadline ~= nil then
				waitTime = math.min(waitTime, math.max(0, deadline - os.clock()))
			end
			if waitTime > 0 then
				task.wait(waitTime)
			end
			delay = math.min(delay * 2, self._config.WriteRetryMaxDelaySeconds)
		end
	end

	if lastError == nil then
		lastError = "WriteFailed"
	end

	return false, lastError
end

function DataStoreAdapter:_runSaveLoop(userId: number, runId: number)
	local state = self._states[userId]
	if state == nil then
		return
	end

	while self._destroyed == false and state.RunId == runId and state.Cancelled == false do
		if state.Pending == false then
			break
		end

		local waitTime = state.NextWriteAt - os.clock()
		while waitTime > 0 and state.RunId == runId and state.Cancelled == false do
			task.wait(math.min(waitTime, self._config.WriteIdlePollIntervalSeconds))
			waitTime = state.NextWriteAt - os.clock()
		end

		if self._destroyed or state.RunId ~= runId or state.Cancelled then
			break
		end

		if state.Pending == false then
			continue
		end

		state.Pending = false
		state.Writing = true
		local ok, err = self:_writeWithRetry(state, nil)
		state.Writing = false
		if not ok then
			state.LastError = err
			state.Pending = true
			state.NextWriteAt = os.clock() + self._config.WriteRetryBaseDelaySeconds
		end
	end

	if self._states[userId] == state then
		state.RunnerActive = false
	end
end

function DataStoreAdapter:_ensureRunner(state: SaveState)
	if state.RunnerActive then
		return
	end

	state.RunnerActive = true
	state.RunId += 1
	local runId = state.RunId
	local userId = state.UserId
	task.spawn(function()
		self:_runSaveLoop(userId, runId)
	end)
end

function DataStoreAdapter:QueueSave(userId: number, context: string?): (boolean, string?)
	if self._destroyed then
		return false, "AdapterDestroyed"
	end

	local state = self:_getState(userId)
	if not self:_isProfileActive(state.Profile) then
		return false, "ProfileInactive"
	end

	state.Pending = true
	state.NextWriteAt = os.clock() + self._config.WriteDebounceDelaySeconds
	if typeof(context) == "string" then
		state.Context = context
	end

	self:_ensureRunner(state)
	return true, nil
end

function DataStoreAdapter:WaitForIdle(userId: number, deadline: number?): boolean
	local state = self._states[userId]
	while state ~= nil and (state.Pending or state.Writing or state.RunnerActive) do
		if deadline ~= nil and os.clock() >= deadline then
			return false
		end
		task.wait(self._config.WriteIdlePollIntervalSeconds)
		state = self._states[userId]
	end
	return true
end

function DataStoreAdapter:FlushSave(userId: number, context: string?, deadline: number?): (boolean, string?)
	if self._destroyed then
		return false, "AdapterDestroyed"
	end

	local state = self._states[userId]
	if state == nil then
		return false, "ProfileNotRegistered"
	end
	if not self:_isProfileActive(state.Profile) then
		return false, "ProfileInactive"
	end

	if typeof(context) == "string" then
		state.Context = context
	end

	state.Pending = false
	state.NextWriteAt = 0

	if not self:WaitForIdle(userId, deadline) then
		return false, "WriteIdleTimeout"
	end

	state.Writing = true
	local ok, err = self:_writeWithRetry(state, deadline)
	state.Writing = false
	if not ok then
		state.LastError = err
		return false, err
	end

	state.LastError = nil
	return true, nil
end

function DataStoreAdapter:UpdateProfile(userId: number, transformFn: (profileData: any) -> any): (boolean, string?)
	if typeof(transformFn) ~= "function" then
		return false, "InvalidTransform"
	end

	local state = self._states[userId]
	if state == nil then
		return false, "ProfileNotRegistered"
	end
	if not self:_isProfileActive(state.Profile) then
		return false, "ProfileInactive"
	end

	local profile = state.Profile :: ProfileSessionLike

	-- Transform functions should be idempotent. Writes may retry under transient datastore failures.
	local ok, result = pcall(transformFn, profile.Data)
	if not ok then
		return false, "TransformError:" .. tostring(result)
	end

	if result ~= nil then
		if typeof(result) ~= "table" then
			return false, "TransformReturnedNonTable"
		end
		profile.Data = result
	end

	return self:QueueSave(userId, "UpdateProfile")
end

function DataStoreAdapter:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true

	for userId in pairs(self._states) do
		self:UnregisterProfile(userId)
	end

	self._janitor:Cleanup()
end

return DataStoreAdapter
