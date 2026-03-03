local WeaponClient = {}
WeaponClient.__index = WeaponClient

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local WeaponData = require(ReplicatedStorage.Shared.Utilities.WeaponData)
local NetworkApi = require(ReplicatedStorage.Shared.Network.NetworkApi)
local MobData = require(ReplicatedStorage.Shared.Data.Data_Mobs)
local GameWorld = require(ReplicatedStorage.Shared.Utilities.GameWorld)
local WeaponReplicationPayload = require(ReplicatedStorage.Shared.Utilities.WeaponReplicationPayload)

local WeaponPacket = NetworkApi.Packets.Weapon

local mobCursor = MobData.Settings.MobCursor
local mobMinDistance = MobData.Settings.MinimumDistance

function WeaponClient.new(uuid: string, weaponType: string, weaponName: string, equipped: boolean, player: Player)
	local weaponDamage = WeaponData.getDamage(weaponType, weaponName, 0)
	local playerWeaponsFolder = GameWorld.getPlayerWeaponsFolder(player.UserId, false)
		or GameWorld.waitForPlayerWeaponsFolder(player.UserId)
	if not playerWeaponsFolder then
		error(string.format("[WeaponClient] Missing weapons folder for player %s", tostring(player.UserId)))
	end

	local self = setmetatable({
		uuid = uuid,
		weaponDamage = weaponDamage,
		weaponType = weaponType,
		weaponName = weaponName,
		weaponModel = ReplicatedStorage.Shared.Assets.Weapons[weaponType][weaponName].Model:Clone(),
		folder = playerWeaponsFolder,
		equipped = equipped,
		engaged = false,
		target = nil,
		replicationInterval = 0.1,
		lastReplicatedAt = 0,
		player = player,
		character = player.Character or player.CharacterAdded:Wait(),
		idleRenderStepName = `WeaponRender_{uuid}`,
		mobRenderStepName = `MobWeaponRender_{uuid}`,
		mobFollow = require(script.Parent.FollowTypes.MobFollow),
		idleFollow = require(script.Parent.FollowTypes.IdleFollow),
		moveFollow = require(script.Parent.FollowTypes.MoveFollow),
	}, WeaponClient)

	self.weaponModel.Name = uuid

	if equipped == true then
		self.weaponModel.Parent = self.folder
		self:updateCursor(player)
		self:setUpMovementDetection()
		self:setUpInteractionDetection(self.player)
	end

	return self
end

function WeaponClient:setUpMobInteraction(target: MeshPart)
	if target == self.target and self.engaged then
		self:disengageMob(target)
		return
	end

	if target and not self.target and not self.engaged then
		self:engageMob(target)
		return
	end
end

function WeaponClient:disengageMob(target: MeshPart)
	if target == self.target and self.engaged then
		self.target = nil
		self.engaged = false
		RunService:UnbindFromRenderStep(self.mobRenderStepName)
		self:setUpMovementDetection()
	end
end

function WeaponClient:engageMob(target: MeshPart)
	self.engaged = true
	self.target = target

	local character = self.player.Character
	local animator = character:WaitForChild("Humanoid"):WaitForChild("Animator")
	local animations = character.CustomAnimations
	local commandAnimation = animator:LoadAnimation(animations.WeaponCommandWalk)

	commandAnimation:Play()
	task.wait(commandAnimation.Length / 4)
	RunService:UnbindFromRenderStep(self.idleRenderStepName)

	local function onMobWeaponRender()
		self.mobFollow(self.folder, target, self.weaponModel, 0.03)
	end

	RunService:UnbindFromRenderStep(self.mobRenderStepName)
	RunService:BindToRenderStep(self.mobRenderStepName, 0, onMobWeaponRender)
end

function WeaponClient:setUpMovementDetection()
	local humanoid = self.character:WaitForChild("Humanoid")
	local humanoidRootPart = self.character:WaitForChild("HumanoidRootPart")

	if not self.engaged and not self.target then
		local function onWeaponRender()
			if humanoid.MoveDirection.Magnitude > 0 then
				self.moveFollow(self.folder, self.character, humanoidRootPart, humanoid, self.weaponModel, 0.03)

				local now = os.clock()
				if now - self.lastReplicatedAt >= self.replicationInterval then
					local payload = WeaponReplicationPayload.fromWeaponModel(self.player.UserId, self.uuid, self.weaponModel)
					if payload then
						WeaponPacket.updateWeaponState.send(payload)
						self.lastReplicatedAt = now
					end
				end
			else
				self.idleFollow(self.folder, self.character, humanoidRootPart, humanoid, self.weaponModel, 0.03)
			end
		end

		RunService:UnbindFromRenderStep(self.idleRenderStepName)
		RunService:BindToRenderStep(self.idleRenderStepName, 0, onWeaponRender)
	end
end

function WeaponClient:setUpInteractionDetection(player: Player)
	if not player then
		return
	end

	local playerMouse = player:GetMouse()
	if playerMouse then
		playerMouse.Button1Down:Connect(function()
			local target = playerMouse.Target
			if target and target:IsA("MeshPart") and target:GetAttribute("Mob") then
				self:setUpMobInteraction(target)
			end
		end)
	end
end

function WeaponClient:updateCursor(player: Player)
	local lastMobInstance = nil
	if not (player and player:GetMouse()) then
		return
	end

	local playerMouse = player:GetMouse()
	playerMouse.Move:Connect(function()
		local target = playerMouse.Target
		local defaultCursor = ""

		if target and target:IsA("MeshPart") and target:GetAttribute("Mob") and target.Highlight then
			if not self.target then
				local distance = player:DistanceFromCharacter(target.Position)
				if distance <= mobMinDistance then
					if lastMobInstance and #lastMobInstance:GetChildren() > 0 then
						lastMobInstance.Highlight.Enabled = false
						lastMobInstance = nil
					end

					UserInputService.MouseIcon = mobCursor
					target.Highlight.Enabled = true
					lastMobInstance = target
				end
			elseif self.target == target then
				UserInputService.MouseIcon = mobCursor
				target.Highlight.Enabled = true
				lastMobInstance = target
			else
				UserInputService.MouseIcon = defaultCursor
				if lastMobInstance and lastMobInstance.Highlight then
					lastMobInstance.Highlight.Enabled = false
					lastMobInstance = nil
				end
			end
		else
			UserInputService.MouseIcon = defaultCursor
			if lastMobInstance and #lastMobInstance:GetChildren() > 0 and lastMobInstance.Highlight then
				lastMobInstance.Highlight.Enabled = false
				lastMobInstance = nil
			end
		end
	end)
end

function WeaponClient:despawn()
	RunService:UnbindFromRenderStep(self.idleRenderStepName)
	RunService:UnbindFromRenderStep(self.mobRenderStepName)
	self.weaponModel:Destroy()

	setmetatable(self, nil)
	table.clear(self)
	table.freeze(self)
end

return WeaponClient
