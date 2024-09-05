-- spawn weapon
    -- send back equipped weapons in remote function

--[[ everytime a lerp is completer from one of the move functions, send an unreliable remote event:
    -- send back weapon data in a remote function
    {
        Orientation: 
        Position:
        Pivot??
    }

    take that data and update the weapons in the Weapons table sorted by player and catalouged by UUID

    fire all clients and find the player, then weapon model, then update the model's primary part with the data sent over --
    -- Use lerp or tween for other clients
]]

-- SERVICES
local ServerScriptService = game:GetService('ServerScriptService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

-- MODULES
local DataHandler = require(ServerScriptService.Server.DataHandler)
local WeaponClass = require(ReplicatedStorage.Shared.Classes.Weapon)


-- VARIABLES

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

    local weaponInstance = WeaponClass.new('Sword', 'Wooden Sword', false, Player)
    profile:addWeapon(weaponInstance)

end)