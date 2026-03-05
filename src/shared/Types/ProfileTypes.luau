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
	UpdateAsync: ((self: DataStoreServiceLike, player: Player, mutator: (ProfileData, ReplicaLike?) -> (), contextTag: string?) -> boolean)?,
	SetAsync: ((self: DataStoreServiceLike, player: Player, contextTag: string?) -> boolean)?,
}

export type ProfileContextRecord = {
	dataStore: DataStoreServiceLike,
	player: Player,
	profile: PlayerProfileLike,
	data: ProfileData,
	replica: ReplicaLike?,
	userId: UserId,
}

export type ProfileSnapshot = {
	Snapshot: {
		Revision: number,
		GeneratedAt: number,
		SchemaVersion: number,
	},
	Meta: {
		CreatedAt: number,
		LastOnline: number,
		TotalPlayTime: number,
		LastDailyReset: number,
	},
	Progression: {
		Level: number,
		XP: number,
	},
	Currencies: {[string]: number},
	Inventory: {
		Weapons: {[string]: any},
		Stackables: {[string]: number},
		Consumables: {[string]: number},
		Gifts: {[string]: any},
	},
	EquippedSlots: {[string]: string},
	UnlockedZones: {[string]: boolean},
	Boosts: {[string]: {Multiplier: number, ExpiresAt: number, Stacks: number}},
	QuestProgress: {[string]: {Progress: number, Claimed: boolean, UpdatedAt: number}},
	Stats: {
		TotalKills: number,
		TotalDeaths: number,
		TotalDamageDealt: number,
		TotalDamageTaken: number,
	},
	Flags: {
		HasCompletedTutorial: boolean,
		ClaimedStarterPack: boolean,
	},
}

export type PlayerDataServiceLike = {
	GetProfile: (self: PlayerDataServiceLike, player: Player) -> (ProfileData?, string?),
	RequestSnapshot: (self: PlayerDataServiceLike, player: Player) -> (ProfileSnapshot?, string?),
	ForceSave: (self: PlayerDataServiceLike, player: Player) -> (boolean, string?),
	MutateProfile: (self: PlayerDataServiceLike, player: Player, transformFn: (ProfileData, ReplicaLike?) -> any, contextTag: string?) -> (boolean, string?),
}

return ProfileTypes
