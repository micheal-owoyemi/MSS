-- Engaged mode (Initial Enaggement Anim)
-- Engaged Idle (Initial Anim, then hurt anim porportional to health)
-- Death (Death anim and destruction, dispersement of coins/xp/items)

local MobClass = {}
MobClass.__index = MobClass

-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local Players = game:GetService('Players')

-- MODULES
local MobConfig = require(ReplicatedStorage.Shared.Configs.MobConfig)
local Trove = require(ReplicatedStorage.Shared.Trove)
 
-- VARIABLES

-- FUNCTIONS
function MobClass.new(mobZone: string, mobName: string, spawnLocation: Instance)
    local self = setmetatable({
        mobHealth = MobConfig[mobZone][mobName].Health,
        spawnLocation = spawnLocation,
        mobZone = mobZone, 
        mobName = mobName,
        mobModel = ReplicatedStorage.Shared.Assets.Mobs[mobZone][mobName].Model:Clone(),
        folder =  workspace:WaitForChild('Zones')[mobZone].Mobs,

        cooldown = false,
        engaged = false,
        damageDoneByPlayers = {},

        trove = Trove.new()
    }, MobClass)

    self:spawn()

    return self
end

function MobClass:spawn()
    if self.spawnLocation:GetAttribute('Active') == false then -- If active == false due to cooldown etc then dont bring to workspace
        self.mobModel.Parent = self.folder
        self.mobModel.PrimaryPart.Position = Vector3.new(self.spawnLocation.Position.X, self.mobModel.PrimaryPart.Size.Y/2, self.spawnLocation.Position.Z)
        self.spawnLocation:SetAttribute('Active', true)

        local animCont = self.mobModel.AnimationController
        local anims = self.mobModel:WaitForChild('Animations')
        local idleAnim = animCont:LoadAnimation(anims.Idle)

        self.trove:Add(self.mobModel)

        idleAnim.Looped = true -- Initializes with idle Anim loop
        idleAnim:Play()
    else 
        return
    end
end

function MobClass:engaged()
    local animCont = self.mobModel.AnimationController
    local anims = self.mobModel:WaitForChild('Animations')

    local idleAnim = animCont:LoadAnimation(anims.Idle)
    local engagedAnim = animCont:LoadAnimation(anims.Engaged)

    if self.mobHealth == MobConfig[self.mobZone][self.mobName].Health then
        if idleAnim.IsPlaying then 
            idleAnim.Looped = false
            --idleAnim:Stop()
            engagedAnim:Play()
            task.wait(engagedAnim.Length)
            idleAnim.Looped = true
            idleAnim:Play()
        end
    end
end

function MobClass:despawn()
    self:Destroy()
end
return MobClass