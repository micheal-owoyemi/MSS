--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local ValidationUtil = require(ReplicatedStorage.Util.ValidationUtil)
local ZoneDefs = require(ReplicatedStorage.Configs.ZoneDefs)
local RemoteSchemas = require(ReplicatedStorage.Net.RemoteSchemas)

local Config = require(script.Config)

local ServiceModules = ServerStorage:WaitForChild("ServiceModules")
local SupportersFolder = ServiceModules:WaitForChild("Supporters")
local RateLimiter = require(SupportersFolder:WaitForChild("RateLimiter"))
local ZoneQueryHelper = require(SupportersFolder:WaitForChild("ZoneQueryHelper"))

type PlayerDataServiceLike = {
	GetProfile: (self: PlayerDataServiceLike, player: Player) -> ({[string]: any}?, string?),
}

type ZoneCacheRecord = {
	ZoneId: string?,
	Position: Vector3,
	ExpiresAt: number,
}

local ZoneService = Knit.CreateService({
	Name = "ZoneService",
	Client = {},
})

function ZoneService.Client:RequestTeleportToZone(player: Player, zoneId: string)
	return self.Server:_requestTeleportInternal(player, zoneId, true)
end

local function isValidZoneId(zoneId: any, maxLength: number): boolean
	if not ValidationUtil.isNonEmptyString(zoneId) then
		return false
	end
	return string.len(zoneId) <= maxLength
end

local function resolvePath(root: Instance, pathSegments: {string}): Instance?
	local current: Instance? = root
	for _, segment in ipairs(pathSegments) do
		if current == nil then
			return nil
		end
		current = current:FindFirstChild(segment)
	end
	return current
end

local function getCharacterRoot(character: Model): BasePart?
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	if character.PrimaryPart ~= nil then
		return character.PrimaryPart
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function extractPositionFromInstance(instance: Instance?): Vector3?
	if instance == nil then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance.Position
	end
	if instance:IsA("Attachment") then
		return instance.WorldPosition
	end
	if instance:IsA("Model") then
		local root = getCharacterRoot(instance)
		if root ~= nil then
			return root.Position
		end
	end
	return nil
end

local function horizontalDistanceSquared(first: Vector3, second: Vector3): number
	local dx = first.X - second.X
	local dz = first.Z - second.Z
	return (dx * dx) + (dz * dz)
end

function ZoneService:KnitInit()
	self._config = Config
	self._zoneDefs = ZoneDefs
	self._playerDataService = nil :: PlayerDataServiceLike?
	self._serviceJanitor = Janitor.new()
	self._teleportRateLimiter = RateLimiter.new()
	self._zoneCacheByUserId = {} :: {[number]: ZoneCacheRecord}
	self._zoneMissingPositionGraceSeconds = math.max(0, self._config.ZoneMissingPositionGraceSeconds)
	local reuseDistance = math.max(0, self._config.ZoneCacheReuseDistance)
	local fallbackDistance = math.max(reuseDistance, reuseDistance * 2)
	self._zoneCacheReuseDistanceSq = reuseDistance * reuseDistance
	self._zoneCacheFallbackDistanceSq = fallbackDistance * fallbackDistance
end

function ZoneService:KnitStart()
	local ok, playerDataService = pcall(function()
		return Knit.GetService("PlayerDataService")
	end)
	if ok then
		self._playerDataService = playerDataService :: PlayerDataServiceLike
	else
		warn(string.format("[ZoneService] PlayerDataService unavailable at start: %s", tostring(playerDataService)))
	end

	self._serviceJanitor:Add(Players.PlayerRemoving:Connect(function(player: Player)
		self._zoneCacheByUserId[player.UserId] = nil
		self._teleportRateLimiter:ClearPlayer(player)
	end), "Disconnect", "PlayerRemovingConnection")
end

function ZoneService:_zoneExists(zoneId: string): boolean
	if self._zoneDefs[zoneId] ~= nil then
		return true
	end

	return ZoneQueryHelper.GetZoneBounds(zoneId, true) ~= nil
end

