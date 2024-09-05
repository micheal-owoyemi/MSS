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

local RemoteEvents = ReplicatedStorage.Shared:WaitForChild('RemoteEvents')
local attackMobRE = RemoteEvents.AttackMob
local equipWeaponRE = RemoteEvents.EquipWeapon
local replicatedEquipWeaponRE = RemoteEvents.ReplicateEquipWeapon
local unequipWeaponRE = RemoteEvents.UnequipWeapon
local replicatedUnequipWeaponRE = RemoteEvents.ReplicateUnequipWeapon


local RemoteFunctions = ReplicatedStorage.Shared:WaitForChild('RemoteFunctions')
local getEquippedWeaponsRF = RemoteFunctions.GetEquippedWeapons

-- FUNCTIONS

-- On Player Join Give Weapons
--[[game.Players.PlayerAdded:Connect(function(Player)
    local profile = DataHandler:getProfileAsync(Player)
    if not profile then
        return
    end
    local weaponsFolder = Instance.new('Folder')
    weaponsFolder.Name = Player.Name
    weaponsFolder.Parent = workspace.Weapons

    local weaponInstance = WeaponClass.new('11223_ee3v2','Sword', 'Wooden Sword', false, Player)
    profile:addWeapon(weaponInstance)

end)]]

local function equipWeapon(player: Player, uuid: string)
    local profile = DataHandler:getProfileAsync(player)
    if not profile then
        return
    end

    local weapon = profile.Replica.Data.Weapons[uuid]
    if not weapon then return end
    if weapon.equipped then return end -- or use unequip function

    profile:equipWeapon(uuid)
    equipWeaponRE:FireClient(player, uuid)

    for _, replicationTarget in Players:GetPlayers() do
        if player == replicationTarget then continue end
        replicatedEquipWeaponRE:FireClient(replicationTarget, player, weapon)
    end
end

local function unequipWeapon(player: Player, uuid: string)
    local profile = DataHandler:getProfileAsync(player)
    if not profile then
        return
    end

    local weapon = profile.Replica.Data.Weapons[uuid]
    if not weapon then return end
    if not weapon.equipped then return end -- or use equip function

    profile:equipWeapon(uuid)
    equipWeaponRE:FireClient(player, uuid)

    for _, replicationTarget in Players:GetPlayers() do
        if player == replicationTarget then continue end
        replicatedEquipWeaponRE:FireClient(replicationTarget, player, weapon)
    end
end

local function getAllEquippedWeapons()
    local allEquippedWeapons = {}

    for _, player in Players:GetPlayers() do
        allEquippedWeapons[player.UserId] = {}

        local profile = DataHandler:getProfileAsync(player)
        if not profile then
            return
        end

        local equippedWeapons = profile:getEquippedWeapons()
        for UUID, weapon in equippedWeapons do
            allEquippedWeapons[player.UserId][UUID] = weapon
        end
    end

    return allEquippedWeapons
end


getEquippedWeaponsRF.OnServerInvoke = getAllEquippedWeapons