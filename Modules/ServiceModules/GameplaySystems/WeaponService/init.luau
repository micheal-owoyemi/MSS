--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local TableUtil = require(ReplicatedStorage.Util.TableUtil)
local ValidationUtil = require(ReplicatedStorage.Util.ValidationUtil)
local WeaponDefs = require(ReplicatedStorage.Configs.WeaponDefs)
local CombatMath = require(ReplicatedStorage.Math.CombatMath)
local RemoteSchemas = require(ReplicatedStorage.Net.RemoteSchemas)

local Config = require(script.Config)
local StateSerializer = require(script.StateSerializer)

local ServiceModules = ServerStorage:WaitForChild("ServiceModules")
local SupportersFolder = ServiceModules:WaitForChild("Supporters")
local RateLimiter = require(SupportersFolder:WaitForChild("RateLimiter"))

type PlayerDataServiceLike = {
	GetProfile: (self: PlayerDataServiceLike, player: Player) -> ({[string]: any}?, string?),
}

type InventoryServiceLike = {
	RequestEquip: (self: InventoryServiceLike, player: Player, weaponUid: string, slot: string) -> (boolean, string?),
}

type MobServiceLike = {
	GetMobById: (self: MobServiceLike, mobId: string) -> any?,
	IsMobAttackable: (self: MobServiceLike, mobId: string) -> (boolean, string?),
	RegisterAttacker: (self: MobServiceLike, mobId: string, player: Player) -> (boolean, string?),
	UnregisterAttacker: (self: MobServiceLike, mobId: string, player: Player) -> (boolean, string?),
	ApplyDamage: (self: MobServiceLike, mobId: string, player: Player, amount: number, sourceMeta: any?) -> (boolean, string?),
}

type ZoneServiceLike = {
	IsMobTargetValidForZone: (self: ZoneServiceLike, mob: any, player: Player) -> (boolean, string?),
}

type GameplayManagerServiceLike = {
	RegisterSystem: (self: GameplayManagerServiceLike, name: string, system: {[string]: any}) -> (),
	UnregisterSystem: (self: GameplayManagerServiceLike, name: string) -> (),
}

type WeaponRuntime = {
	Uid: string,
	DefId: string,
	Slot: string,
	BaseDps: number,
	Cadence: number,
	Range: number,
	TargetMobId: string?,
	NextAttackAt: number,
	LastValidTargetAt: number,
	QueueIndex: number,
}

type PlayerRuntimeState = {
	Player: Player,
	UserId: number,
	WeaponsByUid: {[string]: WeaponRuntime},
	OrderedWeaponUids: {string},
	AssignedCountByMobId: {[string]: number},
	NextAssignCursor: number,
	PlayerTargetMobId: string?,
	LastEquipSignature: string,
	Revision: number,
	Dirty: boolean,
	LastSentRevision: number,
	ScratchTargetValidityByMobId: {[string]: boolean},
	ScratchMobRecordByMobId: {[string]: any},
	ScratchMobPositionByMobId: {[string]: any},
	Janitor: any,
}

type ResolvedEquippedWeapon = {
	Uid: string,
	DefId: string,
	Slot: string,
	BaseDps: number,
	Cadence: number,
	Range: number,
}

local WeaponService = Knit.CreateService({
	Name = "WeaponService",
	Client = {
		WeaponStateDelta = Knit.CreateSignal(),
	},
})

function WeaponService.Client:RequestAttackMob(player: Player, mobId: string, mode: string?)
	return self.Server:_requestAttackMobInternal(player, mobId, mode, true)
end

function WeaponService.Client:RequestEquip(player: Player, weaponUid: string, slot: string)
	return self.Server:_requestEquipInternal(player, weaponUid, slot, true)
end

function WeaponService.Client:ClearTarget(player: Player)
	return self.Server:ClearTarget(player)
end

local function isValidString(value: any, maxLength: number): boolean
	if not ValidationUtil.isNonEmptyString(value) then
		return false
	end
	return string.len(value) <= maxLength
end

local function resolveCharacterRootPosition(player: Player): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart.Position
	end

	if character.PrimaryPart ~= nil then
		return character.PrimaryPart.Position
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant.Position
		end
	end

	return nil
end

local function extractMobPosition(mobRecord: any): Vector3?
	if typeof(mobRecord) ~= "table" then
		return nil
	end

	local clientState = mobRecord.ClientState
	if typeof(clientState) == "table" and typeof(clientState.Position) == "Vector3" then
		return clientState.Position
	end

	local serverState = mobRecord.ServerState
	if typeof(serverState) == "table" and typeof(serverState.PositionXZ) == "Vector2" then
		local groundY = if ValidationUtil.isFiniteNumber(serverState.GroundY) then serverState.GroundY else 0
		local positionXZ = serverState.PositionXZ
		return Vector3.new(positionXZ.X, groundY, positionXZ.Y)
	end

	return nil
