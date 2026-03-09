--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Config = require(script.Parent.MobReplicationControllerConfig)
local MobAnimationPlayer = require(script.Parent.MobAnimationPlayer)
local MobDefs = require(ReplicatedStorage.Configs.MobDefs)

type Packet = {
	seq: number?,
	t: number?,
	a: {{[string]: any}}?,
	u: {{[string]: any}}?,
	rm: {string}?,
}

type TextGuiObject = TextLabel | TextButton

type HealthFillBinding = {
	GuiObject: GuiObject,
	BaseSize: UDim2,
}

type MobUiBinding = {
	Billboard: BillboardGui?,
	NameLabels: {TextGuiObject},
	HealthLabels: {TextGuiObject},
	HealthFillBars: {HealthFillBinding},
	LastName: string?,
	LastHp: number?,
	LastMaxHp: number?,
}

type MobVisualRecord = {
	Model: Model?,
	AnimationPlayer: any?,
	UiBinding: MobUiBinding?,
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
	LastRenderedXZ: Vector2,
	LastRenderedFacingXZ: Vector2,
	LastRenderedGroundY: number,
	HasRenderedPose: boolean,
}

local DEFAULT_TARGET_XZ = Vector2.new(0, 0)
local DEFAULT_FACING_XZ = Vector2.new(0, -1)

local MobReplicationController = Knit.CreateController({
	Name = "MobReplicationController",
})


local function ensurePath(root: Instance, segments: {string}): Instance
	local cursor: Instance = root
	for _, segment in ipairs(segments) do
		local nextNode = cursor:FindFirstChild(segment)
		if nextNode == nil then
			nextNode = Instance.new("Folder")
			assert(nextNode ~= nil)
			nextNode.Name = segment
			nextNode.Parent = cursor
		end
		cursor = nextNode :: Instance
	end
	return cursor
end

local function parseXZ(rawXZ: any): Vector2?
	if typeof(rawXZ) ~= "Vector2" then
		return nil
	end
	return rawXZ
end

local function isTextGuiObject(instance: Instance): boolean
	return instance:IsA("TextLabel") or instance:IsA("TextButton")
end

