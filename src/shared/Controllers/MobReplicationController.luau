--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)

type Packet = {
	seq: number?,
	a: {{[string]: any}}?,
	u: {{[string]: any}}?,
	rm: {string}?,
}

type MobVisualRecord = {
	Model: Model,
	Revision: number,
	ZoneId: string,
	MobDefId: string,
}

local DEFAULT_FACING = Vector3.new(0, 0, -1)
local CLIENT_MOB_ROOT_PATH = {"Game", "MobsClient"}

local MobReplicationController = Knit.CreateController({
	Name = "MobReplicationController",
})

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

		local fallbackZoneModel = zoneFolder:FindFirstChildWhichIsA("Model", true)
		if fallbackZoneModel ~= nil then
			return fallbackZoneModel
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

local function parseFacing(rawFacing: any): Vector3
	if typeof(rawFacing) ~= "Vector3" then
		return DEFAULT_FACING
	end
	if rawFacing.Magnitude <= 1e-4 then
		return DEFAULT_FACING
	end
	return rawFacing.Unit
end

local function parsePosition(rawPosition: any): Vector3?
	if typeof(rawPosition) ~= "Vector3" then
		return nil
	end
	return rawPosition
end

local function applyTransform(model: Model, rawPosition: any, rawFacing: any)
	local position = parsePosition(rawPosition)
	if position == nil then
		return
	end
	local facing = parseFacing(rawFacing)
	model:PivotTo(CFrame.lookAt(position, position + facing))
end

function MobReplicationController:KnitInit()
	self._janitor = Janitor.new()
	self._mobService = nil
	self._mobVisualsFolder = nil :: Instance?
	self._mobVisualById = {} :: {[string]: MobVisualRecord}
	self._lastPacketSequence = 0
end

function MobReplicationController:KnitStart()
	self._mobService = Knit.GetService("MobService")
	self._mobVisualsFolder = ensurePath(Workspace, CLIENT_MOB_ROOT_PATH)

	self._janitor:Add(self._mobService.MobStateDelta:Connect(function(packet: Packet)
		self:_handlePacket(packet)
	end), "Disconnect", "MobStateDeltaConnection")
end

function MobReplicationController:_destroyMobVisual(mobId: string)
	local record = self._mobVisualById[mobId]
	if record == nil then
		return
	end

	if record.Model ~= nil then
		record.Model:Destroy()
	end
	self._mobVisualById[mobId] = nil
end

function MobReplicationController:_ensureMobVisual(state: {[string]: any}): MobVisualRecord?
	local mobId = state.id
	local mobDefId = state.d
	local zoneId = state.z
	if typeof(mobId) ~= "string" or typeof(mobDefId) ~= "string" or typeof(zoneId) ~= "string" then
		return nil
	end

	local existing = self._mobVisualById[mobId]
	if existing ~= nil then
		if existing.MobDefId == mobDefId and existing.ZoneId == zoneId then
			return existing
		end
		self:_destroyMobVisual(mobId)
	end

	local template = resolveTemplate(zoneId, mobDefId)
	if template == nil then
		return nil
	end

	local clone = template:Clone()
	clone.Name = mobId
	applyModelPhysicalProps(clone)

	local rootPart = getModelRoot(clone)
	if rootPart == nil then
		clone:Destroy()
		return nil
	end
	clone.PrimaryPart = rootPart

	clone.Parent = self._mobVisualsFolder
	applyTransform(clone, state.p, state.f)

	local record: MobVisualRecord = {
		Model = clone,
		Revision = tonumber(state.r) or 0,
		ZoneId = zoneId,
		MobDefId = mobDefId,
	}
	self._mobVisualById[mobId] = record
	return record
end

function MobReplicationController:_applyState(record: MobVisualRecord, state: {[string]: any})
	local revision = tonumber(state.r) or 0
	if revision < record.Revision then
		return
	end

	record.Revision = revision
	applyTransform(record.Model, state.p, state.f)

	if state.h ~= nil then
		record.Model:SetAttribute("HP", tonumber(state.h) or 0)
	end
	if state.mh ~= nil then
		record.Model:SetAttribute("MaxHP", tonumber(state.mh) or 0)
	end
	if state.al ~= nil then
		record.Model:SetAttribute("Alive", state.al == true)
	end
	if state.at ~= nil then
		record.Model:SetAttribute("Attackable", state.at == true)
	end
	if state.st ~= nil then
		record.Model:SetAttribute("BrainState", tostring(state.st))
	end
	if state.tu ~= nil then
		record.Model:SetAttribute("TargetUserId", tonumber(state.tu))
	else
		record.Model:SetAttribute("TargetUserId", nil)
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
				self:_destroyMobVisual(mobId)
			end
		end
	end

	local adds = packet.a
	if typeof(adds) == "table" then
		for _, addState in ipairs(adds) do
			if typeof(addState) == "table" then
				local record = self:_ensureMobVisual(addState)
				if record ~= nil then
					self:_applyState(record, addState)
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
					local record = self._mobVisualById[mobId]
					if record ~= nil then
						self:_applyState(record, updateState)
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
		self:_destroyMobVisual(mobId)
	end
end

return MobReplicationController
