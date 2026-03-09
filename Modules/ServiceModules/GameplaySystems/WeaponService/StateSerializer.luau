--!strict

export type WeaponClientState = {
	Uid: string,
	DefId: string,
	Slot: string,
	TargetMobId: string?,
	QueueIndex: number,
	NextAttackAt: number,
	Cadence: number,
	Range: number,
}

local StateSerializer = {}

function StateSerializer.SerializeSnapshot(
	revision: number,
	playerTargetMobId: string?,
	orderedWeapons: {WeaponClientState},
	now: number
): {[string]: any}
	local weaponsOut = table.create(#orderedWeapons)
	for index, weapon in ipairs(orderedWeapons) do
		weaponsOut[index] = {
			u = weapon.Uid,
			d = weapon.DefId,
			s = weapon.Slot,
			m = weapon.TargetMobId,
			q = weapon.QueueIndex,
			na = weapon.NextAttackAt,
			cd = weapon.Cadence,
			rg = weapon.Range,
		}
	end

	return {
		r = revision,
		t = now,
		tm = playerTargetMobId,
		w = weaponsOut,
	}
end

return StateSerializer
