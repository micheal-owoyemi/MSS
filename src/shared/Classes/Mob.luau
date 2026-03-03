local MobClass = {}
MobClass.__index = MobClass

-- SERVICES
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

if RunService:IsClient() then
	error("MobClass is server-only")
end

-- MODULES
local DataHandler = require(ServerScriptService.Server.DataHandler)

local DataMobs = require(ReplicatedStorage.Shared.Data.Data_Mobs)
local DataWeapons = require(ReplicatedStorage.Shared.Data.Data_Weapons)
local NetworkApi = require(ReplicatedStorage.Shared.Network.NetworkApi)
local GameplayPacket = NetworkApi.Packets.Gameplay
local Trove = require(ReplicatedStorage.Shared.Trove)
local RNG = Random.new()

-- FUNCTIONS
function MobClass.new(mobZone: string, mobName: string, spawnLocation: Instance)
	local self = setmetatable({
		mobHealth = DataMobs[mobZone][mobName].Health,
		currentHealth = DataMobs[mobZone][mobName].Health,
		spawnLocation = spawnLocation,
		mobZone = mobZone,
		mobName = mobName,
		mobValue = DataMobs[mobZone][mobName].Value,
		mobModel = ReplicatedStorage.Shared.Assets.Mobs[mobZone][mobName].Model:Clone(),
		folder = workspace:WaitForChild("Game").Zones[mobZone].Mobs,

		cooldown = DataMobs[mobZone][mobName].Cooldown,
		canBeEngaged = false,
		damageDoneByPlayers = {},

		trove = Trove.new(),
	}, MobClass)

	self:spawn()

	return self
end

function MobClass:spawn()
	if self.spawnLocation:GetAttribute("Active") == false then
		self.mobModel.Parent = self.folder
		self.mobModel.PrimaryPart.Position =
			Vector3.new(self.spawnLocation.Position.X, self.mobModel.PrimaryPart.Size.Y / 2, self.spawnLocation.Position.Z)

		self.spawnLocation:SetAttribute("Active", true)

		self.mobModel.Mesh.Attachment.MobNameGUI.MobName.Text = self.mobName

		local animCont = self.mobModel.AnimationController
		local anims = self.mobModel:WaitForChild("Animations")
		local idleAnim = animCont:LoadAnimation(anims.Idle)

		self.trove:Add(self.mobModel)

		idleAnim.Looped = true
		idleAnim:Play()
	end
end

function MobClass:engaged(player: Player, playerWeapons)
	if not self.mobModel then
		return
	end

	local animCont = self.mobModel.AnimationController
	local anims = self.mobModel:WaitForChild("Animations")

	local idleAnim = animCont:LoadAnimation(anims.Idle)
	local engagedAnim = animCont:LoadAnimation(anims.Engaged)

	if self.currentHealth == self.mobHealth and not self.canBeEngaged and self.damageDoneByPlayers[player.UserId] == nil then
		if not self.damageDoneByPlayers[player.UserId] then
			self.damageDoneByPlayers[player.UserId] = 0
		end

		self.mobModel.Mesh.Attachment.Health.Enabled = true
		self:updateHPBar(self.mobModel.Mesh.Attachment.Health, self.currentHealth, self.mobHealth)

		engagedAnim:Play()
		task.wait(engagedAnim.Length)
		engagedAnim:Stop()

		idleAnim.Looped = true
		idleAnim:Play()

		self.canBeEngaged = true
	end

	if self.damageDoneByPlayers[player.UserId] ~= nil and self.canBeEngaged then
		self:attacked(player, playerWeapons)
	end

	if self.mobModel then
		self:updateHPBar(self.mobModel.Mesh.Attachment.Health, self.currentHealth, self.mobHealth)
	end
end

function MobClass:attacked(player: Player, playerWeapons)
	if not (self and self.mobModel and self.mobModel.Mesh) then
		return
	end

	if self.currentHealth >= 0 then
		local animCont = self.mobModel.AnimationController
		local anims = self.mobModel:WaitForChild("Animations")
		local attackedAnim = animCont:LoadAnimation(anims.Attacked)

		self:dealDamage(player, playerWeapons)
		self:updateHPBar(self.mobModel.Mesh.Attachment.Health, self.currentHealth, self.mobHealth)

		attackedAnim:Play()
		task.wait(attackedAnim.Length)
	end

	if self.currentHealth <= self.mobHealth / 8 and self.currentHealth > 0 then
		local animCont = self.mobModel.AnimationController
		local anims = self.mobModel:WaitForChild("Animations")
		local dizzyAnim = animCont:LoadAnimation(anims.Dizzy)

		dizzyAnim:Play()
		task.wait(dizzyAnim.Length)
	end

	if self.currentHealth <= 0 then
		self:updateHPBar(self.mobModel.Mesh.Attachment.Health, self.currentHealth, self.mobHealth)
		self:mobDeath()
	end
end

function MobClass:mobDeath()
	self.mobModel.Mesh.Attachment.MobNameGUI.MobName.Text = ""
	self.mobModel.Mesh.Attachment.MobNameGUI.MobName.TextColor3 = Color3.fromRGB(170, 0, 0)

	local animCont = self.mobModel.AnimationController
	local anims = self.mobModel:WaitForChild("Animations")

	local deathAnim = animCont:LoadAnimation(anims.Death)
	deathAnim:Play()
	task.wait(deathAnim.Length)

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

	if self.mobModel ~= nil then
		self:despawn()
	end
end

function MobClass:despawn()
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

function MobClass:dealDamage(player: Player, playerWeapons)
	if not (playerWeapons and player and self.currentHealth > 0 and next(playerWeapons) ~= nil and self.mobModel) then
		return
	end

	if self.canBeEngaged then
		GameplayPacket.mobAttackFX.sendToAll({
			position = self.mobModel.Mesh.Position,
		})
	end

	for _, weapon in pairs(playerWeapons) do
		local weaponByType = DataWeapons[weapon.weaponType]
		local weaponData = weaponByType and weaponByType[weapon.weaponName]
		local defaultDMG = weaponData and weaponData.Damage
		if type(defaultDMG) ~= "number" then
			continue
		end
		local sentDamage = RNG:NextNumber(defaultDMG * 0.8, defaultDMG)

		if sentDamage > defaultDMG then
			return
		end

		if (self.currentHealth - sentDamage) <= 0 then
			sentDamage = self.currentHealth
		end

		self.currentHealth -= math.round(sentDamage)
		self.damageDoneByPlayers[player.UserId] += sentDamage
	end
end

function MobClass:updateHPBar(healthBar, currentHealth, totalHealth)
	if healthBar then
		local healthBarSize = currentHealth / totalHealth

		if currentHealth < 0 then
			healthBar.HealthGUI.HealthNum.Text = (0 .. " / " .. totalHealth)
			self.mobModel.Mesh.Attachment.Health.Enabled = false
		else
			healthBar.HealthGUI.HealthNum.Text = (math.floor(currentHealth) .. " / " .. math.floor(totalHealth))
			healthBar.HealthGUI.HealthBar.Size = UDim2.new(healthBarSize, 0, 1, 0)
		end
	end
end

function MobClass:dispenseRewards(damageDoneByPlayers)
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

return MobClass
