local MobEntity = {}
MobEntity.__index = MobEntity

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

if RunService:IsClient() then
	error("MobEntity is server-only")
end

local DataHandler = require(ServerScriptService.Server.DataHandler)

local DataMobs = require(ReplicatedStorage.Shared.Data.Data_Mobs)
local NetworkApi = require(ReplicatedStorage.Shared.Network.NetworkApi)
local WeaponData = require(ReplicatedStorage.Shared.Utilities.WeaponData)
local GameWorld = require(ReplicatedStorage.Shared.Utilities.GameWorld)

local GameplayPacket = NetworkApi.Packets.Gameplay
local rng = Random.new()

function MobEntity.new(mobZone: string, mobName: string, spawnLocation: Instance)
	local mobDefinition = DataMobs[mobZone] and DataMobs[mobZone][mobName]
	if type(mobDefinition) ~= "table" then
		error(string.format("[MobEntity] Missing mob definition for %s/%s", tostring(mobZone), tostring(mobName)))
	end

	local self = setmetatable({
		mobHealth = mobDefinition.Health,
		currentHealth = mobDefinition.Health,
		spawnLocation = spawnLocation,
		mobZone = mobZone,
		mobName = mobName,
		mobValue = mobDefinition.Value,
		mobModel = ReplicatedStorage.Shared.Assets.Mobs[mobZone][mobName].Model:Clone(),
		folder = GameWorld.getZonesFolder()[mobZone].Mobs,
		cooldown = mobDefinition.Cooldown,
		canBeEngaged = false,
		damageDoneByPlayers = {},
	}, MobEntity)

	self:spawn()

	return self
end

function MobEntity:spawn()
	if self.spawnLocation:GetAttribute("Active") == false then
		self.mobModel.Parent = self.folder
		self.mobModel.PrimaryPart.Position = Vector3.new(
			self.spawnLocation.Position.X,
			self.mobModel.PrimaryPart.Size.Y / 2,
			self.spawnLocation.Position.Z
		)

		self.spawnLocation:SetAttribute("Active", true)
		self.mobModel.Mesh.Attachment.MobNameGUI.MobName.Text = self.mobName

		local animationController = self.mobModel.AnimationController
		local animations = self.mobModel:WaitForChild("Animations")
		local idleAnimation = animationController:LoadAnimation(animations.Idle)
		idleAnimation.Looped = true
		idleAnimation:Play()
	end
end

function MobEntity:engaged(player: Player, playerWeapons: { [string]: any })
	if not self.mobModel then
		return
	end

	local animationController = self.mobModel.AnimationController
	local animations = self.mobModel:WaitForChild("Animations")
	local idleAnimation = animationController:LoadAnimation(animations.Idle)
	local engagedAnimation = animationController:LoadAnimation(animations.Engaged)

	if self.currentHealth == self.mobHealth and not self.canBeEngaged and self.damageDoneByPlayers[player.UserId] == nil then
		self.damageDoneByPlayers[player.UserId] = 0

		self.mobModel.Mesh.Attachment.Health.Enabled = true
		self:updateHealthBar(self.mobModel.Mesh.Attachment.Health, self.currentHealth, self.mobHealth)

		engagedAnimation:Play()
		task.wait(engagedAnimation.Length)
		engagedAnimation:Stop()

		idleAnimation.Looped = true
		idleAnimation:Play()

		self.canBeEngaged = true
	end

	if self.damageDoneByPlayers[player.UserId] ~= nil and self.canBeEngaged then
		self:attacked(player, playerWeapons)
	end

	if self.mobModel then
		self:updateHealthBar(self.mobModel.Mesh.Attachment.Health, self.currentHealth, self.mobHealth)
	end
end

