local Knit = require(game:GetService("ReplicatedStorage").Packages.Knit)
local ServerStorage = game:GetService("ServerStorage")

Knit.AddServices(ServerStorage.ServiceModules.GamePlaySystems)

Knit.Start():andThen(function()
	print("Knit Started!")
end):catch(warn)