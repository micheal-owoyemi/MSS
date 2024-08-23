--[[ When you do mobclass.new, you can do local newMob = mobClass.new() and then it returns the new mob, then you can store and reference it
    A module script that gets initialized, that would call the mobclass.new and store the new classes in a table contained inside the modulescript
]]


local MobManager = {}
MobManager.__index = MobManager

-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- MODULES
local ZonePlus = require(ReplicatedStorage.Shared:WaitForChild('Zone'))
local MobClass = require(ReplicatedStorage.Shared.Classes.Mob)
local Trove = require(ReplicatedStorage.Shared.Trove)

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
                if part:IsA('Mesh') and part:GetAttribute('Mob') then
                    return
                else
                    self.canSpawn = true
                end
            end

            if self.canSpawn then

                for _, spawnPoint in area:WaitForChild('Spawn Points'):GetChildren() do
                    print('spawning...')
                    local mobInstance = self:spawnMob(tostring(area), tostring(spawnPoint:GetAttribute('Mob')), spawnPoint) 
                    table.insert(self.mobInstances, mobInstance)
                    task.wait(1) -- Bandaid for smoother spawning
                end
                
                return
            end
        end)

        zone.playerExited:Connect(function(player)
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
        end)
    end
end
 
function MobManager:engageMob()
    
end

function MobManager:disengageMob()
    
end



function MobManager:Destroy()
    self:Destroy()
end

return MobManager