-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local Players = game:GetService('Players')

-- MODULES
local WeaponClass = require(ReplicatedStorage.Shared.Classes.Weapon)

local ReplicaController = require(ReplicatedStorage.Shared.ReplicaController)

local idle = require(ReplicatedStorage.Shared.FollowTypes.Idle)
local move = require(ReplicatedStorage.Shared.FollowTypes.Move)

local HelperFunctions = require(ReplicatedStorage.Shared.HelperFunctions.HelperFunctions)
-- VARIABLES

local RemoteEvents = ReplicatedStorage.Shared:WaitForChild('RemoteEvents')
local equipWeaponRE = RemoteEvents.EquipWeapon
local replicateEquipWeaponRE = RemoteEvents.ReplicateEquipWeapon
local unequipWeaponRE = RemoteEvents.UnequipWeapon
local replicateUnequipWeaponRE = RemoteEvents.ReplicateUnequipWeapon


local RemoteFunctions = ReplicatedStorage.Shared:WaitForChild('RemoteFunctions')
local getEquippedWeaponsRF = RemoteFunctions.GetEquippedWeapons


local EquippedWeapons: { [number]: { [string]: Instance }} = {}


local function weaponFollowStates(player: Player, weapon)
    print('follow init')
    local character = player.Character or player.CharacterAdded:Wait()
    if not character then print('no char') return end

    local humanoid = character:WaitForChild('Humanoid')
    local humanoidRootPart = character:WaitForChild('HumanoidRootPart')
    if not humanoidRootPart or humanoid then return end

    local weapons = EquippedWeapons[tostring(player.UserId)]
    if not weapons then print(weapons) return end

    weapons[weapon.uuid] = weapon
    print(weapons[weapon.uuid])
    local weaponsFolder = character:FindFirstChild(tostring(player.UserId))

   
    if not weaponsFolder then
        weaponsFolder = Instance.new('Folder', character)
        weaponsFolder.Name = player.UserId
    end

    local weaponModel: Model = ReplicatedStorage.Shared.Assets.Weapons[weapon.weaponType][weapon.weaponName].Model:Clone()
    print(weaponModel)

    if humanoid.MoveDirection.Magnitude > 0 then
        move(weaponsFolder, character, humanoidRootPart, humanoid, weaponModel, 0.03)
    else
        idle(weaponsFolder, character, humanoidRootPart, humanoid, weaponModel, 0.03)
    end

    wait(0.1)
end

local function endWeaponFollow(player: Player, uuid: string)
    local weapons = EquippedWeapons[player.UserId]
    if not weapons then return end 
    weapons[uuid] = nil

    local character = player.Character
    if not character then return end 

    local weaponsFolder = workspace.Weapons:FindFirstChild(player.UserId)
    if not weaponsFolder then return end

    local model = weaponsFolder:FindFirstChild(uuid)
    if model then
        model:Destroy() -- ADD TROVE
    end
end

local function initPlayer(player: Player)
    EquippedWeapons = getEquippedWeaponsRF:InvokeServer()

    local weapons = EquippedWeapons[tostring(player.UserId)]
    if not weapons then
        EquippedWeapons[tostring(player.UserId)] = {}
    end

    for uuid, weapon in weapons do
        weaponFollowStates(player, weapon)
    end
end


ReplicaController.ReplicaOfClassCreated('PlayerProfile', function(Replica)
    local Player = Players.LocalPlayer
    local isLocal = Replica.Tags.Player == Player
    local replicaData = Replica.Data
    
   if isLocal then 
        -- Grabs init replicaData, spawns weapons for it
        for UUID, weapon in pairs(replicaData.Weapons) do
            local weaponInstance = WeaponClass.new(UUID, weapon.weaponType, weapon.weaponName, weapon.equipped, Player)
        end

        local coinCountUI = Player:WaitForChild('PlayerGui'):WaitForChild('CurrencyCounter').Frame.TextLabel
        coinCountUI.Text = replicaData.Coins


        Replica:ListenToChange({'Weapons'}, function(new_value, old_value)
            print('[Client Init] Data Has Been Changed, New Replica Data: ', new_value)
            -- When changed, does it again

            local additions, deletions = HelperFunctions.compareTables(new_value, old_value)
            
           -- for i, weapon in (deletions) do
            --    weapon:despawn()
            --    Weapons[i] = nil    
           -- end

            for UUID, weapon in (additions) do
                local weaponInstance = WeaponClass.new(UUID, weapon.weaponType, weapon.weaponName, weapon.equipped, Player)

            end
            -- Create comparison function to see what changed, then reflect as such
        end)

        Replica:ListenToChange({'Coins'}, function(new_value, old_value)

            if new_value > old_value then
                local diff = new_value - old_value
                coinCountUI.Text = ('+ '..diff)

                task.wait(2)
                
                coinCountUI.Text = new_value
            end
        end)
    end
end)

Players.PlayerAdded:Connect(function(player)
    EquippedWeapons = getEquippedWeaponsRF:InvokeServer()
    player.CharacterAdded:Connect(function(character)
        initPlayer(player)
    end)
end)

local function runTimeLoop()
    EquippedWeapons = getEquippedWeaponsRF:InvokeServer()
    for _, player in Players:GetPlayers() do
        initPlayer(player)
    end
end



--RunService:BindToRenderStep('runTimeLoop', 0, runTimeLoop)

replicateEquipWeaponRE.OnClientEvent:Connect(weaponFollowStates)
replicateUnequipWeaponRE.OnClientEvent:Connect(endWeaponFollow)