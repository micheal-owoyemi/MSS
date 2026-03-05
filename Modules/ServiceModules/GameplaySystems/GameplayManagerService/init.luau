--!nonstrict

--[[
	GameplayManagerService
	
	A server-side Knit service that manages gameplay systems through a fixed-rate heartbeat loop.
	Handles system lifecycle, player events, and scheduled callbacks to avoid per-frame scanning.
	
	System Lifecycle
	---------------
	Systems implement optional callbacks that fire during specific service events:
	
	- OnStart(manager)
		Called when system is registered; receives manager reference to wire dependencies.
	
	- OnTick(now, dt)
		Called every heartbeat tick. `now` is monotonic server time; `dt` is elapsed seconds since last tick.
	
	- OnPlayerAdded(player)
		Called when a player joins. Fires immediately for existing players on registration (catch-up).
	
	- OnPlayerRemoving(player)
		Called when a player leaves.
	
	Scheduler API
	-------------
	Systems can avoid per-frame checks by scheduling one-off callbacks:
	
	- ScheduleAt(key: string, atTime: number, fn: () -> ())
		Schedule a callback to run when Now() >= atTime. Keys allow updates/cancellations.
	
	- Cancel(key: string)
		Remove a scheduled callback by key.
	
	Example
	-------
	local MySystem = {}
	
	function MySystem:OnStart(manager)
		self.manager = manager
	end
	
	function MySystem:OnPlayerAdded(player)
		-- Schedule cleanup 5 seconds after join
		local now = self.manager:Now()
		self.manager:ScheduleAt("cleanup_" .. player.UserId, now + 5, function()
			print("Cleanup for", player.Name)
		end)
	end
	
	function MySystem:OnTick(now, dt)
		-- Called at the configured heartbeat rate.
	end
	
	-- Register with manager
	local manager = Knit.GetService("GameplayManagerService")
	manager:RegisterSystem("MySystem", MySystem)
]]

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not RunService:IsServer() then
	error("GameplayManagerService must run on the server")
end

local Knit = require(ReplicatedStorage.Packages.Knit)
local Config = require(script.Config)

-- Systems can implement any subset of these callbacks to participate in the manager loop.
export type RegisteredSystem = {
	OnStart: ((RegisteredSystem, GameplayManagerService) -> ())?,
	OnTick: ((RegisteredSystem, number, number) -> ())?,
	OnPlayerAdded: ((RegisteredSystem, Player) -> ())?,
	OnPlayerRemoving: ((RegisteredSystem, Player) -> ())?,
}

type SystemsDictionary = {[string]: RegisteredSystem}
type ScheduledEntry = {
	key: string,
	atTime: number,
	callback: () -> (),
	heapIndex: number,
}
type SchedulerDictionary = {[string]: ScheduledEntry}
type SchedulerHeap = {ScheduledEntry}

local HEARTBEAT_RATE = Config.HeartbeatRateHz
local HEARTBEAT_INTERVAL = 1 / HEARTBEAT_RATE

local GameplayManagerService = Knit.CreateService({
	Name = "GameplayManagerService",
	Client = {},
	_systems = {} :: SystemsDictionary,
	_scheduled = {} :: SchedulerDictionary,
	_scheduledHeap = {} :: SchedulerHeap,
	_loopRunning = false,
	_playerAddedConn = nil :: RBXScriptConnection?,
	_playerRemovingConn = nil :: RBXScriptConnection?,
})

export type GameplayManagerService = typeof(GameplayManagerService)

function GameplayManagerService:KnitInit()
	self._systems = {} :: SystemsDictionary
	self._scheduled = {} :: SchedulerDictionary
	self._scheduledHeap = {} :: SchedulerHeap
	self._loopRunning = false
	self._playerAddedConn = nil
	self._playerRemovingConn = nil
end


function GameplayManagerService:KnitStart()
	-- PlayerService will eventually own lifecycle routing; bind here until it does.
	self:_BindPlayerLifecycle()
	self:StartLoop()
end

function GameplayManagerService:Now(): number
	if Workspace and Workspace.GetServerTimeNow then
		return Workspace:GetServerTimeNow()
	end

	return os.clock()
end

function GameplayManagerService:RegisterSystem(name: string, system: RegisteredSystem)
	self._systems[name] = system

	local onStart = system.OnStart
	if onStart then
		onStart(system, self)
	end

	local onPlayerAdded = system.OnPlayerAdded
	if onPlayerAdded then
		for _, player in Players:GetPlayers() do
			onPlayerAdded(system, player)
		end
	end
end

function GameplayManagerService:UnregisterSystem(name: string)
	self._systems[name] = nil
end

function GameplayManagerService:ScheduleAt(key: string, atTime: number, fn: () -> ())
	local existing = self._scheduled[key]
	if existing then
		self:_HeapRemove(existing.heapIndex)
	end

	local entry: ScheduledEntry = {
		key = key,
		atTime = atTime,
		callback = fn,
		heapIndex = 0,
	}

	self._scheduled[key] = entry
	self:_HeapPush(entry)
end

function GameplayManagerService:Cancel(key: string)
	local entry = self._scheduled[key]
	if not entry then
		return
	end

	self._scheduled[key] = nil
	self:_HeapRemove(entry.heapIndex)
end

function GameplayManagerService:_HeapSwap(heap: SchedulerHeap, leftIndex: number, rightIndex: number)
	local leftEntry = heap[leftIndex]
	local rightEntry = heap[rightIndex]
	heap[leftIndex] = rightEntry
	heap[rightIndex] = leftEntry
	leftEntry.heapIndex = rightIndex
	rightEntry.heapIndex = leftIndex
