--!strict

local TargetSelector = {}

type SelectionParams = {
	Attackers: {[Player]: true},
	CurrentTarget: Player?,
	Now: number,
	AggroLockUntil: number,
	IsValidTarget: (player: Player) -> boolean,
}

function TargetSelector.selectTarget(params: SelectionParams): Player?
	local current = params.CurrentTarget
	if current ~= nil and params.Now <= params.AggroLockUntil and params.IsValidTarget(current) then
		return current
	end

	local candidates = {}
	for player in pairs(params.Attackers) do
		if params.IsValidTarget(player) then
			table.insert(candidates, player)
		end
	end

	if #candidates == 0 then
		return nil
	end

	table.sort(candidates, function(a, b)
		return a.UserId < b.UserId
	end)

	return candidates[1]
end

return TargetSelector
