-- Data_MobTemplate.lua
-- Provides a reusable structure for mob state entries.

local function makeMob(mobName: string, values: { [string]: any }?)
	if not mobName then
		return
	end

	local definition = values or {}
	local maxHealth = definition.HealthValue or 100

	return {
		Name = definition.Name or mobName,
		HealthValue = maxHealth,
		AttackValue = definition.AttackValue or 1,
		CoinValue = definition.CoinValue or 10,
		GemValue = definition.GemValue or 1,
		Weight = definition.Weight or 1,

		CurrentHealth = maxHealth,
		SpawnedAt = 0,
		LastDamagedAt = 0,
	}
end

return makeMob
