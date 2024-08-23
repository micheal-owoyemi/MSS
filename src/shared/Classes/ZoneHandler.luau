local ZoneHandler = {}
ZoneHandler.__index = ZoneHandler

-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- MODULES
local ZonePlus = require(ReplicatedStorage.Shared:WaitForChild('Zone'))
local MobManager = require(ReplicatedStorage.Shared.Managers.Mob)

-- VARIABLES
local zones = workspace:WaitForChild('Zones')
local mobHandler 
-- FUNCTIONS

function ZoneHandler:mobSpawn()
    for _, area in zones:GetChildren() do
        mobHandler = MobManager.new(area.Name)
        
        local container = area.Container
        local zone = ZonePlus.new(container)
        zone:setAccuracy('Low')

        local mobHandler = MobManager.new(area.Name)
    
        zone.playerEntered:Connect(function(player)
            local canSpawn = false
            local zoneParts = zone:getParts()

            for _, part in zoneParts do
                if part:IsA('Mesh') and part:GetAttribute('Mob') then
                    return
                else
                    canSpawn = true
                end
            end

            if canSpawn then
                for _, spawnPoint in area:WaitForChild('Spawn Points'):GetChildren() do
                    mobHandler:spawnMob(tostring(area), tostring(spawnPoint:GetAttribute('Mob')), spawnPoint)
                   task.wait(1) -- Bandaid for smoother spawning
                end

            end
        end)

        zone.playerExited:Connect(function(player)
            local playersArray = zone:getPlayers()
    
            if #playersArray == 0 then
                print('Despawning Mobs')
                -- Here we would add despawning mobs
            end
        end)
    end
end

-- FUNCTIONS

return ZoneHandler