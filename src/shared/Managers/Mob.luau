--[[ When you do mobclass.new, you can do local newMob = mobClass.new() and then it returns the new mob, then you can store and reference it

]]


local MobManager = {}
MobManager.__index = MobManager

-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local ServerScriptService = game:GetService('ServerScriptService')


-- MODULES
local DataHandler = require(ServerScriptService.Server.DataHandler)

local ZonePlus = require(ReplicatedStorage.Shared:WaitForChild('Zone'))
local MobClass = require(ReplicatedStorage.Shared.Classes.Mob)
local Trove = require(ReplicatedStorage.Shared.Trove)

local WeaponConfig = require(ReplicatedStorage.Shared.Configs.WeaponConfig)

-- VARIABLES
local zones = workspace:WaitForChild('Zones')


-- FUNCTIONS

function MobManager.new()
    local self = setmetatable({
        trove = Trove.new(),
        mobInstances = {},
        canSpawn = false
    }, MobManager)

    return self
end
function MobManager:checkEquipped()

end
function MobManager:spawnMob(mobZone: string, mobName: string, spawnLocation: Instance)
    local mobInstance = MobClass.new(mobZone, mobName, spawnLocation)
    table.insert(self.mobInstances, mobInstance)
end

function MobManager:despawnMob(mobInstance)
    mobInstance:Destory()
end

function MobManager:setUpZoneSpawning()
    for _, area in zones:GetChildren() do
        
        local container = area.Container
        local zone = ZonePlus.new(container)
        zone:setAccuracy('Low')
    
        zone.playerEntered:Connect(function(player)
            
            local zoneParts = zone:getParts()

            for _, part in zoneParts do
                if part:IsA('Part') and part:GetAttribute('Mob') then
                    if not part:GetAttribute('Active') then
                        local mobInstance = self:spawnMob(tostring(area), tostring(part:GetAttribute('Mob')), part) 
                        table.insert(self.mobInstances, mobInstance)
                        task.wait(1) -- Bandaid for smoother spawning

                        part:SetAttribute('Active', true)
                    end

                    if self.mobInstances == #area['Spawn Points']:GetChildren() then
                        return
                    end
                    
                end
            end
        end)
    end
end

function MobManager:setUpZoneDespawning()
--[[    zone.playerExited:Connect(function(player)
        local playersArray = zone:getPlayers()
        
        if #playersArray == 0 then
            print('Beginning Countdown till, despawn')
            task.wait(5 + #area['Spawn Points']:GetChildren())

            playersArray = zone:getPlayers()

            if #playersArray == 0 then
                local newTable = {}

                self.canSpawn = false
                for i, mob in self.mobInstances do
                    if mob.mobZone == area.Name then
                        mob:despawn()
                    else
                        table.insert(newTable, mob)
                    end
                end

                self.mobInstances = nil
                self.mobInstances = newTable

                print(self.mobInstances)
            else
                return
            end

        end
    end)]]
end
 
function MobManager:attackMob(Player, mobInstance, playerWeapons) --Player, mobInstance
    --[[
    check HP if > 0
    Server Check equipped weapons
    everytime damage dealt update damageDoneByPlayers table

    increments play dizzy
    on final threshold loop dizzy then play death
    despawn
    dispense rewards
        ]]
    
    for _, mob in self.mobInstances do
        if mob.mobModel == mobInstance.Parent then
            if not mob.isEngaged and playerWeapons then
                print(playerWeapons)
                mob:engaged(Player, playerWeapons)
            end
        end
    end

end

function MobManager:disengageMob()
    
end

function MobManager:Destroy()
    self:Destroy()
end


-- EVENT CONNECTIONS





return MobManager