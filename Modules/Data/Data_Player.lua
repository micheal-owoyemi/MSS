--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProfileSchema = require(ReplicatedStorage.Types.ProfileSchema)

return ProfileSchema.getTemplate()
