local PetClass = {}
PetClass.__index = PetClass

-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
-- MODULES


-- FUNCTIONS
function PetClass.new(petType, petName, player)
    local self = setmetatable({
        petType = petType,
        petName = petName,
        petModel = ReplicatedStorage.Shared.Assets.Weapons[petType][petName].Model:Clone(),
        player = player
    }, PetClass)

    self.petModel.Parent = workspace
    self:interMovement()
    return self
end


function PetClass:interMovement()
    local character = self.player.Character
    local relativeCFrame = CFrame.new(0, 3, 3) -- Gives effect of floating behind player // Offset
    local lerpingSpeed = 0.15

    RunService.RenderStepped:Connect(function()
        self.petModel.PrimaryPart.CFrame = self.petModel.PrimaryPart.CFrame:Lerp(character.HumanoidRootPart.CFrame * relativeCFrame, lerpingSpeed)
    end)
end

return PetClass