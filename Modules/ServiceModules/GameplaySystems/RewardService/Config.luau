--!strict

export type Config = {
	MutationContextPrefix: string,
	DefaultRewardReason: string,
	MaxReasonLength: number,
	MaxTransactionHistoryEntries: number,
	MinContributionShare: number,
	MaxCurrencyGrantPerKill: number,
	MaxDropChancePerEntry: number,
	DropRollsHardCap: number,
}

local Config: Config = {
	MutationContextPrefix = "RewardService",
	DefaultRewardReason = "Reward",
	MaxReasonLength = 64,
	MaxTransactionHistoryEntries = 50,
	MinContributionShare = 0,
	MaxCurrencyGrantPerKill = 1_000_000_000,
	MaxDropChancePerEntry = 0.95,
	DropRollsHardCap = 5,
}

return table.freeze(Config)
