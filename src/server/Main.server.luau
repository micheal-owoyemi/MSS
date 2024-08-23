-- SERVICES
local ServerScriptService = game:GetService('ServerScriptService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

-- MODULES
local DataHandler = require(ServerScriptService.Server.DataHandler)
local WeaponClass = require(ReplicatedStorage.Shared.Classes.Weapon)
--local MobClass = require(ReplicatedStorage.Shared.Classes.Mob)
--local ZoneHandler = require(ReplicatedStorage.Shared.Classes.ZoneHandler)
local MobManager = require(ReplicatedStorage.Shared.Managers.Mob)

-- VARIABLES
local mobManagerInstance = MobManager.new()

-- FUNCTIONS
game.Players.PlayerAdded:Connect(function(Player)
    local profile = DataHandler:getProfileAsync(Player)
    if not profile then
        return
    end
    local weaponsFolder = Instance.new('Folder')
    weaponsFolder.Name = Player.Name
    weaponsFolder.Parent = workspace.Weapons

    --local weaponInstance = WeaponClass.new('Sword', 'Wooden Sword', false, Player)
    --profile:addWeapon(weaponInstance)

end)


mobManagerInstance:setUpZoneSpawning()
