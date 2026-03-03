local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

Knit.AddControllers(script.Parent.Controllers)
Knit.Start():catch(function(err)
	warn("[KnitClient] Failed to start:", err)
end)
