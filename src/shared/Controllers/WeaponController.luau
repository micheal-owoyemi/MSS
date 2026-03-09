--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)

local Config = require(script.Parent.WeaponControllerConfig)
local WeaponVisualLayout = require(script.Parent.WeaponVisualLayout)
local WeaponVisualResolver = require(script.Parent.WeaponVisualResolver)

type WeaponPacketEntry = {
	u: string,
	d: string,
	s: string,
	m: string?,
	q: number?,
	na: number?,
	cd: number?,
	rg: number?,
}

type WeaponPacket = {
	r: number?,
	t: number?,
	tm: string?,
	w: {WeaponPacketEntry}?,
}

type WeaponState = {
	Uid: string,
	DefId: string,
	Slot: string,
	TargetMobId: string?,
	QueueIndex: number,
	NextAttackAt: number,
	Cadence: number,
	Range: number,
}

type WeaponVisualRecord = {
	Uid: string,
	DefId: string,
	Instance: Instance,
	RootPart: BasePart?,
	IsModel: boolean,
	OrientationOffset: CFrame,
	CurrentPosition: Vector3,
	TargetPosition: Vector3,
	CurrentFacing: Vector3,
	TargetFacing: Vector3,
}

type MobPresentationRecord = {
	Instance: Instance,
	Highlight: Highlight?,
	Billboard: BillboardGui?,
	HighlightEnabled: boolean,
	UiEnabled: boolean,
}

local WeaponController = Knit.CreateController({
	Name = "WeaponController",
})

local MOB_POSITION_GRACE_SECONDS = 0.45

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

local function ensurePath(root: Instance, segments: {string}): Instance
	local cursor: Instance = root
	for _, segment in ipairs(segments) do
		local nextNode = cursor:FindFirstChild(segment)
		if nextNode == nil then
			nextNode = Instance.new("Folder") :: Instance;
			(nextNode :: Instance).Name = segment;
			(nextNode :: Instance).Parent = cursor
		end
		cursor = nextNode :: Instance
	end
	return cursor
end

local function resolveCharacterRootCFrame(player: Player): CFrame?
	local character = player.Character
	if character == nil then
		return nil
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart.CFrame
	end

	if character.PrimaryPart ~= nil then
		return character.PrimaryPart.CFrame
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant.CFrame
		end
	end

	return nil
end

local function hashString(input: string): number
	local hash = 2166136261
	for i = 1, #input do
		hash = bit32.bxor(hash, string.byte(input, i))
		hash = (hash * 16777619) % 2^32
	end
	return hash
end

local function safeUnitHorizontal(vector: Vector3, fallback: Vector3): Vector3
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude <= 1e-4 then
		return fallback
	end
	return horizontal.Unit
end

local function sortWeaponByQueue(a: WeaponState, b: WeaponState): boolean
	if a.QueueIndex == b.QueueIndex then
		return a.Uid < b.Uid
	end
	return a.QueueIndex < b.QueueIndex
end

local function resolveInstanceWorldPosition(target: Instance): Vector3?
	if target:IsA("BasePart") then
		return target.Position
	end

	if target:IsA("Model") then
		local rootPart = target.PrimaryPart
		if rootPart == nil then
			local humanoidRoot = target:FindFirstChild("HumanoidRootPart")
			if humanoidRoot and humanoidRoot:IsA("BasePart") then
				rootPart = humanoidRoot
			end
		end
		if rootPart == nil then
			rootPart = target:FindFirstChildWhichIsA("BasePart", true)
		end
		if rootPart ~= nil then
			return rootPart.Position
		end
	end

	return nil
end

local function resolveInstanceHoverInfo(target: Instance): (Vector3?, number)
	if target:IsA("BasePart") then
		local size = target.Size
		local radius = math.max(size.X, size.Y, size.Z) * 0.5
		return target.Position, radius
	end

	if target:IsA("Model") then
		local cf, size = target:GetBoundingBox()
		local radius = math.max(size.X, size.Y, size.Z) * 0.5
		return cf.Position, radius
	end

	return resolveInstanceWorldPosition(target), 0
end

