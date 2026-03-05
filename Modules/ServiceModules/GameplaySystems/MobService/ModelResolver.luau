--!strict

local ModelResolver = {}

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

local function getModelRoot(model: Model): BasePart?
	if model.PrimaryPart ~= nil then
		return model.PrimaryPart
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

function ModelResolver.ResolveSpawnContainer(workspaceRoot: Workspace, spawnRootPath: {string}): Instance
	return ensurePath(workspaceRoot, spawnRootPath)
end

local function resolveFromNode(node: Instance?): Model?
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

	local firstModel = node:FindFirstChildWhichIsA("Model", true)
	if firstModel ~= nil then
		return firstModel
	end

	return nil
end

function ModelResolver.ResolveMobTemplate(replicationRoot: ReplicatedStorage, assetsRootPath: {string}, zoneId: string, mobDefId: string, mobDef: {[string]: any}?): Model?
	local assetsRoot = resolvePath(replicationRoot, assetsRootPath)
	if assetsRoot == nil then
		return nil
	end

	if typeof(mobDef) == "table" and typeof(mobDef.AssetPath) == "table" then
		local explicitPath = {}
		for _, segment in ipairs(mobDef.AssetPath) do
			if typeof(segment) == "string" and segment ~= "" then
				table.insert(explicitPath, segment)
			end
		end
		if #explicitPath > 0 then
			local explicitNode = resolvePath(assetsRoot, explicitPath)
			local explicitModel = resolveFromNode(explicitNode)
			if explicitModel ~= nil then
				return explicitModel
			end
		end
	end

	local zoneFolder = assetsRoot:FindFirstChild(zoneId)
	if zoneFolder ~= nil then
		local zoneMobNode = zoneFolder:FindFirstChild(mobDefId)
		local zoneMobModel = resolveFromNode(zoneMobNode)
		if zoneMobModel ~= nil then
			return zoneMobModel
		end
	end

	local directNode = assetsRoot:FindFirstChild(mobDefId)
	local directModel = resolveFromNode(directNode)
	if directModel ~= nil then
		return directModel
	end

	if zoneFolder ~= nil then
		local fallbackModel = zoneFolder:FindFirstChildWhichIsA("Model", true)
		if fallbackModel ~= nil then
			return fallbackModel
		end
	end

	return nil
end

function ModelResolver.CloneMobModel(template: Model, parent: Instance, mobId: string, zoneId: string, mobDefId: string, spawnPosition: Vector3): (Model?, BasePart?)
	if template == nil or parent == nil then
		return nil, nil
	end

	local proxy = Instance.new("Model")
	proxy.Name = mobId

	local templateRoot = getModelRoot(template)
	local rootSize = if templateRoot ~= nil then templateRoot.Size else Vector3.new(2.5, 3, 2.5)
	rootSize = Vector3.new(
		math.clamp(rootSize.X, 1.5, 6),
		math.clamp(rootSize.Y, 2, 8),
		math.clamp(rootSize.Z, 1.5, 6)
	)

	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = rootSize
	rootPart.Transparency = 1
	rootPart.CanCollide = false
	rootPart.CanTouch = false
	rootPart.CanQuery = false
	rootPart.Anchored = false
	rootPart.Parent = proxy

	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.BreakJointsOnDeath = false
	humanoid.AutoRotate = true
	humanoid.HipHeight = math.max(0, rootSize.Y * 0.5 - 1)
	humanoid.Parent = proxy

	proxy.PrimaryPart = rootPart

	proxy:SetAttribute("MobId", mobId)
	proxy:SetAttribute("MobDefId", mobDefId)
	proxy:SetAttribute("ZoneId", zoneId)
	proxy:SetAttribute("AllowedZoneId", zoneId)
	proxy:SetAttribute("ServerProxy", true)

	proxy.Parent = parent
	proxy:PivotTo(CFrame.new(spawnPosition))
	pcall(function()
		rootPart:SetNetworkOwner(nil)
	end)

	return proxy, rootPart
end

return ModelResolver
