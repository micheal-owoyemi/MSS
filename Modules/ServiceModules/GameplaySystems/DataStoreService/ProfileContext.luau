--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileTypes = require(ReplicatedStorage.Types.ProfileTypes)
local ValidationUtil = require(ReplicatedStorage.Util.ValidationUtil)

local ProfileContext = {}

type ProfileResolveReason = ProfileTypes.ProfileResolveReason
type ProfileData = ProfileTypes.ProfileData
type DataStoreServiceLike = ProfileTypes.DataStoreServiceLike
type ProfileContextRecord = ProfileTypes.ProfileContextRecord

type DirtyContext = {
	dataStore: DataStoreServiceLike?,
	player: Player?,
}

local FALLBACK_REASON: ProfileResolveReason = "ProfileUnavailable"

local function buildContext(dataStoreService: DataStoreServiceLike?, player: Player?): (ProfileContextRecord?, ProfileResolveReason?)
	if not ValidationUtil.isPlayer(player) then
		return nil, ("InvalidPlayer" :: ProfileResolveReason)
	end

	if dataStoreService == nil then
		return nil, ("ServiceUnavailable" :: ProfileResolveReason)
	end

	local profile, reason = dataStoreService:GetProfileAsync(player :: Player)
	if profile == nil then
		return nil, ((reason :: ProfileResolveReason?) or FALLBACK_REASON)
	end

	local rawProfile = profile.Profile
	local data = rawProfile and rawProfile.Data
	if typeof(data) ~= "table" then
		return nil, ("ProfileUnavailable" :: ProfileResolveReason)
	end

	return {
		dataStore = dataStoreService,
		player = player :: Player,
		profile = profile,
		data = data :: ProfileData,
		replica = profile.Replica,
		userId = (player :: Player).UserId,
	}, nil
end

function ProfileContext.resolve(dataStoreService: DataStoreServiceLike?, player: Player?): (ProfileContextRecord?, ProfileResolveReason?)
	local context, reason = buildContext(dataStoreService, player)
	if context == nil then
		return nil, (reason :: ProfileResolveReason?)
	end

	return context, nil
end

function ProfileContext.markDirty(context: (ProfileContextRecord | DirtyContext)?, contextTag: string?): boolean
	if context == nil then
		return false
	end

	local dataStore = context.dataStore
	local player = context.player
	if dataStore == nil or not ValidationUtil.isPlayer(player) then
		return false
	end

	return dataStore:MarkDirty(player :: Player, contextTag)
end

function ProfileContext.mapResolveReason(reason: ProfileResolveReason?, mapping: {[string]: string}, fallback: string): string
	if reason ~= nil then
		local mapped = mapping[reason]
		if mapped ~= nil then
			return mapped
		end
	end

	return fallback
end

return ProfileContext
