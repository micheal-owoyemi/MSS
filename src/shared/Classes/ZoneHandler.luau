local ZoneHandler = {}
ZoneHandler.__index = ZoneHandler

-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- MODULES
local ZonePlus = require(ReplicatedStorage.Shared:WaitForChild('Zone'))
local MobClass = require(ReplicatedStorage.Shared.Classes.Mob)

-- VARIABLES
local zones = workspace:WaitForChild('Zones')


function ZoneHandler:mobSpawn()
    for _, area in zones:GetChildren() do
        local container = area.Container
        local zone = ZonePlus.new(container)
        zone:setAccuracy('Low')
    
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
                    MobClass.new(tostring(area), tostring(spawnPoint:GetAttribute('Mob')), spawnPoint)
                   wait(0.5) -- Bandaid for smoother spawning
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