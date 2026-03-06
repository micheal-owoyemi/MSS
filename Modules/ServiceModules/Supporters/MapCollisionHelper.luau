--!strict

local Workspace = game:GetService("Workspace")

local MAP_ROOT_PATH = {"Game", "Map"}
local ENVIRONMENT_FOLDER_NAME = "Environment"

type ZoneQueryRecord = {
	MapZoneFolder: Instance?,
	OverlapParams: OverlapParams?,
	PassThroughParts: {[BasePart]: true},
}

local ZoneQueryById: {[string]: ZoneQueryRecord} = {}

local MapCollisionHelper = {}

local function resolvePath(root: Instance, segments: {string}): Instance?
	local cursor: Instance? = root
	for _, segment in ipairs(segments) do
		if cursor == nil then
			return nil
		end
		cursor = cursor:FindFirstChild(segment)
	end
	return cursor
end

local function resolveMapZoneFolder(zoneId: string): Instance?
	local mapRoot = resolvePath(Workspace, MAP_ROOT_PATH)
	if mapRoot == nil then
		return nil
	end
	return mapRoot:FindFirstChild(zoneId)
end

local function addDescendantParts(root: Instance, output: {[BasePart]: true})
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			output[descendant] = true
		end
	end
end

local function collectPassThroughParts(mapZoneFolder: Instance): {[BasePart]: true}
	local passThroughParts: {[BasePart]: true} = {}
	local environmentFolder = mapZoneFolder:FindFirstChild(ENVIRONMENT_FOLDER_NAME)
	if environmentFolder == nil then
		return passThroughParts
	end
	if environmentFolder:GetAttribute("MobCanPass") == true then
		addDescendantParts(environmentFolder, passThroughParts)
	end

	for _, descendant in ipairs(environmentFolder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if descendant:GetAttribute("MobCanPass") == true then
				passThroughParts[descendant] = true
			end
		elseif (descendant:IsA("Folder") or descendant:IsA("Model")) and descendant:GetAttribute("MobCanPass") == true then
			addDescendantParts(descendant, passThroughParts)
		end
	end

	return passThroughParts
end

local function buildZoneQuery(zoneId: string): ZoneQueryRecord
	local mapZoneFolder = resolveMapZoneFolder(zoneId)
	if mapZoneFolder == nil then
		return {
			MapZoneFolder = nil,
			OverlapParams = nil,
			PassThroughParts = {},
		}
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = {mapZoneFolder}
	overlapParams.MaxParts = 64

	return {
		MapZoneFolder = mapZoneFolder,
		OverlapParams = overlapParams,
		PassThroughParts = collectPassThroughParts(mapZoneFolder),
	}
end

local function getZoneQuery(zoneId: string): ZoneQueryRecord
	local cached = ZoneQueryById[zoneId]
	if cached ~= nil then
		local folder = cached.MapZoneFolder
		if folder == nil then
			return cached
		end
		if folder.Parent ~= nil then
			return cached
		end
	end

	local rebuilt = buildZoneQuery(zoneId)
	ZoneQueryById[zoneId] = rebuilt
	return rebuilt
end

function MapCollisionHelper.WarmZone(zoneId: string)
	if typeof(zoneId) ~= "string" or zoneId == "" then
		return
	end
	ZoneQueryById[zoneId] = buildZoneQuery(zoneId)
end

function MapCollisionHelper.WarmZones(zoneIds: {string})
	for _, zoneId in ipairs(zoneIds) do
		MapCollisionHelper.WarmZone(zoneId)
	end
end

function MapCollisionHelper.ResolveMapZoneFolder(zoneId: string): Instance?
	if typeof(zoneId) ~= "string" or zoneId == "" then
		return nil
	end
	local query = getZoneQuery(zoneId)
	return query.MapZoneFolder
end

function MapCollisionHelper.IsBaseplatePart(part: BasePart): boolean
	local loweredName = string.lower(part.Name)
	if string.find(loweredName, "baseplate", 1, true) ~= nil then
		return true
	end
	return part:GetAttribute("IsBaseplate") == true
end

function MapCollisionHelper.IsPositionObstructed(
	zoneId: string,
	position: Vector3,
	radius: number,
	height: number?
): boolean
	if typeof(zoneId) ~= "string" or zoneId == "" then
		return false
	end
	if typeof(position) ~= "Vector3" then
		return false
	end

	local query = getZoneQuery(zoneId)
	local overlapParams = query.OverlapParams
	if overlapParams == nil then
		return false
	end

	local resolvedRadius = math.max(0.5, tonumber(radius) or 0.5)
	local resolvedHeight = math.max(1, tonumber(height) or (resolvedRadius * 2))
	local size = Vector3.new(resolvedRadius * 2, resolvedHeight, resolvedRadius * 2)
	local parts = Workspace:GetPartBoundsInBox(CFrame.new(position), size, overlapParams)
	for _, part in ipairs(parts) do
		if part:IsA("BasePart") then
			if query.PassThroughParts[part] ~= true then
				if not MapCollisionHelper.IsBaseplatePart(part) then
					if part.CanCollide == true or part:GetAttribute("MobObstacle") == true then
						return true
					end
				end
			end
		end
	end

	return false
end

function MapCollisionHelper.IsPointObstructedXZ(
	zoneId: string,
	pointXZ: Vector2,
	y: number,
	radius: number,
	height: number?
): boolean
	if typeof(pointXZ) ~= "Vector2" then
		return false
	end
	local worldPosition = Vector3.new(pointXZ.X, y, pointXZ.Y)
	return MapCollisionHelper.IsPositionObstructed(zoneId, worldPosition, radius, height)
end

function MapCollisionHelper.ResetZone(zoneId: string)
	ZoneQueryById[zoneId] = nil
end

function MapCollisionHelper.ResetAll()
	table.clear(ZoneQueryById)
end

return MapCollisionHelper
