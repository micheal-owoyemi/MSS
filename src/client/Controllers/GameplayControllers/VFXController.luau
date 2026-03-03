local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CoinDropEffect = require(script.Parent.Parent.Parent.Gameplay.VFX.CoinDropEffect)
local NetworkApi = require(ReplicatedStorage.Shared.Network.NetworkApi)
local GameWorld = require(ReplicatedStorage.Shared.Utilities.GameWorld)

local GameplayPacket = NetworkApi.Packets.Gameplay

local VFXController = Knit.CreateController({
	Name = "VFXController",
})

local function emitAllParticles(attachment: Attachment)
	for _, child in ipairs(attachment:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			local emitCount = child:GetAttribute("EmitCount")
			child:Emit(tonumber(emitCount) or 1)
		end
	end
end

function VFXController:_spawnVFX(templateName: string, position: Vector3, lifetime: number)
	local template = ReplicatedStorage.Shared:WaitForChild("Assets"):WaitForChild("VFX"):WaitForChild(templateName)
	local effect = template:Clone()
	effect.Parent = GameWorld.getFXFolder(true)
	effect.Position = position

	local attachment = effect:WaitForChild("Main")
	emitAllParticles(attachment)

	task.delay(lifetime, function()
		if effect.Parent then
			effect:Destroy()
		end
	end)
end

function VFXController:_playMobDeathVFX(mobPosition: Vector3)
	self:_spawnVFX("MobExplosion", Vector3.new(mobPosition.X, 2, mobPosition.Z), 4)
end

function VFXController:_playMobAttackVFX(mobPosition: Vector3)
	self:_spawnVFX("MobAttackImpact", mobPosition, 1)
end

function VFXController:KnitStart()
	local player = Players.LocalPlayer

	GameplayPacket.coinDrop.listen(function(data)
		if type(data) ~= "table" or typeof(data.origin) ~= "CFrame" then
			return
		end

		CoinDropEffect.spawn(data.origin, data.reward, player)
	end)

	GameplayPacket.mobDeathFX.listen(function(data)
		if type(data) ~= "table" or typeof(data.position) ~= "Vector3" then
			return
		end

		self:_playMobDeathVFX(data.position)
	end)

	GameplayPacket.mobAttackFX.listen(function(data)
		if type(data) ~= "table" or typeof(data.position) ~= "Vector3" then
			return
		end

		self:_playMobAttackVFX(data.position)
	end)
end

return VFXController