function WeaponController:KnitInit()
	self._janitor = Janitor.new()
	self._weaponService = nil
	self._player = Players.LocalPlayer
	self._mouse = nil :: Mouse?
	self._weaponVisualRoot = nil :: Instance?
	self._mobsClientRoot = nil :: Instance?
	self._serverMobsRoot = nil :: Instance?
	self._weaponStateByUid = {} :: {[string]: WeaponState}
	self._visualByUid = {} :: {[string]: WeaponVisualRecord}
	self._uidHashByUid = {} :: {[string]: number}
	self._layoutDirty = true
	self._cachedUnassignedWeapons = {} :: {WeaponState}
	self._cachedAssignedWeaponsByMobId = {} :: {[string]: {WeaponState}}
	self._ownerOffsetRadians = ((self._player.UserId % 360) / 360) * math.pi * 2
	self._hoverMobId = nil :: string?
	self._lastClickMobId = nil :: string?
	self._lastClickAt = 0
	self._lastRevision = 0
	self._lastHoverFallbackScanAt = 0
	self._lastHoverResolvedAt = 0
	self._mobPositionById = {} :: {[string]: Vector3}
	self._mobPositionExpiresAtById = {} :: {[string]: number}
	self._mobInstanceById = {} :: {[string]: Instance}
	self._mobPresentationById = {} :: {[string]: MobPresentationRecord}
	self._mobPresentationActiveScratch = {} :: {[string]: true}
	self._desiredPositionByUid = {} :: {[string]: Vector3}
	self._desiredFacingByUid = {} :: {[string]: Vector3}
end

function WeaponController:KnitStart()
	self._weaponService = Knit.GetService("WeaponService")
	self._mouse = self._player:GetMouse()
	self._weaponVisualRoot = ensurePath(Workspace, Config.WeaponVisualRootPath)
	self._mobsClientRoot = resolvePath(Workspace, Config.MobsClientRootPath)
	self._serverMobsRoot = resolvePath(Workspace, Config.ServerMobsRootPath)

	self._janitor:Add(self._weaponService.WeaponStateDelta:Connect(function(packet: WeaponPacket)
		self:_handleWeaponPacket(packet)
	end), "Disconnect", "WeaponStateDeltaConnection")

	self._janitor:Add(UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		self:_onInputBegan(input, gameProcessed)
	end), "Disconnect", "InputBeganConnection")

	self._janitor:Add(RunService.RenderStepped:Connect(function(dt: number)
		self:_stepRender(dt)
	end), "Disconnect", "RenderSteppedConnection")
end

function WeaponController:_refreshSceneRoots()
	if self._mobsClientRoot == nil or self._mobsClientRoot.Parent == nil then
		self._mobsClientRoot = resolvePath(Workspace, Config.MobsClientRootPath)
	end
	if self._serverMobsRoot == nil or self._serverMobsRoot.Parent == nil then
		self._serverMobsRoot = resolvePath(Workspace, Config.ServerMobsRootPath)
	end
end

function WeaponController:_resolveMobIdFromInstance(target: Instance?): string?
	if target == nil then
		return nil
	end

	local cursor: Instance? = target
	local mobsClientRoot = self._mobsClientRoot
	local serverMobsRoot = self._serverMobsRoot

	while cursor ~= nil do
		local attributeMobId = cursor:GetAttribute("MobId")
		if typeof(attributeMobId) == "string" and attributeMobId ~= "" then
			return attributeMobId
		end

		if cursor:IsA("Model") then
			if mobsClientRoot ~= nil and cursor.Parent == mobsClientRoot then
				return cursor.Name
			end
			if serverMobsRoot ~= nil and cursor.Parent == serverMobsRoot then
				return cursor.Name
			end
		end

		cursor = cursor.Parent
	end

	return nil
end

