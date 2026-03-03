--!strict

local CoreTypes = require(script.Parent.CoreTypes)
local ProfileSchema = require(script.Parent.ProfileSchema)

local ProfileTypes = {}

type UserId = CoreTypes.UserId

export type ProfileResolveReason = "InvalidPlayer" | "ServiceUnavailable" | "ProfileUnavailable" | "ProfileLoadTimeout"

export type ProfileData = ProfileSchema.ProfileData
export type ReplicaPath = {string | number}

export type ReplicaLike = {
	SetValue: (self: ReplicaLike, path: ReplicaPath, value: any) -> (),
}

export type ProfileSessionLike = {
	Data: ProfileData,
	IsActive: (self: ProfileSessionLike) -> boolean,
	Save: ((self: ProfileSessionLike) -> ())?,
	EndSession: ((self: ProfileSessionLike) -> ())?,
	Key: string?,
}

export type PlayerProfileLike = {
	Profile: ProfileSessionLike?,
	Replica: ReplicaLike?,
	Release: ((self: PlayerProfileLike) -> ())?,
}

export type DataStoreServiceLike = {
	GetProfileAsync: (self: DataStoreServiceLike, player: Player, timeoutSeconds: number?) -> (PlayerProfileLike?, ProfileResolveReason?),
	MarkDirty: (self: DataStoreServiceLike, player: Player, contextTag: string?) -> boolean,
	MarkDirtyThrottled: ((self: DataStoreServiceLike, player: Player, contextTag: string?, minIntervalSeconds: number?) -> boolean)?,
}

export type ProfileContextRecord = {
	dataStore: DataStoreServiceLike,
	player: Player,
	profile: PlayerProfileLike,
	data: ProfileData,
	replica: ReplicaLike?,
	userId: UserId,
}

return ProfileTypes
