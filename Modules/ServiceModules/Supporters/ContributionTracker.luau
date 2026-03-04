--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Janitor = require(ReplicatedStorage.Packages.Janitor)

type ContributorRecord = {
	Damage: number,
	LastContributionAt: number,
}

local ContributionTracker = {}
ContributionTracker.__index = ContributionTracker

function ContributionTracker.new(config: {EligibilityWindowSeconds: number?, MinDamage: number?}?): any
	local eligibilityWindow = if config and typeof(config.EligibilityWindowSeconds) == "number" then config.EligibilityWindowSeconds else 30
	local minDamage = if config and typeof(config.MinDamage) == "number" then config.MinDamage else 0

	local self = setmetatable({
		_eligibilityWindowSeconds = math.max(0, eligibilityWindow),
		_minDamage = math.max(0, minDamage),
		_records = {} :: {[number]: ContributorRecord},
		_janitor = Janitor.new(),
	}, ContributionTracker)

	return self
end

function ContributionTracker:AddDamage(userId: number, amount: number, now: number?): boolean
	if typeof(userId) ~= "number" or userId <= 0 then
		return false
	end
	if typeof(amount) ~= "number" or amount <= 0 then
		return false
	end

	local timestamp = if typeof(now) == "number" then now else os.clock()
	local record = self._records[userId]
	if record == nil then
		record = {
			Damage = 0,
			LastContributionAt = timestamp,
		}
		self._records[userId] = record
	end

	record.Damage += amount
	record.LastContributionAt = timestamp
	return true
end

function ContributionTracker:GetEligibleContributors(now: number?): {{UserId: number, Damage: number, LastContributionAt: number}}
	local timestamp = if typeof(now) == "number" then now else os.clock()
	local out = {}
	for userId, record in pairs(self._records) do
		if record.Damage > self._minDamage then
			local age = timestamp - record.LastContributionAt
			if age <= self._eligibilityWindowSeconds then
				table.insert(out, {
					UserId = userId,
					Damage = record.Damage,
					LastContributionAt = record.LastContributionAt,
				})
			end
		end
	end

	table.sort(out, function(a, b)
		if a.Damage == b.Damage then
			return a.UserId < b.UserId
		end
		return a.Damage > b.Damage
	end)

	return out
end

function ContributionTracker:BuildPayoutShares(totalPool: number, now: number?): {
	Shares: {[number]: number},
	OrderedShares: {{UserId: number, Amount: number}},
	Eligible: {{UserId: number, Damage: number, LastContributionAt: number}},
	TotalDistributed: number,
}
	local eligible = self:GetEligibleContributors(now)
	local shares: {[number]: number} = {}
	local orderedShares = {}

	local pool = if typeof(totalPool) == "number" and totalPool > 0 then math.floor(totalPool) else 0
	if pool <= 0 or #eligible == 0 then
		return {
			Shares = shares,
			OrderedShares = orderedShares,
			Eligible = eligible,
			TotalDistributed = 0,
		}
	end

	local totalDamage = 0
	for _, entry in ipairs(eligible) do
		totalDamage += entry.Damage
	end

	if totalDamage <= 0 then
		return {
			Shares = shares,
			OrderedShares = orderedShares,
			Eligible = eligible,
			TotalDistributed = 0,
		}
	end

	local assigned = 0
	local remainderRanking = {}
	for _, entry in ipairs(eligible) do
		local rawShare = pool * (entry.Damage / totalDamage)
		local floorShare = math.floor(rawShare)
		shares[entry.UserId] = floorShare
		assigned += floorShare
		table.insert(remainderRanking, {
			UserId = entry.UserId,
			Fractional = rawShare - floorShare,
		})
	end

	local remaining = pool - assigned
	if remaining > 0 then
		table.sort(remainderRanking, function(a, b)
			if a.Fractional == b.Fractional then
				return a.UserId < b.UserId
			end
			return a.Fractional > b.Fractional
		end)

		local index = 1
		while remaining > 0 and #remainderRanking > 0 do
			local slot = remainderRanking[index]
			shares[slot.UserId] = (shares[slot.UserId] or 0) + 1
			remaining -= 1
			index += 1
			if index > #remainderRanking then
				index = 1
			end
		end
	end

	for _, entry in ipairs(eligible) do
		table.insert(orderedShares, {
			UserId = entry.UserId,
			Amount = shares[entry.UserId] or 0,
		})
	end

	return {
		Shares = shares,
		OrderedShares = orderedShares,
		Eligible = eligible,
		TotalDistributed = pool,
	}
end

function ContributionTracker:Reset()
	table.clear(self._records)
end

function ContributionTracker:Destroy()
	self:Reset()
	self._janitor:Cleanup()
end

return ContributionTracker
