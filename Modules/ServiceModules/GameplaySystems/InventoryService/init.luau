--!strict

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local TableUtil = require(ReplicatedStorage.Util.TableUtil)
local ValidationUtil = require(ReplicatedStorage.Util.ValidationUtil)
local ItemTypes = require(ReplicatedStorage.Types.ItemTypes)
local ItemDefinitions = require(ReplicatedStorage.Configs.ItemDefinitions)
local RemoteSchemas = require(ReplicatedStorage.Net.RemoteSchemas)

local Config = require(script.Config)
local InventoryRules = require(script.InventoryRules)
local SnapshotBuilder = require(script.SnapshotBuilder)

local ServiceModules = ServerStorage:WaitForChild("ServiceModules")
local SupportersFolder = ServiceModules:WaitForChild("Supporters")
local RateLimiter = require(SupportersFolder:WaitForChild("RateLimiter"))

local InventoryService = Knit.CreateService({
	Name = "InventoryService",
	Client = {},
})

function InventoryService.Client:RequestEquip(player: Player, weaponUid: string, slot: string)
	return self.Server:_requestEquipInternal(player, weaponUid, slot, true)
end

type PlayerDataServiceLike = {
	GetProfile: (self: PlayerDataServiceLike, player: Player) -> ({[string]: any}?, string?),
	MutateProfile: (self: PlayerDataServiceLike, player: Player, transformFn: (profileData: {[string]: any}, replica: any?) -> any, contextTag: string?) -> (boolean, string?),
}

local function isValidString(value: any, maxLength: number?): boolean
	if not ValidationUtil.isNonEmptyString(value) then
		return false
	end
	if maxLength ~= nil and string.len(value) > maxLength then
		return false
	end
	return true
end

local function clearEquippedUid(equippedSlots: {[string]: any}, uid: string)
	for slotName, equippedUid in pairs(equippedSlots) do
		if equippedUid == uid then
			equippedSlots[slotName] = ""
		end
	end
end

function InventoryService:KnitInit()
	self._config = Config
	self._itemDefinitions = ItemDefinitions
	self._playerDataService = nil :: PlayerDataServiceLike?
	self._serviceJanitor = Janitor.new()
	self._equipRateLimiter = RateLimiter.new()
end

function InventoryService:KnitStart()
	self._playerDataService = Knit.GetService("PlayerDataService") :: PlayerDataServiceLike

	self._serviceJanitor:Add(Players.PlayerRemoving:Connect(function(player: Player)
		self._equipRateLimiter:ClearPlayer(player)
	end), "Disconnect", "PlayerRemovingConnection")
end

function InventoryService:_buildUniqueUid(defId: string): string
	return string.format("%s_%s", defId, HttpService:GenerateGUID(false))
end

function InventoryService:_getProfile(player: Player): ({[string]: any}?, string?)
	local playerDataService = self._playerDataService
	if playerDataService == nil then
		return nil, "PlayerDataServiceUnavailable"
	end

	return playerDataService:GetProfile(player)
end

function InventoryService:HasItem(player: Player, itemUidOrDefId: string): (boolean, string?)
	if not ValidationUtil.isPlayer(player) then
		return false, "InvalidPlayer"
	end
	if not isValidString(itemUidOrDefId, self._config.MaxDefIdLength) then
		return false, "InvalidIdentifier"
	end

	local profile, reason = self:_getProfile(player)
	if profile == nil then
		return false, reason
	end

	return InventoryRules.hasItem(profile, itemUidOrDefId), nil
end