function ZoneService:_getPlayerDataService(): (PlayerDataServiceLike?, string?)
	if self._playerDataService ~= nil then
		return self._playerDataService, nil
	end

	local ok, playerDataService = pcall(function()
		return Knit.GetService("PlayerDataService")
	end)
	if not ok then
		return nil, "PlayerDataServiceUnavailable"
	end

	self._playerDataService = playerDataService :: PlayerDataServiceLike
	return self._playerDataService, nil
end

function ZoneService:_getMapZoneFolder(zoneId: string): Instance?
	local mapRoot = resolvePath(Workspace, self._config.MapRootPath)
	if mapRoot == nil then
		return nil
	end

	return mapRoot:FindFirstChild(zoneId)
end

function ZoneService:_resolveSpawnPosition(zoneId: string): Vector3?
	local mapZoneFolder = self:_getMapZoneFolder(zoneId)
	if mapZoneFolder == nil then
		return nil
	end

	local playerSpawnFolder = mapZoneFolder:FindFirstChild(self._config.PlayerSpawnFolderName)
	if playerSpawnFolder == nil then
		return nil
	end

	local spawnLocation = playerSpawnFolder:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawnLocation ~= nil then
		return spawnLocation.Position + Vector3.new(0, self._config.TeleportArrivalHeightOffset, 0)
	end

	local part = playerSpawnFolder:FindFirstChildWhichIsA("BasePart", true)
	if part ~= nil then
		return part.Position + Vector3.new(0, self._config.TeleportArrivalHeightOffset, 0)
	end

	return nil
end

function ZoneService:_resolveTeleportDestination(zoneId: string, teleportId: string): (Vector3?, string?)
	local zoneDef = self._zoneDefs[zoneId]
	if typeof(zoneDef) == "table" and typeof(zoneDef.TeleportPoints) == "table" then
		local teleportPoints = zoneDef.TeleportPoints
		local pointEntry = teleportPoints[teleportId]
		if pointEntry == nil then
			pointEntry = teleportPoints[self._config.DefaultTeleportId]
		end

		if typeof(pointEntry) == "Vector3" then
			return pointEntry, nil
		end

		if typeof(pointEntry) == "string" and pointEntry ~= "" then
			local mapZoneFolder = self:_getMapZoneFolder(zoneId)
			if mapZoneFolder ~= nil then
				local namedTarget = mapZoneFolder:FindFirstChild(pointEntry, true)
				local namedPosition = extractPositionFromInstance(namedTarget)
				if namedPosition ~= nil then
					return namedPosition + Vector3.new(0, self._config.TeleportArrivalHeightOffset, 0), nil
				end
			end
		end
	end

	local spawnPosition = self:_resolveSpawnPosition(zoneId)
	if spawnPosition ~= nil then
		return spawnPosition, nil
	end

	local bounds = ZoneQueryHelper.GetZoneBounds(zoneId, true)
	if bounds ~= nil then
		local centerX = (bounds.Min.X + bounds.Max.X) * 0.5
		local centerZ = (bounds.Min.Z + bounds.Max.Z) * 0.5
		local y = bounds.Max.Y + self._config.TeleportArrivalHeightOffset
		return Vector3.new(centerX, y, centerZ), nil
	end

	return nil, "NoTeleportDestination"
end

