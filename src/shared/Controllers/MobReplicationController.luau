--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Config = require(script.Parent.MobReplicationControllerConfig)

type Packet = {
	seq: number?,
	t: number?,
	a: {{[string]: any}}?,
	u: {{[string]: any}}?,
	rm: {string}?,
}

type MobVisualRecord = {
	Part: Part,
	Revision: number,
	CurrentXZ: Vector2,
	TargetXZ: Vector2,
	VelocityXZ: Vector2,
	LastTargetSampleAt: number,
	GroundY: number,
}

local CLIENT_MOB_ROOT_PATH = {"Game", "MobDebugSpheres"}
local DEFAULT_TARGET_XZ = Vector2.new(0, 0)

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

local function parseXZ(rawXZ: any): Vector2?
	if typeof(rawXZ) ~= "Vector2" then
		return nil
	end
	return rawXZ
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

local function applyRenderPosition(record: MobVisualRecord)
	record.Part.Position = Vector3.new(
		record.CurrentXZ.X,
		record.GroundY + Config.RenderHeightOffset,
		record.CurrentXZ.Y
	)
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

	self._janitor:Add(RunService.RenderStepped:Connect(function(dt: number)
		self:_stepSmoothing(dt)
	end), "Disconnect", "RenderSteppedConnection")
end

function MobReplicationController:_destroyVisual(mobId: string)
	local existing = self._mobVisualById[mobId]
	if existing == nil then
		return
	end
	existing.Part:Destroy()
	self._mobVisualById[mobId] = nil
end

function MobReplicationController:_ensureVisual(addState: {[string]: any}): MobVisualRecord?
	local mobId = addState.id
	if typeof(mobId) ~= "string" then
		return nil
	end

	local existing = self._mobVisualById[mobId]
	if existing ~= nil then
		return existing
	end

	local visualsFolder = self._mobVisualsFolder
	if visualsFolder == nil then
		return nil
	end

	local part = createSpherePart(mobId, visualsFolder)
	local initialXZ = parseXZ(addState.xz) or DEFAULT_TARGET_XZ
	local groundY = tonumber(addState.gy) or Config.DefaultGroundY
	local record: MobVisualRecord = {
		Part = part,
		Revision = tonumber(addState.r) or 0,
		CurrentXZ = initialXZ,
		TargetXZ = initialXZ,
		VelocityXZ = Vector2.zero,
		LastTargetSampleAt = os.clock(),
		GroundY = groundY,
	}
	self._mobVisualById[mobId] = record
	applyRenderPosition(record)
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

	if state.h ~= nil then
		record.Part:SetAttribute("HP", tonumber(state.h) or 0)
	end
	if state.mh ~= nil then
		record.Part:SetAttribute("MaxHP", tonumber(state.mh) or 0)
	end
	if state.st ~= nil then
		record.Part:SetAttribute("BrainState", tostring(state.st))
	end
	if state.z ~= nil then
		record.Part:SetAttribute("ZoneId", tostring(state.z))
	end
end

function MobReplicationController:_stepSmoothing(dt: number)
	local alpha = 1 - math.exp(-Config.PositionSmoothingK * math.max(dt, 0))
	alpha = math.clamp(alpha, Config.MinSmoothingAlpha, Config.MaxSmoothingAlpha)
	for _, record in pairs(self._mobVisualById) do
		local predictedTarget = record.TargetXZ + (record.VelocityXZ * Config.PredictionLeadSeconds)
		local delta = predictedTarget - record.CurrentXZ
		if delta.Magnitude >= Config.SnapDistanceStuds then
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
		applyRenderPosition(record)
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
					local record = self:_ensureVisual(addState)
					if record ~= nil then
						self:_applyState(record, addState)
					end
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
end

return MobReplicationController
