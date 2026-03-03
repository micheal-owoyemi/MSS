-- Data_MobTemplate.lua
-- Provides a reusable structure for mob state entries.

local function makeMob(mobName: string, values: { [string]: any }?)
	if not mobName then
		return
	end

	local definition = values or {}
	local defaultHealth = definition.DefaultHealth or definition.HealthValue or 100
	local currentHealth = definition.Health or definition.CurrentHealth or defaultHealth
	local canBeEngaged = definition.CanBeEngaged
	if canBeEngaged == nil then
		canBeEngaged = false
	end

	return {
		Name = definition.Name or mobName,
		UUID = definition.UUID,
		ParentZone = definition.ParentZone,

		DefaultHealth = defaultHealth,
		Health = currentHealth,
		HealthValue = defaultHealth,
		CurrentHealth = currentHealth,

		AttackValue = definition.AttackValue or 0,

		CoinValue = definition.CoinValue or 0,
		GemValue = definition.GemValue or 0,

		Weight = definition.Weight or 0,


		SpawnLocation = definition.SpawnLocation,
		CanBeEngaged = canBeEngaged,
		DamageDoneByPlayers = {},

		SpawnedAt = 0,
		LastDamagedAt = 0,
	}
end

return makeMob
