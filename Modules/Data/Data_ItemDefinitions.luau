--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TableUtil = require(ReplicatedStorage.Util.TableUtil)
local Data_WeaponDefs = require(ReplicatedStorage.Data.Data_WeaponDefs)

export type ItemDefinition = {
	DefId: string,
	ItemType: "Weapon" | "Stackable" | "Consumable" | "Gift",
	DisplayName: string,
	Stackable: boolean,
	MaxStack: number,
	EquipSlots: {string}?,
	Tradable: boolean,
}

local ItemDefinitions = {
	SlotDefinitions = {
		PrimaryWeapon = {
			AllowedItemTypes = {"Weapon"},
		},
		SecondaryWeapon = {
			AllowedItemTypes = {"Weapon"},
		},
	},
	ItemsByDefId = {} :: {[string]: ItemDefinition},
}

for defId, weaponDef in pairs(Data_WeaponDefs) do
	ItemDefinitions.ItemsByDefId[defId] = {
		DefId = defId,
		ItemType = "Weapon",
		DisplayName = weaponDef.DisplayName,
		Stackable = false,
		MaxStack = 1,
		EquipSlots = {"PrimaryWeapon", "SecondaryWeapon"},
		Tradable = true,
	}
end

ItemDefinitions.ItemsByDefId.HealthPotion = {
	DefId = "HealthPotion",
	ItemType = "Consumable",
	DisplayName = "Health Potion",
	Stackable = true,
	MaxStack = 99,
	EquipSlots = nil,
	Tradable = true,
}

ItemDefinitions.ItemsByDefId.ZoneKey_Starter = {
	DefId = "ZoneKey_Starter",
	ItemType = "Stackable",
	DisplayName = "Starter Zone Key",
	Stackable = true,
	MaxStack = 999,
	EquipSlots = nil,
	Tradable = false,
}

return TableUtil.deepFreeze(ItemDefinitions)