function WeaponController:_resolveHoverMobId(now: number): string?
	local mouse = self._mouse
	if mouse == nil then
		return nil
	end

	local target = mouse.Target
	if target ~= nil then
		local mobId = self:_resolveMobIdFromInstance(target)
		if mobId ~= nil then
			self._lastHoverResolvedAt = now
			return mobId
		end
	end

	if (now - self._lastHoverFallbackScanAt) < math.max(0, Config.HoverFallbackScanIntervalSeconds) then
		if self._hoverMobId ~= nil and (now - self._lastHoverResolvedAt) <= math.max(0, Config.HoverCacheGraceSeconds) then
			return self._hoverMobId
		end
		return nil
	end
	self._lastHoverFallbackScanAt = now

	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end

	local threshold = math.max(0, Config.HoverMaxScreenDistancePixels)
	if threshold <= 0 then
		return nil
	end

	local mousePosition = UserInputService:GetMouseLocation()
	local mouseX = mousePosition.X
	local mouseY = mousePosition.Y
	local bestDistanceSquared = threshold * threshold
	local bestMobId: string? = nil

	local function considerRoot(root: Instance?)
		if root == nil then
			return
		end

		for _, child in ipairs(root:GetChildren()) do
			local mobId = self:_resolveMobIdFromInstance(child)
			if mobId ~= nil then
				local worldPosition, worldRadius = resolveInstanceHoverInfo(child)
				if worldPosition ~= nil then
					local screenPoint, onScreen = camera:WorldToViewportPoint(worldPosition)
					if onScreen and screenPoint.Z > 0 then
						local dx = screenPoint.X - mouseX
						local dy = screenPoint.Y - mouseY
						local distanceSquared = (dx * dx) + (dy * dy)
						local effectiveThreshold = threshold
						if worldRadius > 0 then
							local edgePoint = worldPosition + (camera.CFrame.RightVector * worldRadius)
							local edgeScreenPoint, edgeOnScreen = camera:WorldToViewportPoint(edgePoint)
							if edgeOnScreen then
								effectiveThreshold = math.max(effectiveThreshold, math.abs(edgeScreenPoint.X - screenPoint.X))
							end
						end
						local effectiveThresholdSq = effectiveThreshold * effectiveThreshold
						if distanceSquared <= effectiveThresholdSq and distanceSquared <= bestDistanceSquared then
							bestDistanceSquared = distanceSquared
							bestMobId = mobId
						end
					end
				end
			end
		end
	end

	considerRoot(self._mobsClientRoot)
	if bestMobId == nil then
		considerRoot(self._serverMobsRoot)
	end

	if bestMobId ~= nil then
		self._lastHoverResolvedAt = now
	end
	return bestMobId
end

function WeaponController:_onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	local now = os.clock()
	local hoverMobId = self._hoverMobId
	if hoverMobId == nil then
		self:_refreshSceneRoots()
		hoverMobId = self:_resolveHoverMobId(now)
	end
	if hoverMobId == nil then
		return
	end

	local mode = "Single"
	if self._lastClickMobId == hoverMobId and (now - self._lastClickAt) <= Config.DoubleClickThresholdSeconds then
		mode = "Double"
	end

	self._lastClickMobId = hoverMobId
	self._lastClickAt = now

	local weaponService = self._weaponService
	if weaponService == nil then
		return
	end

	task.spawn(function()
		local ok, rawPrimary = pcall(function()
			return weaponService:RequestAttackMob(hoverMobId, mode)
		end)
		if not ok then
			warn(string.format("[WeaponController] RequestAttackMob failed: %s", tostring(rawPrimary)))
			return
		end
	end)
end

function WeaponController:_destroyVisual(uid: string)
	local record = self._visualByUid[uid]
	if record == nil then
		return
	end

	record.Instance:Destroy()
	self._visualByUid[uid] = nil
end

function WeaponController:_ensureVisual(uid: string, defId: string): WeaponVisualRecord?
	local existing = self._visualByUid[uid]
	if existing ~= nil then
		if existing.DefId == defId and existing.Instance.Parent ~= nil then
			return existing
		end
		self:_destroyVisual(uid)
	end

	local visualRoot = self._weaponVisualRoot
	if visualRoot == nil then
		return nil
	end

	local created = WeaponVisualResolver.CreateVisual(uid, defId, visualRoot, Config)
	local record: WeaponVisualRecord = {
		Uid = uid,
		DefId = defId,
		Instance = created.Instance,
		RootPart = created.RootPart,
		IsModel = created.IsModel,
		OrientationOffset = created.OrientationOffset,
		CurrentPosition = created.RootPart.Position,
		TargetPosition = created.RootPart.Position,
		CurrentFacing = Vector3.new(0, 0, -1),
		TargetFacing = Vector3.new(0, 0, -1),
	}

	self._visualByUid[uid] = record
	return record
end

