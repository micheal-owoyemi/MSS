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
local WeaponConfig = require(ReplicatedStorage.Shared.Configs.WeaponConfig)
local Trove = require(ReplicatedStorage.Shared.Trove)
 
-- FUNCTIONS
function MobClass.new(mobZone: string, mobName: string, spawnLocation: Instance)
    local self = setmetatable({
        mobHealth = MobConfig[mobZone][mobName].Health,
        currentHealth = MobConfig[mobZone][mobName].Health,
        spawnLocation = spawnLocation,
        mobZone = mobZone, 
        mobName = mobName,
        mobModel = ReplicatedStorage.Shared.Assets.Mobs[mobZone][mobName].Model:Clone(),
        folder =  workspace:WaitForChild('Zones')[mobZone].Mobs,

        cooldown = false,
        isEngaged = false,
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
        
        self.mobModel.Mesh.Attachment.MobNameGUI.MobName.Text = self.mobName

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

function MobClass:engaged(Player, playerWeapons)
    local animCont = self.mobModel.AnimationController
    local anims = self.mobModel:WaitForChild('Animations')

    local idleAnim = animCont:LoadAnimation(anims.Idle)
    local engagedAnim = animCont:LoadAnimation(anims:WaitForChild('Engaged'))

    if self.currentHealth == self.mobHealth and self.damageDoneByPlayers[Player.UserId] == nil then
        self.damageDoneByPlayers[Player.UserId] = 0

        self.mobModel.Mesh.Attachment.Health.Enabled = true
        self:updateHPBar(self.mobModel.Mesh.Attachment.Health, self.currentHealth, self.mobHealth)

        idleAnim.Looped = false
        idleAnim:Stop()

        engagedAnim:Play()
        task.wait(engagedAnim.Length)
        engagedAnim:Stop()

        idleAnim.Looped = true
        idleAnim:Play()
    end 

    print(playerWeapons)
    self:attacked(Player, playerWeapons)

    self:updateHPBar(self.mobModel.Mesh.Attachment.Health, self.currentHealth, self.mobHealth)
end

function MobClass:dealDamage(Player, playerWeapons)
    if playerWeapons and Player then
        for _, weapon in playerWeapons do
            if self.currentHealth <= 0 then
                return
            else
                self.currentHealth -= WeaponConfig[weapon.weaponType][weapon.weaponName].Damage
                self.damageDoneByPlayers[Player.UserId] += WeaponConfig[weapon.weaponType][weapon.weaponName].Damage
            end
        end
    end
end

function MobClass:attacked(Player, playerWeapons)
    -- NORMAL ATTACK
    if self.currentHealth > 0 and self.currentHealth > self.mobHealth / 10 then

        self:dealDamage(Player, playerWeapons)

        local animCont = self.mobModel.AnimationController
        local anims = self.mobModel:WaitForChild('Animations')
    
        local idleAnim = animCont:LoadAnimation(anims.Idle)
        local attackedAnim = animCont:LoadAnimation(anims.Attacked)
    
        idleAnim.Looped = false
        idleAnim:Stop()
    
        attackedAnim:Play()
        task.wait(attackedAnim.Length)
        attackedAnim:Stop()
    
        idleAnim.Looped = true
        idleAnim:Play()
    end

    -- DIZZY TRIGGER
    if self.currentHealth <= self.mobHealth / 10 and self.currentHealth > 0 then

        self:dealDamage(Player, playerWeapons)

        local animCont = self.mobModel.AnimationController
        local anims = self.mobModel:WaitForChild('Animations')
    
        local idleAnim = animCont:LoadAnimation(anims.Idle)
        local dizzyAnim = animCont:LoadAnimation(anims.Dizzy)

        idleAnim.Looped = false
        idleAnim:Stop()

        dizzyAnim.Looped = true
        dizzyAnim:Play()
    end

    -- DEATH TRIGGER
    if self.currentHealth <= 0 then
        self:updateHPBar(self.mobModel.Mesh.Attachment.Health, self.currentHealth, self.mobHealth)
        self:mobDeath()
        return
    end
end

function MobClass:mobDeath()

    self.mobModel.Mesh.Attachment.MobNameGUI.MobName.Text = '[ DEFEATED ]'
    self.mobModel.Mesh.Attachment.MobNameGUI.MobName.TextColor3 = Color3.new(170, 0, 0)

    local animCont = self.mobModel.AnimationController
    local anims = self.mobModel:WaitForChild('Animations')

    local dizzyAnim = animCont:LoadAnimation(anims.Dizzy)
    local deathAnim = animCont:LoadAnimation(anims.Death)

    dizzyAnim.Looped = false

    deathAnim:Play()
    task.wait(3)
    print(self.damageDoneByPlayers)
    -- Disengage all players engaged
    -- FIRE REWARD DISPENSTION

    self:despawn()

end


function MobClass:updateHPBar(healthBar, currentHealth, totalHealth)
    if healthBar then
        local healthBarSize = currentHealth / totalHealth

        if currentHealth < 0 then
            healthBar.HealthGUI.HealthNum.Text = (0 ..' / '.. totalHealth)
        else
            healthBar.HealthGUI.HealthNum.Text = (math.floor(currentHealth) ..' / '.. math.floor(totalHealth))
            healthBar.HealthGUI.HealthBar.Size = UDim2.new(healthBarSize, 0, 1, 0)
        end
    end
end

function MobClass:despawn()
    self.mobModel:Destroy()

    setmetatable(self, nil)
    table.clear(self)
    table.freeze(self)
end



return MobClass