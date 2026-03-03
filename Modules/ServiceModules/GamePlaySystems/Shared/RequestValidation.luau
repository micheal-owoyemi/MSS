local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DataMobs = require(ReplicatedStorage.Shared.Data.Data_Mobs)

local RequestValidation = {}

local DEFAULT_MAX_DISTANCE = 100

do
	local settings = DataMobs.Settings
	if type(settings) == "table" and type(settings.MinimumDistance) == "number" then
		DEFAULT_MAX_DISTANCE = settings.MinimumDistance
	end
end

function RequestValidation.validateAttackTarget(
	player: Player,
	target: Instance,
	maxDistance: number?
): (boolean, string?, BasePart?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "InvalidPlayer", nil
	end

	if typeof(target) ~= "Instance" or target:IsDescendantOf(Workspace) == false then
		return false, "InvalidTarget", nil
	end

	local targetPart: BasePart? = nil
	if target:IsA("BasePart") then
		targetPart = target
	elseif target:IsA("Model") then
		targetPart = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
	end

	if not targetPart then
		return false, "TargetMissingPart", nil
	end
	if targetPart:GetAttribute("Mob") == nil then
		return false, "TargetNotMob", nil
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not (rootPart and rootPart:IsA("BasePart")) then
		return false, "CharacterUnavailable", nil
	end

	local allowedDistance = tonumber(maxDistance) or DEFAULT_MAX_DISTANCE
	if (rootPart.Position - targetPart.Position).Magnitude > allowedDistance then
		return false, "TargetOutOfRange", nil
	end

	return true, nil, targetPart
end

return RequestValidation
