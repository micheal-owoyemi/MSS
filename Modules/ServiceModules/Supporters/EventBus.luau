--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Janitor = require(ReplicatedStorage.Packages.Janitor)

local EventBus = {}
EventBus.__index = EventBus

function EventBus.new(): any
	local self = setmetatable({
		_listenersByEvent = {} :: {[string]: {[number]: (payload: any) -> ()}},
		_nextListenerId = 0,
		_janitor = Janitor.new(),
	}, EventBus)
	return self
end

function EventBus:Subscribe(eventName: string, callback: (payload: any) -> ())
	assert(typeof(eventName) == "string" and eventName ~= "", "Event name must be a non-empty string")
	assert(typeof(callback) == "function", "Event callback must be a function")

	local listeners = self._listenersByEvent[eventName]
	if listeners == nil then
		listeners = {}
		self._listenersByEvent[eventName] = listeners
	end

	self._nextListenerId += 1
	local listenerId = self._nextListenerId
	listeners[listenerId] = callback

	local disconnected = false
	local function disconnect()
		if disconnected then
			return
		end
		disconnected = true
		local current = self._listenersByEvent[eventName]
		if current ~= nil then
			current[listenerId] = nil
			if next(current) == nil then
				self._listenersByEvent[eventName] = nil
			end
		end
	end

	return {
		Disconnect = disconnect,
	}
end

function EventBus:Publish(eventName: string, payload: any?): number
	local listeners = self._listenersByEvent[eventName]
	if listeners == nil then
		return 0
	end

	local dispatched = 0
	for _, callback in pairs(listeners) do
		local ok, err = pcall(callback, payload)
		if not ok then
			warn(string.format("[EventBus] %s listener error: %s", eventName, tostring(err)))
		else
			dispatched += 1
		end
	end

	return dispatched
end

function EventBus:Destroy()
	for eventName, listeners in pairs(self._listenersByEvent) do
		table.clear(listeners)
		self._listenersByEvent[eventName] = nil
	end
	self._janitor:Cleanup()
end

return EventBus
