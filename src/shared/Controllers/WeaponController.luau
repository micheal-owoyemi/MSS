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
	RootPart: BasePart,
	IsModel: boolean,
	CurrentPosition: Vector3,
	TargetPosition: Vector3,
	CurrentFacing: Vector3,
	TargetFacing: Vector3,
}

local WeaponController = Knit.CreateController({
	Name = "WeaponController",
})

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
			nextNode = Instance.new("Folder")
			nextNode.Name = segment
			nextNode.Parent = cursor
		end
		cursor = nextNode
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
	self._ownerOffsetRadians = ((self._player.UserId % 360) / 360) * math.pi * 2
	self._hoverMobId = nil :: string?
	self._lastClickMobId = nil :: string?
	self._lastClickAt = 0
	self._lastRevision = 0
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

function WeaponController:_resolveHoverMobId(): string?
	local mouse = self._mouse
	if mouse == nil then
		return nil
	end

	local target = mouse.Target
	if target ~= nil then
		local mobId = self:_resolveMobIdFromInstance(target)
		if mobId ~= nil then
			return mobId
		end
	end

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
				local worldPosition = resolveInstanceWorldPosition(child)
				if worldPosition ~= nil then
					local screenPoint, onScreen = camera:WorldToViewportPoint(worldPosition)
					if onScreen and screenPoint.Z > 0 then
						local dx = screenPoint.X - mouseX
						local dy = screenPoint.Y - mouseY
						local distanceSquared = (dx * dx) + (dy * dy)
						if distanceSquared <= bestDistanceSquared then
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

	return bestMobId
end

function WeaponController:_applyCursorForHover(mobId: string?)
	local mouse = self._mouse
	if mouse == nil then
		return
	end

	local desiredIcon = ""
	if mobId ~= nil and Config.HoverCursorIcon ~= nil and Config.HoverCursorIcon ~= "" then
		desiredIcon = Config.HoverCursorIcon
	end

	if mouse.Icon ~= desiredIcon then
		mouse.Icon = desiredIcon
	end
end

function WeaponController:_onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	local hoverMobId = self._hoverMobId
	if hoverMobId == nil then
		hoverMobId = self:_resolveHoverMobId()
	end
	if hoverMobId == nil then
		return
	end

	local now = os.clock()
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
		end
	end

	self._weaponStateByUid = nextStateByUid
end

function WeaponController:_getMobPosition(mobId: string): Vector3?
	local mobsClientRoot = self._mobsClientRoot
	if mobsClientRoot ~= nil then
		local mobVisual = mobsClientRoot:FindFirstChild(mobId)
		if mobVisual ~= nil then
			if mobVisual:IsA("Model") then
				local root = mobVisual.PrimaryPart or mobVisual:FindFirstChildWhichIsA("BasePart", true)
				if root ~= nil then
					return root.Position
				end
			elseif mobVisual:IsA("BasePart") then
				return mobVisual.Position
			end
		end
	end

	local serverMobsRoot = self._serverMobsRoot
	if serverMobsRoot ~= nil then
		local proxy = serverMobsRoot:FindFirstChild(mobId)
		if proxy ~= nil and proxy:IsA("Model") then
			local root = proxy.PrimaryPart or proxy:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				return root.Position
			end
		end
	end

	return nil
end

function WeaponController:_buildOrderedWeaponsByMode()
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

	local function sortByQueue(a: WeaponState, b: WeaponState): boolean
		if a.QueueIndex == b.QueueIndex then
			return a.Uid < b.Uid
		end
		return a.QueueIndex < b.QueueIndex
	end

	table.sort(unassigned, sortByQueue)
	for _, bucket in pairs(assignedByMobId) do
		table.sort(bucket, sortByQueue)
	end

	return unassigned, assignedByMobId
end

function WeaponController:_applyVisualPose(record: WeaponVisualRecord)
	local facing = safeUnitHorizontal(record.CurrentFacing, Vector3.new(0, 0, -1))
	local lookTarget = record.CurrentPosition + facing
	local pose = CFrame.lookAt(record.CurrentPosition, lookTarget)

	if record.IsModel and record.Instance:IsA("Model") then
		record.Instance:PivotTo(pose)
	elseif record.RootPart ~= nil then
		record.RootPart.CFrame = pose
	end
end

function WeaponController:_stepRender(dt: number)
	self._hoverMobId = self:_resolveHoverMobId()
	self:_applyCursorForHover(self._hoverMobId)

	local rootCFrame = resolveCharacterRootCFrame(self._player)
	if rootCFrame == nil then
		return
	end

	local now = os.clock()
	local unassigned, assignedByMobId = self:_buildOrderedWeaponsByMode()
	local desiredPoseByUid = {} :: {[string]: {Position: Vector3, Facing: Vector3}}

	for index, weapon in ipairs(unassigned) do
		local uidHash = hashString(weapon.Uid)
		local position, facing = WeaponVisualLayout.ComputeFollowPose(
			rootCFrame,
			index,
			#unassigned,
			Config,
			now,
			uidHash
		)
		desiredPoseByUid[weapon.Uid] = {
			Position = position,
			Facing = facing,
		}
	end

	for mobId, bucket in pairs(assignedByMobId) do
		local mobPosition = self:_getMobPosition(mobId)
		if mobPosition ~= nil then
			for index, weapon in ipairs(bucket) do
				local uidHash = hashString(weapon.Uid)
				local position, facing = WeaponVisualLayout.ComputeAssignedPose(
					mobPosition,
					index,
					#bucket,
					Config,
					now,
					self._ownerOffsetRadians,
					uidHash
				)
				desiredPoseByUid[weapon.Uid] = {
					Position = position,
					Facing = facing,
				}
			end
		end
	end

	for uid, state in pairs(self._weaponStateByUid) do
		local record = self:_ensureVisual(uid, state.DefId)
		if record ~= nil then
			local desired = desiredPoseByUid[uid]
			if desired ~= nil then
				record.TargetPosition = desired.Position
				record.TargetFacing = desired.Facing
			else
				record.TargetPosition = rootCFrame.Position + Vector3.new(0, Config.FollowVerticalOffset, 0)
				record.TargetFacing = rootCFrame.LookVector
			end

			local distance = (record.TargetPosition - record.CurrentPosition).Magnitude
			if distance >= Config.SnapDistanceStuds then
				record.CurrentPosition = record.TargetPosition
				record.CurrentFacing = record.TargetFacing
			else
				local alpha = math.clamp(1 - math.exp(-Config.PositionSmoothingK * math.max(dt, 0)), 0, 1)
				record.CurrentPosition = record.CurrentPosition:Lerp(record.TargetPosition, alpha)
				local blendedFacing = record.CurrentFacing:Lerp(record.TargetFacing, alpha)
				record.CurrentFacing = safeUnitHorizontal(blendedFacing, record.TargetFacing)
			end

			self:_applyVisualPose(record)
		end
	end
end

function WeaponController:Destroy()
	self:_applyCursorForHover(nil)
	for uid in pairs(self._visualByUid) do
		self:_destroyVisual(uid)
	end
	table.clear(self._weaponStateByUid)

	if self._janitor ~= nil then
		self._janitor:Cleanup()
	end
end

return WeaponController
