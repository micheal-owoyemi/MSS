local WeaponClass = {}
WeaponClass.__index = WeaponClass

-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')

-- MODULES
local WeaponConfig = require(ReplicatedStorage.Shared.Configs.WeaponConfig)
local MobConfig =  require(ReplicatedStorage.Shared.Configs.MobConfig)

local PID = require(ReplicatedStorage.Shared.PID)
local Trove = require(ReplicatedStorage.Shared.Trove)

-- VARIABLES
local mobCursor = MobConfig.Settings.MobCursor
local mobMinDistance = MobConfig.Settings.MinimumDistance

-- FUNCTIONS
function WeaponClass.new(weaponType: string, weaponName: string, equipped: boolean, player: Player)
    local self = setmetatable({
        weaponDMG = WeaponConfig[weaponType][weaponName].Damage,
        weaponType = weaponType,
        weaponName = weaponName,
        weaponModel = ReplicatedStorage.Shared.Assets.Weapons[weaponType][weaponName].Model:Clone(),
        folder = workspace:WaitForChild('Weapons'):WaitForChild(player.Name),

        equipped = equipped,
        engaged = false,
        target = nil,

        player = player,
        character = player.Character or player.CharacterAdded:Wait(),

        trove = Trove.new(),
        pid = PID.new(0, 1, 0.0375, 0, 0),

        mobIdle = require(ReplicatedStorage.Shared.FollowTypes.Mob),
        idle = require(ReplicatedStorage.Shared.FollowTypes.Idle),
        move = require(ReplicatedStorage.Shared.FollowTypes.Move),
        

    }, WeaponClass)
    
    if equipped == true then  
        self.weaponModel.Parent = self.folder
        self:updateCursor(player)
        self:setUpMovementDetection()
        self:setUpInteractionDetection(self.player)
    end

    return self
end

function WeaponClass:setUpMobInteraction(target: MeshPart)
    if target == self.target and self.engaged then
        self:disengageMob(target)
        return
    end

    if target and not self.target and not self.engaged then
        self:engageMob(target)
        return
    end
end
 
function WeaponClass:disengageMob(target: MeshPart)
    if target == self.target and self.engaged then
        self.target = nil
        self.engaged = false
        RunService:UnbindFromRenderStep("Mob Weapon Render")
        
        self:setUpMovementDetection()
    end
end

function WeaponClass:engageMob(target: MeshPart)
    self.engaged = true
    self.target = target
    self:setupTargetDetection()
    RunService:UnbindFromRenderStep('Weapon Render')

    local function mobWeaponRender(dt)
        self.mobIdle(self.folder, target, self.weaponModel, 0.03)
    end

    RunService:BindToRenderStep('Mob Weapon Render', 0, mobWeaponRender)
end



function WeaponClass:setUpMovementDetection()
    local humanoid = self.character:WaitForChild('Humanoid')
    local humanoidRootPart = self.character:WaitForChild('HumanoidRootPart')

    if not self.engaged and not self.target then
        local function weaponRender(dt)
            if humanoid.MoveDirection.Magnitude > 0 then
                self.move(self.folder, self.character, humanoidRootPart, humanoid, self.weaponModel, 0.03)
                
            else
                self.idle(self.folder, self.character, humanoidRootPart, humanoid, self.weaponModel, 0.03)
            end
        end
    
        RunService:BindToRenderStep('Weapon Render', 0, weaponRender)
    end
end

function WeaponClass:setupTargetDetection()
	local connection = nil 
	
	connection = RunService.RenderStepped:Connect(function()
		if self.target then
			if self.player:DistanceFromCharacter(self.target.Position) > mobMinDistance/2 then
                self.target = nil
                self.engaged = false
				self:setUpInteractionDetection(self.player)
				self:setUpMovementDetection()
				RunService:UnbindFromRenderStep("Mob Weapon Render")
				connection:Disconnect()	
			end
		end
	end)
end

function WeaponClass:setUpInteractionDetection(player: Player)
    if player then
        local playerMouse = player:GetMouse()
        if playerMouse then
            playerMouse.Button1Down:Connect(function()
                local target = playerMouse.Target
                
                if target:IsA('MeshPart') then
                    if target:GetAttribute('Mob') then
                        self:setUpMobInteraction(target)
                    end
                end
            end)
        end
    end
end

function WeaponClass:updateCursor(player: Player) -- MAKE THIS BETTER!!
    local lastMobInstance = nil
    if player and player:GetMouse() then
        local playerMouse = player:GetMouse()

        local updateCursorConnection = RunService.RenderStepped:Connect(function(dt)
            local target = playerMouse.Target


            if target and target:IsA('MeshPart') and target:GetAttribute('Mob') then

                if target:GetAttribute('Mob') then
                    local distance = player:DistanceFromCharacter(target.Position)
                    if distance <= mobMinDistance then

                        if lastMobInstance then
                            lastMobInstance.Highlight.Enabled = false
                            lastMobInstance = nil
                        end

                        UserInputService.MouseIcon = mobCursor
                        target.Highlight.Enabled = true
                        lastMobInstance = target
                    end
                else
                    UserInputService.MouseIcon = ''
                    if lastMobInstance then
                        lastMobInstance.Highlight.Enabled = false
                        lastMobInstance = nil
                    end
                    
                end
            else
                UserInputService.MouseIcon = ''
                if lastMobInstance then
                    lastMobInstance.Highlight.Enabled = false
                    lastMobInstance = nil
                end
            end
        end)
    end
end


function WeaponClass:interState()
    
end

return WeaponClass