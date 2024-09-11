-- SERVICES
local ServerScriptService = game:GetService('ServerScriptService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

-- MODULES
local DataHandler = require(ServerScriptService.Server.DataHandler)

local WeaponClass = require(ReplicatedStorage.Shared.Classes.Weapon)
local WeaponConfig = require(ReplicatedStorage.Shared.Configs.WeaponConfig)

local Trove = require(ReplicatedStorage.Shared.Trove)

-- VARIABLES
local RemoteEvents = ReplicatedStorage.Shared:WaitForChild('RemoteEvents')
local OpenShopRE = RemoteEvents.OpenShop

local WeaponsData = {}

--    local profile = DataHandler:getProfileAsync(Player)

-- FUNCTIONS
OpenShopRE.OnServerEvent:Connect(function(Player, weaponType, weaponName)
    local profile = DataHandler:getProfileAsync(Player)
    if not profile then
        return
    end

    local Weapon = WeaponConfig[weaponType][weaponName]
    if not Weapon then return end

    local equippedWeapons = profile:getEquippedWeapons()

end)
