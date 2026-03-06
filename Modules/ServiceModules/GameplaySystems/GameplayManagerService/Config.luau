--!nonstrict

--[[
	GameplayManagerService Config

	Controls manager heartbeat scheduling.
	Time units are seconds unless stated otherwise.
]]

local Config = {
	-- MOST LIKELY TO TWEAK (global tick cadence):
	-- For "60fps-like" server stepping, set this to 60 if server load permits.
	HeartbeatRateHz = 10,
}

return table.freeze(Config)