end

local function normalizeMode(rawMode: any): string
	if rawMode == "Double" then
		return "Double"
	end
	return "Single"
end

local NIL_CACHE_SENTINEL = {}

function WeaponService:KnitInit()
	self._config = Config
	self._weaponDefs = WeaponDefs
	self._playerDataService = nil :: PlayerDataServiceLike?
	self._inventoryService = nil :: InventoryServiceLike?
	self._mobService = nil :: MobServiceLike?
	self._zoneService = nil :: ZoneServiceLike?
	self._gameplayManager = nil :: GameplayManagerServiceLike?
	self._gameplaySystemName = "WeaponServiceRuntime"

	self._serviceJanitor = Janitor.new()
	self._requestRateLimiter = RateLimiter.new()
	self._statesByPlayer = {} :: {[Player]: PlayerRuntimeState}
	self._activePlayers = {} :: {[Player]: true}
	self._damageByMobIdScratch = {} :: {[string]: {[Player]: number}}
	self._damageBucketPool = {} :: {{[Player]: number}}
	self._replicationAccumulator = 0
	self._equipmentRefreshAccumulator = 0
end

function WeaponService:_acquireDamageBucket(): {[Player]: number}
	local pool = self._damageBucketPool
	local lastIndex = #pool
	if lastIndex <= 0 then
		return {}
	end
	local bucket = pool[lastIndex]
	pool[lastIndex] = nil
	return bucket
end

function WeaponService:_resetDamageScratch()
	local scratch = self._damageByMobIdScratch
	local pool = self._damageBucketPool
	for mobId, bucket in pairs(scratch) do
		table.clear(bucket)
		table.insert(pool, bucket)
		scratch[mobId] = nil
	end
end

function WeaponService:KnitStart()
	self._playerDataService = Knit.GetService("PlayerDataService") :: PlayerDataServiceLike
	self._inventoryService = Knit.GetService("InventoryService") :: InventoryServiceLike
	self._mobService = Knit.GetService("MobService") :: MobServiceLike
	self._zoneService = Knit.GetService("ZoneService") :: ZoneServiceLike
	self._gameplayManager = Knit.GetService("GameplayManagerService") :: GameplayManagerServiceLike

	local gameplayManager = self._gameplayManager
	if gameplayManager == nil then
		error("[WeaponService] GameplayManagerService is required")
	end

	gameplayManager:RegisterSystem(self._gameplaySystemName, {
		OnTick = function(_: any, now: number, dt: number)
			self:StepSimulation(now, dt)
			self:FlushReplication(now, dt)
		end,
		OnPlayerAdded = function(_: any, player: Player)
			self:_onPlayerAdded(player)
		end,
		OnPlayerRemoving = function(_: any, player: Player)
			self:_onPlayerRemoving(player)
		end,
	})
end

function WeaponService:_newState(player: Player): PlayerRuntimeState
	local stateJanitor = Janitor.new()
	local state: PlayerRuntimeState = {
		Player = player,
		UserId = player.UserId,
		WeaponsByUid = {},
		OrderedWeaponUids = {},
		AssignedCountByMobId = {},
		NextAssignCursor = 1,
		PlayerTargetMobId = nil,
		LastEquipSignature = "",
		Revision = 1,
		Dirty = true,
		LastSentRevision = 0,
		ScratchTargetValidityByMobId = {},
		ScratchMobRecordByMobId = {},
		ScratchMobPositionByMobId = {},
		Janitor = stateJanitor,
	}

	stateJanitor:Add(function()
		if self._statesByPlayer[player] == state then
			self._statesByPlayer[player] = nil
		end
	end)

	return state
end

function WeaponService:_getOrCreateState(player: Player): PlayerRuntimeState
	local existing = self._statesByPlayer[player]
	if existing ~= nil then
		return existing
	end

	local state = self:_newState(player)
	self._statesByPlayer[player] = state
	return state
end

function WeaponService:_markStateDirty(state: PlayerRuntimeState)
	state.Revision += 1
	state.Dirty = true
end

function WeaponService:_refreshPlayerTargetMobId(state: PlayerRuntimeState): boolean
	local previous = state.PlayerTargetMobId
	state.PlayerTargetMobId = nil
	for _, uid in ipairs(state.OrderedWeaponUids) do
		local weapon = state.WeaponsByUid[uid]
		if weapon ~= nil and weapon.TargetMobId ~= nil then
			state.PlayerTargetMobId = weapon.TargetMobId
			break
		end
	end
	return previous ~= state.PlayerTargetMobId
