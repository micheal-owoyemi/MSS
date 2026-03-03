local ClientRequestGate = {}

local function toNonNegativeNumber(value: any, fallback: number): number
	local numeric = tonumber(value)
	if type(numeric) ~= "number" or numeric ~= numeric or numeric < 0 then
		return fallback
	end

	return numeric
end

function ClientRequestGate.allow(
	cooldownsByUserId: { [number]: { [string]: number } },
	userId: number,
	actionName: string,
	cooldownsByAction: { [string]: number }?
): boolean
	if type(cooldownsByUserId) ~= "table" or type(userId) ~= "number" then
		return false
	end

	local cooldown = toNonNegativeNumber(
		type(cooldownsByAction) == "table" and cooldownsByAction[actionName] or nil,
		0
	)
	if cooldown <= 0 then
		return true
	end

	local perPlayer = cooldownsByUserId[userId]
	if type(perPlayer) ~= "table" then
		perPlayer = {}
		cooldownsByUserId[userId] = perPlayer
	end

	local now = os.clock()
	local nextAllowedAt = toNonNegativeNumber(perPlayer[actionName], 0)
	if now < nextAllowedAt then
		return false
	end

	perPlayer[actionName] = now + cooldown
	return true
end

return ClientRequestGate
