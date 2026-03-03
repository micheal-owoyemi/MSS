local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoinDrop = require(ReplicatedStorage.Shared.Classes.CoinDrop)
local NetworkApi = require(ReplicatedStorage.Shared.Network.NetworkApi)
local GameplayPacket = NetworkApi.Packets.Gameplay

local VFXController = {
	_started = false,
}

local function emitAllParticles(attachment: Attachment)
	for _, child in ipairs(attachment:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			local emitCount = child:GetAttribute("EmitCount")
			child:Emit(tonumber(emitCount) or 1)
		end
	end
end

function VFXController:_playMobDeathVFX(mobPosition: Vector3)
	local template = ReplicatedStorage.Shared:WaitForChild("Assets"):WaitForChild("VFX"):WaitForChild("MobExplosion")
	local effect = template:Clone()
	effect.Parent = workspace:WaitForChild("Game"):WaitForChild("FX")
	effect.Position = Vector3.new(mobPosition.X, 2, mobPosition.Z)

	local attachment = effect:WaitForChild("Main")
	emitAllParticles(attachment)

	task.delay(4, function()
		if effect.Parent then
			effect:Destroy()
		end
	end)
end

function VFXController:_playMobAttackVFX(mobPosition: Vector3)
	local template = ReplicatedStorage.Shared:WaitForChild("Assets"):WaitForChild("VFX"):WaitForChild("MobAttackImpact")
	local effect = template:Clone()
	effect.Parent = workspace:WaitForChild("Game"):WaitForChild("FX")
	effect.Position = mobPosition

	local attachment = effect:WaitForChild("Main")
	emitAllParticles(attachment)

	task.delay(1, function()
		if effect.Parent then
			effect:Destroy()
		end
	end)
end

function VFXController:Start()
	if self._started then
		return
	end

	self._started = true

	local player = Players.LocalPlayer

	GameplayPacket.coinDrop.listen(function(data)
		if type(data) ~= "table" or typeof(data.origin) ~= "CFrame" then
			return
		end
		CoinDrop.spawn(data.origin, data.reward, player)
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