end

function WeaponService:_incrementMobAssignment(state: PlayerRuntimeState, mobId: string): boolean
	local mobService = self._mobService
	if mobService == nil then
		return false
	end

	local currentCount = state.AssignedCountByMobId[mobId] or 0
	if currentCount <= 0 then
		local okRegister = mobService:RegisterAttacker(mobId, state.Player)
		if not okRegister then
			return false
		end
	end

	state.AssignedCountByMobId[mobId] = currentCount + 1
	return true
end

function WeaponService:_decrementMobAssignment(state: PlayerRuntimeState, mobId: string)
	local currentCount = state.AssignedCountByMobId[mobId] or 0
	if currentCount <= 1 then
		state.AssignedCountByMobId[mobId] = nil
		local mobService = self._mobService
		if mobService ~= nil then
			mobService:UnregisterAttacker(mobId, state.Player)
		end
		return
	end

	state.AssignedCountByMobId[mobId] = currentCount - 1
end

function WeaponService:_unsetWeaponTarget(state: PlayerRuntimeState, weapon: WeaponRuntime): boolean
	local previousMobId = weapon.TargetMobId
	if previousMobId == nil then
		return false
	end

	weapon.TargetMobId = nil
	self:_decrementMobAssignment(state, previousMobId)
	return true
end

function WeaponService:_assignWeaponToMob(state: PlayerRuntimeState, weapon: WeaponRuntime, mobId: string, now: number): (boolean, boolean, string?)
	local previousMobId = weapon.TargetMobId
	if previousMobId == mobId then
		return true, false, nil
	end

	local changed = false
	if previousMobId ~= nil then
		changed = self:_unsetWeaponTarget(state, weapon) or changed
	end

	if not self:_incrementMobAssignment(state, mobId) then
		return false, changed, "UnableToRegisterAttacker"
	end

	weapon.TargetMobId = mobId
	weapon.NextAttackAt = math.min(weapon.NextAttackAt, now)
	weapon.LastValidTargetAt = now
	return true, true, nil
end

function WeaponService:_clearAssignments(state: PlayerRuntimeState, onlyMobId: string?, now: number?): boolean
	local changed = false
	for _, uid in ipairs(state.OrderedWeaponUids) do
		local weapon = state.WeaponsByUid[uid]
		if weapon ~= nil then
			local targetMobId = weapon.TargetMobId
			if targetMobId ~= nil then
				if onlyMobId == nil or onlyMobId == targetMobId then
					changed = self:_unsetWeaponTarget(state, weapon) or changed
					if now ~= nil then
						weapon.NextAttackAt = now
					end
				end
			end
		end
	end
	if self:_refreshPlayerTargetMobId(state) then
		changed = true
	end
	return changed
end

function WeaponService:_releaseStateAssignments(state: PlayerRuntimeState)
	self:_clearAssignments(state, nil, nil)
	table.clear(state.AssignedCountByMobId)
	state.PlayerTargetMobId = nil
end

function WeaponService:_destroyState(player: Player)
	local state = self._statesByPlayer[player]
	if state == nil then
		self._requestRateLimiter:ClearPlayer(player)
		return
	end

	self:_releaseStateAssignments(state)
	state.Janitor:Cleanup()
	self._requestRateLimiter:ClearPlayer(player)
end

function WeaponService:_resolveMobTargetValidity(player: Player, mobId: string): (boolean, string?)
	local mobService = self._mobService
	local zoneService = self._zoneService
	if mobService == nil then
		return false, "MobServiceUnavailable"
	end
	if zoneService == nil then
		return false, "ZoneServiceUnavailable"
	end

	local mobRecord = mobService:GetMobById(mobId)
	if mobRecord == nil then
		return false, "MobNotFound"
	end
	local clientState = mobRecord.ClientState
	if clientState == nil or clientState.Alive ~= true then
		return false, "MobDead"
	end
	if clientState.Attackable ~= true then
		return false, "MobNotAttackable"
	end

	local validForZone, zoneReason = zoneService:IsMobTargetValidForZone(mobRecord, player)
	if not validForZone then
		return false, zoneReason or "InvalidTargetForZone"
	end

	return true, nil
end

