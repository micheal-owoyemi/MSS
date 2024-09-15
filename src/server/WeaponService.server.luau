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

local RemoteFunctions = ReplicatedStorage.Shared:WaitForChild('RemoteFunctions')
local GetWeaponsRF = RemoteFunctions.GetWeapons

local WeaponsData = {}

--    local profile = DataHandler:getProfileAsync(Player)

-- FUNCTIONS
local function getWeapons(Player)
    local profile = DataHandler:getProfileAsync(Player)
    if not profile then
        return
    end

    local weaponInventory = profile:getWeapons()

    print(weaponInventory)
    
    return weaponInventory
end
GetWeaponsRF.OnServerInvoke = getWeapons