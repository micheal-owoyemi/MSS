local WeaponClass = {}
WeaponClass.__index = WeaponClass

-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')

-- MODULES
local WeaponConfig = require(ReplicatedStorage.Shared.Configs.WeaponConfig)

-- FUNCTIONS
function WeaponClass.new(weaponType, weaponName, equipped, player)
    local self = setmetatable({
        weaponDMG = WeaponConfig[weaponType][weaponName].Damage,
        weaponType = weaponType,
        weaponName = weaponName,
        equipped = equipped,
        weaponModel = ReplicatedStorage.Shared.Assets.Weapons[weaponType][weaponName].Model:Clone(),
        player = player
    }, WeaponClass)
    
    if equipped == true then
        self.weaponModel.Parent = workspace.Weapons
    end
    
    self:interMovement()
    return self
end


function WeaponClass:interMovement()
    local character = self.player.Character or self.player.CharacterAdded:Wait()
    local relativeCFrame = CFrame.new(0, 3, 3)
    local lerpingSpeed = 0.15

    if self.equipped then
        RunService.RenderStepped:Connect(function()
            self.weaponModel.PrimaryPart.CFrame = self.weaponModel.PrimaryPart.CFrame:Lerp(character.HumanoidRootPart.CFrame * relativeCFrame, lerpingSpeed)
        end)
    else 
        return
    end

end


return WeaponClass