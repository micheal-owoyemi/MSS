-- SERVICES
local ServerScriptService = game:GetService('ServerScriptService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- MODULES
local DataHandler = require(ServerScriptService.Server.DataHandler)
local WeaponClass = require(ReplicatedStorage.Shared.Classes.Weapon)
local MobClass = require(ReplicatedStorage.Shared.Classes.Mob)

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



MobClass.spawnMobs() -- Link to Region3