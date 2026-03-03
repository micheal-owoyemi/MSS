--!strict

local ValidationUtil = {}

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and (value :: Instance):IsA("Player")
end

local function isFiniteNumber(value: any): boolean
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

local function isNonEmptyString(value: any): boolean
	return typeof(value) == "string" and value ~= ""
end

local function isArray(value: any): boolean
	if typeof(value) ~= "table" then
		return false
	end

	local length = #value
	for key in pairs(value) do
		if typeof(key) ~= "number" or key < 1 or key > length or key % 1 ~= 0 then
			return false
		end
	end

	return true
end

local function isDictionary(value: any): boolean
	if typeof(value) ~= "table" then
		return false
	end

	for key in pairs(value) do
		if typeof(key) ~= "string" then
			return false
		end
	end

	return true
end

ValidationUtil.isPlayer = isPlayer
ValidationUtil.isFiniteNumber = isFiniteNumber
ValidationUtil.isNonEmptyString = isNonEmptyString
ValidationUtil.isArray = isArray
ValidationUtil.isDictionary = isDictionary

return ValidationUtil