function ZoneService:_resolvePlayerZone(player: Player): (string?, string?)
	local position = ZoneQueryHelper.GetPlayerPosition(player)

	local now = os.clock()
	local cacheRecord = self._zoneCacheByUserId[player.UserId]
	local missingPositionGrace = self._zoneMissingPositionGraceSeconds

	if position == nil then
		if cacheRecord ~= nil and cacheRecord.ZoneId ~= nil and now <= (cacheRecord.ExpiresAt + missingPositionGrace) then
			return cacheRecord.ZoneId, nil
		end
		return nil, "PlayerPositionUnavailable"
	end

	if cacheRecord ~= nil and now <= cacheRecord.ExpiresAt then
		if horizontalDistanceSquared(position, cacheRecord.Position) <= self._zoneCacheReuseDistanceSq then
			return cacheRecord.ZoneId, nil
		end
	end

	local zoneId = ZoneQueryHelper.GetContainingZoneId(position, self._config.ZonePadding)
	if zoneId == nil and cacheRecord ~= nil and cacheRecord.ZoneId ~= nil then
		if horizontalDistanceSquared(position, cacheRecord.Position) <= self._zoneCacheFallbackDistanceSq and now <= (cacheRecord.ExpiresAt + missingPositionGrace) then
			self._zoneCacheByUserId[player.UserId] = {
				ZoneId = cacheRecord.ZoneId,
				Position = position,
				ExpiresAt = now + self._config.ZoneCacheTtlSeconds,
			}
			return cacheRecord.ZoneId, nil
		end
	end

	self._zoneCacheByUserId[player.UserId] = {
		ZoneId = zoneId,
		Position = position,
		ExpiresAt = now + self._config.ZoneCacheTtlSeconds,
	}

	return zoneId, nil
end

function ZoneService:GetPlayerZone(player: Player): (string?, string?)
	if not ValidationUtil.isPlayer(player) then
		return nil, "InvalidPlayer"
	end

	return self:_resolvePlayerZone(player)
end

function ZoneService:IsPlayerInZone(player: Player, zoneId: string): (boolean, string?)
	if not ValidationUtil.isPlayer(player) then
		return false, "InvalidPlayer"
	end
	if not isValidZoneId(zoneId, self._config.MaxZoneIdLength) then
		return false, "InvalidZoneId"
	end
	if not self:_zoneExists(zoneId) then
		return false, "UnknownZone"
	end

	local resolvedZoneId, resolveReason = self:_resolvePlayerZone(player)
	if resolvedZoneId ~= nil then
		return resolvedZoneId == zoneId, nil
	end

	if resolveReason == "PlayerPositionUnavailable" then
		return false, resolveReason
	end

	return ZoneQueryHelper.IsPlayerInZone(player, zoneId, self._config.ZonePadding), nil
end

function ZoneService:IsZoneUnlocked(player: Player, zoneId: string): (boolean, string?)
	if not ValidationUtil.isPlayer(player) then
		return false, "InvalidPlayer"
	end
	if not isValidZoneId(zoneId, self._config.MaxZoneIdLength) then
		return false, "InvalidZoneId"
	end
	if not self:_zoneExists(zoneId) then
		return false, "UnknownZone"
	end

	local playerDataService, resolveReason = self:_getPlayerDataService()
	if playerDataService == nil then
		return false, resolveReason
	end

	local profileData, profileReason = playerDataService:GetProfile(player)
	if profileData == nil then
		return false, profileReason
	end

	local unlockedZones = profileData.UnlockedZones
	if typeof(unlockedZones) == "table" and unlockedZones[zoneId] == true then
		return true, nil
	end

	local zoneDef = self._zoneDefs[zoneId]
	if typeof(zoneDef) == "table" and typeof(zoneDef.UnlockRequirement) == "table" then
		local requirementAmount = tonumber(zoneDef.UnlockRequirement.Amount) or 0
		if requirementAmount <= 0 then
			return true, nil
		end
	end

	return false, "ZoneLocked"
end

function ZoneService:_resolveMobPosition(mob: any): Vector3?
	if typeof(mob) == "Instance" then
		local mobInstance = mob :: Instance
		if mobInstance:IsA("BasePart") then
			return mobInstance.Position
		end
		if mobInstance:IsA("Model") then
			local root = getCharacterRoot(mobInstance)
			if root ~= nil then
				return root.Position
			end
		end
	end

	if typeof(mob) == "table" then
		if typeof(mob.Position) == "Vector3" then
			return mob.Position
		end
		if typeof(mob.SpawnOrigin) == "Vector3" then
			return mob.SpawnOrigin
		end
	end

	return nil
end

