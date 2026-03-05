--!strict

local SnapshotBuilder = {}

local function sanitizeString(value: any): string
	if typeof(value) == "string" then
		return value
	end
	return ""
end

local function sanitizeNumber(value: any): number
	if typeof(value) == "number" then
		return value
	end
	return 0
end

function SnapshotBuilder.build(profileData: {[string]: any}, itemDefinitions: any)
	local inventory = if typeof(profileData.Inventory) == "table" then profileData.Inventory else {}
	local lockedItems = if typeof(inventory.LockedItems) == "table" then inventory.LockedItems else {}
	local equippedSlots = if typeof(profileData.EquippedSlots) == "table" then profileData.EquippedSlots else {}

	local weapons = {}
	for uid, weaponRecord in pairs(if typeof(inventory.Weapons) == "table" then inventory.Weapons else {}) do
		if typeof(uid) == "string" and typeof(weaponRecord) == "table" then
			local defId = sanitizeString(weaponRecord.DefId)
			local definition = if typeof(itemDefinitions.ItemsByDefId) == "table" then itemDefinitions.ItemsByDefId[defId] else nil
			weapons[uid] = {
				Uid = uid,
				DefId = defId,
				DisplayName = if definition and definition.DisplayName then definition.DisplayName else sanitizeString(weaponRecord.DisplayName),
				Rarity = sanitizeString(weaponRecord.Rarity),
				Level = sanitizeNumber(weaponRecord.Level),
				IsTradable = weaponRecord.IsTradable == true,
				IsLocked = lockedItems[uid] ~= nil,
			}
		end
	end

	local gifts = {}
	for uid, giftRecord in pairs(if typeof(inventory.Gifts) == "table" then inventory.Gifts else {}) do
		if typeof(uid) == "string" and typeof(giftRecord) == "table" then
			gifts[uid] = {
				Uid = uid,
				DefId = sanitizeString(giftRecord.DefId),
				CreatedAt = sanitizeNumber(giftRecord.CreatedAt),
				ExpiresAt = sanitizeNumber(giftRecord.ExpiresAt),
				IsLocked = lockedItems[uid] ~= nil,
			}
		end
	end

	local stackables = {}
	for defId, amount in pairs(if typeof(inventory.Stackables) == "table" then inventory.Stackables else {}) do
		if typeof(defId) == "string" and typeof(amount) == "number" and amount > 0 then
			stackables[defId] = amount
		end
	end

	local consumables = {}
	for defId, amount in pairs(if typeof(inventory.Consumables) == "table" then inventory.Consumables else {}) do
		if typeof(defId) == "string" and typeof(amount) == "number" and amount > 0 then
			consumables[defId] = amount
		end
	end

	local slots = {}
	for slotName, uid in pairs(equippedSlots) do
		if typeof(slotName) == "string" and typeof(uid) == "string" then
			slots[slotName] = uid
		end
	end

	return {
		GeneratedAt = os.time(),
		Items = {
			Weapons = weapons,
			Gifts = gifts,
			Stackables = stackables,
			Consumables = consumables,
		},
		EquippedSlots = slots,
		Counts = {
			WeaponCount = (function()
				local count = 0
				for _ in pairs(weapons) do
					count += 1
				end
				return count
			end)(),
			GiftCount = (function()
				local count = 0
				for _ in pairs(gifts) do
					count += 1
				end
				return count
			end)(),
		},
	}
end

return SnapshotBuilder
