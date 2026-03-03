--!strict
--[[
	TimeHelpers
	
	Common time resolution utilities used across services.
	
	Provides a consistent way to get server time with fallback to alternative sources.
]]

local Workspace = game:GetService("Workspace")

local TimeHelpers = {}

export type TimeHelpers = typeof(TimeHelpers)

--[=[
	Gets the current server time with intelligent fallback.
	
	Priority order:
	1. GameplayManagerService:Now() if available and provided
	2. Workspace:GetServerTimeNow() if available
	3. os.clock() as fallback
	
	@param gameplayManager? any -- Optional GameplayManagerService reference
	@return number -- Current server time in seconds
]=]
local function getServerTime(gameplayManager: any?): number
	if gameplayManager and typeof(gameplayManager.Now) == "function" then
		return (gameplayManager :: any):Now() :: number
	end

	if Workspace and typeof(Workspace.GetServerTimeNow) == "function" then
		return Workspace:GetServerTimeNow() :: number
	end

	return os.clock()
end

TimeHelpers.getServerTime = getServerTime

return TimeHelpers
