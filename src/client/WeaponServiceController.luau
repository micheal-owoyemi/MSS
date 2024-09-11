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

local function LoadWeapons(inventoryUI, Weapons)
    task.spawn(function()
        for _, frame in inventoryUI.Main.Middle.ScrollingFrame.Weapons:GetChildren() do
            if frame:IsA('Frame') then
                trove.Add(trove, frame)
            end
        end

        for weapon, data in Weapons do
            SortedWeapons[#SortedWeapons + 1] = {Name = data.Name, Damage = data.Damage}
        end

        table.sort(SortedWeapons, function(a, b)
            return a.Damage < b.Damage
        end)

        for _, data in SortedWeapons do
            local WeaponTemplate = ReplicatedStorage:WaitForChild('GUI')['WeaponTemplate']:Clone()

        end
    end)
end
