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
local RemoteEvents = ReplicatedStorage.Shared:WaitForChild('RemoteEvents')

local MobDeathRE = RemoteEvents.MobDeath
local MobDeathFXRE = RemoteEvents.MobDeathFX
local MobAttackFXRE = RemoteEvents.AttackMobFX
local CoinDropRE = RemoteEvents.CoinDrop

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

        self.trove:Add(self.trove, self.mobModel)

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

        if self.currentHealth == self.mobHealth and not self.canBeEngaged and self.damageDoneByPlayers[Player.UserId] == nil then

            print( self.damageDoneByPlayers[Player.UserId])

            if not self.damageDoneByPlayers[Player.UserId] then self.damageDoneByPlayers[Player.UserId] = 0 end

            self.mobModel.Mesh.Attachment.Health.Enabled = true
            self:updateHPBar(self.mobModel.Mesh.Attachment.Health, self.currentHealth, self.mobHealth)

            engagedAnim:Play()
            task.wait(engagedAnim.Length)
            engagedAnim:Stop()

            idleAnim.Looped = true
            idleAnim:Play()

            self.canBeEngaged = true

        else
            print(self.currentHealth, self.mobHealth, self.canBeEngaged, self.damageDoneByPlayers[Player.UserId])
        end 

        if self.damageDoneByPlayers[Player.UserId] ~= nil and self.canBeEngaged then
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
        if self.currentHealth >= 0 then

            local animCont = self.mobModel.AnimationController
            local anims = self.mobModel:WaitForChild('Animations')
            local attackedAnim = animCont:LoadAnimation(anims.Attacked)
        
            self:dealDamage(Player, playerWeapons)
            self:updateHPBar(self.mobModel.Mesh.Attachment.Health, self.currentHealth, self.mobHealth)

            attackedAnim:Play()
            task.wait(attackedAnim.Length)
        end

        -- DIZZY TRIGGER
        if self.currentHealth <= self.mobHealth / 8  and self.currentHealth > 0 then
            local animCont = self.mobModel.AnimationController
            local anims = self.mobModel:WaitForChild('Animations')
            local dizzyAnim = animCont:LoadAnimation(anims.Dizzy)
        
            dizzyAnim:Play()
            task.wait(dizzyAnim.Length)

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

    self.mobModel.Mesh.Attachment.MobNameGUI.MobName.Text = ''
    self.mobModel.Mesh.Attachment.MobNameGUI.MobName.TextColor3 = Color3.new(170, 0, 0)

    local animCont = self.mobModel.AnimationController
    local anims = self.mobModel:WaitForChild('Animations')

    local deathAnim = animCont:LoadAnimation(anims.Death)

    deathAnim:Play()
    task.wait(deathAnim.Length)

    MobDeathFXRE:FireAllClients(self.mobModel.Mesh.Position)

    print(self.damageDoneByPlayers)

    if self.damageDoneByPlayers then 
        for i, damage in self.damageDoneByPlayers do

            print(i)
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
    self.canBeEngaged = false

    self:spawn()

end


function MobClass:dealDamage(Player, playerWeapons)
    if playerWeapons and Player and self.currentHealth > 0 and #playerWeapons >= 1 and self.mobModel then

        if self.canBeEngaged then
            MobAttackFXRE:FireAllClients(self.mobModel.Mesh.Position)
        end

        for _, weapon in playerWeapons do
            local defaultDMG = WeaponConfig[weapon.weaponType][weapon.weaponName].Damage
            local sentDamage = (math.random(defaultDMG *0.8, defaultDMG))

            if sentDamage > defaultDMG then return end


            if (self.currentHealth - sentDamage) <= 0 then
                sentDamage = (self.currentHealth)
            end

            self.currentHealth -= math.round(sentDamage)
            self.damageDoneByPlayers[Player.UserId] += sentDamage
        end
    end
end

function MobClass:updateHPBar(healthBar, currentHealth, totalHealth)
    if healthBar then
        local healthBarSize = currentHealth / totalHealth

        if currentHealth < 0 then
            healthBar.HealthGUI.HealthNum.Text = (0 ..' / '.. totalHealth)
            self.mobModel.Mesh.Attachment.Health.Enabled = false
        else
            healthBar.HealthGUI.HealthNum.Text = (math.floor(currentHealth) ..' / '.. math.floor(totalHealth))
            healthBar.HealthGUI.HealthBar.Size = UDim2.new(healthBarSize, 0, 1, 0)
        end
    end
end

-- Remote Event for Mob Defeat Reward Distribution
function MobClass:dispenseRewards(damageDoneByPlayers)
    if damageDoneByPlayers and self.mobValue and self.mobHealth then
        for i, damage in damageDoneByPlayers do
            local profile = DataHandler:getProfileAsync(Players:GetPlayerByUserId(i))
            if not profile then
                return
            end
        
            local individualReward = (damage / self.mobHealth) * self.mobValue
            
            CoinDropRE:FireClient(Players:GetPlayerByUserId(i), self.mobModel.PrimaryPart.CFrame, individualReward )

            profile:giveCoins(math.round(individualReward))
        end
    end
end





return MobClass
