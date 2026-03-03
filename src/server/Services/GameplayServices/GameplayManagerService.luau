local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local DataGameplayManager = require(script.Parent.Parent.Parent.Config.Data_GameplayManager)

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

local GameplayManagerService = Knit.CreateService({
	Name = "GameplayManagerService",
	Client = {},
})

function GameplayManagerService:KnitInit()
	self._systems = {} :: { [string]: RegisteredSystem }
	self._scheduled = {} :: { [string]: ScheduledEntry }
	self._loopRunning = false
	self._connections = {} :: { RBXScriptConnection }
end

function GameplayManagerService:KnitStart()
	self:_bindPlayerLifecycle()
	self:_startLoop()
end

function GameplayManagerService:Now(): number
	if Workspace.GetServerTimeNow then
		return Workspace:GetServerTimeNow()
	end

	return os.clock()
end

function GameplayManagerService:RegisterSystem(name: string, system: RegisteredSystem)
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

function GameplayManagerService:UnregisterSystem(name: string)
	self._systems[name] = nil
end

function GameplayManagerService:ScheduleAt(key: string, atTime: number, callback: () -> ())
	if type(key) ~= "string" or key == "" or type(callback) ~= "function" then
		return
	end

	self._scheduled[key] = {
		key = key,
		atTime = tonumber(atTime) or self:Now(),
		callback = callback,
	}
end

function GameplayManagerService:Cancel(key: string)
	self._scheduled[key] = nil
end

function GameplayManagerService:_startLoop()
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

function GameplayManagerService:_runScheduled(now: number)
	for key, entry in pairs(self._scheduled) do
		if entry.atTime <= now then
			self._scheduled[key] = nil
			local ok, err = pcall(entry.callback)
			if not ok then
				warn(string.format("[GameplayManagerService] Scheduled callback '%s' failed: %s", key, tostring(err)))
			end
		end
	end
end

function GameplayManagerService:_tick(now: number, dt: number)
	self:_runScheduled(now)
	for _, system in pairs(self._systems) do
		local onTick = system.OnTick
		if type(onTick) == "function" then
			onTick(system, now, dt)
		end
	end
end

function GameplayManagerService:_bindPlayerLifecycle()
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

return GameplayManagerService
