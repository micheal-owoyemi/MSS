-- SERVICES
local ServerScriptService = game:GetService('ServerScriptService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local Players = game:GetService('Players')

-- MODULES
local DataHandler = require(ServerScriptService.Server.DataHandler)

local WeaponClass = require(ReplicatedStorage.Shared.Classes.Weapon)

local WeaponIdle = require(ReplicatedStorage.Shared.FollowTypes.Idle)
local WeaponMove require(ReplicatedStorage.Shared.FollowTypes.Move)

-- Variables

local WeaponFolder = workspace:WaitForChild('Weapons')

local RemoteEvents = ReplicatedStorage.Shared:WaitForChild('RemoteEvents')
local PlayerMovedRE = RemoteEvents.PlayerMoved
local UpdateWeaponPositionRE = RemoteEvents.UpdateWeaponPositions

local RemoteFunctions = ReplicatedStorage.Shared:WaitForChild('RemoteFunctions')
local EquipWeaponRF = RemoteFunctions.EquipWeapon

local WeaponTable = {}

-- Functions

-- Equip Weapons on Join
Players.PlayerAdded:Connect(function(Player)
    local profile = DataHandler:getProfileAsync(Player)
    if not profile then
        return
    end

    local playerWeaponData = profile.Replica.Data.Weapons

    local weaponOwner = Player
    local weaponsFolder = Instance.new('Folder')
    weaponsFolder.Name = Player.Name
    weaponsFolder.Parent = workspace.Weapons

    for _, player in Players:GetPlayers() do

        if player then
            for uuid, weapon in playerWeaponData do
                local weaponPositionData = EquipWeaponRF:InvokeClient(player, uuid, weapon.weaponType, weapon.weaponName, weapon.equipped, weaponOwner)
                -- do checks on the weapon data
                if not WeaponTable[uuid] then
                    WeaponTable[uuid] = weaponPositionData
                end
            end
        end
    end

    print(WeaponTable)
end)

local function sendPositionData()
    for _, player in Players:GetPlayers() do
        local character = player.Character

        if character then
            local humanoid = character:WaitForChild('Humanoid')
            if humanoid then
                if humanoid.MoveDirection.Magnitude > 0 then
                    
                    UpdateWeaponPositionRE:FireAllClients(player)

                    task.wait(0.1)
                end
            end
        end
    end
end

RunService.Heartbeat:Connect(sendPositionData)