-- SERVICES
local ServerScriptService = game:GetService('ServerScriptService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

-- MODULES
local DataHandler = require(ServerScriptService.Server.DataHandler)
local WeaponClass = require(ReplicatedStorage.Shared.Classes.Weapon)

local MobManager = require(ReplicatedStorage.Shared.Managers.Mob)

-- VARIABLES
local mobManagerInstance = MobManager.new()

local RemoteEvents = ReplicatedStorage.Shared.RemoteEvents

local attackMobRE = RemoteEvents:WaitForChild('AttackMob')

-- FUNCTIONS

-- On Player Join Give Weapons
game.Players.PlayerAdded:Connect(function(Player)
    local profile = DataHandler:getProfileAsync(Player)
    if not profile then
        return
    end
    local weaponsFolder = Instance.new('Folder')
    weaponsFolder.Name = Player.Name
    weaponsFolder.Parent = workspace.Weapons

    local weaponInstance = WeaponClass.new('233r3', 'Sword', 'Wooden Sword', false, Player)
    profile:addWeapon(weaponInstance)

end)

-- Spawns Mobs For Each Zone
mobManagerInstance:setUpZoneSpawning()

-- Remote Event for Mob Attacking
local function attackMobREConnection(Player, mobInstance)
    local profile = DataHandler:getProfileAsync(Player)
    if not profile then
        return
    end

    local attackingWeapons = {}

    for _, weapon in profile.Replica.Data.Weapons do
        if weapon.equipped then
            table.insert(attackingWeapons, weapon)
        end
    end

    mobManagerInstance:attackMob(Player, mobInstance, attackingWeapons)
end


attackMobRE.OnServerEvent:Connect(attackMobREConnection)
