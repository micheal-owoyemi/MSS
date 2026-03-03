local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local controllersFolder = ReplicatedStorage:FindFirstChild("Controllers")
if controllersFolder ~= nil then
	Knit.AddControllers(controllersFolder)
end

local playerControllersFolder = ReplicatedStorage:FindFirstChild("PlayerControllers")
if playerControllersFolder ~= nil then
	Knit.AddControllers(playerControllersFolder)
end

Knit.Start():andThen(function()
	print("Knit Started!")
end):catch(warn)
