--!strict
--[[
	TableHelpers
	
	Common table manipulation utilities used across services.
]]

local TableHelpers = {}

export type TableHelpers = typeof(TableHelpers)

--[=[
	Creates a shallow clone of a table.
	
	Only copies immediate key-value pairs; nested tables are referenced, not cloned.
	
	@param source {[any]: any} -- The table to clone
	@return {[any]: any} -- A new table with the same immediate contents
]=]
local function cloneTable(source: {[any]: any}): {[any]: any}
	local copy: {[any]: any} = {}
	for key, value in pairs(source) do
		copy[key] = value
	end
	return copy
end

--[=[
	Ensures a nested table structure exists in the given data.
	
	If the table or any intermediate keys don't exist, they are created.
	
	@param data {[any]: any} -- The root data table
	@param ... string -- Path keys to ensure exist
	@return {[any]: any} -- The table at the specified path
]=]
local function ensurePath(data: {[any]: any}, ...: string): {[any]: any}
	local current = data
	for i = 1, select("#", ...) do
		local key = select(i, ...)
		if typeof(current[key]) ~= "table" then
			current[key] = {}
		end
		current = current[key] :: {[any]: any}
	end
	return current
end

--[=[
	Recursively compares two values for deep equality.

	Supports primitive values and tables. Cycles are tolerated via pair memoization.
]=]
local function deepEqual(a: any, b: any, seenPairs: {[any]: {[any]: boolean}}?): boolean
	if a == b then
		return true
	end

	local typeA = typeof(a)
	local typeB = typeof(b)
	if typeA ~= typeB then
		return false
	end

	if typeA ~= "table" then
		return false
	end

	local seen = seenPairs or {}
	if seenPairs == nil then
		seenPairs = seen
	end

	local seenForA = seen[a]
	if seenForA == nil then
		seenForA = {}
		seen[a] = seenForA
	elseif seenForA[b] == true then
		return true
	end

	seenForA[b] = true

	for key, value in pairs(a :: {[any]: any}) do
		if not deepEqual(value, (b :: {[any]: any})[key], seen) then
			return false
		end
	end

	for key in pairs(b :: {[any]: any}) do
		if (a :: {[any]: any})[key] == nil then
			return false
		end
	end

	return true
end

--[=[
	Compares two array-like tables for shallow equality.

	Supports an optional normalizer callback applied to each element before comparison.
]=]
local function arrayShallowEqual(a: any, b: any, normalizer: ((any) -> any)?): boolean
	if a == b then
		return true
	end

	if typeof(a) ~= "table" or typeof(b) ~= "table" then
		return false
	end

	if #a ~= #b then
		return false
	end

	for index = 1, #a do
		local valueA = a[index]
		local valueB = b[index]
		if normalizer ~= nil then
			valueA = normalizer(valueA)
			valueB = normalizer(valueB)
		end
		if valueA ~= valueB then
			return false
		end
	end

	return true
end

TableHelpers.cloneTable = cloneTable
TableHelpers.ensurePath = ensurePath
TableHelpers.deepEqual = deepEqual
TableHelpers.arrayShallowEqual = arrayShallowEqual

return TableHelpers
