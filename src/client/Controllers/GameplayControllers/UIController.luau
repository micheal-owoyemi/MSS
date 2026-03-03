local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Trove = require(ReplicatedStorage.Shared.Trove)
local NetworkApi = require(ReplicatedStorage.Shared.Network.NetworkApi)
local WeaponData = require(ReplicatedStorage.Shared.Utilities.WeaponData)

local UIController = Knit.CreateController({
	Name = "UIController",
})

local function resolveWeaponDamage(weaponType: string, weaponName: string): number
	return WeaponData.getDamage(weaponType, weaponName, 0)
end

local function resolveWeaponImage(weaponType: string, weaponName: string): string
	return WeaponData.getImage(weaponType, weaponName, "")
end

function UIController:KnitInit()
	self._renderTrove = Trove.new()
	self._trove = Trove.new()
	self._weaponDataByUuid = {}
end

function UIController:_resolveGui()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local mainGui = playerGui:WaitForChild("Main")
	local inventoryRoot = mainGui:WaitForChild("WeaponInventory")

	self._inventoryUI = inventoryRoot:WaitForChild("InventoryUI")
	self._inventoryButton = inventoryRoot:WaitForChild("InventoryButton")
	self._exitButton = self._inventoryUI:WaitForChild("Main"):WaitForChild("Exit"):WaitForChild("Button")
	self._lateral = self._inventoryUI.Main:WaitForChild("Lateral")
	self._weaponContainer = self._inventoryUI.Main.Middle.ScrollingFrame:WaitForChild("Weapons")
end

function UIController:_clearWeaponFrames()
	for _, child in ipairs(self._weaponContainer:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

function UIController:_renderWeapons(weapons: { [string]: any })
	self:_clearWeaponFrames()
	self._renderTrove:Clean()

	local entries = {}
	for uuid, data in pairs(weapons) do
		if type(data) == "table" then
			local weaponType = tostring(data.weaponType or "")
			local weaponName = tostring(data.weaponName or "")
			table.insert(entries, {
				uuid = uuid,
				weaponType = weaponType,
				weaponName = weaponName,
				equipped = data.equipped == true,
				damage = resolveWeaponDamage(weaponType, weaponName),
			})
		end
	end

	table.sort(entries, function(a, b)
		return a.damage > b.damage
	end)

	local template = ReplicatedStorage.Shared.Assets:WaitForChild("GUI"):WaitForChild("WeaponTemplate")
	for _, entry in ipairs(entries) do
		local frame = template:Clone()
		frame.Name = entry.weaponName ~= "" and entry.weaponName or entry.uuid
		frame.Parent = self._weaponContainer

		local main = frame:FindFirstChild("Main")
		if main and main:IsA("Frame") then
			main.Size = UDim2.fromScale(0, 0)
			TweenService:Create(
				main,
				TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ Size = UDim2.fromScale(1, 1) }
			):Play()

			local shadow = main:FindFirstChild("Shadow")
			if shadow and shadow:IsA("Frame") and entry.equipped then
				shadow.BackgroundColor3 = Color3.fromRGB(167, 245, 255)
			end

			local button = main:FindFirstChild("Button")
			if button and button:IsA("GuiButton") then
				self._renderTrove:Add(button.MouseButton1Click:Connect(function()
					self._inventoryUI:SetAttribute("WeaponSelected", entry.uuid)
				end))
			end
		end
	end
end

function UIController:_updateLateral(selectedUUID: string)
	local weaponData = self._weaponDataByUuid[selectedUUID]
	if type(weaponData) ~= "table" then
		return
	end

	local weaponType = tostring(weaponData.weaponType or "")
	local weaponName = tostring(weaponData.weaponName or "")
	local damage = resolveWeaponDamage(weaponType, weaponName)
	local image = resolveWeaponImage(weaponType, weaponName)

	self._lateral.WeaponName.Text = weaponName
	self._lateral.Damage.Text = "ATK: " .. tostring(damage)
	self._lateral.Image.Image = image
	self._lateral.Description.Text = tostring(weaponData.Description or "DESCRIPTION")

	if weaponData.equipped == true then
		self._lateral.Equip.BackgroundColor3 = Color3.fromRGB(255, 93, 93)
		self._lateral.Equip.Shadow.BackgroundColor3 = Color3.fromRGB(202, 73, 73)
		self._lateral.Equip.Text.Text = "UNEQUIP"
	else
		self._lateral.Equip.BackgroundColor3 = Color3.fromRGB(85, 170, 127)
		self._lateral.Equip.Shadow.BackgroundColor3 = Color3.fromRGB(63, 127, 94)
		self._lateral.Equip.Text.Text = "EQUIP"
	end
end

function UIController:_openInventory()
	if self._inventoryUI.Visible then
		return
	end

	local getWeapons = NetworkApi.waitForRemoteFunction("GetWeapons")
	local weapons = getWeapons:InvokeServer()
	if type(weapons) ~= "table" then
		weapons = {}
	end

	self._weaponDataByUuid = weapons
	self._inventoryUI.Visible = true
	self:_renderWeapons(weapons)
end

function UIController:_closeInventory()
	if not self._inventoryUI.Visible then
		return
	end

	self._inventoryUI.Visible = false
	self._inventoryUI:SetAttribute("WeaponSelected", "")
	self:_clearWeaponFrames()
	self._renderTrove:Clean()
end

function UIController:KnitStart()
	self:_resolveGui()

	self._trove:Add(self._inventoryButton.MouseButton1Click:Connect(function()
		self:_openInventory()
	end))
	self._trove:Add(self._exitButton.MouseButton1Click:Connect(function()
		self:_closeInventory()
	end))
	self._trove:Add(self._inventoryUI.AttributeChanged:Connect(function(attributeName: string)
		if attributeName ~= "WeaponSelected" then
			return
		end
		self:_updateLateral(tostring(self._inventoryUI:GetAttribute(attributeName) or ""))
	end))
end

return UIController
