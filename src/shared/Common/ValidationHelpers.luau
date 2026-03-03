--!strict
--[[
	ValidationHelpers
	
	Common validation and type-checking utilities used across services.
]]

local ValidationHelpers = {}

export type ValidationHelpers = typeof(ValidationHelpers)

--[=[
	Checks if a value is a valid Player instance.
	
	@param value any -- The value to check
	@return boolean -- True if value is a Player instance
]=]
local function isPlayer(value: any): boolean
	if typeof(value) ~= "Instance" then
		return false
	end
	local success = pcall(function()
		return (value :: Instance):IsA("Player")
	end)
	return success and (value :: Instance):IsA("Player") or false
end

--[=[
	Checks if a value is a finite number.
	
	Rejects NaN, infinity, and non-numeric types.
	
	@param value any -- The value to check
	@return boolean -- True if value is a finite number
]=]
local function isNumberFinite(value: any): boolean
	if typeof(value) ~= "number" then
		return false
	end

	if value ~= value then
		return false
	end

	if value == math.huge or value == -math.huge then
		return false
	end

	return true
end

--[=[
	Checks if a value is a non-empty string.
	
	@param value any -- The value to check
	@return boolean -- True if value is a non-empty string
]=]
local function isNonEmptyString(value: any): boolean
	return typeof(value) == "string" and value ~= ""
end

--[=[
	Checks if a value is a table.
	
	@param value any -- The value to check
	@return boolean -- True if value is a table
]=]
local function isTable(value: any): boolean
	return typeof(value) == "table"
end

ValidationHelpers.isPlayer = isPlayer
ValidationHelpers.isNumberFinite = isNumberFinite
ValidationHelpers.isNonEmptyString = isNonEmptyString
ValidationHelpers.isTable = isTable

return ValidationHelpers
