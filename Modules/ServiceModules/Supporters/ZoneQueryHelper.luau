--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data_ZoneDefs = require(ReplicatedStorage.Data.Data_ZoneDefs)

local ZoneQueryHelper = {}

type ZoneBounds = {
	Min: Vector3,
	Max: Vector3,
}

local NormalizedBoundsByZone: {[string]: ZoneBounds} = {}
for zoneId, zoneDef in pairs(Data_ZoneDefs) do
	local bounds = zoneDef.Bounds
	if typeof(bounds) == "table" and typeof(bounds.Min) == "Vector3" and typeof(bounds.Max) == "Vector3" then
		NormalizedBoundsByZone[zoneId] = {
			Min = Vector3.new(
				math.min(bounds.Min.X, bounds.Max.X),
				math.min(bounds.Min.Y, bounds.Max.Y),
				math.min(bounds.Min.Z, bounds.Max.Z)
			),
			Max = Vector3.new(
				math.max(bounds.Min.X, bounds.Max.X),
				math.max(bounds.Min.Y, bounds.Max.Y),
				math.max(bounds.Min.Z, bounds.Max.Z)
			),
		}
	end
end

local function getCharacterRootPosition(player: Player): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart.Position
	end

	local primaryPart = character.PrimaryPart
	if primaryPart ~= nil then
		return primaryPart.Position
	end

	return nil
end

function ZoneQueryHelper.GetZoneDef(zoneId: string): any?
	return Data_ZoneDefs[zoneId]
end

function ZoneQueryHelper.IsPointInBounds(point: Vector3, bounds: ZoneBounds, padding: number?): boolean
	local pad = if typeof(padding) == "number" and padding > 0 then padding else 0

	return point.X >= (bounds.Min.X - pad)
		and point.X <= (bounds.Max.X + pad)
		and point.Y >= (bounds.Min.Y - pad)
		and point.Y <= (bounds.Max.Y + pad)
		and point.Z >= (bounds.Min.Z - pad)
		and point.Z <= (bounds.Max.Z + pad)
end

function ZoneQueryHelper.IsPointInZone(point: Vector3, zoneId: string, padding: number?): boolean
	local bounds = NormalizedBoundsByZone[zoneId]
	if bounds == nil then
		return false
	end

	return ZoneQueryHelper.IsPointInBounds(point, bounds, padding)
end

function ZoneQueryHelper.GetContainingZoneId(point: Vector3, padding: number?): string?
	for zoneId, bounds in pairs(NormalizedBoundsByZone) do
		if ZoneQueryHelper.IsPointInBounds(point, bounds, padding) then
			return zoneId
		end
	end

	return nil
end

function ZoneQueryHelper.GetPlayerPosition(player: Player): Vector3?
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end
	return getCharacterRootPosition(player)
end

function ZoneQueryHelper.IsPlayerInZone(player: Player, zoneId: string, padding: number?): boolean
	local position = ZoneQueryHelper.GetPlayerPosition(player)
	if position == nil then
		return false
	end
	return ZoneQueryHelper.IsPointInZone(position, zoneId, padding)
end

function ZoneQueryHelper.IsPlayerWithinAllowedZone(player: Player, allowedZoneId: string, padding: number?): boolean
	return ZoneQueryHelper.IsPlayerInZone(player, allowedZoneId, padding)
end

function ZoneQueryHelper.ArePointsInSameZone(firstPoint: Vector3, secondPoint: Vector3, padding: number?): (boolean, string?, string?)
	local firstZone = ZoneQueryHelper.GetContainingZoneId(firstPoint, padding)
	local secondZone = ZoneQueryHelper.GetContainingZoneId(secondPoint, padding)
	if firstZone == nil or secondZone == nil then
		return false, firstZone, secondZone
	end

	return firstZone == secondZone, firstZone, secondZone
end

function ZoneQueryHelper.GetNormalizedBoundsByZone(): {[string]: ZoneBounds}
	return NormalizedBoundsByZone
end

return ZoneQueryHelper
