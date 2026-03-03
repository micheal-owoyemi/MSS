--!strict

local TableUtil = {}

export type AnyMap = {[any]: any}

local function shallowClone(source: AnyMap): AnyMap
	local copy: AnyMap = {}
	for key, value in pairs(source) do
		copy[key] = value
	end
	return copy
end

local function deepCopy(value: any, seen: {[any]: any}?): any
	if typeof(value) ~= "table" then
		return value
	end

	local visited = seen
	if visited == nil then
		visited = {}
	end

	if visited[value] ~= nil then
		return visited[value]
	end

	local copy: AnyMap = {}
	visited[value] = copy

	for key, child in pairs(value :: AnyMap) do
		copy[deepCopy(key, visited)] = deepCopy(child, visited)
	end

	return copy
end

local function deepFreeze<T>(value: T, seen: {[any]: boolean}?): T
	if typeof(value) ~= "table" then
		return value
	end

	if table.isfrozen(value :: any) then
		return value
	end

	local visited = seen
	if visited == nil then
		visited = {}
	end

	if visited[value] then
		return value
	end
	visited[value] = true

	for _, child in pairs(value :: AnyMap) do
		if typeof(child) == "table" then
			deepFreeze(child, visited)
		end
	end

	return table.freeze(value :: any)
end

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

	local seen = seenPairs
	if seen == nil then
		seen = {}
	end

	local seenForA = seen[a]
	if seenForA == nil then
		seenForA = {}
		seen[a] = seenForA
	elseif seenForA[b] == true then
		return true
	end

	seenForA[b] = true

	for key, value in pairs(a :: AnyMap) do
		if not deepEqual(value, (b :: AnyMap)[key], seen) then
			return false
		end
	end

	for key in pairs(b :: AnyMap) do
		if (a :: AnyMap)[key] == nil then
			return false
		end
	end

	return true
end

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

local function mergeWithDefaults(source: AnyMap?, defaults: AnyMap): AnyMap
	local output = if source ~= nil then deepCopy(source) else {}
	for key, defaultValue in pairs(defaults) do
		local value = output[key]
		if value == nil then
			output[key] = deepCopy(defaultValue)
		elseif typeof(defaultValue) == "table" and typeof(value) == "table" then
			output[key] = mergeWithDefaults(value, defaultValue)
		end
	end
	return output
end

TableUtil.shallowClone = shallowClone
TableUtil.deepCopy = deepCopy
TableUtil.deepFreeze = deepFreeze
TableUtil.deepEqual = deepEqual
TableUtil.arrayShallowEqual = arrayShallowEqual
TableUtil.mergeWithDefaults = mergeWithDefaults

return TableUtil
