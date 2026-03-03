local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local MobManager = require(script.Parent.Parent.Parent.Gameplay.Mob.MobManager)

local MobService = Knit.CreateService({
	Name = "MobService",
	Client = {},
})

function MobService:KnitInit()
	self._mobManager = MobManager.new()
end

function MobService:KnitStart()
	if not self._mobManager then
		return
	end

	self._mobManager:setupZoneSpawning()
end

function MobService:AttackMob(player: Player, targetPart: BasePart, equippedWeapons: { [string]: any })
	if not self._mobManager then
		return false, "MobManagerUnavailable"
	end

	self._mobManager:attackMob(player, targetPart, equippedWeapons)
	return true
end

return MobService
