--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type CreatedVisual = {
	Instance: Instance,
	RootPart: BasePart,
	IsModel: boolean,
}

local WeaponVisualResolver = {}

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

local function getModelRoot(model: Model): BasePart?
	if model.PrimaryPart ~= nil then
		return model.PrimaryPart
	end

	local humanoidRoot = model:FindFirstChild("HumanoidRootPart")
	if humanoidRoot and humanoidRoot:IsA("BasePart") then
		return humanoidRoot
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

local function createFallbackPart(uid: string, parent: Instance, config: {[string]: any}): CreatedVisual
	local part = Instance.new("Part")
	part.Name = uid
	part.Size = config.FallbackPartSize
	part.Color = config.FallbackPartColor
	part.Material = Enum.Material.Metal
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Parent = parent

	return {
		Instance = part,
		RootPart = part,
		IsModel = false,
	}
end

local function findNamedNode(root: Instance, targetName: string): Instance?
	local direct = root:FindFirstChild(targetName)
	if direct ~= nil then
		return direct
	end

	local loweredTarget = string.lower(targetName)
	for _, descendant in ipairs(root:GetDescendants()) do
		if string.lower(descendant.Name) == loweredTarget then
			return descendant
		end
	end

	return nil
end

function WeaponVisualResolver.CreateVisual(uid: string, defId: string, parent: Instance, config: {[string]: any}): CreatedVisual
	local assetsRoot = resolvePath(ReplicatedStorage, config.WeaponAssetsRootPath)
	if assetsRoot == nil then
		return createFallbackPart(uid, parent, config)
	end

	local templateName = config.TemplateByDefId[defId]
	local templateNode: Instance? = nil
	if typeof(templateName) == "string" and templateName ~= "" then
		templateNode = findNamedNode(assetsRoot, templateName)
	end

	if templateNode == nil then
		templateNode = findNamedNode(assetsRoot, defId)
	end

	local templateModel = resolveModelNode(templateNode)
	if templateModel == nil then
		templateModel = assetsRoot:FindFirstChildWhichIsA("Model", true)
	end

	if templateModel == nil then
		return createFallbackPart(uid, parent, config)
	end

	local clone = templateModel:Clone()
	clone.Name = uid
	applyModelPhysicalProps(clone)

	local rootPart = getModelRoot(clone)
	if rootPart == nil then
		clone:Destroy()
		return createFallbackPart(uid, parent, config)
	end

	clone.PrimaryPart = rootPart
	clone.Parent = parent

	return {
		Instance = clone,
		RootPart = rootPart,
		IsModel = true,
	}
end

return WeaponVisualResolver
