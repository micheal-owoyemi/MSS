-- Engaged mode (Initial Enaggement Anim)
-- Engaged Idle (Initial Anim, then hurt anim porportional to health)
-- Death (Death anim and destruction, dispersement of coins/xp/items)

local MobClass = {}
MobClass.__index = MobClass

-- SERVICES
local ServerScriptService = game:GetService('ServerScriptService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local Players = game:GetService('Players')
local TweenService = game:GetService('TweenService')

-- MODULES
local DataHandler = require(ServerScriptService.Server.DataHandler)

local MobConfig = require(ReplicatedStorage.Shared.Configs.MobConfig)
local WeaponConfig = require(ReplicatedStorage.Shared.Configs.WeaponConfig)

local CoinDrop = require(ReplicatedStorage.Shared.Classes.CoinDrop)
local Trove = require(ReplicatedStorage.Shared.Trove)
 
-- VARIABLES
local RemoteEvents = ReplicatedStorage.Shared.RemoteEvents

local MobDeathRE = RemoteEvents:WaitForChild('MobDeath')

-- FUNCTIONS
function MobClass.new(mobZone: string, mobName: string, spawnLocation: Instance)
    local self = setmetatable({
        mobHealth = MobConfig[mobZone][mobName].Health,
        currentHealth = MobConfig[mobZone][mobName].Health,
        spawnLocation = spawnLocation,
        mobZone = mobZone, 
        mobName = mobName,
        mobValue = MobConfig[mobZone][mobName].Value,
        mobModel = ReplicatedStorage.Shared.Assets.Mobs[mobZone][mobName].Model:Clone(),
        folder =  workspace:WaitForChild('Zones')[mobZone].Mobs,

        cooldown = MobConfig[mobZone][mobName].Cooldown,
        canBeEngaged = false,
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
    if self.mobModel then
        local animCont = self.mobModel.AnimationController
        local anims = self.mobModel:WaitForChild('Animations')

        local idleAnim = animCont:LoadAnimation(anims.Idle)
        local engagedAnim = animCont:LoadAnimation(anims.Engaged)

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

        if self.damageDoneByPlayers[Player.UserId] ~= nil then
            self:attacked(Player, playerWeapons)

        end
    
        if self.mobModel then
            self:updateHPBar(self.mobModel.Mesh.Attachment.Health, self.currentHealth, self.mobHealth)
        end
    end
end

function MobClass:attacked(Player, playerWeapons)
    if self and self.mobModel and self.mobModel.Mesh then
        
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

        
            idleAnim.Looped = true
            idleAnim:Play()
        end

        -- DIZZY TRIGGER
        if self.currentHealth <= self.mobHealth / 10  and self.currentHealth > 0 then

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
end


function MobClass:mobDeath()

    self.mobModel.Mesh.Attachment.MobNameGUI.MobName.Text = '[ DEFEATED ]'
    self.mobModel.Mesh.Attachment.MobNameGUI.MobName.TextColor3 = Color3.new(170, 0, 0)

    local animCont = self.mobModel.AnimationController
    local anims = self.mobModel:WaitForChild('Animations')

    local dizzyAnim = animCont:LoadAnimation(anims.Dizzy)
    local deathAnim = animCont:LoadAnimation(anims.Death)

    dizzyAnim.Looped = false
    dizzyAnim:Stop()

    deathAnim:Play()

    self:tweenMeshTransparency(3)
    task.wait(3)

    
    if self.damageDoneByPlayers then
        for i, player in self.damageDoneByPlayers do
            MobDeathRE:FireClient(Players:GetPlayerByUserId(i), self.mobModel.Mesh)
        end

        self:dispenseRewards(self.damageDoneByPlayers)
    end

    if self.mobModel ~= nil then
        self:despawn()
    else
        return
    end
end

function MobClass:despawn()
    -- Deletes Current Mob Model instance then resets current mob object instance stats with default stats

    local newModel = ReplicatedStorage.Shared.Assets.Mobs[self.mobZone][self.mobName].Model:Clone()


    self.mobModel:Destroy()
    self.mobModel = nil
    self.mobModel = newModel

    self.currentHealth = self.mobHealth

    table.clear(self.damageDoneByPlayers)

    task.wait(self.cooldown)

    self.spawnLocation:SetAttribute('Active', false)

    self:spawn()

end


function MobClass:dealDamage(Player, playerWeapons)
    if playerWeapons and Player then
        for _, weapon in playerWeapons do
            if self.currentHealth <= 0 then
                return
            else
                local defaultDMG = WeaponConfig[weapon.weaponType][weapon.weaponName].Damage
                local sentDamage = math.random(defaultDMG /0.9, defaultDMG)

                self.currentHealth -= sentDamage

                self.damageDoneByPlayers[Player.UserId] += sentDamage
            end
        end
    end
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

function MobClass:tweenMeshTransparency(deathDur)
    local tweenInfo = TweenInfo.new(deathDur)
    local tween = TweenService:Create(self.mobModel.Mesh, tweenInfo, {
        Transparency = 1
    })

    tween:Play()
end

-- Remote Event for Mob Defeat Reward Distribution
function MobClass:dispenseRewards(damageDoneByPlayers)
    if damageDoneByPlayers and self.mobValue and self.mobHealth then
        for i, damage in damageDoneByPlayers do
            local profile = DataHandler:getProfileAsync(Players:GetPlayerByUserId(i))
            if not profile then
                return
            end
        
            local shareOfReward = (damage / self.mobHealth) * self.mobValue
        
            profile:giveCoins(shareOfReward)
            
            local coinDropModel = ReplicatedStorage.Shared:WaitForChild('Assets').VFX.CoinDrop:Clone()
            local coinDropInstance = CoinDrop.spawn(self.mobModel.PrimaryPart.CFrame, coinDropModel, shareOfReward, Players:GetPlayerByUserId(i))

        end
    end
end





return MobClass
