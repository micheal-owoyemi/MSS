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

	local selected: Player? = nil
	local selectedUserId = math.huge
	for player in pairs(params.Attackers) do
		if params.IsValidTarget(player) then
			local userId = player.UserId
			if selected == nil or userId < selectedUserId then
				selected = player
				selectedUserId = userId
			end
		end
	end

	return selected
end

return TargetSelector