local function isFiniteNumber(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function isFiniteVector2(value: Vector2): boolean
	return isFiniteNumber(value.X) and isFiniteNumber(value.Y)
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

	if zoneFolder ~= nil then
		local fallbackModel = zoneFolder:FindFirstChildWhichIsA("Model", true)
		if fallbackModel ~= nil then
			return fallbackModel
		end
	end

	local globalFallbackModel = mobsRoot:FindFirstChildWhichIsA("Model", true)
	if globalFallbackModel ~= nil then
		return globalFallbackModel
	end

	return nil
end

local function resolveDisplayName(mobDefId: string): string
	local def = MobDefs[mobDefId]
	if typeof(def) == "table" then
		local displayName = def.DisplayName
		if typeof(displayName) == "string" and displayName ~= "" then
			return displayName
		end
	end

	-- Fallback for unknown defs: convert "ChestMimic2" -> "Chest Mimic 2"
	local humanized = string.gsub(mobDefId, "(%l)(%u)", "%1 %2")
	humanized = string.gsub(humanized, "(%a)(%d)", "%1 %2")
	humanized = string.gsub(humanized, "(%d)(%a)", "%1 %2")
	return humanized
end

local function templateCacheKey(zoneId: string, mobDefId: string): string
	return string.format("%s::%s", zoneId, mobDefId)
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

local function stripExecutableDescendants(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("ModuleScript") then
			descendant:Destroy()
		end
	end
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

local function vector2DistanceSquared(left: Vector2, right: Vector2): number
	local dx = left.X - right.X
	local dy = left.Y - right.Y
	return (dx * dx) + (dy * dy)
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
		local hp = tonumber(state.h) or 0
		if target:GetAttribute("HP") ~= hp then
			target:SetAttribute("HP", hp)
		end
	end
	if state.mh ~= nil then
		local maxHp = tonumber(state.mh) or 0
		if target:GetAttribute("MaxHP") ~= maxHp then
			target:SetAttribute("MaxHP", maxHp)
		end
	end
	if state.st ~= nil then
		local brainState = tostring(state.st)
		if target:GetAttribute("BrainState") ~= brainState then
			target:SetAttribute("BrainState", brainState)
		end
	end
	if state.z ~= nil then
		local zoneId = tostring(state.z)
		if target:GetAttribute("ZoneId") ~= zoneId then
			target:SetAttribute("ZoneId", zoneId)
		end
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

function MobReplicationController:_resolveUiAttachment(model: Model): Attachment?
	local direct = model:FindFirstChild("UIAttachment")
	if direct ~= nil and direct:IsA("Attachment") then
		return direct
	end
	local directContainer = model:FindFirstChild("UIContainer")
	if directContainer ~= nil and directContainer:IsA("Attachment") then
		return directContainer
	end
	local recursive = model:FindFirstChild("UIAttachment", true)
	if recursive ~= nil and recursive:IsA("Attachment") then
		return recursive
	end
	local recursiveContainer = model:FindFirstChild("UIContainer", true)
	if recursiveContainer ~= nil and recursiveContainer:IsA("Attachment") then
		return recursiveContainer
	end
	return nil
end

function MobReplicationController:_resolveBillboard(model: Model, uiAttachment: Attachment?): BillboardGui?
	local preferred: BillboardGui? = nil
	local fallback: BillboardGui? = nil

	if uiAttachment ~= nil then
		for _, child in ipairs(uiAttachment:GetChildren()) do
			if child:IsA("BillboardGui") then
				local billboard = child :: BillboardGui
				local lowerName = string.lower(billboard.Name)
				if preferred == nil and (lowerName == "mobpropertiescontainer" or string.find(lowerName, "mobproperties", 1, true) ~= nil) then
					preferred = billboard
				end
				if fallback == nil then
					fallback = billboard
				end
			end
		end
	end

	if preferred ~= nil then
		if uiAttachment ~= nil and preferred.Adornee == nil then
			preferred.Adornee = uiAttachment
		end
		return preferred
	end
	if fallback ~= nil then
		if uiAttachment ~= nil and fallback.Adornee == nil then
			fallback.Adornee = uiAttachment
		end
		return fallback
	end

	for _, descendant in ipairs(model:GetDescendants()) do
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

	local resolved = if preferred ~= nil then preferred else fallback
	if resolved ~= nil and uiAttachment ~= nil and resolved.Adornee == nil then
		resolved.Adornee = uiAttachment
	end
	return resolved
end

function MobReplicationController:_buildUiBinding(model: Model, mobDefId: string): MobUiBinding?
	local uiAttachment = self:_resolveUiAttachment(model)
	local billboard = self:_resolveBillboard(model, uiAttachment)
	if billboard == nil then
		return nil
	end
	if billboard.Enabled ~= true then
		billboard.Enabled = true
	end

	local nameLabels = {} :: {TextGuiObject}
	local healthLabels = {} :: {TextGuiObject}
	local healthFillBars = {} :: {HealthFillBinding}

	local explicitName = billboard:FindFirstChild("MobName", true)
	if explicitName ~= nil and isTextGuiObject(explicitName) then
		table.insert(nameLabels, explicitName :: TextGuiObject)
	end
	local explicitHealthNumber = billboard:FindFirstChild("HealthNumber", true)
	if explicitHealthNumber ~= nil and isTextGuiObject(explicitHealthNumber) then
		table.insert(healthLabels, explicitHealthNumber :: TextGuiObject)
	end
	local explicitHealthBar = billboard:FindFirstChild("HealthBar", true)
	if explicitHealthBar ~= nil and explicitHealthBar:IsA("GuiObject") then
		local healthBar = explicitHealthBar :: GuiObject
		table.insert(healthFillBars, {
			GuiObject = healthBar,
			BaseSize = healthBar.Size,
		})
	end

	for _, descendant in ipairs(billboard:GetDescendants()) do
		if isTextGuiObject(descendant) then
			local textObject = descendant :: TextGuiObject
			local lowerName = string.lower(textObject.Name)
			if #nameLabels == 0 and string.find(lowerName, "name", 1, true) ~= nil then
				table.insert(nameLabels, textObject)
			elseif #healthLabels == 0 and (string.find(lowerName, "healthnumber", 1, true) ~= nil or string.find(lowerName, "hp", 1, true) ~= nil) then
				table.insert(healthLabels, textObject)
			end
		elseif #healthFillBars == 0 and descendant:IsA("GuiObject") then
			local guiObject = descendant :: GuiObject
			local lowerName = string.lower(guiObject.Name)
			local isHealthFill = string.find(lowerName, "healthbar", 1, true) ~= nil
				or string.find(lowerName, "hpbar", 1, true) ~= nil
				or string.find(lowerName, "fill", 1, true) ~= nil
			if isHealthFill then
				table.insert(healthFillBars, {
					GuiObject = guiObject,
					BaseSize = guiObject.Size,
				})
			end
		end
	end

	local binding: MobUiBinding = {
		Billboard = billboard,
		NameLabels = nameLabels,
		HealthLabels = healthLabels,
		HealthFillBars = healthFillBars,
		LastName = nil,
		LastHp = nil,
		LastMaxHp = nil,
	}

	return binding
end

function MobReplicationController:_applyUiState(record: MobVisualRecord, state: {[string]: any})
	local binding = record.UiBinding
	if binding == nil then
		return
	end

	local nextName = resolveDisplayName(record.MobDefId)
	local hp = tonumber(state.h)
	local maxHp = tonumber(state.mh)
	local hasHealth = hp ~= nil and maxHp ~= nil and maxHp > 0
	local safeHp = if hp ~= nil then math.max(0, hp) else 0
	local safeMaxHp = if maxHp ~= nil then math.max(1, maxHp) else 1
	local ratio = math.clamp(safeHp / safeMaxHp, 0, 1)

	if binding.LastName ~= nextName then
		binding.LastName = nextName
		for _, label in ipairs(binding.NameLabels) do
			if label.Parent ~= nil then
				label.Text = nextName
			end
		end
	end

	if hasHealth and (binding.LastHp ~= safeHp or binding.LastMaxHp ~= safeMaxHp) then
		binding.LastHp = safeHp
		binding.LastMaxHp = safeMaxHp

		local healthText = string.format("%d/%d", math.floor(safeHp + 0.5), math.floor(safeMaxHp + 0.5))
		for _, label in ipairs(binding.HealthLabels) do
			if label.Parent ~= nil then
				label.Text = healthText
			end
		end

		for _, fillBinding in ipairs(binding.HealthFillBars) do
			local guiObject = fillBinding.GuiObject
			if guiObject.Parent ~= nil then
				local baseSize = fillBinding.BaseSize
				guiObject.Size = UDim2.new(
					baseSize.X.Scale * ratio,
					math.floor(baseSize.X.Offset * ratio + 0.5),
					baseSize.Y.Scale,
					baseSize.Y.Offset
				)
			end
		end
	end
end

function MobReplicationController:_applyRenderPose(record: MobVisualRecord)
	local renderPosition = Vector3.new(record.CurrentXZ.X, record.GroundY, record.CurrentXZ.Y)
	local model = record.Model
	if model == nil then
		return
	end
	local desiredYaw = yawFromFacingXZ(record.FacingXZ)
	local yawDelta = desiredYaw - record.BaseYawRadians
	local finalRotation = CFrame.Angles(0, yawDelta, 0) * record.BaseRotation
	model:PivotTo(CFrame.new(renderPosition) * finalRotation)
	record.LastRenderedXZ = record.CurrentXZ
	record.LastRenderedFacingXZ = record.FacingXZ
	record.LastRenderedGroundY = record.GroundY
	record.HasRenderedPose = true
end

function MobReplicationController:_shouldApplyRenderPose(record: MobVisualRecord): boolean
	if record.HasRenderedPose ~= true then
		return true
	end

	local minDistance = math.max(0, Config.RenderPoseMinDistanceStuds)
	if minDistance > 0 then
		if vector2DistanceSquared(record.CurrentXZ, record.LastRenderedXZ) >= (minDistance * minDistance) then
			return true
		end
	end

	if math.abs(record.GroundY - record.LastRenderedGroundY) > 1e-3 then
		return true
	end

	local facingDotThreshold = math.clamp(tonumber(Config.RenderPoseFacingDotThreshold) or 1, -1, 1)
	local facingDot = record.FacingXZ:Dot(record.LastRenderedFacingXZ)
	return facingDot <= facingDotThreshold
end

function MobReplicationController:KnitInit()
	self._janitor = Janitor.new()
	self._mobService = nil
	self._mobVisualsFolder = nil :: Instance?
	self._mobVisualById = {} :: {[string]: MobVisualRecord}
	self._pendingAddByMobId = {} :: {[string]: {[string]: any}}
	self._pendingAddQueue = {} :: {[number]: string}
	self._pendingAddQueueHead = 1
	self._pendingAddQueueTail = 0
	self._lastPacketSequence = 0
	self._warnedMissingTemplateByKey = {} :: {[string]: true}
	self._pendingRemoveExpiresAtByMobId = {} :: {[string]: number}
	self._templateCacheByKey = {} :: {[string]: Model}
	self._pendingRemoveScratch = {} :: {string}
end

function MobReplicationController:KnitStart()
	self._mobService = Knit.GetService("MobService")
	self._mobVisualsFolder = ensurePath(Workspace, Config.ModelRenderRootPath)

	self._janitor:Add(self._mobService.MobStateDelta:Connect(function(packet: Packet)
		self:_handlePacket(packet)
	end), "Disconnect", "MobStateDeltaConnection")

	self._janitor:Add(RunService.RenderStepped:Connect(function(dt: number)
		self:_stepSmoothing(dt)
	end), "Disconnect", "RenderSteppedConnection")
end

function MobReplicationController:_destroyVisual(mobId: string)
	local existing = self._mobVisualById[mobId]
	if existing == nil then
		self._pendingAddByMobId[mobId] = nil
		self._pendingRemoveExpiresAtByMobId[mobId] = nil
		return
	end

	if existing.AnimationPlayer ~= nil then
		existing.AnimationPlayer:Destroy()
	end

	if existing.Model ~= nil then
		existing.Model:Destroy()
	end

	self._mobVisualById[mobId] = nil
	self._pendingAddByMobId[mobId] = nil
	self._pendingRemoveExpiresAtByMobId[mobId] = nil
end

function MobReplicationController:_cancelPendingRemove(mobId: string)
	self._pendingRemoveExpiresAtByMobId[mobId] = nil
end

function MobReplicationController:_scheduleRemove(mobId: string, graceSeconds: number)
	if typeof(mobId) ~= "string" or mobId == "" then
		return
	end

	local resolvedGrace = math.max(0, graceSeconds)
	if resolvedGrace <= 0 then
		self:_destroyVisual(mobId)
		return
	end

	self._pendingRemoveExpiresAtByMobId[mobId] = os.clock() + resolvedGrace
end

function MobReplicationController:_processPendingRemoves()
	local now = os.clock()
	local dueMobIds = self._pendingRemoveScratch
	table.clear(dueMobIds)

	for mobId, expiresAt in pairs(self._pendingRemoveExpiresAtByMobId) do
		if now >= expiresAt then
			table.insert(dueMobIds, mobId)
		end
	end

	for _, mobId in ipairs(dueMobIds) do
		if self._pendingRemoveExpiresAtByMobId[mobId] ~= nil then
			self:_destroyVisual(mobId)
		end
	end
end

function MobReplicationController:_enqueuePendingAdd(state: {[string]: any})
	local mobId = state.id
	if typeof(mobId) ~= "string" then
		return
	end
	self:_cancelPendingRemove(mobId)

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
			self:_scheduleRemove(mobId, Config.DeadRemoveGraceSeconds)
			continue
		end

		local record = self:_ensureVisual(addState)
		if record ~= nil then
			self:_applyState(record, addState)
		else
			-- Retry on later frames when template/content becomes available.
			self:_enqueuePendingAdd(addState)
		end
	end
end

function MobReplicationController:_resolveTemplateCached(zoneId: string, mobDefId: string): Model?
	local cacheKey = templateCacheKey(zoneId, mobDefId)
	local cached = self._templateCacheByKey[cacheKey]
	if cached ~= nil then
		return cached
	end

	local sourceTemplate = resolveTemplate(zoneId, mobDefId)
	if sourceTemplate == nil then
		return nil
	end

	local prepared = sourceTemplate:Clone()
	prepared.Name = sourceTemplate.Name
	stripExecutableDescendants(prepared)
	applyModelPhysicalProps(prepared)

	local preparedRoot = getModelRoot(prepared)
	if preparedRoot == nil then
		prepared:Destroy()
		return nil
	end
	prepared.PrimaryPart = preparedRoot
	prepared.Parent = nil

	self._templateCacheByKey[cacheKey] = prepared
	return prepared
end

function MobReplicationController:_createVisual(
	mobId: string,
	zoneId: string,
	mobDefId: string,
	parent: Instance
): Model?
	local template = self:_resolveTemplateCached(zoneId, mobDefId)
	if template == nil then
		self:_warnMissingTemplateOnce(zoneId, mobDefId)
		return nil
	end

	local clone = template:Clone()
	clone.Name = mobId

	local root = getModelRoot(clone)
	if root == nil then
		clone:Destroy()
		self:_warnMissingTemplateOnce(zoneId, mobDefId)
		return nil
	end
	clone.PrimaryPart = root
	clone.Parent = parent
	return clone
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

	local model = self:_createVisual(mobId, zoneId, mobDefId, visualsFolder)
	if model == nil then
		return nil
	end
	local initialXZ = parseXZ(addState.xz) or DEFAULT_TARGET_XZ
	local groundY = tonumber(addState.gy) or Config.DefaultGroundY
	local baseFacingXZ = DEFAULT_FACING_XZ
	local baseRotation = CFrame.new()
	local baseYaw = yawFromFacingXZ(baseFacingXZ)
	local animationPlayer = nil
	local modelPivot = model:GetPivot()
	baseRotation = modelPivot - modelPivot.Position
	baseFacingXZ = resolveBaseFacingFromModel(model, baseRotation)
	baseYaw = yawFromFacingXZ(baseFacingXZ)
	animationPlayer = MobAnimationPlayer.new(model)
	local record: MobVisualRecord = {
		Model = model,
		AnimationPlayer = animationPlayer,
		UiBinding = self:_buildUiBinding(model, mobDefId),
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
		LastRenderedXZ = initialXZ,
		LastRenderedFacingXZ = baseFacingXZ,
		LastRenderedGroundY = groundY,
		HasRenderedPose = false,
	}
	self._mobVisualById[mobId] = record
	self:_applyRenderPose(record)

	setCommonAttributes(model, addState)
	self:_applyUiState(record, addState)
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
	if nextXZ ~= nil and isFiniteVector2(nextXZ) then
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

	if record.Model ~= nil then
		setCommonAttributes(record.Model, state)
	end
	self:_applyUiState(record, state)

	local brainState = getStateString(state)
	if brainState ~= nil and record.AnimationPlayer ~= nil then
		record.AnimationPlayer:ApplyState(brainState)
	end
end

function MobReplicationController:_stepSmoothing(dt: number)
	self:_processPendingAdds()
	self:_processPendingRemoves()

	local dtClamped = math.max(dt, 0)
	local alpha = 1 - math.exp(-Config.PositionSmoothingK * dtClamped)
	alpha = math.clamp(alpha, Config.MinSmoothingAlpha, Config.MaxSmoothingAlpha)
	local snapDistance = math.max(0, Config.SnapDistanceStuds)
	local snapDistanceSq = snapDistance * snapDistance
	local maxStep = Config.MaxCatchUpSpeedStudsPerSecond * dtClamped
	local maxStepSq = maxStep * maxStep
	local epsilonSq = 1e-8

	for _, record in pairs(self._mobVisualById) do
		local predictedTarget = record.TargetXZ + (record.VelocityXZ * Config.PredictionLeadSeconds)
		local deltaToPredicted = predictedTarget - record.CurrentXZ
		local deltaToPredictedSq = deltaToPredicted:Dot(deltaToPredicted)
		if deltaToPredictedSq >= snapDistanceSq then
			record.CurrentXZ = predictedTarget
		else
			local desired = record.CurrentXZ:Lerp(predictedTarget, alpha)
			local step = desired - record.CurrentXZ
			local stepSq = step:Dot(step)
			if stepSq > maxStepSq and stepSq > epsilonSq then
				record.CurrentXZ += step * (maxStep / math.sqrt(stepSq))
			else
				record.CurrentXZ = desired
			end
		end

		local movementDelta = predictedTarget - record.CurrentXZ
		local movementSq = movementDelta:Dot(movementDelta)
		if movementSq > epsilonSq then
			record.FacingXZ = movementDelta * (1 / math.sqrt(movementSq))
		end

		if self:_shouldApplyRenderPose(record) then
			self:_applyRenderPose(record)
		end
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
				self:_scheduleRemove(mobId, Config.RelevanceRemoveGraceSeconds)
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
						self:_scheduleRemove(mobId, Config.DeadRemoveGraceSeconds)
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
						self:_scheduleRemove(mobId, Config.DeadRemoveGraceSeconds)
					else
						self:_cancelPendingRemove(mobId)
						local record = self._mobVisualById[mobId]
						if record ~= nil then
							self:_applyState(record, updateState)
						else
							local pendingState = self._pendingAddByMobId[mobId]
							if pendingState ~= nil then
								for key, value in pairs(updateState) do
									pendingState[key] = value
								end
							elseif updateState.al == true then
								local zoneId = updateState.z
								local mobDefId = updateState.d
								if typeof(zoneId) == "string" and typeof(mobDefId) == "string" then
									self:_enqueuePendingAdd(updateState)
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
	table.clear(self._pendingRemoveExpiresAtByMobId)
	self._pendingAddQueueHead = 1
	self._pendingAddQueueTail = 0
	table.clear(self._warnedMissingTemplateByKey)
	for cacheKey, template in pairs(self._templateCacheByKey) do
		template:Destroy()
		self._templateCacheByKey[cacheKey] = nil
	end
	table.clear(self._pendingRemoveScratch)
end

return MobReplicationController