function WeaponController:_handleWeaponPacket(packet: WeaponPacket)
	if typeof(packet) ~= "table" then
		return
	end

	local revision = tonumber(packet.r) or 0
	if revision < self._lastRevision then
		return
	end
	self._lastRevision = revision

	local nextStateByUid = {} :: {[string]: WeaponState}
	local entries = packet.w
	if typeof(entries) == "table" then
		for _, rawEntry in ipairs(entries) do
			if typeof(rawEntry) == "table" then
				local uid = rawEntry.u
				local defId = rawEntry.d
				local slot = rawEntry.s
				if typeof(uid) == "string" and uid ~= "" and typeof(defId) == "string" and defId ~= "" and typeof(slot) == "string" then
					nextStateByUid[uid] = {
						Uid = uid,
						DefId = defId,
						Slot = slot,
						TargetMobId = if typeof(rawEntry.m) == "string" and rawEntry.m ~= "" then rawEntry.m else nil,
						QueueIndex = math.max(1, math.floor(tonumber(rawEntry.q) or 1)),
						NextAttackAt = tonumber(rawEntry.na) or 0,
						Cadence = math.max(0, tonumber(rawEntry.cd) or 0),
						Range = math.max(0, tonumber(rawEntry.rg) or 0),
					}
				end
			end
		end
	end

	for uid in pairs(self._weaponStateByUid) do
		if nextStateByUid[uid] == nil then
			self:_destroyVisual(uid)
			self._uidHashByUid[uid] = nil
		end
	end

	for uid in pairs(nextStateByUid) do
		if self._uidHashByUid[uid] == nil then
			self._uidHashByUid[uid] = hashString(uid)
		end
	end

	self._weaponStateByUid = nextStateByUid
	self._layoutDirty = true
end

function WeaponController:_getMobPosition(mobId: string): Vector3?
	local now = os.clock()

	local cachedInstance = self._mobInstanceById[mobId]
	if cachedInstance ~= nil then
		if cachedInstance.Parent ~= nil then
			local cachedPosition = resolveInstanceWorldPosition(cachedInstance)
			if cachedPosition ~= nil then
				self._mobPositionById[mobId] = cachedPosition
				self._mobPositionExpiresAtById[mobId] = now + MOB_POSITION_GRACE_SECONDS
				return cachedPosition
			end
		else
			self._mobInstanceById[mobId] = nil
		end
	end

	local mobsClientRoot = self._mobsClientRoot
	if mobsClientRoot ~= nil then
		local mobVisual = mobsClientRoot:FindFirstChild(mobId)
		if mobVisual ~= nil then
			local position = resolveInstanceWorldPosition(mobVisual)
			if position ~= nil then
				self._mobInstanceById[mobId] = mobVisual
				self._mobPositionById[mobId] = position
				self._mobPositionExpiresAtById[mobId] = now + MOB_POSITION_GRACE_SECONDS
				return position
			end
		end
	end

	local serverMobsRoot = self._serverMobsRoot
	if serverMobsRoot ~= nil then
		local proxy = serverMobsRoot:FindFirstChild(mobId)
		if proxy ~= nil then
			local position = resolveInstanceWorldPosition(proxy)
			if position ~= nil then
				self._mobInstanceById[mobId] = proxy
				self._mobPositionById[mobId] = position
				self._mobPositionExpiresAtById[mobId] = now + MOB_POSITION_GRACE_SECONDS
				return position
			end
		end
	end

	local cached = self._mobPositionById[mobId]
	local expiresAt = self._mobPositionExpiresAtById[mobId]
	if cached ~= nil and expiresAt ~= nil and now <= expiresAt then
		return cached
	end
	self._mobPositionById[mobId] = nil
	self._mobPositionExpiresAtById[mobId] = nil

	return nil
end

function WeaponController:_rebuildLayoutCacheIfDirty()
	if self._layoutDirty ~= true then
		return
	end

	local assignedByMobId = {} :: {[string]: {WeaponState}}
	local unassigned = {} :: {WeaponState}

	for _, state in pairs(self._weaponStateByUid) do
		if state.TargetMobId ~= nil then
			local bucket = assignedByMobId[state.TargetMobId]
			if bucket == nil then
				bucket = {}
				assignedByMobId[state.TargetMobId] = bucket
			end
			table.insert(bucket, state)
		else
			table.insert(unassigned, state)
		end
	end

	table.sort(unassigned, sortWeaponByQueue)
	for _, bucket in pairs(assignedByMobId) do
		table.sort(bucket, sortWeaponByQueue)
	end

	for mobId in pairs(self._mobPositionById) do
		if assignedByMobId[mobId] == nil then
			self._mobPositionById[mobId] = nil
			self._mobPositionExpiresAtById[mobId] = nil
			self._mobInstanceById[mobId] = nil
		end
	end
	for mobId in pairs(self._mobInstanceById) do
		if assignedByMobId[mobId] == nil then
			self._mobInstanceById[mobId] = nil
		end
	end

	self._cachedUnassignedWeapons = unassigned
	self._cachedAssignedWeaponsByMobId = assignedByMobId
	self._layoutDirty = false
