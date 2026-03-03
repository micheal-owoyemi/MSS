local Knit = require(game:GetService("ReplicatedStorage").Packages.Knit)
local ServerStorage = game:GetService("ServerStorage")

local serviceModules = ServerStorage:WaitForChild("ServiceModules")
local gameplaySystems = serviceModules:FindFirstChild("GameplaySystems")
	or serviceModules:FindFirstChild("GamePlaySystems")

if gameplaySystems == nil then
	error("Missing GameplaySystems folder under ServerStorage.ServiceModules")
end

Knit.AddServices(gameplaySystems)

Knit.Start():andThen(function()
	print("Knit Started!")
end):catch(warn)
