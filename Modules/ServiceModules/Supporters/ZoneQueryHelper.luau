--!strict

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data_ZoneDefs = require(ReplicatedStorage.Data.Data_ZoneDefs)

local ZoneQueryHelper = {}

export type ZoneBounds = {
	Min: Vector3,
	Max: Vector3,
	Source: string?,
	MarkerCount: number?,
}

local REFRESH_INTERVAL_SECONDS = 1
local MIN_CORNER_MARKERS = 4
local ZONE_HEIGHT_ABOVE_BASEPLATE = 40

local NormalizedBoundsByZone: {[string]: ZoneBounds} = {}
local OrderedZoneIds: {string} = {}
local MarkerPointsByZone: {[string]: {Vector3}} = {}
local LastRefreshAt = 0
local WarnedMarkerIssues: {[string]: true} = {}
local warnMarkerIssue: (zoneId: string, message: string) -> ()

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

local function normalizeMinMax(minimum: Vector3, maximum: Vector3): (Vector3, Vector3)
	return Vector3.new(
		math.min(minimum.X, maximum.X),
		math.min(minimum.Y, maximum.Y),
		math.min(minimum.Z, maximum.Z)
	), Vector3.new(
		math.max(minimum.X, maximum.X),
		math.max(minimum.Y, maximum.Y),
		math.max(minimum.Z, maximum.Z)
	)
end

local function normalizeBoundsFromDef(zoneDef: any): ZoneBounds?
	if typeof(zoneDef) ~= "table" then
		return nil
	end

	local bounds = zoneDef.Bounds
	if typeof(bounds) ~= "table" or typeof(bounds.Min) ~= "Vector3" or typeof(bounds.Max) ~= "Vector3" then
		return nil
	end

	local minimum, maximum = normalizeMinMax(bounds.Min, bounds.Max)
	return {
		Min = minimum,
		Max = maximum,
		Source = "Defs",
		MarkerCount = nil,
	}
end

local function getZonesRoot(): Instance?
	local gameFolder = Workspace:FindFirstChild("Game")
	if gameFolder == nil then
		return nil
	end

	return gameFolder:FindFirstChild("Zones")
end

local function getZoneFolder(zoneId: string): Instance?
	local zonesRoot = getZonesRoot()
	if zonesRoot == nil then
		return nil
	end
	return zonesRoot:FindFirstChild(zoneId)
end

local function getMapZoneFolder(zoneId: string): Instance?
	local gameFolder = Workspace:FindFirstChild("Game")
	if gameFolder == nil then
		return nil
	end

	local mapFolder = gameFolder:FindFirstChild("Map")
	if mapFolder == nil then
		return nil
	end

	return mapFolder:FindFirstChild(zoneId)
end

warnMarkerIssue = function(zoneId: string, message: string)
	if WarnedMarkerIssues[zoneId] then
		return
	end
	WarnedMarkerIssues[zoneId] = true
	warn(string.format("[ZoneQueryHelper] Zone '%s' marker issue: %s", zoneId, message))
end

local function collectCornerMarkers(zoneId: string, zoneFolder: Instance): {BasePart}
	local markers: {BasePart} = {}
	local seen: {[BasePart]: true} = {}
	local foundUnanchored = false

	local function addMarker(candidate: Instance)
		if not candidate:IsA("BasePart") then
			return
		end
		local basePart = candidate :: BasePart
		if seen[basePart] then
			return
		end
		if basePart.Anchored ~= true then
			foundUnanchored = true
		end
		seen[basePart] = true
		table.insert(markers, basePart)
	end

	for _, child in ipairs(zoneFolder:GetChildren()) do
		addMarker(child)
	end

	if #markers < MIN_CORNER_MARKERS then
		for _, descendant in ipairs(zoneFolder:GetDescendants()) do
			addMarker(descendant)
		end
	end

	if foundUnanchored then
		warnMarkerIssue(zoneId, "one or more marker parts are unanchored and may move/fall; zone detection can become inaccurate")
	end

	return markers
end

