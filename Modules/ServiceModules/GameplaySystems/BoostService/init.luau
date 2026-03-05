--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local BoostService = Knit.CreateService({
	Name = "BoostService",
	Client = {},
})

function BoostService:GetCurrencyPayoutMultiplier(_player: Player, _currencyId: string): number
	return 1
end

function BoostService:GetDropRateMultiplier(_player: Player): number
	return 1
end

return BoostService
