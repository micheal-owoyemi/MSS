--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data_MobDefs = require(ReplicatedStorage.Data.Data_MobDefs)
local Data_ZoneDefs = require(ReplicatedStorage.Data.Data_ZoneDefs)

local Data_Mobs = {
	Zones = {} :: {[string]: {Mobs: {[string]: any}}},
	Settings = {
		SpawnIntervals = 10,
		MinimumDistance = 100,
		MobCursor = "rbxasset://SystemCursors/PointingHand",
		DisengageCursor = "rbxassetid://100382422313044",
		Icons = {
			AlarmedIcon = "rbxassetid://111847898662707",
			TargetIcon = "rbxassetid://79817429248444",
			DeathIcon = "rbxassetid://108877701366175",
			VictoryIcon = "rbxassetid://87187170692394",
		},
	},
}

for zoneId, zoneDef in pairs(Data_ZoneDefs) do
	local mobsByName: {[string]: any} = {}
	for _, spawnInfo in ipairs(zoneDef.MobSpawnTable or {}) do
		local mobId = spawnInfo.MobId
		local mobDef = Data_MobDefs[mobId]
		if mobDef ~= nil then
			local displayName = mobDef.DisplayName
			mobsByName[displayName] = {
				Name = displayName,
				ParentZone = zoneId,
				ModelTemplate = mobId,
				DefaultHealth = mobDef.BaseHP,
				HealthValue = mobDef.BaseHP,
				AttackValue = mobDef.Damage,
				CoinValue = mobDef.Rewards.Gold,
				GemValue = mobDef.Rewards.Gems,
				Weight = spawnInfo.Weight or 0,
				CanBeEngaged = false,
			}
		end
	end
	Data_Mobs.Zones[zoneId] = {
		Mobs = mobsByName,
	}
end

return Data_Mobs
