local MobManager = {}
MobManager.__index = MobManager

-- SERVICES
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if RunService:IsClient() then
	error("MobManager is server-only")
end

-- MODULES
local ZonePlus = require(ReplicatedStorage.Shared:WaitForChild("Zone"))
local MobClass = require(ReplicatedStorage.Shared.Classes.Mob)
local Trove = require(ReplicatedStorage.Shared.Trove)

-- VARIABLES
local zones = workspace:WaitForChild("Game"):WaitForChild("Zones")

-- FUNCTIONS
function MobManager.new()
	local self = setmetatable({
		trove = Trove.new(),
		mobInstances = {},
	}, MobManager)

	return self
end

function MobManager:spawnMob(mobZone: string, mobName: string, spawnLocation: Instance)
	local mobInstance = MobClass.new(mobZone, mobName, spawnLocation)
	table.insert(self.mobInstances, mobInstance)
	return mobInstance
end

function MobManager:despawnMob(mobInstance)
	if mobInstance and type(mobInstance.despawn) == "function" then
		mobInstance:despawn()
	end
end

function MobManager:setUpZoneSpawning()
	for _, area in ipairs(zones:GetChildren()) do
		local container = area:FindFirstChild("Container")
		if not container then
			continue
		end

		local zone = ZonePlus.new(container)
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
				local mobInstance = self:spawnMob(area.Name, mobName, part)
				if mobInstance then
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

	for _, mob in ipairs(self.mobInstances) do
		if mob and mob.mobModel == mobModel then
			mob:engaged(player, playerWeapons)
			return
		end
	end
end

function MobManager:Destroy()
	if self.trove then
		self.trove:Destroy()
	end

	for _, mob in ipairs(self.mobInstances) do
		if mob and type(mob.despawn) == "function" then
			mob:despawn()
		end
	end
	
	table.clear(self.mobInstances)
end

return MobManager