function InventoryService:AddItem(player: Player, itemRecord: {[string]: any}): (boolean, string?)
	if not ValidationUtil.isPlayer(player) then
		return false, "InvalidPlayer"
	end

	local payloadOk, payloadError = InventoryRules.validateAddPayload(itemRecord, self._config.MaxUidLength, self._config.MaxDefIdLength)
	if not payloadOk then
		return false, payloadError
	end

	local addError: string? = nil
	local contextTag = string.format("%s:AddItem", self._config.MutationContextPrefix)

	local playerDataService = self._playerDataService
	if playerDataService == nil then
		return false, "PlayerDataServiceUnavailable"
	end

	local success, reason = playerDataService:MutateProfile(player, function(profileData)
		local inventory = InventoryRules.ensureInventoryState(profileData)
		local defId = itemRecord.DefId
		local definition = InventoryRules.getDefinition(self._itemDefinitions, defId)
		if definition == nil then
			addError = "UnknownItemDefinition"
			error(addError)
		end

		local definitionType = definition.ItemType
		if not ItemTypes.isValidItemType(definitionType) then
			addError = "InvalidDefinitionType"
			error(addError)
		end

		local itemType = InventoryRules.normalizeItemType(itemRecord.ItemType or itemRecord.Type, definitionType)
		if itemType == nil then
			addError = "ItemTypeMismatch"
			error(addError)
		end

		local quantity = ItemTypes.sanitizeQuantity(itemRecord.Quantity, 1)
		if quantity <= 0 then
			addError = "InvalidQuantity"
			error(addError)
		end

		if definition.Stackable == true then
			local stackTable
			if itemType == "Stackable" then
				stackTable = inventory.Stackables
			elseif itemType == "Consumable" then
				stackTable = inventory.Consumables
			else
				addError = "InvalidStackItemType"
				error(addError)
			end

			local currentAmount = tonumber(stackTable[defId]) or 0
			local nextAmount = currentAmount + quantity
			local maxStack = tonumber(definition.MaxStack) or math.huge
			if nextAmount > maxStack then
				addError = "StackOverflow"
				error(addError)
			end
			stackTable[defId] = nextAmount
			return
		end

		if itemType ~= "Weapon" and itemType ~= "Gift" then
			addError = "InvalidUniqueItemType"
			error(addError)
		end

		local uid = itemRecord.Uid
		if uid == nil or uid == "" then
			uid = self:_buildUniqueUid(defId)
		end
		if not isValidString(uid, self._config.MaxUidLength) then
			addError = "InvalidUid"
			error(addError)
		end

		local existingGroup = InventoryRules.resolveUniqueItemByUid(inventory, uid)
		if existingGroup ~= nil then
			addError = "DuplicateUid"
			error(addError)
		end

		local now = os.time()
		if itemType == "Weapon" then
			inventory.Weapons[uid] = {
				Uid = uid,
				DefId = defId,
				Type = "Weapon",
				DisplayName = itemRecord.DisplayName or definition.DisplayName,
				Rarity = itemRecord.Rarity or "Common",
				Quantity = 1,
				CreatedAt = itemRecord.CreatedAt or now,
				WeaponDefId = defId,
				Level = ItemTypes.sanitizeQuantity(itemRecord.Level, 1),
				RolledStats = if typeof(itemRecord.RolledStats) == "table" then TableUtil.deepCopy(itemRecord.RolledStats) else {},
				IsTradable = if itemRecord.IsTradable ~= nil then itemRecord.IsTradable == true else definition.Tradable == true,
			}
		else
			inventory.Gifts[uid] = {
				Uid = uid,
				DefId = defId,
				Type = "Gift",
				DisplayName = itemRecord.DisplayName or definition.DisplayName,
				CreatedAt = itemRecord.CreatedAt or now,
				ExpiresAt = itemRecord.ExpiresAt or 0,
				SenderUserId = itemRecord.SenderUserId,
				RecipientUserId = itemRecord.RecipientUserId,
			}
		end
	end, contextTag)

	if not success then
		return false, addError or reason or "AddItemFailed"
	end

	return true, nil
end

