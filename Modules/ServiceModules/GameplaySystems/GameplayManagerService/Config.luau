--!nonstrict

--[[
	GameplayManagerService Config

	Controls manager heartbeat scheduling.
	Time units are seconds unless stated otherwise.
]]

local Config = {
	HeartbeatRateHz = 1,
}

return table.freeze(Config)
