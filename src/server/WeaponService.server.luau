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