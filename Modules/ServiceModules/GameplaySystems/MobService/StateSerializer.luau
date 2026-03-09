--!strict

export type ClientMobState = {
	MobId: string,
	MobDefId: string,
	ZoneId: string,
	SpawnIndex: number,
	PositionXZ: Vector2,
	GroundY: number,
	HP: number,
	MaxHP: number,
	Alive: boolean,
	Attackable: boolean,
	BrainState: string,
	TargetUserId: number?,
	Revision: number,
}

local StateSerializer = {}

function StateSerializer.SerializeAdd(state: ClientMobState): {[string]: any}
	return {
		id = state.MobId,
		d = state.MobDefId,
		z = state.ZoneId,
		sp = state.SpawnIndex,
		r = state.Revision,
		xz = state.PositionXZ,
		gy = state.GroundY,
		h = state.HP,
		mh = state.MaxHP,
		al = state.Alive,
		at = state.Attackable,
		st = state.BrainState,
		tu = state.TargetUserId,
	}
end

function StateSerializer.SerializeUpdate(state: ClientMobState): {[string]: any}
	return {
		id = state.MobId,
		d = state.MobDefId,
		z = state.ZoneId,
		sp = state.SpawnIndex,
		r = state.Revision,
		xz = state.PositionXZ,
		gy = state.GroundY,
		h = state.HP,
		mh = state.MaxHP,
		al = state.Alive,
		at = state.Attackable,
		st = state.BrainState,
		tu = state.TargetUserId,
	}
end

return StateSerializer
