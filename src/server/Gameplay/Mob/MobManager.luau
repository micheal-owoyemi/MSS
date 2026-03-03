local MobManager = {}
MobManager.__index = MobManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if RunService:IsClient() then
	error("MobManager is server-only")
end

local Zone = require(ReplicatedStorage.Shared:WaitForChild("Zone"))
local MobEntity = require(script.Parent.MobEntity)
local GameWorld = require(ReplicatedStorage.Shared.Utilities.GameWorld)

local zonesFolder = GameWorld.getZonesFolder()

function MobManager.new()
	local self = setmetatable({
		mobEntities = {},
	}, MobManager)

	return self
end

function MobManager:spawnMob(mobZone: string, mobName: string, spawnLocation: Instance)
	local mobEntity = MobEntity.new(mobZone, mobName, spawnLocation)
	table.insert(self.mobEntities, mobEntity)
	return mobEntity
end

function MobManager:setupZoneSpawning()
	for _, area in ipairs(zonesFolder:GetChildren()) do
		local container = area:FindFirstChild("Container")
		if not container then
			continue
		end

		local zone = Zone.new(container)
		zone:setAccuracy("Low")

		zone.playerEntered:Connect(function()
			local zoneParts = zone:getParts()
			for _, part in ipairs(zoneParts) do
				if not part:IsA("BasePart") then
					continue
				end
				if part:GetAttribute("Mob") == nil then
					continue
				end
				if part:GetAttribute("Active") == true then
					continue
				end

				local mobName = tostring(part:GetAttribute("Mob"))
				local mobEntity = self:spawnMob(area.Name, mobName, part)
				if mobEntity then
					part:SetAttribute("Active", true)
					task.wait(0.1)
				end
			end
		end)
	end
end

function MobManager:attackMob(player: Player, mobPart: Instance, playerWeapons: { [string]: any })
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	if typeof(mobPart) ~= "Instance" then
		return
	end
	if type(playerWeapons) ~= "table" or next(playerWeapons) == nil then
		return
	end

	local mobModel = mobPart.Parent
	if not mobModel then
		return
	end

	for _, mobEntity in ipairs(self.mobEntities) do
		if mobEntity and mobEntity.mobModel == mobModel then
			mobEntity:engaged(player, playerWeapons)
			return
		end
	end
end

return MobManager
