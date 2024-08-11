local WeaponClass = {}
WeaponClass.__index = WeaponClass

-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')

-- MODULES
local WeaponConfig = require(ReplicatedStorage.Shared.Configs.WeaponConfig)
local PID = require(ReplicatedStorage.Shared.PID)
local Trove = require(ReplicatedStorage.Shared.Trove)

-- VARIABLES


-- FUNCTIONS
function WeaponClass.new(weaponType, weaponName, equipped, player)
    local self = setmetatable({
        weaponDMG = WeaponConfig[weaponType][weaponName].Damage,
        weaponType = weaponType,
        weaponName = weaponName,
        equipped = equipped,
        weaponModel = ReplicatedStorage.Shared.Assets.Weapons[weaponType][weaponName].Model:Clone(),
        player = player,
        character = player.Character or player.CharacterAdded:Wait(),
        trove = Trove.new(),
        pid = PID.new(0, 1, 0.0375, 0, 0),
        idle = require(ReplicatedStorage.Shared.FollowTypes.Idle),
        move = require(ReplicatedStorage.Shared.FollowTypes.Move),
        folder = workspace:WaitForChild('Weapons'):WaitForChild(player.Name)
    }, WeaponClass)
    
    if equipped == true then
        self.weaponModel.Parent = self.folder
    end
    
    self:setUpMovementDetection()

    return self
end

function WeaponClass:setUpMovementDetection()
    local humanoid = self.character:WaitForChild('Humanoid')
    local humanoidRootPart = self.character:WaitForChild('HumanoidRootPart')

    local movementConnection = RunService.RenderStepped:Connect(function(dt)
        if humanoid.MoveDirection.Magnitude > 0 then
            print('pi')
            self.move(self.folder, self.character, humanoidRootPart, humanoid, self.weaponModel, 0.03)
            
        else

        end
    end)

end

function WeaponClass:interState()
    
end

return WeaponClass