function InventoryService:RemoveItem(player: Player, itemUidOrStackCount: any): (boolean, string?)
	if not ValidationUtil.isPlayer(player) then
		return false, "InvalidPlayer"
	end

	local removeSpec: {[string]: any}
	if typeof(itemUidOrStackCount) == "string" then
		removeSpec = {
			Identifier = itemUidOrStackCount,
			Quantity = 1,
		}
	elseif typeof(itemUidOrStackCount) == "table" then
		removeSpec = itemUidOrStackCount
	else
		return false, "InvalidRemoveSpec"
	end

	local removeError: string? = nil
	local contextTag = string.format("%s:RemoveItem", self._config.MutationContextPrefix)

	local playerDataService = self._playerDataService
	if playerDataService == nil then
		return false, "PlayerDataServiceUnavailable"
	end

	local success, reason = playerDataService:MutateProfile(player, function(profileData)
		local inventory, equippedSlots = InventoryRules.ensureInventoryState(profileData)
		local identifier = removeSpec.Uid or removeSpec.DefId or removeSpec.Identifier
		if not isValidString(identifier, self._config.MaxDefIdLength) then
			removeError = "InvalidIdentifier"
			error(removeError)
		end

		local quantity = ItemTypes.sanitizeQuantity(removeSpec.Quantity, 1)
		if quantity <= 0 then
			removeError = "InvalidQuantity"
			error(removeError)
		end

		local groupName, uniqueItem = InventoryRules.resolveUniqueItemByUid(inventory, identifier)
		if groupName ~= nil and uniqueItem ~= nil then
			if InventoryRules.isLocked(inventory, identifier) then
				removeError = "ItemLocked"
				error(removeError)
			end
			inventory[groupName][identifier] = nil
			inventory.LockedItems[identifier] = nil
			clearEquippedUid(equippedSlots, identifier)
			return
		end

		local stackType = removeSpec.ItemType or removeSpec.Type
		local stackTable = nil
		if stackType == "Stackable" then
			stackTable = inventory.Stackables
		elseif stackType == "Consumable" then
			stackTable = inventory.Consumables
		else
			if tonumber(inventory.Stackables[identifier]) ~= nil then
				stackTable = inventory.Stackables
			elseif tonumber(inventory.Consumables[identifier]) ~= nil then
				stackTable = inventory.Consumables
			end
		end

		if stackTable ~= nil then
			local currentAmount = tonumber(stackTable[identifier]) or 0
			if currentAmount < quantity then
				removeError = "InsufficientStack"
				error(removeError)
			end

			local nextAmount = currentAmount - quantity
			if nextAmount <= 0 then
				stackTable[identifier] = nil
			else
				stackTable[identifier] = nextAmount
			end
			return
		end

		for uid, weaponRecord in pairs(inventory.Weapons) do
			if typeof(weaponRecord) == "table" and weaponRecord.DefId == identifier then
				if InventoryRules.isLocked(inventory, uid) then
					removeError = "ItemLocked"
					error(removeError)
				end
				inventory.Weapons[uid] = nil
				inventory.LockedItems[uid] = nil
				clearEquippedUid(equippedSlots, uid)
				return
			end
		end

		for uid, giftRecord in pairs(inventory.Gifts) do
			if typeof(giftRecord) == "table" and giftRecord.DefId == identifier then
				if InventoryRules.isLocked(inventory, uid) then
					removeError = "ItemLocked"
					error(removeError)
				end
				inventory.Gifts[uid] = nil
				inventory.LockedItems[uid] = nil
				return
			end
		end

		removeError = "ItemNotFound"
		error(removeError)
	end, contextTag)

	if not success then
		return false, removeError or reason or "RemoveItemFailed"
	end

	return true, nil
end

function InventoryService:LockItem(player: Player, itemUid: string, reason: string?): (boolean, string?)
	if not ValidationUtil.isPlayer(player) then
		return false, "InvalidPlayer"
	end
	if not isValidString(itemUid, self._config.MaxUidLength) then
		return false, "InvalidUid"
	end
	if reason ~= nil and (typeof(reason) ~= "string" or string.len(reason) > self._config.LockReasonMaxLength) then
		return false, "InvalidLockReason"
	end

	local lockError: string? = nil
	local contextTag = string.format("%s:LockItem", self._config.MutationContextPrefix)

	local playerDataService = self._playerDataService
	if playerDataService == nil then
		return false, "PlayerDataServiceUnavailable"
	end

	local success, mutateReason = playerDataService:MutateProfile(player, function(profileData)
		local inventory = InventoryRules.ensureInventoryState(profileData)
		local groupName = InventoryRules.resolveUniqueItemByUid(inventory, itemUid)
		if groupName == nil then
			lockError = "ItemNotFound"
			error(lockError)
		end

		inventory.LockedItems[itemUid] = {
			Reason = reason,
			LockedAt = os.time(),
		}
	end, contextTag)

	if not success then
		return false, lockError or mutateReason or "LockFailed"
	end

	return true, nil
end

