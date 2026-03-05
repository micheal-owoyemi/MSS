--!strict

type BufferConfig = {
	MaxAddsPerFlushPerPlayer: number,
	MaxUpdatesPerFlushPerPlayer: number,
	MaxRemovesPerFlushPerPlayer: number,
	MaxTotalMobEntriesPerFlush: number,
}

type PlayerViewState = {
	KnownMobRevisionById: {[string]: number},
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
	local relevantSet: {[string]: true} = {}

	for _, mobId in ipairs(relevantMobIds) do
		relevantSet[mobId] = true
	end

	local maxAdds = self._config.MaxAddsPerFlushPerPlayer
	local maxUpdates = self._config.MaxUpdatesPerFlushPerPlayer
	local maxRemoves = self._config.MaxRemovesPerFlushPerPlayer
	local maxTotal = self._config.MaxTotalMobEntriesPerFlush

	local adds = {}
	local updates = {}
	local removes = {}
	local totalEntries = 0

	for mobId in pairs(known) do
		if totalEntries >= maxTotal or #removes >= maxRemoves then
			break
		end

		local state = getAddState(mobId)
		if relevantSet[mobId] ~= true or state == nil then
			known[mobId] = nil
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
				if #adds < maxAdds then
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
					if #updates < maxUpdates then
						table.insert(updates, updateState)
						known[mobId] = revision
						totalEntries += 1
					end
				end
			end
		end
	end

	if #adds == 0 and #updates == 0 and #removes == 0 then
		return nil
	end

	self._sequence += 1
	return {
		seq = self._sequence,
		t = now,
		a = adds,
		u = updates,
		rm = removes,
	}
end

function ReplicationBuffer:Destroy()
	table.clear(self._viewByUserId)
end

return ReplicationBuffer