end

function GameplayManagerService:_HeapSiftUp(heap: SchedulerHeap, startIndex: number)
	local index = startIndex
	while index > 1 do
		local parentIndex = math.floor(index / 2)
		if heap[parentIndex].atTime <= heap[index].atTime then
			return
		end

		self:_HeapSwap(heap, parentIndex, index)
		index = parentIndex
	end
end

function GameplayManagerService:_HeapSiftDown(heap: SchedulerHeap, startIndex: number)
	local count = #heap
	local index = startIndex

	while true do
		local leftIndex = index * 2
		if leftIndex > count then
			return
		end

		local rightIndex = leftIndex + 1
		local smallestIndex = leftIndex
		if rightIndex <= count and heap[rightIndex].atTime < heap[leftIndex].atTime then
			smallestIndex = rightIndex
		end

		if heap[index].atTime <= heap[smallestIndex].atTime then
			return
		end

		self:_HeapSwap(heap, index, smallestIndex)
		index = smallestIndex
	end
end

function GameplayManagerService:_HeapPush(entry: ScheduledEntry)
	local heap = self._scheduledHeap
	table.insert(heap, entry)
	entry.heapIndex = #heap
	self:_HeapSiftUp(heap, entry.heapIndex)
end

function GameplayManagerService:_HeapPop(): ScheduledEntry?
	local heap = self._scheduledHeap
	local count = #heap
	if count == 0 then
		return nil
	end

	local root = heap[1]
	if count == 1 then
		heap[1] = nil
		root.heapIndex = 0
		return root
	end

	local last = heap[count]
	heap[1] = last
	heap[count] = nil
	last.heapIndex = 1
	self:_HeapSiftDown(heap, 1)
	root.heapIndex = 0
	return root
end

function GameplayManagerService:_HeapRemove(index: number)
	local heap = self._scheduledHeap
	local count = #heap
	if index < 1 or index > count then
		return
	end

	local removed = heap[index]
	if index == count then
		heap[count] = nil
		removed.heapIndex = 0
		return
	end

	heap[index] = heap[count]
	heap[count] = nil
	heap[index].heapIndex = index
	removed.heapIndex = 0

	local parentIndex = math.floor(index / 2)
	if parentIndex >= 1 and heap[index].atTime < heap[parentIndex].atTime then
		self:_HeapSiftUp(heap, index)
	else
		self:_HeapSiftDown(heap, index)
	end
end

function GameplayManagerService:StartLoop()
	if self._loopRunning then
		return
	end

	self._loopRunning = true

	-- Manual heartbeat remains until the shared scheduler replaces it.
	task.spawn(function()
		local lastNow = self:Now()

		while self._loopRunning do
			task.wait(HEARTBEAT_INTERVAL)

			local currentNow = self:Now()
			local dt = currentNow - lastNow

			self:_Tick(currentNow, dt)
			lastNow = currentNow
		end
	end)
end

function GameplayManagerService:_BindPlayerLifecycle()
	if self._playerAddedConn or self._playerRemovingConn then
		return
	end

	self._playerAddedConn = Players.PlayerAdded:Connect(function(player: Player)
		self:_HandlePlayerAdded(player)
	end)

	self._playerRemovingConn = Players.PlayerRemoving:Connect(function(player: Player)
		self:_HandlePlayerRemoving(player)
	end)

	for _, player in Players:GetPlayers() do
		self:_HandlePlayerAdded(player)
	end
end

function GameplayManagerService:_Tick(now: number, dt: number)
	self:_RunScheduled(now)

	for _, system in pairs(self._systems) do
		local onTick = system.OnTick
		if onTick then
			local ok, err = pcall(onTick, system, now, dt)
			if not ok then
				warn(string.format("GameplayManagerService tick error: %s", tostring(err)))
			end
		end
	end
end

function GameplayManagerService:_RunScheduled(now: number)
	local scheduled = self._scheduled
	local heap = self._scheduledHeap

	while true do
		local entry = heap[1]
		if not entry or entry.atTime > now then
			return
		end

		self:_HeapPop()
		scheduled[entry.key] = nil
		local ok, err = pcall(entry.callback)
		if not ok then
			-- Forward scheduler errors to logging once a central sink exists.
			warn(string.format("GameplayManagerService scheduler error for '%s': %s", entry.key, tostring(err)))
		end
	end
end

function GameplayManagerService:_HandlePlayerAdded(player: Player)
	for _, system in pairs(self._systems) do
		local onPlayerAdded = system.OnPlayerAdded
		if onPlayerAdded then
			local ok, err = pcall(onPlayerAdded, system, player)
			if not ok then
				warn(string.format("GameplayManagerService player-added error: %s", tostring(err)))
			end
		end
	end
end

function GameplayManagerService:_HandlePlayerRemoving(player: Player)
	for _, system in pairs(self._systems) do
		local onPlayerRemoving = system.OnPlayerRemoving
		if onPlayerRemoving then
			local ok, err = pcall(onPlayerRemoving, system, player)
			if not ok then
				warn(string.format("GameplayManagerService player-removing error: %s", tostring(err)))
			end
		end
	end
end

function GameplayManagerService:_cleanup()
	self._loopRunning = false

	if self._playerAddedConn then
		self._playerAddedConn:Disconnect()
		self._playerAddedConn = nil
	end

	if self._playerRemovingConn then
		self._playerRemovingConn:Disconnect()
		self._playerRemovingConn = nil
	end

	self._systems = {}
	self._scheduled = {}
	self._scheduledHeap = {}
end

function GameplayManagerService:Destroy()
	self:_cleanup()
end

return GameplayManagerService
