--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Janitor = require(ReplicatedStorage.Packages.Janitor)

local TradeLedger = {}
TradeLedger.__index = TradeLedger

local function makeTransactionId(prefix: string?): string
	local scope = if typeof(prefix) == "string" and prefix ~= "" then prefix else "TX"
	return string.format("%s_%d_%s", scope, os.time(), HttpService:GenerateGUID(false))
end

function TradeLedger.new(config: {MaxTransactions: number?}?): any
	local maxTransactions = if config and typeof(config.MaxTransactions) == "number" then math.max(100, math.floor(config.MaxTransactions)) else 5000
	local self = setmetatable({
		_records = {} :: {[string]: any},
		_appliedById = {} :: {[string]: boolean},
		_order = {} :: {string},
		_maxTransactions = maxTransactions,
		_janitor = Janitor.new(),
	}, TradeLedger)
	return self
end

function TradeLedger:_pruneIfNeeded()
	while #self._order > self._maxTransactions do
		local oldestId = table.remove(self._order, 1)
		if oldestId ~= nil then
			self._records[oldestId] = nil
			self._appliedById[oldestId] = nil
		end
	end
end

function TradeLedger:CreateTransaction(kind: string, metadata: any?, explicitId: string?): (string, any)
	local txKind = if typeof(kind) == "string" and kind ~= "" then kind else "Unknown"
	local txId = if typeof(explicitId) == "string" and explicitId ~= "" then explicitId else makeTransactionId(txKind)

	local existing = self._records[txId]
	if existing ~= nil then
		return txId, existing
	end

	local now = os.time()
	local record = {
		Id = txId,
		Kind = txKind,
		CreatedAt = now,
		UpdatedAt = now,
		AppliedAt = nil,
		Status = "Pending",
		Metadata = metadata,
		Escrow = nil,
		Recovery = nil,
	}

	self._records[txId] = record
	table.insert(self._order, txId)
	self:_pruneIfNeeded()

	return txId, record
end

function TradeLedger:GetRecord(transactionId: string): any?
	return self._records[transactionId]
end

function TradeLedger:IsApplied(transactionId: string): boolean
	return self._appliedById[transactionId] == true
end

function TradeLedger:MarkApplied(transactionId: string): boolean
	local record = self._records[transactionId]
	if record == nil then
		return false
	end

	if self._appliedById[transactionId] == true then
		return true
	end

	local now = os.time()
	self._appliedById[transactionId] = true
	record.Status = "Applied"
	record.AppliedAt = now
	record.UpdatedAt = now
	return true
end

function TradeLedger:TrackEscrow(transactionId: string, escrowMetadata: any): boolean
	local record = self._records[transactionId]
	if record == nil then
		return false
	end
	local now = os.time()
	record.Escrow = escrowMetadata
	record.UpdatedAt = now
	return true
end

function TradeLedger:TrackRecovery(transactionId: string, recoveryMetadata: any): boolean
	local record = self._records[transactionId]
	if record == nil then
		return false
	end
	local now = os.time()
	record.Recovery = recoveryMetadata
	record.UpdatedAt = now
	return true
end

function TradeLedger:EnsureIdempotent(transactionId: string, applyFn: ((record: any) -> any)?): (boolean, any?)
	local record = self._records[transactionId]
	if record == nil then
		return false, "UnknownTransaction"
	end

	if self:IsApplied(transactionId) then
		return false, "AlreadyApplied"
	end

	if typeof(applyFn) == "function" then
		local ok, result = pcall(applyFn, record)
		if not ok then
			return false, result
		end
		self:MarkApplied(transactionId)
		return true, result
	end

	self:MarkApplied(transactionId)
	return true, nil
end

function TradeLedger:Reset()
	table.clear(self._records)
	table.clear(self._appliedById)
	table.clear(self._order)
end

function TradeLedger:Destroy()
	self:Reset()
	self._janitor:Cleanup()
end

return TradeLedger
