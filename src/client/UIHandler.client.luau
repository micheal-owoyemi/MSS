-- SERVICES
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local Player = game:GetService("Players").LocalPlayer;
local TweenService = game:GetService("TweenService");
local PlayerGui = Player:WaitForChild("PlayerGui")

-- MODULES
local WeaponClass = require(ReplicatedStorage.Shared.Classes.Weapon)
local WeaponConfig = require(ReplicatedStorage.Shared.Configs.WeaponConfig)

local Trove = require(ReplicatedStorage.Shared.Trove)

-- VARIABLES
local RemoteEvents = ReplicatedStorage.Shared:WaitForChild('RemoteEvents')
local OpenShopRE = RemoteEvents.OpenShop

local RemoteFunctions = ReplicatedStorage.Shared:WaitForChild('RemoteFunctions')
local GetWeaponsRF = RemoteFunctions.GetWeapons

local SortedWeapons = {}
local trove = Trove.new()
local cleanup = trove:WrapClean()

-- WEAPON INVENTORY
local WeaponInventory = PlayerGui:WaitForChild('WeaponInventory')
local weaponInventoryUI = WeaponInventory:WaitForChild('InventoryUI')
local weaponInventoryButton = WeaponInventory:WaitForChild('InventoryButton')
local weaponInventoryExitButton = weaponInventoryUI:WaitForChild('Main').Exit.Button

-- FUNCTIONS

-- WEAPON INVENTORY
local function loadWeapons(inventoryUI, Weapons)
    task.spawn(function()
        for _, frame in inventoryUI.Main.Middle.ScrollingFrame.Weapons:GetChildren() do
            if frame:IsA('Frame') then
                trove.Add(frame)
            end
        end

        for weapon, data in Weapons do
            SortedWeapons[weapon] = {Name = data.weaponName,
             Damage = WeaponConfig[data.weaponType][data.weaponName].Damage, Equipped = data.equipped, UUID = weapon}
        end

        table.sort(SortedWeapons, function(a, b)
            return a.Damage < b.Damage
        end)

        for _, data in SortedWeapons do
            local Template = ReplicatedStorage.Shared.Assets:WaitForChild('GUI')['WeaponTemplate']:Clone()
            -- Image, Damage, Description, Name
            Template.Name = data.Name
            Template.Main.Size = UDim2.fromScale(0, 0)

            if data.Equipped then 
                Template.Main.Shadow.BackgroundColor3 = Color3.fromRGB(167, 245, 255);
            end

            Template.Parent = inventoryUI.Main.Middle.ScrollingFrame.Weapons

            Template.Main:TweenSize(UDim2.fromScale(1, 1), 'Out', 'Quart', 0.2, true)
            task.wait(0.1)
            trove.Add(trove,
                 Template.Main.Button.MouseButton1Click:Connect(function()
                    inventoryUI:SetAttribute('WeaponSelected', data.UUID)
             end))
        end
    end)
end

local function fadeLateral(inventoryUI, Weapons, Lateral)
    Lateral.Equip.BackgroundTransparency = 1;
	Lateral.Equip.Shadow.BackgroundTransparency = 1;
	Lateral.Equip.Text.TextTransparency = 1;
	
	Lateral.Image.ImageTransparency = 1;
	Lateral.Description.TextTransparency = 1;
	Lateral.WeaponName.TextTransparency = 1;
	
	Lateral.Damage.TextTransparency = 1;
	--Lateral.Damage.Icon.ImageTransparency = 1;
	
	local tweenInfo = TweenInfo.new(
		0.4,
		Enum.EasingStyle.Quart,
		Enum.EasingDirection.Out,
		0,
		false,
		0.2
	);
	TweenService:Create(Lateral.Equip.Text, tweenInfo, {["TextTransparency"] = 0}):Play();
	TweenService:Create(Lateral.Equip, tweenInfo, {["BackgroundTransparency"] = 0}):Play();
	TweenService:Create(Lateral.WeaponName, tweenInfo, {["TextTransparency"] = 0}):Play();
	TweenService:Create(Lateral.Damage, tweenInfo, {["TextTransparency"] = 0}):Play();
	TweenService:Create(Lateral.Image, tweenInfo, {["ImageTransparency"] = 0}):Play();
	TweenService:Create(Lateral.Equip.Shadow, tweenInfo, {["BackgroundTransparency"] = 0}):Play();
	TweenService:Create(Lateral.Description, tweenInfo, {["TextTransparency"] = 0}):Play();
	--TweenService:Create(Lateral.Damage.Icon, tweenInfo, {["ImageTransparency"] = 0}):Play();
end

local function openWeaponInventory()
    if weaponInventoryUI.Visible then return end

    local Weapons = GetWeaponsRF:InvokeServer()
    weaponInventoryUI.Visible = true

    loadWeapons(weaponInventoryUI, Weapons)
    fadeLateral(weaponInventoryUI, Weapons, weaponInventoryUI.Main:WaitForChild('Lateral'))

    trove.Add(trove, (weaponInventoryUI.AttributeChanged:Connect(function(AttributeName)
		local WeaponSelected = weaponInventoryUI:GetAttribute(AttributeName)

        local Lateral = weaponInventoryUI.Main.Lateral
        local weaponData = Weapons[WeaponSelected]

        Lateral.WeaponName.Text = weaponData.weaponName
		Lateral.Damage.Text = ('ATK: '.. WeaponConfig[weaponData.weaponType][weaponData.weaponName].Damage) or 'ATK: '
		Lateral.Image.Image = WeaponConfig[weaponData.weaponType][weaponData.weaponName].Image or ''
		Lateral.Description.Text = WeaponConfig[weaponData.weaponType][weaponData.weaponName].Description or 'DESCRIPTION'

        if not weaponData.equipped then 
            Lateral.Equip.BackgroundColor3 = Color3.fromRGB(85, 170, 127);
            Lateral.Equip.Shadow.BackgroundColor3 = Color3.fromRGB(63, 127, 94);
            Lateral.Equip.Text.Text = "EQUIP";
        else
            Lateral.Equip.BackgroundColor3 = Color3.fromRGB(255, 93, 93);
            Lateral.Equip.Shadow.BackgroundColor3 = Color3.fromRGB(202, 73, 73);
            Lateral.Equip.Text.Text = "UNEQUIP";
        end
		
	end)))
end

local function closeWeaponInventory()
    if not weaponInventoryUI.Visible then return end

    weaponInventoryUI.Visible = false

    for _, frame in weaponInventoryUI.Main.Middle.ScrollingFrame.Weapons:GetChildren() do
        if frame:IsA('Frame') then
            frame:Destroy()
        end
    end

    weaponInventoryUI:SetAttribute("WeaponSelected", "");
    cleanup()
end

weaponInventoryButton.MouseButton1Click:Connect(openWeaponInventory)
weaponInventoryExitButton.MouseButton1Click:Connect(closeWeaponInventory)