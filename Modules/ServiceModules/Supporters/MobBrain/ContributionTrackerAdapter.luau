--!strict

local ContributionTracker = require(script.Parent.Parent.ContributionTracker)

local ContributionTrackerAdapter = {}
ContributionTrackerAdapter.__index = ContributionTrackerAdapter

function ContributionTrackerAdapter.new(config: {[string]: any}?): any
	local self = setmetatable({
		_tracker = ContributionTracker.new(config),
	}, ContributionTrackerAdapter)
	return self
end

local function resolveUserId(playerOrUserId: Player | number): number?
	if typeof(playerOrUserId) == "Instance" then
		local player = playerOrUserId :: Player
		if player:IsA("Player") then
			return player.UserId
		end
		return nil
	end

	if typeof(playerOrUserId) == "number" then
		return playerOrUserId
	end
	return nil
end

function ContributionTrackerAdapter:AddDamage(playerOrUserId: Player | number, amount: number, now: number?): boolean
	local userId = resolveUserId(playerOrUserId)
	if userId == nil then
		return false
	end
	return self._tracker:AddDamage(userId, amount, now)
end

function ContributionTrackerAdapter:GetEligibleContributors(now: number?)
	return self._tracker:GetEligibleContributors(now)
end

function ContributionTrackerAdapter:BuildPayoutShares(totalPool: number, now: number?)
	return self._tracker:BuildPayoutShares(totalPool, now)
end

function ContributionTrackerAdapter:Reset()
	self._tracker:Reset()
end

function ContributionTrackerAdapter:Destroy()
	self._tracker:Destroy()
end

return ContributionTrackerAdapter
