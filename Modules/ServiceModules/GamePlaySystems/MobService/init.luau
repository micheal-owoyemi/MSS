local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MobManager = require(ReplicatedStorage.Shared.Managers.Mob)

local MobService = {
	Name = "MobService",
}

function MobService:Init()
	self._mobManager = MobManager.new()
end

function MobService:Start()
	if not self._mobManager then
		return
	end

	self._mobManager:setUpZoneSpawning()
end

function MobService:AttackMob(player: Player, targetPart: BasePart, equippedWeapons: { [string]: any })
	if not self._mobManager then
		return false, "MobManagerUnavailable"
	end

	self._mobManager:attackMob(player, targetPart, equippedWeapons)
	return true
end

return MobService
