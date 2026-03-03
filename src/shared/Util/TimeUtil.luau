--!strict

local Workspace = game:GetService("Workspace")

local TimeUtil = {}

local function getServerTime(timeProvider: {Now: (any) -> number}?): number
	if timeProvider and typeof(timeProvider.Now) == "function" then
		return timeProvider:Now()
	end

	if typeof(Workspace.GetServerTimeNow) == "function" then
		return Workspace:GetServerTimeNow()
	end

	return os.clock()
end

TimeUtil.getServerTime = getServerTime

return TimeUtil