local function markersToPoints(markers: {BasePart}): {Vector3}
	local points = table.create(#markers)
	for index, marker in ipairs(markers) do
		points[index] = marker.Position
	end
	return points
end

local function resolveVerticalRange(zoneId: string, markerMinY: number, markerMaxY: number): (number, number, string)
	local mapZoneFolder = getMapZoneFolder(zoneId)
	if mapZoneFolder ~= nil then
		local basePlateCandidate = mapZoneFolder:FindFirstChild("BasePlate")
		if basePlateCandidate == nil then
			basePlateCandidate = mapZoneFolder:FindFirstChild("BasePlate", true)
		end

		if basePlateCandidate ~= nil and basePlateCandidate:IsA("BasePart") then
			local basePart = basePlateCandidate :: BasePart
			local topY = basePart.CFrame:PointToWorldSpace(Vector3.new(0, basePart.Size.Y * 0.5, 0)).Y
			return topY, topY + ZONE_HEIGHT_ABOVE_BASEPLATE, "CornersExactBaseplate"
		end
	end

	warnMarkerIssue(zoneId, "zone baseplate not found; falling back to marker Y range")
	return markerMinY, markerMaxY, "CornersExactMarkers"
end

local function buildExactBoundsFromPoints(zoneId: string, points: {Vector3}): ZoneBounds?
	if #points < MIN_CORNER_MARKERS then
		return nil
	end

	local minX = math.huge
	local minY = math.huge
	local minZ = math.huge
	local maxX = -math.huge
	local maxY = -math.huge
	local maxZ = -math.huge

	for _, point in ipairs(points) do
		minX = math.min(minX, point.X)
		minY = math.min(minY, point.Y)
		minZ = math.min(minZ, point.Z)
		maxX = math.max(maxX, point.X)
		maxY = math.max(maxY, point.Y)
		maxZ = math.max(maxZ, point.Z)
	end

	local resolvedMinY, resolvedMaxY, source = resolveVerticalRange(zoneId, minY, maxY)
	local minimum, maximum = normalizeMinMax(
		Vector3.new(minX, resolvedMinY, minZ),
		Vector3.new(maxX, resolvedMaxY, maxZ)
	)

	return {
		Min = minimum,
		Max = maximum,
		Source = source,
		MarkerCount = #points,
	}
end

local function rebuildZoneBounds()
	local previousBounds = NormalizedBoundsByZone
	local previousMarkerPoints = MarkerPointsByZone

	local byZone: {[string]: ZoneBounds} = {}
	local ordered: {string} = {}
	local markerPoints: {[string]: {Vector3}} = {}

	for zoneId, zoneDef in pairs(Data_ZoneDefs) do
		local fallback = normalizeBoundsFromDef(zoneDef)
		local zoneFolder = getZoneFolder(zoneId)
		local bounds: ZoneBounds? = nil

		if zoneFolder ~= nil then
			local markers = collectCornerMarkers(zoneId, zoneFolder)
			if #markers >= MIN_CORNER_MARKERS then
				local points = markersToPoints(markers)
				markerPoints[zoneId] = points
				bounds = buildExactBoundsFromPoints(zoneId, points)
			else
				local previous = previousBounds[zoneId]
				local previousPoints = previousMarkerPoints[zoneId]
				if previous ~= nil and previous.Source == "CornersExact" and previousPoints ~= nil and #previousPoints >= MIN_CORNER_MARKERS then
					bounds = previous
					markerPoints[zoneId] = previousPoints
				else
					warnMarkerIssue(zoneId, string.format("expected at least %d corner parts, found %d. Zone bounds are disabled until fixed.", MIN_CORNER_MARKERS, #markers))
				end
			end
		else
			bounds = fallback
		end

		if bounds ~= nil then
			byZone[zoneId] = bounds
			table.insert(ordered, zoneId)
		end
	end

	local zonesRoot = getZonesRoot()
	if zonesRoot ~= nil then
		for _, zoneFolder in ipairs(zonesRoot:GetChildren()) do
			local zoneId = zoneFolder.Name
			if byZone[zoneId] == nil then
				local markers = collectCornerMarkers(zoneId, zoneFolder)
				if #markers >= MIN_CORNER_MARKERS then
					local points = markersToPoints(markers)
					markerPoints[zoneId] = points
					local inferredBounds = buildExactBoundsFromPoints(zoneId, points)
					if inferredBounds ~= nil then
						byZone[zoneId] = inferredBounds
						table.insert(ordered, zoneId)
					end
				else
					local previous = previousBounds[zoneId]
					local previousPoints = previousMarkerPoints[zoneId]
					if previous ~= nil and previous.Source == "CornersExact" and previousPoints ~= nil and #previousPoints >= MIN_CORNER_MARKERS then
						byZone[zoneId] = previous
						markerPoints[zoneId] = previousPoints
						table.insert(ordered, zoneId)
					else
						warnMarkerIssue(zoneId, string.format("expected at least %d corner parts, found %d. Zone bounds are disabled until fixed.", MIN_CORNER_MARKERS, #markers))
					end
				end
			end
		end
	end

	table.sort(ordered)
	NormalizedBoundsByZone = byZone
	OrderedZoneIds = ordered
	MarkerPointsByZone = markerPoints
end

local function refreshIfNeeded(force: boolean?)
	local now = os.clock()
	if force ~= true and (now - LastRefreshAt) < REFRESH_INTERVAL_SECONDS then
		return
	end

	LastRefreshAt = now
	rebuildZoneBounds()
end

function ZoneQueryHelper.RefreshZoneBounds(force: boolean?)
	refreshIfNeeded(force)
end

function ZoneQueryHelper.GetZoneDef(zoneId: string): any?
	return Data_ZoneDefs[zoneId]
end

function ZoneQueryHelper.GetZoneFolder(zoneId: string): Instance?
	return getZoneFolder(zoneId)
end

function ZoneQueryHelper.GetZoneBounds(zoneId: string, forceRefresh: boolean?): ZoneBounds?
	refreshIfNeeded(forceRefresh)
	return NormalizedBoundsByZone[zoneId]
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
	local bounds = ZoneQueryHelper.GetZoneBounds(zoneId, false)
	if bounds == nil then
		return false
	end

	return ZoneQueryHelper.IsPointInBounds(point, bounds, padding)
end

function ZoneQueryHelper.GetContainingZoneId(point: Vector3, padding: number?): string?
	refreshIfNeeded(false)

	for _, zoneId in ipairs(OrderedZoneIds) do
		local bounds = NormalizedBoundsByZone[zoneId]
		if bounds ~= nil and ZoneQueryHelper.IsPointInBounds(point, bounds, padding) then
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
	refreshIfNeeded(false)
	return NormalizedBoundsByZone
end

function ZoneQueryHelper.GetZoneMarkerPoints(zoneId: string, forceRefresh: boolean?): {Vector3}
	refreshIfNeeded(forceRefresh)
	local points = MarkerPointsByZone[zoneId]
	if points == nil then
		return {}
	end

	local copied = table.create(#points)
	for index, point in ipairs(points) do
		copied[index] = point
	end
	return copied
end

function ZoneQueryHelper.GetMarkerExactBounds(zoneId: string, forceRefresh: boolean?): ZoneBounds?
	local points = ZoneQueryHelper.GetZoneMarkerPoints(zoneId, forceRefresh)
	return buildExactBoundsFromPoints(zoneId, points)
end

function ZoneQueryHelper.CreateDebugBoundsVisuals(parent: Instance?, clearExisting: boolean?): Instance?
	refreshIfNeeded(true)

	local targetParent = if parent ~= nil then parent else Workspace
	local folderName = "ZoneDebugBounds"
	local debugFolder = targetParent:FindFirstChild(folderName)
	if debugFolder == nil then
		debugFolder = Instance.new("Folder")
		debugFolder.Name = folderName
		debugFolder.Parent = targetParent
	end

	if clearExisting ~= false then
		for _, child in ipairs(debugFolder:GetChildren()) do
			child:Destroy()
		end
	end

	for _, zoneId in ipairs(OrderedZoneIds) do
		local points = MarkerPointsByZone[zoneId]
		local exactBounds = if points ~= nil then buildExactBoundsFromPoints(zoneId, points) else nil
		if exactBounds ~= nil then
			local zoneFolder = Instance.new("Folder")
			zoneFolder.Name = zoneId
			zoneFolder.Parent = debugFolder

			local size = exactBounds.Max - exactBounds.Min
			local center = (exactBounds.Min + exactBounds.Max) * 0.5

			local boundsPart = Instance.new("Part")
			boundsPart.Name = "Bounds"
			boundsPart.Anchored = true
			boundsPart.CanCollide = false
			boundsPart.CanQuery = false
			boundsPart.CanTouch = false
			boundsPart.Material = Enum.Material.ForceField
			boundsPart.Color = Color3.fromRGB(255, 170, 0)
			boundsPart.Transparency = 0.8
			boundsPart.Size = Vector3.new(
				math.max(0.25, size.X),
				math.max(0.25, size.Y),
				math.max(0.25, size.Z)
			)
			boundsPart.CFrame = CFrame.new(center)
			boundsPart:SetAttribute("ZoneId", zoneId)
			boundsPart.Parent = zoneFolder

			for index, point in ipairs(points) do
				local markerPart = Instance.new("Part")
				markerPart.Name = string.format("Corner_%d", index)
				markerPart.Anchored = true
				markerPart.CanCollide = false
				markerPart.CanQuery = false
				markerPart.CanTouch = false
				markerPart.Shape = Enum.PartType.Ball
				markerPart.Material = Enum.Material.Neon
				markerPart.Color = Color3.fromRGB(0, 255, 149)
				markerPart.Transparency = 0.2
				markerPart.Size = Vector3.new(1, 1, 1)
				markerPart.CFrame = CFrame.new(point)
				markerPart.Parent = zoneFolder
			end
		end
	end

	return debugFolder
end

refreshIfNeeded(true)

return ZoneQueryHelper
