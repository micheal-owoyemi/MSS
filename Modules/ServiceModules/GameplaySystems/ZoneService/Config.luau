--!strict

export type Config = {
	TeleportActionName: string,
	DefaultTeleportId: string,
	MaxZoneIdLength: number,
	ZonePadding: number,
	ZoneCacheTtlSeconds: number,
	ZoneCacheReuseDistance: number,
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
	TeleportArrivalHeightOffset = 3,
	TeleportDestinationPadding = 3,
	MapRootPath = {"Game", "Map"},
	PlayerSpawnFolderName = "PlayerSpawn",
}

return table.freeze(Config)
