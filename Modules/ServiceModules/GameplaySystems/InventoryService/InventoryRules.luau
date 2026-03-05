--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ValidationUtil = require(ReplicatedStorage.Util.ValidationUtil)
local ItemTypes = require(ReplicatedStorage.Types.ItemTypes)

local InventoryRules = {}

local function isNonEmptyString(value: any, maxLength: number?): boolean
	if not ValidationUtil.isNonEmptyString(value) then
		return false
	end
	if maxLength ~= nil and string.len(value) > maxLength then
		return false
	end
	return true
end

function InventoryRules.ensureInventoryState(profileData: {[string]: any}): ({[string]: any}, {[string]: string})
	if typeof(profileData.Inventory) ~= "table" then
		profileData.Inventory = {}
	end

	local inventory = profileData.Inventory
	if typeof(inventory.Weapons) ~= "table" then
		inventory.Weapons = {}
	end
	if typeof(inventory.Stackables) ~= "table" then
		inventory.Stackables = {}
	end
	if typeof(inventory.Consumables) ~= "table" then
		inventory.Consumables = {}
	end
	if typeof(inventory.Gifts) ~= "table" then
		inventory.Gifts = {}
	end
	if typeof(inventory.LockedItems) ~= "table" then
		inventory.LockedItems = {}
	end

	if typeof(profileData.EquippedSlots) ~= "table" then
		profileData.EquippedSlots = {}
	end

	return inventory, profileData.EquippedSlots
end

function InventoryRules.getDefinition(itemDefinitions: any, defId: string)
	if typeof(itemDefinitions) ~= "table" then
		return nil
	end
	local byDefId = itemDefinitions.ItemsByDefId
	if typeof(byDefId) ~= "table" then
		return nil
	end
	local definition = byDefId[defId]
	if typeof(definition) ~= "table" then
		return nil
	end
	return definition
end

function InventoryRules.resolveUniqueItemByUid(inventory: {[string]: any}, uid: string): (string?, {[string]: any}?)
	local weapons = inventory.Weapons
	if typeof(weapons) == "table" and typeof(weapons[uid]) == "table" then
		return "Weapons", weapons[uid]
	end

	local gifts = inventory.Gifts
	if typeof(gifts) == "table" and typeof(gifts[uid]) == "table" then
		return "Gifts", gifts[uid]
	end

	return nil, nil
end

function InventoryRules.isLocked(inventory: {[string]: any}, uid: string): boolean
	local lockedItems = inventory.LockedItems
	if typeof(lockedItems) ~= "table" then
		return false
	end
	return lockedItems[uid] ~= nil
end

function InventoryRules.isSlotAllowed(slotDefinitions: any, definition: any, slot: string): boolean
	if typeof(slotDefinitions) ~= "table" or typeof(definition) ~= "table" then
		return false
	end
	local slotDef = slotDefinitions[slot]
	if typeof(slotDef) ~= "table" then
		return false
	end

	local allowedItemTypes = slotDef.AllowedItemTypes
	if typeof(allowedItemTypes) == "table" then
		local typeAllowed = false
		local definitionItemType = definition.ItemType
		for _, itemType in ipairs(allowedItemTypes) do
			if definitionItemType == itemType then
				typeAllowed = true
				break
			end
		end
		if not typeAllowed then
			return false
		end
	end

	local equipSlots = definition.EquipSlots
	if typeof(equipSlots) == "table" then
		for _, allowedSlot in ipairs(equipSlots) do
			if allowedSlot == slot then
				return true
			end
		end
		return false
	end

	return true
end

function InventoryRules.hasItem(profileData: {[string]: any}, identifier: string): boolean
	local inventory = profileData.Inventory
	if typeof(inventory) ~= "table" then
		return false
	end

	local weapons = inventory.Weapons
	if typeof(weapons) == "table" then
		if weapons[identifier] ~= nil then
			return true
		end
		for _, weapon in pairs(weapons) do
			if typeof(weapon) == "table" and weapon.DefId == identifier then
				return true
			end
		end
	end

	local gifts = inventory.Gifts
	if typeof(gifts) == "table" then
		if gifts[identifier] ~= nil then
			return true
		end
		for _, gift in pairs(gifts) do
			if typeof(gift) == "table" and gift.DefId == identifier then
				return true
			end
		end
	end

	local stackables = inventory.Stackables
	if typeof(stackables) == "table" and ValidationUtil.isFiniteNumber(stackables[identifier]) and stackables[identifier] > 0 then
		return true
	end

	local consumables = inventory.Consumables
	if typeof(consumables) == "table" and ValidationUtil.isFiniteNumber(consumables[identifier]) and consumables[identifier] > 0 then
		return true
	end

	return false
end

function InventoryRules.normalizeItemType(rawType: any, definitionType: string): string?
	if rawType == nil then
		return definitionType
	end
	if not ItemTypes.isValidItemType(rawType) then
		return nil
	end
	if rawType ~= definitionType then
		return nil
	end
	return rawType
end

function InventoryRules.validateAddPayload(itemRecord: any, maxUidLength: number, maxDefIdLength: number): (boolean, string?)
	if typeof(itemRecord) ~= "table" then
		return false, "InvalidItemRecord"
	end

	if not isNonEmptyString(itemRecord.DefId, maxDefIdLength) then
		return false, "InvalidDefId"
	end

	local uid = itemRecord.Uid
	if uid ~= nil and not isNonEmptyString(uid, maxUidLength) then
		return false, "InvalidUid"
	end

	local quantity = itemRecord.Quantity
	if quantity ~= nil then
		if not ValidationUtil.isFiniteNumber(quantity) then
			return false, "InvalidQuantity"
		end
		if quantity <= 0 then
			return false, "QuantityMustBePositive"
		end
	end

	return true, nil
end

return InventoryRules