end

function WeaponController:_resolvePreferredBillboard(instance: Instance): BillboardGui?
	local preferred: BillboardGui? = nil
	local fallback: BillboardGui? = nil
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BillboardGui") then
			local billboard = descendant :: BillboardGui
			local lowerName = string.lower(billboard.Name)
			if preferred == nil and (lowerName == "mobpropertiescontainer" or string.find(lowerName, "mobproperties", 1, true) ~= nil) then
				preferred = billboard
			end
			if fallback == nil then
				fallback = billboard
			end
		end
	end
	if preferred ~= nil then
		return preferred
	end
	return fallback
end

function WeaponController:_resolveMobPresentationRecord(mobId: string): MobPresentationRecord?
	local cached = self._mobPresentationById[mobId]
	local mobsClientRoot = self._mobsClientRoot
	local expectedInstance = if mobsClientRoot ~= nil then mobsClientRoot:FindFirstChild(mobId) else nil

	if cached ~= nil then
		if cached.Instance.Parent ~= nil and (expectedInstance == nil or expectedInstance == cached.Instance) then
			return cached
		end
		self._mobPresentationById[mobId] = nil
	end

	if expectedInstance == nil then
		return nil
	end

	local highlight = expectedInstance:FindFirstChildWhichIsA("Highlight", true)
	local billboard = self:_resolvePreferredBillboard(expectedInstance)

	local record: MobPresentationRecord = {
		Instance = expectedInstance,
		Highlight = highlight,
		Billboard = billboard,
		HighlightEnabled = false,
		UiEnabled = false,
	}

	if highlight ~= nil and highlight.Enabled ~= false then
		highlight.Enabled = false
	end
	if billboard ~= nil and billboard.Enabled ~= false then
		billboard.Enabled = false
	end

	self._mobPresentationById[mobId] = record
	return record
end

function WeaponController:_applyMobPresentation(assignedByMobId: {[string]: {WeaponState}})
	local activeMobIds = self._mobPresentationActiveScratch
	table.clear(activeMobIds)

	for mobId in pairs(assignedByMobId) do
		activeMobIds[mobId] = true
	end

	local hoverMobId = self._hoverMobId
	if hoverMobId ~= nil then
		activeMobIds[hoverMobId] = true
	end

	for mobId in pairs(activeMobIds) do
		local record = self:_resolveMobPresentationRecord(mobId)
		if record ~= nil then
			local shouldHighlight = hoverMobId == mobId
			local shouldShowUi = assignedByMobId[mobId] ~= nil

			local highlight = record.Highlight
			if highlight ~= nil and record.HighlightEnabled ~= shouldHighlight then
				highlight.Enabled = shouldHighlight
				record.HighlightEnabled = shouldHighlight
			end

			local billboard = record.Billboard
			if billboard ~= nil and record.UiEnabled ~= shouldShowUi then
				billboard.Enabled = shouldShowUi
				record.UiEnabled = shouldShowUi
			end
		end
	end

	for mobId, record in pairs(self._mobPresentationById) do
		if activeMobIds[mobId] ~= true then
			local highlight = record.Highlight
			if highlight ~= nil and record.HighlightEnabled ~= false then
				highlight.Enabled = false
				record.HighlightEnabled = false
			end

			local billboard = record.Billboard
			if billboard ~= nil and record.UiEnabled ~= false then
				billboard.Enabled = false
				record.UiEnabled = false
			end

			if record.Instance.Parent == nil then
				self._mobPresentationById[mobId] = nil
			end
		end
	end
end

function WeaponController:_applyVisualPose(record: WeaponVisualRecord)
	local facing = safeUnitHorizontal(record.CurrentFacing, Vector3.new(0, 0, -1))
	local lookTarget = record.CurrentPosition + facing
	local pose = CFrame.lookAt(record.CurrentPosition, lookTarget)

	if record.IsModel and record.Instance:IsA("Model") then
		record.Instance:PivotTo(pose * record.OrientationOffset)
	elseif record.RootPart ~= nil then
		record.RootPart.CFrame = pose
	end
end

