--!strict

local ValidationUtil = require(script.Parent.Parent.Util.ValidationUtil)

return {
	isPlayer = ValidationUtil.isPlayer,
	isNumberFinite = ValidationUtil.isFiniteNumber,
	isNonEmptyString = ValidationUtil.isNonEmptyString,
	isTable = function(value: any): boolean
		return typeof(value) == "table"
	end,
	isArray = ValidationUtil.isArray,
	isDictionary = ValidationUtil.isDictionary,
}
