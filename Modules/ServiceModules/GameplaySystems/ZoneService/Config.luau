--!strict

export type Config = {
	TeleportActionName: string,
	DefaultTeleportId: string,
	MaxZoneIdLength: number,
	ZonePadding: number,
	ZoneCacheTtlSeconds: number,
	ZoneCacheReuseDistance: number,
	ZoneDebugEnabled: boolean,
	ZoneDebugCreatePhysicalBounds: boolean,
	ZoneDebugPollIntervalSeconds: number,
	ZoneDebugInZonePrintIntervalSeconds: number,
	TeleportArrivalHeightOffset: number,
	TeleportDestinationPadding: number,
	MapRootPath: {string},
	PlayerSpawnFolderName: string,
}

local Config: Config = {
	TeleportActionName = "Teleport",
	DefaultTeleportId = "Default",
	MaxZoneIdLength = 64,
	ZonePadding = 0,
	ZoneCacheTtlSeconds = 0.15,
	ZoneCacheReuseDistance = 4,
	ZoneDebugEnabled = false,
	ZoneDebugCreatePhysicalBounds = false,
	ZoneDebugPollIntervalSeconds = 0.4,
	ZoneDebugInZonePrintIntervalSeconds = 2,
	TeleportArrivalHeightOffset = 3,
	TeleportDestinationPadding = 3,
	MapRootPath = {"Game", "Map"},
	PlayerSpawnFolderName = "PlayerSpawn",
}

return table.freeze(Config)
