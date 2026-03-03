local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

Knit.AddControllers(ReplicatedStorage.Controllers)
Knit.AddControllers(ReplicatedStorage.PlayerControllers)

Knit.Start():andThen(function()
	print("Knit Started!")
end):catch(warn)