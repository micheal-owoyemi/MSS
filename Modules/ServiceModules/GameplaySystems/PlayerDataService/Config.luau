--!strict

export type Config = {
	ProfileLoadTimeoutSeconds: number,
	PendingLoadPollIntervalSeconds: number,
	MutationLockTimeoutSeconds: number,
	MutationLockPollIntervalSeconds: number,
	SnapshotActionName: string,
	MutationContextPrefix: string,
	ForceSaveContextTag: string,
}

local Config: Config = {
	ProfileLoadTimeoutSeconds = 20,
	PendingLoadPollIntervalSeconds = 0.05,
	MutationLockTimeoutSeconds = 6,
	MutationLockPollIntervalSeconds = 0.03,
	SnapshotActionName = "RequestSnapshot",
	MutationContextPrefix = "PlayerDataServiceMutate",
	ForceSaveContextTag = "PlayerDataServiceForceSave",
}

return table.freeze(Config)
