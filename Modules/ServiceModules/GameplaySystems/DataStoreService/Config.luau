--!strict

--[[
	DataStoreService Config

	Central tunables for profile load/save lifecycle.
	Time units are seconds unless stated otherwise.
]]

export type Config = {
	MaxLoadTimeSeconds: number,
	InitialRetryDelaySeconds: number,
	MaxRetryDelaySeconds: number,
	MaxWriteRetries: number,
	WriteRetryBaseDelaySeconds: number,
	WriteRetryMaxDelaySeconds: number,
	WriteDebounceDelaySeconds: number,
	WriteIdlePollIntervalSeconds: number,
	DataStoreBudgetPollIntervalSeconds: number,
	SerializationDepthLimit: number,
	AutoSaveIntervalMinSeconds: number,
	AutoSaveIntervalMaxSeconds: number,
	ShutdownSaveTimeoutSeconds: number,
	SessionLockTimeoutSeconds: number,
	DebugReplicaLogs: boolean,
}

local Config: Config = {
	MaxLoadTimeSeconds = 30,
	InitialRetryDelaySeconds = 0.75,
	MaxRetryDelaySeconds = 6,
	MaxWriteRetries = 6,
	WriteRetryBaseDelaySeconds = 1,
	WriteRetryMaxDelaySeconds = 8,
	WriteDebounceDelaySeconds = 5,
	WriteIdlePollIntervalSeconds = 0.1,
	DataStoreBudgetPollIntervalSeconds = 0.25,
	SerializationDepthLimit = 64,
	AutoSaveIntervalMinSeconds = 60,
	AutoSaveIntervalMaxSeconds = 120,
	ShutdownSaveTimeoutSeconds = 30,
	SessionLockTimeoutSeconds = 10,
	DebugReplicaLogs = false,
}

return table.freeze(Config)
