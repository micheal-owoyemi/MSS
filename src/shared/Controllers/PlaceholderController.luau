local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local PlaceholderController = Knit.CreateController({
	Name = "PlaceholderController",
})

function PlaceholderController:KnitInit()
	-- Placeholder to keep client bootstrap stable when no gameplay controllers are present.
end

return PlaceholderController