function MobEntity:attacked(player: Player, playerWeapons: { [string]: any })
	if not (self and self.mobModel and self.mobModel.Mesh) then
		return
	end

	if self.currentHealth >= 0 then
		local animationController = self.mobModel.AnimationController
		local animations = self.mobModel:WaitForChild("Animations")
		local attackedAnimation = animationController:LoadAnimation(animations.Attacked)

		self:dealDamage(player, playerWeapons)
		self:updateHealthBar(self.mobModel.Mesh.Attachment.Health, self.currentHealth, self.mobHealth)

		attackedAnimation:Play()
		task.wait(attackedAnimation.Length)
	end

	if self.currentHealth <= self.mobHealth / 8 and self.currentHealth > 0 then
		local animationController = self.mobModel.AnimationController
		local animations = self.mobModel:WaitForChild("Animations")
		local dizzyAnimation = animationController:LoadAnimation(animations.Dizzy)

		dizzyAnimation:Play()
		task.wait(dizzyAnimation.Length)
	end

	if self.currentHealth <= 0 then
		self:updateHealthBar(self.mobModel.Mesh.Attachment.Health, self.currentHealth, self.mobHealth)
		self:handleDeath()
	end
end

function MobEntity:handleDeath()
	self.mobModel.Mesh.Attachment.MobNameGUI.MobName.Text = ""
	self.mobModel.Mesh.Attachment.MobNameGUI.MobName.TextColor3 = Color3.fromRGB(170, 0, 0)

	local animationController = self.mobModel.AnimationController
	local animations = self.mobModel:WaitForChild("Animations")
	local deathAnimation = animationController:LoadAnimation(animations.Death)

	deathAnimation:Play()
	task.wait(deathAnimation.Length)

	GameplayPacket.mobDeathFX.sendToAll({
		position = self.mobModel.Mesh.Position,
	})

	for userId in pairs(self.damageDoneByPlayers) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			GameplayPacket.mobDeath.sendTo({
				mob = self.mobModel.Mesh,
			}, player)
		end
	end

	self:dispenseRewards(self.damageDoneByPlayers)
	self:respawn()
end

function MobEntity:respawn()
	local newModel = ReplicatedStorage.Shared.Assets.Mobs[self.mobZone][self.mobName].Model:Clone()

	self.mobModel:Destroy()
	self.mobModel = newModel
	self.currentHealth = self.mobHealth

	table.clear(self.damageDoneByPlayers)
	task.wait(self.cooldown)

	self.spawnLocation:SetAttribute("Active", false)
	self.canBeEngaged = false

	self:spawn()
end

function MobEntity:dealDamage(player: Player, playerWeapons: { [string]: any })
	if not (playerWeapons and player and self.currentHealth > 0 and next(playerWeapons) ~= nil and self.mobModel) then
		return
	end

	if self.canBeEngaged then
		GameplayPacket.mobAttackFX.sendToAll({
			position = self.mobModel.Mesh.Position,
		})
	end

	for _, weapon in pairs(playerWeapons) do
		local defaultDamage = WeaponData.getDamage(weapon.weaponType, weapon.weaponName, nil)
		if type(defaultDamage) ~= "number" or defaultDamage <= 0 then
			continue
		end

		local sentDamage = rng:NextNumber(defaultDamage * 0.8, defaultDamage)
		if self.currentHealth - sentDamage <= 0 then
			sentDamage = self.currentHealth
		end

		self.currentHealth -= math.round(sentDamage)
		self.damageDoneByPlayers[player.UserId] += sentDamage
	end
end

function MobEntity:updateHealthBar(healthBar: any, currentHealth: number, totalHealth: number)
	if not healthBar then
		return
	end

	local healthBarSize = currentHealth / totalHealth

	if currentHealth < 0 then
		healthBar.HealthGUI.HealthNum.Text = (0 .. " / " .. totalHealth)
		self.mobModel.Mesh.Attachment.Health.Enabled = false
	else
		healthBar.HealthGUI.HealthNum.Text = (math.floor(currentHealth) .. " / " .. math.floor(totalHealth))
		healthBar.HealthGUI.HealthBar.Size = UDim2.new(healthBarSize, 0, 1, 0)
	end
end

function MobEntity:dispenseRewards(damageDoneByPlayers: { [number]: number })
	if not (damageDoneByPlayers and self.mobValue and self.mobHealth) then
		return
	end

	for userId, damage in pairs(damageDoneByPlayers) do
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			continue
		end

		local profile = DataHandler:getProfileAsync(player)
		if not profile then
			continue
		end

		local individualReward = (damage / self.mobHealth) * self.mobValue
		GameplayPacket.coinDrop.sendTo({
			origin = self.mobModel.PrimaryPart.CFrame,
			reward = individualReward,
		}, player)

		profile:giveCoins(math.round(individualReward))
	end
end

return MobEntity
