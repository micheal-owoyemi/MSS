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

-- WEAPON INVENTORY
local function loadWeapons(inventoryUI, Weapons)
    task.spawn(function()
        for _, frame in inventoryUI.Main.Middle.ScrollingFrame.Weapons:GetChildren() do
            if frame:IsA('Frame') then
                trove.Add(frame)
            end
        end

        for weapon, data in Weapons do
            SortedWeapons[#SortedWeapons + 1] = {Name = data.weaponName, Damage = WeaponConfig[data.weaponType][data.weaponName].Damage, Equipped = data.equipped}
        end

        table.sort(SortedWeapons, function(a, b)
            return a.Damage < b.Damage
        end)

        for _, data in SortedWeapons do
            local Template = ReplicatedStorage:WaitForChild('GUI')['WeaponTemplate']:Clone()
            -- Image, Damage, Description, Name
            Template.Name = data.Name
            Template.Main.Size = UDim2.fromScale(0, 0)
            Template.Parent = inventoryUI.Main.Middle.ScrollingFrame.Weapons

            Template.Main:TweenSize(UDim2.fromScale(1, 1), 'Out', 'Quart', 0.2, true)
            task.wait(0.1)
            trove.Add(trove,
                Template.Main.Button.MoseButton1Click:Connect(function()
                    inventoryUI:SetAttribute('WeaponSelected', data.WeaponName)
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
	Lateral.Name.TextTransparency = 1;
	
	Lateral.Damage.TextTransparency = 1;
	Lateral.Damage.Icon.ImageTransparency = 1;
	
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
	TweenService:Create(Lateral.Name, tweenInfo, {["TextTransparency"] = 0}):Play();
	TweenService:Create(Lateral.Damage, tweenInfo, {["TextTransparency"] = 0}):Play();
	TweenService:Create(Lateral.Image, tweenInfo, {["ImageTransparency"] = 0}):Play();
	TweenService:Create(Lateral.Equip.Shadow, tweenInfo, {["BackgroundTransparency"] = 0}):Play();
	TweenService:Create(Lateral.Description, tweenInfo, {["TextTransparency"] = 0}):Play();
	TweenService:Create(Lateral.Damage.Icon, tweenInfo, {["ImageTransparency"] = 0}):Play();
end