function InventoryService:UnlockItem(player: Player, itemUid: string): (boolean, string?)
	if not ValidationUtil.isPlayer(player) then
		return false, "InvalidPlayer"
	end
	if not isValidString(itemUid, self._config.MaxUidLength) then
		return false, "InvalidUid"
	end

	local unlockError: string? = nil
	local contextTag = string.format("%s:UnlockItem", self._config.MutationContextPrefix)

	local playerDataService = self._playerDataService
	if playerDataService == nil then
		return false, "PlayerDataServiceUnavailable"
	end

	local success, mutateReason = playerDataService:MutateProfile(player, function(profileData)
		local inventory = InventoryRules.ensureInventoryState(profileData)
		local groupName = InventoryRules.resolveUniqueItemByUid(inventory, itemUid)
		if groupName == nil then
			unlockError = "ItemNotFound"
			error(unlockError)
		end

		inventory.LockedItems[itemUid] = nil
	end, contextTag)

	if not success then
		return false, unlockError or mutateReason or "UnlockFailed"
	end

	return true, nil
end

function InventoryService:_requestEquipInternal(player: Player, weaponUid: string, slot: string, enforceRateLimit: boolean): (boolean, string?)
	if not ValidationUtil.isPlayer(player) then
		return false, "InvalidPlayer"
	end

	local validatedWeaponUid = weaponUid
	local validatedSlot = slot
	if enforceRateLimit then
		if self._equipRateLimiter:Consume(player, self._config.EquipActionName) == false then
			return false, "RateLimited"
		end

		local validation = RemoteSchemas.validate("Equip", {
			Slot = slot,
			ItemId = weaponUid,
		})
		if validation.ok ~= true then
			return false, validation.errorCode or "InvalidEquipPayload"
		end

		validatedWeaponUid = validation.sanitizedPayload.ItemId
		validatedSlot = validation.sanitizedPayload.Slot
	end

	if not isValidString(validatedWeaponUid, self._config.MaxUidLength) then
		return false, "InvalidWeaponUid"
	end
	if not isValidString(validatedSlot, self._config.MaxDefIdLength) then
		return false, "InvalidSlot"
	end

	local equipError: string? = nil
	local contextTag = string.format("%s:Equip", self._config.MutationContextPrefix)

	local playerDataService = self._playerDataService
	if playerDataService == nil then
		return false, "PlayerDataServiceUnavailable"
	end

	local success, mutateReason = playerDataService:MutateProfile(player, function(profileData)
		local inventory, equippedSlots = InventoryRules.ensureInventoryState(profileData)
		local weaponRecord = inventory.Weapons[validatedWeaponUid]
		if typeof(weaponRecord) ~= "table" then
			equipError = "WeaponNotOwned"
			error(equipError)
		end

		if InventoryRules.isLocked(inventory, validatedWeaponUid) then
			equipError = "ItemLocked"
			error(equipError)
		end

		local defId = weaponRecord.DefId
		local definition = InventoryRules.getDefinition(self._itemDefinitions, defId)
		if definition == nil then
			equipError = "UnknownItemDefinition"
			error(equipError)
		end
		if definition.ItemType ~= "Weapon" then
			equipError = "ItemTypeNotEquipable"
			error(equipError)
		end

		if not InventoryRules.isSlotAllowed(self._itemDefinitions.SlotDefinitions, definition, validatedSlot) then
			equipError = "InvalidEquipSlot"
			error(equipError)
		end

		clearEquippedUid(equippedSlots, validatedWeaponUid)
		equippedSlots[validatedSlot] = validatedWeaponUid
	end, contextTag)

	if not success then
		return false, equipError or mutateReason or "EquipFailed"
	end

	return true, nil
end

function InventoryService:RequestEquip(player: Player, weaponUid: string, slot: string): (boolean, string?)
	return self:_requestEquipInternal(player, weaponUid, slot, false)
end

function InventoryService:GetInventorySnapshot(player: Player): ({[string]: any}?, string?)
	if not ValidationUtil.isPlayer(player) then
		return nil, "InvalidPlayer"
	end

	local profile, reason = self:_getProfile(player)
	if profile == nil then
		return nil, reason
	end

	local snapshot = SnapshotBuilder.build(profile, self._itemDefinitions)
	return TableUtil.deepFreeze(snapshot), nil
end

function InventoryService:Destroy()
	if self._serviceJanitor ~= nil then
		self._serviceJanitor:Cleanup()
	end
	if self._equipRateLimiter ~= nil then
		self._equipRateLimiter:Destroy()
	end
end

return InventoryService
