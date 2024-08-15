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
        target = player,

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
        self:checkMouseTarget(self.player)
    end

    return self
end

function WeaponClass:setUpMovementDetection()
    local humanoid = self.character:WaitForChild('Humanoid')
    local humanoidRootPart = self.character:WaitForChild('HumanoidRootPart')

    local function weaponRender(dt)
        if humanoid.MoveDirection.Magnitude > 0 then
            self.move(self.folder, self.character, humanoidRootPart, humanoid, self.weaponModel, 0.03)
            
        else
            self.idle(self.folder, self.character, humanoidRootPart, humanoid, self.weaponModel, 0.03)
        end
    end

    RunService:BindToRenderStep('Weapon Render', 0, weaponRender)
end

function WeaponClass:checkMouseTarget(player: Player)
    if player then
        local playerMouse = player:GetMouse()
        if playerMouse then
                playerMouse.Button1Down:Connect(function()
                    local target = playerMouse.Target
                    if target:IsA('MeshPart') then
                       if target:GetAttribute('Mob') then
                            self.engaged = true
                            self.target = target
                            RunService:UnbindFromRenderStep('Weapon Render')

                            local function mobWeaponRender(dt)
                                self.mobIdle(self.folder, target, self.weaponModel, 0.03)
                            end

                            RunService:BindToRenderStep('Mob Weapon Render', 0, mobWeaponRender)
                    end
                end
            end)
        end
    end
end

function WeaponClass:updateCursor(player: Player)
    if player and player:GetMouse() then
        local playerMouse = player:GetMouse()

        local updateCursorConnection = RunService.RenderStepped:Connect(function(dt)
            local target = playerMouse.Target

            if target ~= nil and target:IsA('MeshPart') then
                if target:GetAttribute('Mob') then
                    local distance = player:DistanceFromCharacter(target.Position)
                    if distance <= mobMinDistance then
                        UserInputService.MouseIcon = mobCursor
                    end
                else
                    UserInputService.MouseIcon = ''
                end
            else
                UserInputService.MouseIcon = ''
            end
        end)
    end
end

function WeaponClass:interState()
    
end

function WeaponClass:engageMob(targetMob)
    
end



--[[So on the client-side you would do Player:GetMouse() 
and you would use the Mouse to detect when they click their mouse button, and then check mouse.target   
 if it's a Mob, then you would basically cancel the movement detection and send them over to mob ]]


return WeaponClass