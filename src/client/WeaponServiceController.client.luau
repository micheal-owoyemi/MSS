-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

-- MODULE(S)
local ReplicaController = require(ReplicatedStorage.Shared.ReplicaController)
ReplicaController.RequestData() -- INIT ONCE FOR ENTIRE CLIENT

local WeaponClass = require(ReplicatedStorage.Shared.Classes.Weapon)
local HelperFunctions = require(ReplicatedStorage.Shared.HelperFunctions.HelperFunctions)

local WeaponIdle = require(ReplicatedStorage.Shared.FollowTypes.Idle)
local WeaponMove require(ReplicatedStorage.Shared.FollowTypes.Move)

-- VARIABLES
local Player = Players.LocalPlayer

local RemoteEvents = ReplicatedStorage.Shared:WaitForChild('RemoteEvents')
local PlayerMovedRE = RemoteEvents.PlayerMoved
local UpdateWeaponPositionRE = RemoteEvents.UpdateWeaponPositions

local RemoteFunctions = ReplicatedStorage.Shared:WaitForChild('RemoteFunctions')
local EquipWeaponRF = RemoteFunctions.EquipWeapon

local WeaponsFolder = workspace:WaitForChild('Weapons')
local Weapons = {}


local function onEquipWeapon(uuid: string, weaponType: string, weaponName: string, equipped: boolean, player: Player)

    local equippedWeapon = WeaponClass.new(uuid, weaponType, weaponName, equipped, player)

    Weapons[equippedWeapon.uuid] = equippedWeapon

    print(equippedWeapon.folder:GetChildren())

    return equippedWeapon:getPositionData()

end
EquipWeaponRF.OnClientInvoke = onEquipWeapon


local function onWeaponPositionUpdate(player)
    
    local playerWeapons = WeaponsFolder[player.Name]

    for _, weapon in playerWeapons:GetChildren() do
        local targetWeapon = Weapons[weapon.Name]
        local humanoidRootPart = targetWeapon.character:WaitForChild('HumanoidRootPart')
        local humanoid = targetWeapon.character:WaitForChild('Humanoid')

        print(targetWeapon.folder:GetChildren())
        targetWeapon:move(targetWeapon.folder:GetChildren(), targetWeapon.character, targetWeapon.humanoidRootPart, humanoid, targetWeapon.weaponModel, 0.03)
    end

end

UpdateWeaponPositionRE.OnClientEvent:Connect(onWeaponPositionUpdate)

