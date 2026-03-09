--!strict

type BufferConfig = {
	MaxAddsPerFlushPerPlayer: number,
	MaxUpdatesPerFlushPerPlayer: number,
	MaxRemovesPerFlushPerPlayer: number,
	MaxTotalMobEntriesPerFlush: number,
}

type PlayerViewState = {
	KnownMobRevisionById: {[string]: number},
	RelevantSetScratch: {[string]: true},
}

type Packet = {
	seq: number,
	t: number,
	a: {{[string]: any}},
	u: {{[string]: any}},
	rm: {string},
}

local ReplicationBuffer = {}
ReplicationBuffer.__index = ReplicationBuffer
local EMPTY_STATE_LIST = table.freeze({}) :: {{[string]: any}}
local EMPTY_MOB_ID_LIST = table.freeze({}) :: {string}

function ReplicationBuffer.new(config: BufferConfig): any
	local self = setmetatable({
		_config = config,
		_sequence = 0,
		_viewByUserId = {} :: {[number]: PlayerViewState},
	}, ReplicationBuffer)

	return self
end

function ReplicationBuffer:_getOrCreateView(userId: number): PlayerViewState
	local view = self._viewByUserId[userId]
	if view ~= nil then
		return view
	end

	view = {
		KnownMobRevisionById = {},
		RelevantSetScratch = {},
	}
	self._viewByUserId[userId] = view
	return view
end

function ReplicationBuffer:ResetPlayer(userId: number)
	self._viewByUserId[userId] = nil
end

function ReplicationBuffer:BuildPacketForPlayer(
	userId: number,
	now: number,
	relevantMobIds: {string},
	getAddState: (mobId: string) -> {[string]: any}?,
	getUpdateState: (mobId: string) -> {[string]: any}?
): Packet?
	local view = self:_getOrCreateView(userId)
	local known = view.KnownMobRevisionById
	local relevantSet = view.RelevantSetScratch
	table.clear(relevantSet)

	for _, mobId in ipairs(relevantMobIds) do
		relevantSet[mobId] = true
	end

	local maxAdds = self._config.MaxAddsPerFlushPerPlayer
	local maxUpdates = self._config.MaxUpdatesPerFlushPerPlayer
	local maxRemoves = self._config.MaxRemovesPerFlushPerPlayer
	local maxTotal = self._config.MaxTotalMobEntriesPerFlush

	local adds: {{[string]: any}}? = nil
	local updates: {{[string]: any}}? = nil
	local removes: {string}? = nil
	local totalEntries = 0

	for mobId in pairs(known) do
		local removeCount = if removes ~= nil then #removes else 0
		if totalEntries >= maxTotal or removeCount >= maxRemoves then
			break
		end

		local state = getAddState(mobId)
		if relevantSet[mobId] ~= true or state == nil then
			known[mobId] = nil
			if removes == nil then
				removes = {}
			end
			table.insert(removes, mobId)
			totalEntries += 1
		end
	end

	for _, mobId in ipairs(relevantMobIds) do
		if totalEntries >= maxTotal then
			break
		end

		local sentRevision = known[mobId]
		if sentRevision == nil then
			local addState = getAddState(mobId)
			if addState ~= nil then
				local revision = tonumber(addState.r) or 0
				local addCount = if adds ~= nil then #adds else 0
				if addCount < maxAdds then
					if adds == nil then
						adds = {}
					end
					table.insert(adds, addState)
					known[mobId] = revision
					totalEntries += 1
				end
			end
		else
			local updateState = getUpdateState(mobId)
			if updateState ~= nil then
				local revision = tonumber(updateState.r) or 0
				if revision > sentRevision then
					local updateCount = if updates ~= nil then #updates else 0
					if updateCount < maxUpdates then
						if updates == nil then
							updates = {}
						end
						table.insert(updates, updateState)
						known[mobId] = revision
						totalEntries += 1
					end
				end
			end
		end
	end

	if adds == nil and updates == nil and removes == nil then
		return nil
	end

	self._sequence += 1
	return {
		seq = self._sequence,
		t = now,
		a = if adds ~= nil then adds else EMPTY_STATE_LIST,
		u = if updates ~= nil then updates else EMPTY_STATE_LIST,
		rm = if removes ~= nil then removes else EMPTY_MOB_ID_LIST,
	}
end

function ReplicationBuffer:Destroy()
	table.clear(self._viewByUserId)
end

return ReplicationBuffer
