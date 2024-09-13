-- SERVICES
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local Player = game:GetService("Players").LocalPlayer;
local TweenService = game:GetService("TweenService");

-- MODULES
local WeaponClass = require(ReplicatedStorage.Shared.Classes.Weapon)
local WeaponConfig = require(ReplicatedStorage.Shared.Configs.WeaponConfig)

local Trove = require(ReplicatedStorage.Shared.Trove)

-- VARIABLES
local RemoteEvents = ReplicatedStorage.Shared:WaitForChild('RemoteEvents')
local OpenShopRE = RemoteEvents.OpenShop

local SortedWeapons = {}
local trove = Trove.new()

-- FUNCTIONS