function WeaponController:_stepRender(dt: number)
	self:_refreshSceneRoots()

	local now = os.clock()
	self._hoverMobId = self:_resolveHoverMobId(now)
	self:_rebuildLayoutCacheIfDirty()
	local assignedByMobId = self._cachedAssignedWeaponsByMobId
	self:_applyMobPresentation(assignedByMobId)

	local rootCFrame = resolveCharacterRootCFrame(self._player)
	if rootCFrame == nil then
		return
	end

	local unassigned = self._cachedUnassignedWeapons
	local desiredPositionByUid = self._desiredPositionByUid
	local desiredFacingByUid = self._desiredFacingByUid
	table.clear(desiredPositionByUid)
	table.clear(desiredFacingByUid)
	local alpha = math.clamp(1 - math.exp(-Config.PositionSmoothingK * math.max(dt, 0)), 0, 1)

	for index, weapon in ipairs(unassigned) do
		local uidHash = self._uidHashByUid[weapon.Uid]
		if uidHash == nil then
			uidHash = hashString(weapon.Uid)
			self._uidHashByUid[weapon.Uid] = uidHash
		end
		local position, facing = WeaponVisualLayout.ComputeFollowPose(
			rootCFrame,
			index,
			#unassigned,
			Config,
			now,
			uidHash
		)
		desiredPositionByUid[weapon.Uid] = position
		desiredFacingByUid[weapon.Uid] = facing
	end

	for mobId, bucket in pairs(assignedByMobId) do
		local mobPosition = self:_getMobPosition(mobId)
		if mobPosition ~= nil then
			for index, weapon in ipairs(bucket) do
				local uidHash = self._uidHashByUid[weapon.Uid]
				if uidHash == nil then
					uidHash = hashString(weapon.Uid)
					self._uidHashByUid[weapon.Uid] = uidHash
				end
				local position, facing = WeaponVisualLayout.ComputeAssignedPose(
					mobPosition,
					index,
					#bucket,
					Config,
					now,
					self._ownerOffsetRadians,
					uidHash
				)
				desiredPositionByUid[weapon.Uid] = position
				desiredFacingByUid[weapon.Uid] = facing
			end
		end
	end

	for uid, state in pairs(self._weaponStateByUid) do
		local record = self:_ensureVisual(uid, state.DefId)
		if record ~= nil then
			local desiredPosition = desiredPositionByUid[uid]
			local desiredFacing = desiredFacingByUid[uid]
			if desiredPosition ~= nil and desiredFacing ~= nil then
				record.TargetPosition = desiredPosition
				record.TargetFacing = desiredFacing
			else
				record.TargetPosition = rootCFrame.Position + Vector3.new(0, Config.FollowVerticalOffset, 0)
				record.TargetFacing = rootCFrame.LookVector
			end

			local delta = record.TargetPosition - record.CurrentPosition
			local distanceSq = delta:Dot(delta)
			local snapDistance = Config.SnapDistanceStuds
			if distanceSq >= (snapDistance * snapDistance) then
				record.CurrentPosition = record.TargetPosition
				record.CurrentFacing = record.TargetFacing
			else
				record.CurrentPosition = record.CurrentPosition:Lerp(record.TargetPosition, alpha)
				local blendedFacing = record.CurrentFacing:Lerp(record.TargetFacing, alpha)
				record.CurrentFacing = safeUnitHorizontal(blendedFacing, record.TargetFacing)
			end

			self:_applyVisualPose(record)
		end
	end
end

function WeaponController:Destroy()
	for uid in pairs(self._visualByUid) do
		self:_destroyVisual(uid)
	end
	table.clear(self._weaponStateByUid)
	table.clear(self._uidHashByUid)
	table.clear(self._cachedUnassignedWeapons)
	table.clear(self._cachedAssignedWeaponsByMobId)
	table.clear(self._mobPositionById)
	table.clear(self._mobPositionExpiresAtById)
	table.clear(self._mobInstanceById)
	for _, record in pairs(self._mobPresentationById) do
		if record.Highlight ~= nil then
			record.Highlight.Enabled = false
		end
		if record.Billboard ~= nil then
			record.Billboard.Enabled = false
		end
	end
	table.clear(self._mobPresentationById)
	table.clear(self._mobPresentationActiveScratch)
	table.clear(self._desiredPositionByUid)
	table.clear(self._desiredFacingByUid)

	if self._janitor ~= nil then
		self._janitor:Cleanup()
	end
end

return WeaponController
