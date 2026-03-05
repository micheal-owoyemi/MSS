--!strict

export type Config = {
	EquipActionName: string,
	MutationContextPrefix: string,
	LockReasonMaxLength: number,
	MaxUidLength: number,
	MaxDefIdLength: number,
}

local Config: Config = {
	EquipActionName = "Equip",
	MutationContextPrefix = "InventoryService",
	LockReasonMaxLength = 96,
	MaxUidLength = 80,
	MaxDefIdLength = 80,
}

return table.freeze(Config)
