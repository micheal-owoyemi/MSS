local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local PlaceholderPlayerController = Knit.CreateController({
	Name = "PlaceholderPlayerController",
})

function PlaceholderPlayerController:KnitInit()
	-- Placeholder to keep player controller loading stable during early architecture setup.
end

return PlaceholderPlayerController
