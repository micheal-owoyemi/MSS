local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local DataGameplayManager = require(ServerStorage.Data.Data_GameplayManager)

type RegisteredSystem = {
	OnStart: ((self: RegisteredSystem, manager: any) -> ())?,
	OnTick: ((self: RegisteredSystem, now: number, dt: number) -> ())?,
	OnPlayerAdded: ((self: RegisteredSystem, player: Player) -> ())?,
	OnPlayerRemoving: ((self: RegisteredSystem, player: Player) -> ())?,
}

type ScheduledEntry = {
	key: string,
	atTime: number,
	callback: () -> (),
}

local HEARTBEAT_RATE = tonumber(DataGameplayManager.HeartbeatRateHz) or 10
local HEARTBEAT_INTERVAL = 1 / math.max(1, HEARTBEAT_RATE)

local GamePlayManagerService = {
	Name = "GamePlayManagerService",
}

function GamePlayManagerService:Init()
	self._systems = {} :: { [string]: RegisteredSystem }
	self._scheduled = {} :: { [string]: ScheduledEntry }
	self._loopRunning = false
	self._connections = {} :: { RBXScriptConnection }
end

function GamePlayManagerService:Start()
	self:_bindPlayerLifecycle()
	self:startLoop()
end

function GamePlayManagerService:Now(): number
	if Workspace.GetServerTimeNow then
		return Workspace:GetServerTimeNow()
	end

	return os.clock()
end

function GamePlayManagerService:RegisterSystem(name: string, system: RegisteredSystem)
	if type(name) ~= "string" or name == "" or type(system) ~= "table" then
		return
	end

	self._systems[name] = system

	local onStart = system.OnStart
	if type(onStart) == "function" then
		onStart(system, self)
	end

	local onPlayerAdded = system.OnPlayerAdded
	if type(onPlayerAdded) == "function" then
		for _, player in ipairs(Players:GetPlayers()) do
			onPlayerAdded(system, player)
		end
	end
end

function GamePlayManagerService:UnregisterSystem(name: string)
	self._systems[name] = nil
end

function GamePlayManagerService:ScheduleAt(key: string, atTime: number, callback: () -> ())
	if type(key) ~= "string" or key == "" or type(callback) ~= "function" then
		return
	end

	self._scheduled[key] = {
		key = key,
		atTime = tonumber(atTime) or self:Now(),
		callback = callback,
	}
end

function GamePlayManagerService:Cancel(key: string)
	self._scheduled[key] = nil
end

function GamePlayManagerService:startLoop()
	if self._loopRunning then
		return
	end

	self._loopRunning = true
	task.spawn(function()
		local lastNow = self:Now()
		while self._loopRunning do
			task.wait(HEARTBEAT_INTERVAL)
			local now = self:Now()
			local dt = now - lastNow
			self:_tick(now, dt)
			lastNow = now
		end
	end)
end

function GamePlayManagerService:_runScheduled(now: number)
	for key, entry in pairs(self._scheduled) do
		if entry.atTime <= now then
			self._scheduled[key] = nil
			local ok, err = pcall(entry.callback)
			if not ok then
				warn(string.format("[GamePlayManagerService] Scheduled callback '%s' failed: %s", key, tostring(err)))
			end
		end
	end
end

function GamePlayManagerService:_tick(now: number, dt: number)
	self:_runScheduled(now)
	for _, system in pairs(self._systems) do
		local onTick = system.OnTick
		if type(onTick) == "function" then
			onTick(system, now, dt)
		end
	end
end

function GamePlayManagerService:_bindPlayerLifecycle()
	table.insert(self._connections, Players.PlayerAdded:Connect(function(player)
		for _, system in pairs(self._systems) do
			local onPlayerAdded = system.OnPlayerAdded
			if type(onPlayerAdded) == "function" then
				onPlayerAdded(system, player)
			end
		end
	end))

	table.insert(self._connections, Players.PlayerRemoving:Connect(function(player)
		for _, system in pairs(self._systems) do
			local onPlayerRemoving = system.OnPlayerRemoving
			if type(onPlayerRemoving) == "function" then
				onPlayerRemoving(system, player)
			end
		end
	end))
end

function GamePlayManagerService:Destroy()
	self._loopRunning = false
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	table.clear(self._systems)
	table.clear(self._scheduled)
end

return GamePlayManagerService
