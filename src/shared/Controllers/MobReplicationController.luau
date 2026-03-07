--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Config = require(script.Parent.MobReplicationControllerConfig)
local MobAnimationPlayer = require(script.Parent.MobAnimationPlayer)

type Packet = {
	seq: number?,
	t: number?,
	a: {{[string]: any}}?,
	u: {{[string]: any}}?,
	rm: {string}?,
}

type VisualKind = "Sphere" | "Model"

type MobVisualRecord = {
	Kind: VisualKind,
	Part: Part?,
	Model: Model?,
	AnimationPlayer: any?,
	Revision: number,
	ZoneId: string,
	MobDefId: string,
	CurrentXZ: Vector2,
	TargetXZ: Vector2,
	VelocityXZ: Vector2,
	LastTargetSampleAt: number,
	FacingXZ: Vector2,
	BaseFacingXZ: Vector2,
	BaseRotation: CFrame,
	BaseYawRadians: number,
	GroundY: number,
}

local DEFAULT_TARGET_XZ = Vector2.new(0, 0)
local DEFAULT_FACING_XZ = Vector2.new(0, -1)

local MobReplicationController = Knit.CreateController({
	Name = "MobReplicationController",
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

local function parseXZ(rawXZ: any): Vector2?
	if typeof(rawXZ) ~= "Vector2" then
		return nil
	end
	return rawXZ
end

local function resolveModelNode(node: Instance?): Model?
	if node == nil then
		return nil
	end
	if node:IsA("Model") then
		return node
	end

	local modelChild = node:FindFirstChild("Model")
	if modelChild and modelChild:IsA("Model") then
		return modelChild
	end

	return node:FindFirstChildWhichIsA("Model", true)
end

local function resolveTemplate(zoneId: string, mobDefId: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets == nil then
		return nil
	end
	local mobsRoot = assets:FindFirstChild("Mobs")
	if mobsRoot == nil then
		return nil
	end

	local zoneFolder = mobsRoot:FindFirstChild(zoneId)
	if zoneFolder ~= nil then
		local zoneMobNode = zoneFolder:FindFirstChild(mobDefId)
		local zoneMobModel = resolveModelNode(zoneMobNode)
		if zoneMobModel ~= nil then
			return zoneMobModel
		end
	end

	local directNode = mobsRoot:FindFirstChild(mobDefId)
	local directModel = resolveModelNode(directNode)
	if directModel ~= nil then
		return directModel
	end

	return nil
end

local function getModelRoot(model: Model): BasePart?
	if model.PrimaryPart ~= nil then
		return model.PrimaryPart
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function applyModelPhysicalProps(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
end

local function createSpherePart(mobId: string, parent: Instance): Part
	local sphere = Instance.new("Part")
	sphere.Name = mobId
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(Config.SphereSize, Config.SphereSize, Config.SphereSize)
	sphere.Color = Color3.fromRGB(255, 170, 0)
	sphere.Material = Enum.Material.Neon
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanTouch = false
	sphere.CanQuery = false
	sphere.Parent = parent
	return sphere
end

local function facingVector3FromXZ(value: Vector2): Vector3
	local magnitude = value.Magnitude
	if magnitude <= 1e-4 then
		return Vector3.new(0, 0, -1)
	end
	local unit = value / magnitude
	return Vector3.new(unit.X, 0, unit.Y)
end

local function safeFacingXZ(value: Vector2): Vector2
	if value.Magnitude <= 1e-4 then
		return DEFAULT_FACING_XZ
	end
	return value.Unit
end

local function yawFromFacingXZ(value: Vector2): number
	local normalized = safeFacingXZ(value)
	return math.atan2(normalized.X, normalized.Y)
end

local function resolveFaceReference(model: Model): BasePart?
	local named = model:FindFirstChild("FaceReference", true)
	if named and named:IsA("BasePart") then
		return named
	end
	return nil
end

local function resolveBaseFacingFromModel(model: Model, baseRotation: CFrame): Vector2
	local faceReference = resolveFaceReference(model)
	if faceReference ~= nil then
		local look = faceReference.CFrame.LookVector
		local facing = Vector2.new(look.X, look.Z)
		if facing.Magnitude > 1e-4 then
			return facing.Unit
		end
	end

	local fallbackLook = baseRotation.LookVector
	return safeFacingXZ(Vector2.new(fallbackLook.X, fallbackLook.Z))
end

local function setCommonAttributes(target: Instance, state: {[string]: any})
	if state.h ~= nil then
		target:SetAttribute("HP", tonumber(state.h) or 0)
	end
	if state.mh ~= nil then
		target:SetAttribute("MaxHP", tonumber(state.mh) or 0)
	end
	if state.st ~= nil then
		target:SetAttribute("BrainState", tostring(state.st))
	end
	if state.z ~= nil then
		target:SetAttribute("ZoneId", tostring(state.z))
	end
end

local function getStateString(state: {[string]: any}): string?
	local rawState = state.st
	if typeof(rawState) ~= "string" then
		return nil
	end
	return rawState
end

function MobReplicationController:_warnMissingTemplateOnce(zoneId: string, mobDefId: string)
	local warnKey = string.format("%s::%s", zoneId, mobDefId)
	if self._warnedMissingTemplateByKey[warnKey] == true then
		return
	end
	self._warnedMissingTemplateByKey[warnKey] = true
	warn(string.format("[MobReplicationController] Missing template for zone='%s' mobDefId='%s'", zoneId, mobDefId))
end

function MobReplicationController:_applyRenderPose(record: MobVisualRecord)
	local renderPosition = Vector3.new(record.CurrentXZ.X, record.GroundY, record.CurrentXZ.Y)
	if record.Kind == "Sphere" then
		local part = record.Part
		if part ~= nil then
			part.Position = renderPosition + Vector3.new(0, Config.RenderHeightOffset, 0)
		end
		return
	end

	local model = record.Model
	if model == nil then
		return
	end
	local desiredYaw = yawFromFacingXZ(record.FacingXZ)
	local yawDelta = desiredYaw - record.BaseYawRadians
	local finalRotation = CFrame.Angles(0, yawDelta, 0) * record.BaseRotation
	model:PivotTo(CFrame.new(renderPosition) * finalRotation)
end

function MobReplicationController:KnitInit()
	self._janitor = Janitor.new()
	self._mobService = nil
	self._mobVisualsFolder = nil :: Instance?
	self._serverProxyFolder = nil :: Instance?
	self._mobVisualById = {} :: {[string]: MobVisualRecord}
	self._pendingAddByMobId = {} :: {[string]: {[string]: any}}
	self._pendingAddQueue = {} :: {[number]: string}
	self._pendingAddQueueHead = 1
	self._pendingAddQueueTail = 0
	self._lastPacketSequence = 0
	self._lastDebugCompareAt = 0
	self._warnedMissingTemplateByKey = {} :: {[string]: true}
end

function MobReplicationController:KnitStart()
	self._mobService = Knit.GetService("MobService")
	local renderRootPath = if Config.RenderDebugSpheres then Config.SphereRenderRootPath else Config.ModelRenderRootPath
	self._mobVisualsFolder = ensurePath(Workspace, renderRootPath)
	self._serverProxyFolder = resolvePath(Workspace, Config.ServerProxyRootPath)
	self:_reportClientRenderDebug({
		phase = "start",
		proxies = 0,
		mobsClientFolder = 0,
		visuals = 0,
		liveVisuals = 0,
		pending = 0,
		reconciledAdds = 0,
		removedStale = 0,
		orphaned = 0,
		droppedPending = 0,
		invalidProxies = 0,
	})

	self._janitor:Add(self._mobService.MobStateDelta:Connect(function(packet: Packet)
		self:_handlePacket(packet)
	end), "Disconnect", "MobStateDeltaConnection")

	self._janitor:Add(RunService.RenderStepped:Connect(function(dt: number)
		self:_stepSmoothing(dt)
	end), "Disconnect", "RenderSteppedConnection")
end

function MobReplicationController:_reportClientRenderDebug(payload: {[string]: any})
	local mobService = self._mobService
	if mobService == nil then
		return
	end

	pcall(function()
		mobService:ReportClientRenderDebug(payload)
	end)
end

function MobReplicationController:_destroyVisual(mobId: string)
	local existing = self._mobVisualById[mobId]
	if existing == nil then
		self._pendingAddByMobId[mobId] = nil
		return
	end

	if existing.AnimationPlayer ~= nil then
		existing.AnimationPlayer:Destroy()
	end

	if existing.Part ~= nil then
		existing.Part:Destroy()
	end
	if existing.Model ~= nil then
		existing.Model:Destroy()
	end

	self._mobVisualById[mobId] = nil
	self._pendingAddByMobId[mobId] = nil
end

function MobReplicationController:_enqueuePendingAdd(state: {[string]: any})
	local mobId = state.id
	if typeof(mobId) ~= "string" then
		return
	end

	local existingState = self._pendingAddByMobId[mobId]
	if existingState ~= nil then
		for key, value in pairs(state) do
			existingState[key] = value
		end
		return
	end

	self._pendingAddQueueTail += 1
	self._pendingAddQueue[self._pendingAddQueueTail] = mobId
	self._pendingAddByMobId[mobId] = state
end

function MobReplicationController:_dequeuePendingAddMobId(): string?
	if self._pendingAddQueueHead > self._pendingAddQueueTail then
		self._pendingAddQueueHead = 1
		self._pendingAddQueueTail = 0
		return nil
	end

	local index = self._pendingAddQueueHead
	local mobId = self._pendingAddQueue[index]
	self._pendingAddQueue[index] = nil
	self._pendingAddQueueHead += 1
	if self._pendingAddQueueHead > self._pendingAddQueueTail then
		self._pendingAddQueueHead = 1
		self._pendingAddQueueTail = 0
	end
	return mobId
end

function MobReplicationController:_processPendingAdds()
	local budget = math.max(1, Config.MaxVisualCreatesPerFrame)
	for _ = 1, budget do
		local mobId = self:_dequeuePendingAddMobId()
		if mobId == nil then
			break
		end

		local addState = self._pendingAddByMobId[mobId]
		self._pendingAddByMobId[mobId] = nil
		if addState == nil then
			continue
		end

		local alive = addState.al
		if alive == false then
			self:_destroyVisual(mobId)
			continue
		end

		local record = self:_ensureVisual(addState)
		if record ~= nil then
			self:_applyState(record, addState)
		end
	end
end

function MobReplicationController:_createVisual(
	mobId: string,
	zoneId: string,
	mobDefId: string,
	parent: Instance
): (VisualKind?, Part?, Model?)
	if Config.RenderDebugSpheres then
		return "Sphere", createSpherePart(mobId, parent), nil
	end

	local template = resolveTemplate(zoneId, mobDefId)
	if template == nil then
		self:_warnMissingTemplateOnce(zoneId, mobDefId)
		return nil, nil, nil
	end

	local clone = template:Clone()
	clone.Name = mobId
	applyModelPhysicalProps(clone)

	local root = getModelRoot(clone)
	if root == nil then
		clone:Destroy()
		self:_warnMissingTemplateOnce(zoneId, mobDefId)
		return nil, nil, nil
	end
	clone.PrimaryPart = root
	clone.Parent = parent
	return "Model", nil, clone
end

function MobReplicationController:_ensureVisual(addState: {[string]: any}): MobVisualRecord?
	local mobId = addState.id
	local mobDefId = addState.d
	local zoneId = addState.z
	if typeof(mobId) ~= "string" or typeof(mobDefId) ~= "string" or typeof(zoneId) ~= "string" then
		return nil
	end

	local existing = self._mobVisualById[mobId]
	if existing ~= nil then
		if existing.ZoneId == zoneId and existing.MobDefId == mobDefId then
			return existing
		end
		self:_destroyVisual(mobId)
	end

	local visualsFolder = self._mobVisualsFolder
	if visualsFolder == nil then
		return nil
	end

	local kind, part, model = self:_createVisual(mobId, zoneId, mobDefId, visualsFolder)
	if kind == nil then
		return nil
	end
	local initialXZ = parseXZ(addState.xz) or DEFAULT_TARGET_XZ
	local groundY = tonumber(addState.gy) or Config.DefaultGroundY
	local baseFacingXZ = DEFAULT_FACING_XZ
	local baseRotation = CFrame.new()
	local baseYaw = yawFromFacingXZ(baseFacingXZ)
	local animationPlayer = nil
	if model ~= nil then
		local modelPivot = model:GetPivot()
		baseRotation = modelPivot - modelPivot.Position
		baseFacingXZ = resolveBaseFacingFromModel(model, baseRotation)
		baseYaw = yawFromFacingXZ(baseFacingXZ)
		animationPlayer = MobAnimationPlayer.new(model)
	end
	local record: MobVisualRecord = {
		Kind = kind,
		Part = part,
		Model = model,
		AnimationPlayer = animationPlayer,
		Revision = tonumber(addState.r) or 0,
		ZoneId = zoneId,
		MobDefId = mobDefId,
		CurrentXZ = initialXZ,
		TargetXZ = initialXZ,
		VelocityXZ = Vector2.zero,
		LastTargetSampleAt = os.clock(),
		FacingXZ = baseFacingXZ,
		BaseFacingXZ = baseFacingXZ,
		BaseRotation = baseRotation,
		BaseYawRadians = baseYaw,
		GroundY = groundY,
	}
	self._mobVisualById[mobId] = record
	self:_applyRenderPose(record)

	local target: Instance? = if record.Model ~= nil then record.Model else record.Part
	if target ~= nil then
		setCommonAttributes(target, addState)
	end
	local initialState = getStateString(addState)
	if initialState ~= nil and record.AnimationPlayer ~= nil then
		record.AnimationPlayer:ApplyState(initialState)
	end

	return record
end

function MobReplicationController:_applyState(record: MobVisualRecord, state: {[string]: any})
	local revision = tonumber(state.r) or 0
	if revision < record.Revision then
		return
	end

	record.Revision = revision
	local nextXZ = parseXZ(state.xz)
	if nextXZ ~= nil then
		local now = os.clock()
		local sampleDt = math.max(Config.MinVelocitySampleSeconds, now - record.LastTargetSampleAt)
		local rawVelocity = (nextXZ - record.TargetXZ) / sampleDt
		local rawSpeed = rawVelocity.Magnitude
		if rawSpeed > Config.MaxPredictedSpeedStudsPerSecond and rawSpeed > 1e-4 then
			rawVelocity = rawVelocity.Unit * Config.MaxPredictedSpeedStudsPerSecond
		end
		local velocityAlpha = 1 - math.exp(-Config.VelocitySmoothingK * sampleDt)
		record.VelocityXZ = record.VelocityXZ:Lerp(rawVelocity, math.clamp(velocityAlpha, 0, 1))
		record.LastTargetSampleAt = now
		record.TargetXZ = nextXZ
	end

	local nextGroundY = tonumber(state.gy)
	if nextGroundY ~= nil then
		record.GroundY = nextGroundY
	end

	local target: Instance? = if record.Model ~= nil then record.Model else record.Part
	if target ~= nil then
		setCommonAttributes(target, state)
	end

	local brainState = getStateString(state)
	if brainState ~= nil and record.AnimationPlayer ~= nil then
		record.AnimationPlayer:ApplyState(brainState)
	end
end

function MobReplicationController:_resolveServerProxyFolder(): Instance?
	local folder = self._serverProxyFolder
	if folder ~= nil and folder.Parent ~= nil then
		return folder
	end

	folder = resolvePath(Workspace, Config.ServerProxyRootPath)
	self._serverProxyFolder = folder
	return folder
end

function MobReplicationController:_countMapEntries(source: {[string]: any}): number
	local count = 0
	for _ in pairs(source) do
		count += 1
	end
	return count
end

function MobReplicationController:_isVisualRenderable(record: MobVisualRecord): boolean
	if record.Kind == "Sphere" then
		return record.Part ~= nil and record.Part.Parent ~= nil
	end
	return record.Model ~= nil and record.Model.Parent ~= nil
end

function MobReplicationController:_buildProxyAddState(proxyModel: Model): {[string]: any}?
	local mobId = proxyModel:GetAttribute("MobId")
	local mobDefId = proxyModel:GetAttribute("MobDefId")
	local zoneId = proxyModel:GetAttribute("ZoneId")
	if typeof(mobId) ~= "string" or typeof(mobDefId) ~= "string" or typeof(zoneId) ~= "string" then
		return nil
	end

	local pivot = proxyModel:GetPivot()
	local position = pivot.Position
	local hp = proxyModel:GetAttribute("HP")
	local maxHp = proxyModel:GetAttribute("MaxHP")
	local brainState = proxyModel:GetAttribute("BrainState")

	local addState: {[string]: any} = {
		id = mobId,
		d = mobDefId,
		z = zoneId,
		xz = Vector2.new(position.X, position.Z),
		gy = position.Y,
		al = true,
	}
	if typeof(hp) == "number" then
		addState.h = hp
	end
	if typeof(maxHp) == "number" then
		addState.mh = maxHp
	end
	if typeof(brainState) == "string" then
		addState.st = brainState
	end
	return addState
end

function MobReplicationController:_debugCompareAndReconcile()
	if Config.DebugCompareMobsEnabled ~= true then
		return
	end

	local now = os.clock()
	local interval = math.max(0.1, Config.DebugCompareIntervalSeconds)
	if (now - self._lastDebugCompareAt) < interval then
		return
	end
	self._lastDebugCompareAt = now

	local proxyFolder = self:_resolveServerProxyFolder()
	local proxyAddByMobId: {[string]: {[string]: any}} = {}
	local proxyCount = 0
	local invalidProxyCount = 0
	if proxyFolder ~= nil then
		for _, child in ipairs(proxyFolder:GetChildren()) do
			if child:IsA("Model") then
				local addState = self:_buildProxyAddState(child)
				if addState ~= nil then
					local mobId = addState.id
					if typeof(mobId) == "string" then
						proxyAddByMobId[mobId] = addState
						proxyCount += 1
					end
				else
					invalidProxyCount += 1
				end
			end
		end
	end

	local visualsCount = 0
	local orphanedVisuals = 0
	for mobId, record in pairs(self._mobVisualById) do
		if self:_isVisualRenderable(record) then
			visualsCount += 1
		else
			orphanedVisuals += 1
			self:_destroyVisual(mobId)
		end
	end

	local folderVisualCount = 0
	local visualsFolder = self._mobVisualsFolder
	if visualsFolder ~= nil and visualsFolder.Parent ~= nil then
		for _, child in ipairs(visualsFolder:GetChildren()) do
			if child:IsA("Model") or child:IsA("BasePart") then
				folderVisualCount += 1
			end
		end
	end

	local reconciledAdds = 0
	for mobId, addState in pairs(proxyAddByMobId) do
		if self._mobVisualById[mobId] == nil and self._pendingAddByMobId[mobId] == nil then
			self:_enqueuePendingAdd(addState)
			reconciledAdds += 1
		end
	end

	local removedStaleVisuals = 0
	for mobId in pairs(self._mobVisualById) do
		if proxyAddByMobId[mobId] == nil then
			removedStaleVisuals += 1
			self:_destroyVisual(mobId)
		end
	end

	local droppedStalePending = 0
	for mobId in pairs(self._pendingAddByMobId) do
		if proxyAddByMobId[mobId] == nil then
			droppedStalePending += 1
			self._pendingAddByMobId[mobId] = nil
		end
	end

	local pendingCount = self:_countMapEntries(self._pendingAddByMobId)
	local liveVisualCount = self:_countMapEntries(self._mobVisualById)
	print(string.format(
		"[MobReplicationController][Compare] proxies=%d mobsClientFolder=%d visuals=%d liveVisuals=%d pending=%d reconciledAdds=%d removedStale=%d orphaned=%d droppedPending=%d invalidProxies=%d",
		proxyCount,
		folderVisualCount,
		visualsCount,
		liveVisualCount,
		pendingCount,
		reconciledAdds,
		removedStaleVisuals,
		orphanedVisuals,
		droppedStalePending,
		invalidProxyCount
	))

	self:_reportClientRenderDebug({
		phase = "compare",
		proxies = proxyCount,
		mobsClientFolder = folderVisualCount,
		visuals = visualsCount,
		liveVisuals = liveVisualCount,
		pending = pendingCount,
		reconciledAdds = reconciledAdds,
		removedStale = removedStaleVisuals,
		orphaned = orphanedVisuals,
		droppedPending = droppedStalePending,
		invalidProxies = invalidProxyCount,
	})
end

function MobReplicationController:_stepSmoothing(dt: number)
	self:_processPendingAdds()
	self:_debugCompareAndReconcile()

	local alpha = 1 - math.exp(-Config.PositionSmoothingK * math.max(dt, 0))
	alpha = math.clamp(alpha, Config.MinSmoothingAlpha, Config.MaxSmoothingAlpha)

	for _, record in pairs(self._mobVisualById) do
		local predictedTarget = record.TargetXZ + (record.VelocityXZ * Config.PredictionLeadSeconds)
		local deltaToPredicted = predictedTarget - record.CurrentXZ
		if deltaToPredicted.Magnitude >= Config.SnapDistanceStuds then
			record.CurrentXZ = predictedTarget
		else
			local desired = record.CurrentXZ:Lerp(predictedTarget, alpha)
			local step = desired - record.CurrentXZ
			local maxStep = Config.MaxCatchUpSpeedStudsPerSecond * math.max(dt, 0)
			if step.Magnitude > maxStep and step.Magnitude > 1e-4 then
				record.CurrentXZ += step.Unit * maxStep
			else
				record.CurrentXZ = desired
			end
		end

		local movementDelta = predictedTarget - record.CurrentXZ
		if movementDelta.Magnitude > 1e-4 then
			record.FacingXZ = movementDelta.Unit
		end

		self:_applyRenderPose(record)
	end
end

function MobReplicationController:_handlePacket(packet: Packet)
	if typeof(packet) ~= "table" then
		return
	end

	local sequence = tonumber(packet.seq)
	if sequence ~= nil then
		if sequence <= self._lastPacketSequence then
			return
		end
		self._lastPacketSequence = sequence
	end

	local removes = packet.rm
	if typeof(removes) == "table" then
		for _, mobId in ipairs(removes) do
			if typeof(mobId) == "string" then
				self:_destroyVisual(mobId)
			end
		end
	end

	local adds = packet.a
	if typeof(adds) == "table" then
		for _, addState in ipairs(adds) do
			if typeof(addState) == "table" then
				local alive = addState.al
				if alive == false then
					local mobId = addState.id
					if typeof(mobId) == "string" then
						self:_destroyVisual(mobId)
					end
				else
					self:_enqueuePendingAdd(addState)
				end
			end
		end
	end

	local updates = packet.u
	if typeof(updates) == "table" then
		for _, updateState in ipairs(updates) do
			if typeof(updateState) == "table" then
				local mobId = updateState.id
				if typeof(mobId) == "string" then
					if updateState.al == false then
						self:_destroyVisual(mobId)
					else
						local record = self._mobVisualById[mobId]
						if record ~= nil then
							self:_applyState(record, updateState)
						else
							local pendingState = self._pendingAddByMobId[mobId]
							if pendingState ~= nil then
								for key, value in pairs(updateState) do
									pendingState[key] = value
								end
							end
						end
					end
				end
			end
		end
	end
end

function MobReplicationController:Destroy()
	if self._janitor ~= nil then
		self._janitor:Cleanup()
	end
	for mobId in pairs(self._mobVisualById) do
		self:_destroyVisual(mobId)
	end
	table.clear(self._pendingAddByMobId)
	table.clear(self._pendingAddQueue)
	self._pendingAddQueueHead = 1
	self._pendingAddQueueTail = 0
	table.clear(self._warnedMissingTemplateByKey)
end

return MobReplicationController
