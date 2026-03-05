--!nonstrict

--[[
	GameplayManagerService Config

	Controls manager heartbeat scheduling.
	Time units are seconds unless stated otherwise.
]]

local Config = {
	HeartbeatRateHz = 10,
}

return table.freeze(Config)