function ZoneService:_resolveMobZoneId(mob: any): string?
	if typeof(mob) == "table" then
		local tableZoneId = mob.AllowedZoneId or mob.ZoneId or mob.ParentZone
		if isValidZoneId(tableZoneId, self._config.MaxZoneIdLength) then
			return tableZoneId
		end
	end

	if typeof(mob) == "Instance" then
		local mobInstance = mob :: Instance
		local attributeZoneId = mobInstance:GetAttribute("AllowedZoneId") or mobInstance:GetAttribute("ZoneId")
		if isValidZoneId(attributeZoneId, self._config.MaxZoneIdLength) then
			return attributeZoneId
		end

		local zoneIdValue = mobInstance:FindFirstChild("ZoneId")
		if zoneIdValue and zoneIdValue:IsA("StringValue") and isValidZoneId(zoneIdValue.Value, self._config.MaxZoneIdLength) then
			return zoneIdValue.Value
		end
	end

	local mobPosition = self:_resolveMobPosition(mob)
	if mobPosition ~= nil then
		return ZoneQueryHelper.GetContainingZoneId(mobPosition, self._config.ZonePadding)
	end

	return nil
end

function ZoneService:IsMobTargetValidForZone(mob: any, player: Player): (boolean, string?)
	if not ValidationUtil.isPlayer(player) then
		return false, "InvalidPlayer"
	end

	local mobZoneId = self:_resolveMobZoneId(mob)
	if mobZoneId == nil then
		return false, "MobZoneUnknown"
	end
	if not self:_zoneExists(mobZoneId) then
		return false, "UnknownZone"
	end

	local inZone, reason = self:IsPlayerInZone(player, mobZoneId)
	if not inZone then
		return false, reason or "ZoneMismatch"
	end

	return true, nil
end

function ZoneService:_teleportCharacter(player: Player, destination: Vector3): (boolean, string?)
	local character = player.Character
	if character == nil then
		return false, "CharacterUnavailable"
	end

	local root = getCharacterRoot(character)
	if root == nil then
		return false, "CharacterRootUnavailable"
	end

	character:PivotTo(CFrame.new(destination))
	return true, nil
end

function ZoneService:_requestTeleportInternal(player: Player, zoneId: string, enforceRateLimit: boolean): (boolean, string?)
	if not ValidationUtil.isPlayer(player) then
		return false, "InvalidPlayer"
	end

	if enforceRateLimit then
		if self._teleportRateLimiter:Consume(player, self._config.TeleportActionName) == false then
			return false, "RateLimited"
		end
	end

	local validation = RemoteSchemas.validate("Teleport", {
		ZoneId = zoneId,
		TeleportId = self._config.DefaultTeleportId,
	})
	if validation.ok ~= true then
		return false, validation.errorCode or "InvalidTeleportPayload"
	end

	local sanitizedPayload = validation.sanitizedPayload
	local validatedZoneId = sanitizedPayload.ZoneId
	local teleportId = sanitizedPayload.TeleportId

	if not self:_zoneExists(validatedZoneId) then
		return false, "UnknownZone"
	end

	local unlocked, unlockReason = self:IsZoneUnlocked(player, validatedZoneId)
	if not unlocked then
		return false, unlockReason or "ZoneLocked"
	end

	local destination, destinationReason = self:_resolveTeleportDestination(validatedZoneId, teleportId)
	if destination == nil then
		return false, destinationReason or "InvalidTeleportDestination"
	end

	if not ZoneQueryHelper.IsPointInZone(destination, validatedZoneId, self._config.TeleportDestinationPadding) then
		return false, "TeleportDestinationOutsideZone"
	end

	local teleported, teleportReason = self:_teleportCharacter(player, destination)
	if not teleported then
		return false, teleportReason or "TeleportFailed"
	end

	self._zoneCacheByUserId[player.UserId] = nil
	return true, nil
end

function ZoneService:RequestTeleportToZone(player: Player, zoneId: string): (boolean, string?)
	return self:_requestTeleportInternal(player, zoneId, false)
end

function ZoneService:Destroy()
	if self._teleportRateLimiter ~= nil then
		self._teleportRateLimiter:Destroy()
	end

	if self._serviceJanitor ~= nil then
		self._serviceJanitor:Cleanup()
	end

	table.clear(self._zoneCacheByUserId)
end

return ZoneService
