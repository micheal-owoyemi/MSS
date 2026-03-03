--!strict

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local TableHelpers = {}

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

TableHelpers.cloneTable = TableUtil.shallowClone
TableHelpers.deepCopy = TableUtil.deepCopy
TableHelpers.deepFreeze = TableUtil.deepFreeze
TableHelpers.deepEqual = TableUtil.deepEqual
TableHelpers.arrayShallowEqual = TableUtil.arrayShallowEqual
TableHelpers.mergeWithDefaults = TableUtil.mergeWithDefaults
TableHelpers.ensurePath = ensurePath

return TableHelpers
