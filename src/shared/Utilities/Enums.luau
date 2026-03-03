--!strict

local Data_EconomyDefs = require(script.Parent.Parent.Data.Data_EconomyDefs)

local currencies = {}
for currencyName in pairs(Data_EconomyDefs.Currencies) do
	currencies[currencyName] = currencyName
end

local Enums = {
	Currencies = table.freeze(currencies),

	SaveContext = {
		AutoSave = "AutoSave",
		ManualUpdate = "ManualUpdate",
		ManualSet = "ManualSet",
		Shutdown = "Shutdown",
	},

	LootTransactionContext = {
		Add = "AddCurrency",
		Remove = "RemoveCurrency",
		InitialSync = "InitialSync",
	},

	LootTransactionStatus = {
		Success = "Success",
		Rejected = "Rejected",
		Failed = "Failed",
	},

	LootError = {
		InvalidArguments = "InvalidArguments",
		InvalidPlayer = "InvalidPlayer",
		InvalidCurrency = "InvalidCurrency",
		ProfileUnavailable = "ProfileUnavailable",
		InvalidAmount = "InvalidAmount",
		ProfileServiceUnavailable = "ProfileServiceUnavailable",
		InsufficientFunds = "InsufficientFunds",
		UpdateAsyncFailed = "UpdateAsyncFailed",
		UpdateFailed = "UpdateFailed",
		AmountMustBePositive = "AmountMustBePositive",
	},

	InventoryError = {
		InvalidPlayer = "InvalidPlayer",
		ProfileServiceUnavailable = "ProfileServiceUnavailable",
		ProfileUnavailable = "ProfileUnavailable",
		InvalidAmount = "InvalidAmount",
		UpdateFailed = "UpdateFailed",
	},

	-- Input / Keybinds
	Keybinds = {
		--TBD
	},
}

return Enums