function WeaponService:_buildEquippedWeaponsFromProfile(player: Player): ({ResolvedEquippedWeapon}, string, string?)
	local playerDataService = self._playerDataService
	if playerDataService == nil then
		return {}, "", "PlayerDataServiceUnavailable"
	end

	local profileData, profileReason = playerDataService:GetProfile(player)
	if profileData == nil then
		return {}, "", profileReason or "ProfileUnavailable"
	end

	local inventory = if typeof(profileData.Inventory) == "table" then profileData.Inventory else {}
	local inventoryWeapons = if typeof(inventory.Weapons) == "table" then inventory.Weapons else {}
	local lockedItems = if typeof(inventory.LockedItems) == "table" then inventory.LockedItems else {}
	local equippedSlots = if typeof(profileData.EquippedSlots) == "table" then profileData.EquippedSlots else {}

	local slotNames = {}
	local seenSlotNames = {} :: {[string]: true}
	for _, slotName in ipairs(self._config.SlotPriority) do
		local uid = equippedSlots[slotName]
		if typeof(uid) == "string" and uid ~= "" then
			table.insert(slotNames, slotName)
			seenSlotNames[slotName] = true
		end
	end

	local extraSlotNames = {}
	for slotName, uid in pairs(equippedSlots) do
		if typeof(slotName) == "string" and typeof(uid) == "string" and uid ~= "" and seenSlotNames[slotName] ~= true then
			table.insert(extraSlotNames, slotName)
		end
	end

	table.sort(extraSlotNames)
	for _, slotName in ipairs(extraSlotNames) do
		table.insert(slotNames, slotName)
	end

	local seenByUid: {[string]: true} = {}
	local signatureParts = table.create(#slotNames)
	local resolved = {} :: {ResolvedEquippedWeapon}

	for _, slotName in ipairs(slotNames) do
		local weaponUid = equippedSlots[slotName]
		if typeof(weaponUid) == "string" and weaponUid ~= "" then
			table.insert(signatureParts, slotName .. "=" .. weaponUid)
			if seenByUid[weaponUid] ~= true and lockedItems[weaponUid] == nil then
				local weaponRecord = inventoryWeapons[weaponUid]
				if typeof(weaponRecord) == "table" then
					local defId = weaponRecord.DefId
					if typeof(defId) ~= "string" or defId == "" then
						defId = weaponRecord.WeaponDefId
					end
					local weaponDef = if typeof(defId) == "string" then self._weaponDefs[defId] else nil
					if typeof(weaponDef) == "table" then
						local cadence = math.max(0, tonumber(weaponDef.Cadence) or self._config.DefaultCadencePerSecond)
						local baseDps = math.max(0, tonumber(weaponDef.BaseDPS) or self._config.DefaultBaseDps)
						local range = math.max(0, tonumber(weaponDef.Range) or self._config.DefaultRangeStuds)

						seenByUid[weaponUid] = true
						table.insert(resolved, {
							Uid = weaponUid,
							DefId = defId,
							Slot = slotName,
							BaseDps = baseDps,
							Cadence = cadence,
							Range = range,
						})
					end
				end
			end
		end
	end

	return resolved, table.concat(signatureParts, "|"), nil
end

function WeaponService:_syncPlayerEquipmentState(player: Player, force: boolean?): (PlayerRuntimeState?, boolean, string?)
	if not ValidationUtil.isPlayer(player) then
		return nil, false, "InvalidPlayer"
	end

	local state = self:_getOrCreateState(player)
	local resolvedWeapons, signature, resolveReason = self:_buildEquippedWeaponsFromProfile(player)
	if resolveReason ~= nil then
		return state, false, resolveReason
	end

	local shouldApply = force == true or state.LastEquipSignature ~= signature
	if not shouldApply then
		return state, false, nil
	end

	local now = os.clock()
	local previousWeaponsByUid = state.WeaponsByUid
	local preservedTargetByUid: {[string]: string} = {}
	local preservedNextAttackAtByUid: {[string]: number} = {}
	for uid, previousWeapon in pairs(previousWeaponsByUid) do
		if previousWeapon.TargetMobId ~= nil then
			preservedTargetByUid[uid] = previousWeapon.TargetMobId
		end
		preservedNextAttackAtByUid[uid] = previousWeapon.NextAttackAt
	end

	self:_releaseStateAssignments(state)

	local rebuiltByUid: {[string]: WeaponRuntime} = {}
	local rebuiltOrdered: {string} = table.create(#resolvedWeapons)
	local queueIndex = 1

	for _, resolvedWeapon in ipairs(resolvedWeapons) do
		local uid = resolvedWeapon.Uid
		local nextAttackAt = preservedNextAttackAtByUid[uid]
		if not ValidationUtil.isFiniteNumber(nextAttackAt) then
			nextAttackAt = now
		end

		local rebuilt: WeaponRuntime = {
			Uid = uid,
			DefId = resolvedWeapon.DefId,
			Slot = resolvedWeapon.Slot,
			BaseDps = resolvedWeapon.BaseDps,
			Cadence = resolvedWeapon.Cadence,
			Range = resolvedWeapon.Range,
			TargetMobId = nil,
			NextAttackAt = nextAttackAt,
			LastValidTargetAt = now,
			QueueIndex = queueIndex,
		}

		local preservedTarget = preservedTargetByUid[uid]
		if preservedTarget ~= nil then
			local validTarget = self:_resolveMobTargetValidity(player, preservedTarget)
			if validTarget then
				if self:_incrementMobAssignment(state, preservedTarget) then
					rebuilt.TargetMobId = preservedTarget
				end
			end
		end

		rebuiltByUid[uid] = rebuilt
		rebuiltOrdered[queueIndex] = uid
		queueIndex += 1
	end

	state.WeaponsByUid = rebuiltByUid
	state.OrderedWeaponUids = rebuiltOrdered
	state.LastEquipSignature = signature

	local orderedCount = #state.OrderedWeaponUids
	if orderedCount <= 0 then
		state.NextAssignCursor = 1
	else
		state.NextAssignCursor = math.clamp(state.NextAssignCursor, 1, orderedCount)
	end

	self:_refreshPlayerTargetMobId(state)
	self:_markStateDirty(state)
	return state, true, nil
end

function WeaponService:_onPlayerAdded(player: Player)
	self._activePlayers[player] = true
	self:_syncPlayerEquipmentState(player, true)
end

function WeaponService:_onPlayerRemoving(player: Player)
	self._activePlayers[player] = nil
	self:_destroyState(player)
end

function WeaponService:_resolveStateForRequest(player: Player): (PlayerRuntimeState?, string?)
	local state, _, syncReason = self:_syncPlayerEquipmentState(player, false)
	if state == nil then
		return nil, syncReason or "StateUnavailable"
	end
	if syncReason ~= nil and #state.OrderedWeaponUids == 0 then
		return nil, syncReason
	end
	return state, nil
end

function WeaponService:_assignSingle(state: PlayerRuntimeState, targetMobId: string, now: number): (boolean, string?)
	local totalWeapons = #state.OrderedWeaponUids
	if totalWeapons <= 0 then
		return false, "NoEquippedWeapons"
	end

	local cursor = math.clamp(state.NextAssignCursor, 1, totalWeapons)
	local selectedWeapon: WeaponRuntime? = nil
	local selectedIndex = cursor

	for offset = 0, totalWeapons - 1 do
		local index = ((cursor + offset - 1) % totalWeapons) + 1
		local uid = state.OrderedWeaponUids[index]
		local weapon = state.WeaponsByUid[uid]
		if weapon ~= nil and weapon.TargetMobId == nil then
			selectedWeapon = weapon
			selectedIndex = index
			break
		end
	end

	if selectedWeapon == nil then
		local hadAssignments = self:_clearAssignments(state, nil, now)
		state.NextAssignCursor = 1
		if hadAssignments then
			self:_markStateDirty(state)
		end
		return true, nil
	end

	local assigned, changed, assignReason = self:_assignWeaponToMob(state, selectedWeapon, targetMobId, now)
	if not assigned then
		if changed then
			self:_markStateDirty(state)
		end
		return false, assignReason or "AssignFailed"
	end

	state.NextAssignCursor = (selectedIndex % totalWeapons) + 1
	state.PlayerTargetMobId = targetMobId
	if changed then
		self:_markStateDirty(state)
	end
	return true, nil
end

function WeaponService:_assignDouble(state: PlayerRuntimeState, targetMobId: string, now: number): (boolean, string?)
	if #state.OrderedWeaponUids <= 0 then
		return false, "NoEquippedWeapons"
	end

	local hasExistingOnTarget = false
	for _, uid in ipairs(state.OrderedWeaponUids) do
		local weapon = state.WeaponsByUid[uid]
		if weapon ~= nil and weapon.TargetMobId == targetMobId then
			hasExistingOnTarget = true
			break
		end
	end

	if hasExistingOnTarget then
		local changed = self:_clearAssignments(state, targetMobId, now)
		if changed then
			self:_markStateDirty(state)
		end
		return true, nil
	end

	local changed = false
	for _, uid in ipairs(state.OrderedWeaponUids) do
		local weapon = state.WeaponsByUid[uid]
		if weapon ~= nil then
			local assigned, didChange = self:_assignWeaponToMob(state, weapon, targetMobId, now)
			if not assigned then
				continue
			end
			changed = changed or didChange
		end
	end

	state.NextAssignCursor = 1
	if changed then
		state.PlayerTargetMobId = targetMobId
		self:_markStateDirty(state)
	end
	return true, nil
end

function WeaponService:_requestAttackMobInternal(player: Player, mobId: string, mode: string?, enforceRateLimit: boolean): (boolean, string?)
	if not ValidationUtil.isPlayer(player) then
		return false, "InvalidPlayer"
	end

	local normalizedMode = normalizeMode(mode)
	local normalizedMobId = mobId

	if enforceRateLimit then
		if self._requestRateLimiter:Consume(player, self._config.AttackActionName) == false then
			return false, "RateLimited"
		end

		local validation = RemoteSchemas.validate("Attack", {
			MobId = mobId,
			Mode = normalizedMode,
		})
		if validation.ok ~= true then
			return false, validation.errorCode or "InvalidAttackPayload"
		end

		normalizedMobId = validation.sanitizedPayload.MobId
		normalizedMode = validation.sanitizedPayload.Mode
	end

	if not isValidString(normalizedMobId, self._config.MaxMobIdLength) then
		return false, "InvalidMobId"
	end

	local state, stateReason = self:_resolveStateForRequest(player)
	if state == nil then
		return false, stateReason or "WeaponStateUnavailable"
	end
	if #state.OrderedWeaponUids <= 0 then
		return false, "NoEquippedWeapons"
	end

	local validTarget, validationReason = self:_resolveMobTargetValidity(player, normalizedMobId)
	if not validTarget then
		return false, validationReason or "InvalidTarget"
	end

	local now = os.clock()
	if normalizedMode == "Double" then
		return self:_assignDouble(state, normalizedMobId, now)
	end

	return self:_assignSingle(state, normalizedMobId, now)
end

function WeaponService:RequestAttackMob(player: Player, mobId: string, mode: string?): (boolean, string?)
	return self:_requestAttackMobInternal(player, mobId, mode, false)
end

function WeaponService:_requestEquipInternal(player: Player, weaponUid: string, slot: string, enforceRateLimit: boolean): (boolean, string?)
	if not ValidationUtil.isPlayer(player) then
		return false, "InvalidPlayer"
	end

	local normalizedWeaponUid = weaponUid
	local normalizedSlot = slot

	if enforceRateLimit then
		if self._requestRateLimiter:Consume(player, self._config.EquipActionName) == false then
			return false, "RateLimited"
		end

		local validation = RemoteSchemas.validate("Equip", {
			ItemId = weaponUid,
			Slot = slot,
		})
		if validation.ok ~= true then
			return false, validation.errorCode or "InvalidEquipPayload"
		end

		normalizedWeaponUid = validation.sanitizedPayload.ItemId
		normalizedSlot = validation.sanitizedPayload.Slot
	end

	if not isValidString(normalizedWeaponUid, self._config.MaxWeaponUidLength) then
		return false, "InvalidWeaponUid"
	end
	if not isValidString(normalizedSlot, self._config.MaxSlotLength) then
		return false, "InvalidSlot"
	end

	local inventoryService = self._inventoryService
	if inventoryService == nil then
		return false, "InventoryServiceUnavailable"
	end

	local equipOk, equipReason = inventoryService:RequestEquip(player, normalizedWeaponUid, normalizedSlot)
	if not equipOk then
		return false, equipReason or "EquipFailed"
	end

	self:_syncPlayerEquipmentState(player, true)
	return true, nil
end

function WeaponService:RequestEquip(player: Player, weaponUid: string, slot: string): (boolean, string?)
	return self:_requestEquipInternal(player, weaponUid, slot, false)
end

function WeaponService:GetEquippedWeapons(player: Player): ({[string]: any}?, string?)
	if not ValidationUtil.isPlayer(player) then
		return nil, "InvalidPlayer"
	end

	local state, resolveReason = self:_resolveStateForRequest(player)
	if state == nil then
		return nil, resolveReason or "WeaponStateUnavailable"
	end

	local out = table.create(#state.OrderedWeaponUids)
	for index, uid in ipairs(state.OrderedWeaponUids) do
		local weapon = state.WeaponsByUid[uid]
		if weapon ~= nil then
			out[index] = {
				Uid = weapon.Uid,
				DefId = weapon.DefId,
				Slot = weapon.Slot,
				TargetMobId = weapon.TargetMobId,
				QueueIndex = weapon.QueueIndex,
				NextAttackAt = weapon.NextAttackAt,
				Cadence = weapon.Cadence,
				Range = weapon.Range,
			}
		end
	end

	return TableUtil.deepFreeze(out), nil
end

function WeaponService:ClearTarget(player: Player): (boolean, string?)
	if not ValidationUtil.isPlayer(player) then
		return false, "InvalidPlayer"
	end

	local state, resolveReason = self:_resolveStateForRequest(player)
	if state == nil then
		return false, resolveReason or "WeaponStateUnavailable"
	end

	local changed = self:_clearAssignments(state, nil, os.clock())
	if changed then
		state.NextAssignCursor = 1
		self:_markStateDirty(state)
	end

	return true, nil
end

function WeaponService:_isWeaponInRange(weapon: WeaponRuntime, playerPosition: Vector3?, mobPosition: Vector3?): boolean
	if playerPosition == nil or mobPosition == nil then
		return false
	end
	return CombatMath.isWithinRange(playerPosition, mobPosition, weapon.Range, self._config.RangePaddingStuds)
end

function WeaponService:_stepPlayerState(now: number, state: PlayerRuntimeState, damageByMobId: {[string]: {[Player]: number}})
	local player = state.Player
	if player.Parent ~= Players then
		self:_destroyState(player)
		return
	end

	local stateChanged = false
	local mobService = self._mobService
	local zoneService = self._zoneService
	if mobService == nil then
		return
	end

	local playerPosition = resolveCharacterRootPosition(player)
	local targetValidityByMobId = state.ScratchTargetValidityByMobId
	local mobRecordByMobId = state.ScratchMobRecordByMobId
	local mobPositionByMobId = state.ScratchMobPositionByMobId
	table.clear(targetValidityByMobId)
	table.clear(mobRecordByMobId)
	table.clear(mobPositionByMobId)

	local function isTargetValidCached(mobId: string): boolean
		local cached = targetValidityByMobId[mobId]
		if cached ~= nil then
			return cached
		end

		local mobRecord = mobService:GetMobById(mobId)
		if mobRecord == nil then
			targetValidityByMobId[mobId] = false
			return false
		end
		local clientState = mobRecord.ClientState
		if clientState == nil or clientState.Alive ~= true or clientState.Attackable ~= true then
			targetValidityByMobId[mobId] = false
			return false
		end

		if zoneService ~= nil then
			local validForZone, _ = zoneService:IsMobTargetValidForZone(mobRecord, player)
			if not validForZone then
				targetValidityByMobId[mobId] = false
				return false
			end
		end

		targetValidityByMobId[mobId] = true
		mobRecordByMobId[mobId] = mobRecord
		return true
	end

	local function getMobPositionCached(mobId: string, mobRecord: any): Vector3?
		local cachedPosition = mobPositionByMobId[mobId]
		if cachedPosition ~= nil then
			if cachedPosition == NIL_CACHE_SENTINEL then
				return nil
			end
			return cachedPosition
		end
		local resolved = extractMobPosition(mobRecord)
		mobPositionByMobId[mobId] = if resolved ~= nil then resolved else NIL_CACHE_SENTINEL
		return resolved
	end

	for _, uid in ipairs(state.OrderedWeaponUids) do
		local weapon = state.WeaponsByUid[uid]
		if weapon ~= nil then
			local targetMobId = weapon.TargetMobId
			if targetMobId ~= nil then
				local stillValid = isTargetValidCached(targetMobId)
				if not stillValid then
					local invalidForSeconds = now - (weapon.LastValidTargetAt or now)
					if invalidForSeconds >= self._config.InvalidTargetGraceSeconds then
						stateChanged = self:_unsetWeaponTarget(state, weapon) or stateChanged
					end
				else
					local mobRecord = mobRecordByMobId[targetMobId]
					if mobRecord == nil then
						local invalidForSeconds = now - (weapon.LastValidTargetAt or now)
						if invalidForSeconds >= self._config.InvalidTargetGraceSeconds then
							stateChanged = self:_unsetWeaponTarget(state, weapon) or stateChanged
						end
					else
						weapon.LastValidTargetAt = now
						local cadence = weapon.Cadence
						local interval = CombatMath.cadenceToInterval(cadence)
						if interval ~= math.huge and interval > 0 then
							local nextAttackAt = weapon.NextAttackAt
							if not ValidationUtil.isFiniteNumber(nextAttackAt) then
								nextAttackAt = now
							end

							if now >= nextAttackAt then
								local due = math.floor(((now - nextAttackAt) / interval) + 1)
								local attacksDue = math.max(0, math.min(self._config.AttackCatchUpLimitPerTick, due))
								if attacksDue > 0 then
									local mobPosition = getMobPositionCached(targetMobId, mobRecord)
									if self:_isWeaponInRange(weapon, playerPosition, mobPosition) then
										local damagePerAttack = CombatMath.computeDamage(weapon.BaseDps, cadence, self._config.DamageMultiplier, 0)
										if damagePerAttack > 0 then
											local byPlayer = damageByMobId[targetMobId]
											if byPlayer == nil then
												byPlayer = self:_acquireDamageBucket()
												damageByMobId[targetMobId] = byPlayer
											end
											byPlayer[player] = (byPlayer[player] or 0) + (damagePerAttack * attacksDue)
										end
									end
									nextAttackAt += interval * attacksDue
								end
							end

							weapon.NextAttackAt = nextAttackAt
						end
					end
				end
			end
		end
	end

	if self:_refreshPlayerTargetMobId(state) then
		stateChanged = true
	end

	if stateChanged then
		self:_markStateDirty(state)
	end
end

function WeaponService:StepSimulation(now: number, dt: number)
	local refreshInterval = math.max(0.1, self._config.EquipmentRefreshIntervalSeconds)
	self._equipmentRefreshAccumulator += math.max(dt, 0)

	local shouldRefreshEquip = false
	if self._equipmentRefreshAccumulator >= refreshInterval then
		self._equipmentRefreshAccumulator -= refreshInterval
		shouldRefreshEquip = true
	end

	self:_resetDamageScratch()
	local damageByMobId: {[string]: {[Player]: number}} = self._damageByMobIdScratch

	for player in pairs(self._activePlayers) do
		local state = self._statesByPlayer[player]
		if state == nil then
			local createdState = self:_getOrCreateState(player)
			self:_syncPlayerEquipmentState(player, true)
			state = createdState
		elseif shouldRefreshEquip then
			self:_syncPlayerEquipmentState(player, false)
		end

		if state ~= nil then
			self:_stepPlayerState(now, state, damageByMobId)
		end
	end

	local mobService = self._mobService
	if mobService == nil then
		self:_resetDamageScratch()
		return
	end

	for mobId, byPlayer in pairs(damageByMobId) do
		for player, totalDamage in pairs(byPlayer) do
			mobService:ApplyDamage(mobId, player, totalDamage, {
				Source = "WeaponService",
				Timestamp = now,
			})
		end
	end

	self:_resetDamageScratch()
end

function WeaponService:_serializeState(state: PlayerRuntimeState, now: number): {[string]: any}
	local ordered = table.create(#state.OrderedWeaponUids)
	for index, uid in ipairs(state.OrderedWeaponUids) do
		local weapon = state.WeaponsByUid[uid]
		if weapon ~= nil then
			ordered[index] = {
				Uid = weapon.Uid,
				DefId = weapon.DefId,
				Slot = weapon.Slot,
				TargetMobId = weapon.TargetMobId,
				QueueIndex = weapon.QueueIndex,
				NextAttackAt = weapon.NextAttackAt,
				Cadence = weapon.Cadence,
				Range = weapon.Range,
			}
		end
	end

	return StateSerializer.SerializeSnapshot(
		state.Revision,
		state.PlayerTargetMobId,
		ordered,
		now
	)
end

function WeaponService:FlushReplication(now: number, dt: number)
	self._replicationAccumulator += math.max(dt, 0)
	local flushInterval = math.max(0.05, self._config.WeaponStateFlushIntervalSeconds)
	while self._replicationAccumulator >= flushInterval do
		self._replicationAccumulator -= flushInterval

		for player in pairs(self._activePlayers) do
			local state = self._statesByPlayer[player]
			if state == nil then
				local createdState = self:_getOrCreateState(player)
				self:_syncPlayerEquipmentState(player, true)
				state = createdState
			end

			if state ~= nil then
				if state.Dirty or state.LastSentRevision ~= state.Revision then
					local packet = self:_serializeState(state, now)
					self.Client.WeaponStateDelta:Fire(player, packet)
					state.Dirty = false
					state.LastSentRevision = state.Revision
				end
			end
		end
	end
end

function WeaponService:Destroy()
	local gameplayManager = self._gameplayManager
	if gameplayManager ~= nil then
		pcall(function()
			gameplayManager:UnregisterSystem(self._gameplaySystemName)
		end)
	end

	if self._serviceJanitor ~= nil then
		self._serviceJanitor:Cleanup()
	end
	if self._requestRateLimiter ~= nil then
		self._requestRateLimiter:Destroy()
	end

	for _, state in pairs(self._statesByPlayer) do
		self:_releaseStateAssignments(state)
		state.Janitor:Cleanup()
	end

	table.clear(self._statesByPlayer)
	table.clear(self._activePlayers)
	self:_resetDamageScratch()
	table.clear(self._damageBucketPool)
end

return WeaponService
