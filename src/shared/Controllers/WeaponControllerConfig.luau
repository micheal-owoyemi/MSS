--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data_Mobs = require(ReplicatedStorage.Data.Data_Mobs)

export type Config = {
	HoverCursorIcon: string?,
	DoubleClickThresholdSeconds: number,
	HoverMaxScreenDistancePixels: number,
	HoverFallbackScanIntervalSeconds: number,
	HoverCacheGraceSeconds: number,
	WeaponVisualRootPath: {string},
	MobsClientRootPath: {string},
	ServerMobsRootPath: {string},
	WeaponAssetsRootPath: {string},
	TemplateByDefId: {[string]: string},
	PositionSmoothingK: number,
	SnapDistanceStuds: number,
	FollowDistanceBehind: number,
	FollowLateralSpacing: number,
	FollowRowSpacing: number,
	FollowVerticalOffset: number,
	AssignedRingRadiusBase: number,
	AssignedRingRadiusPerWeapon: number,
	AssignedRingHeight: number,
	AssignedRingSpinRateRadians: number,
	AssignedOwnerAngleSpreadRadians: number,
	BobAmplitudeStuds: number,
	BobFrequencyHz: number,
	FallbackPartSize: Vector3,
	FallbackPartColor: Color3,
}

local Config: Config = {
	HoverCursorIcon = if typeof(Data_Mobs.Settings.MobCursor) == "string" then Data_Mobs.Settings.MobCursor else nil,
	DoubleClickThresholdSeconds = 0.24,
	HoverMaxScreenDistancePixels = 36,
	HoverFallbackScanIntervalSeconds = 0.08,
	HoverCacheGraceSeconds = 0.12,
	WeaponVisualRootPath = {"Game", "WeaponsClient"},
	MobsClientRootPath = {"Game", "MobsClient"},
	ServerMobsRootPath = {"Game", "Mobs"},
	WeaponAssetsRootPath = {"Assets", "Weapons"},
	TemplateByDefId = {
		RustySword = "Wooden Sword",
		KnightBlade = "Iron Sword",
		RoyalClaymore = "Superior Iron Sword",
	},
	PositionSmoothingK = 18,
	SnapDistanceStuds = 30,
	FollowDistanceBehind = 4.5,
	FollowLateralSpacing = 2.2,
	FollowRowSpacing = 1.4,
	FollowVerticalOffset = 2.3,
	AssignedRingRadiusBase = 4.2,
	AssignedRingRadiusPerWeapon = 0.5,
	AssignedRingHeight = 3,
	AssignedRingSpinRateRadians = 0.35,
	AssignedOwnerAngleSpreadRadians = 0.85,
	BobAmplitudeStuds = 0.35,
	BobFrequencyHz = 1.4,
	FallbackPartSize = Vector3.new(1.8, 0.45, 3.6),
	FallbackPartColor = Color3.fromRGB(255, 215, 120),
}

return table.freeze(Config)
