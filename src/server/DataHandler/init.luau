
local ProfileTemplate = require(script.DefaultStats)

----- Services -------
local RunService = game:GetService('RunService')
local Players = game:GetService("Players")

----- Loaded Modules -----
local DataHandler = {}
local ProfileService = require(game.ServerScriptService.Server.ProfileService)
local PlayerProfileClass = require(script.PlayerProfile)
local ReplicaService = require(game.ServerScriptService.Server.ReplicaService)

----- Private Variables -----
local ClassToken = ReplicaService.NewClassToken("PlayerProfile")
local ProfileStore = ProfileService.GetProfileStore(
    "PlayerData",
    ProfileTemplate
)

if RunService:IsStudio() then
    ProfileStore = ProfileStore.Mock
end

local Profiles = PlayerProfileClass.PlayerProfiles 
local PlayerProfile = PlayerProfileClass.PlayerProfile

----- Private Functions -----

local function PlayerAdded(player)
    local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId)
    if profile ~= nil then
        profile:AddUserId(player.UserId) -- GDPR compliance
        profile:Reconcile() -- Fill in missing variables from ProfileTemplate (optional)
        profile:ListenToRelease(function()
            local profile = Profiles[player]
            if profile then
                profile:Release()
            end
            -- The profile could've been loaded on another Roblox server:
            player:Kick()
        end)
        if player:IsDescendantOf(Players) == true then

            local replica = ReplicaService.NewReplica({
                ClassToken = ClassToken,
                Tags = {Player = player},
                Data = profile.Data,
                Replication = 'All'
            })
            
            local playerProfile = PlayerProfile.new(profile, player, replica)
            -- A profile has been successfully loaded:
        else
            -- Player left before the profile loaded:
            profile:Release()
        end
    else
        -- The profile couldn't be loaded possibly due to other
        --   Roblox servers trying to load this profile at the same time:
        player:Kick() 
    end
end

function DataHandler:getProfileAsync(player)
    local profile = Profiles[player]

    while profile == nil and player:IsDescendantOf(Players) == true do
        task.wait()
        profile = Profiles[player]
    end

    return profile
end

----- Initialize -----

-- In case Players have joined the server earlier than this script ran:
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(PlayerAdded, player)
end

----- Connections -----

Players.PlayerAdded:Connect(PlayerAdded)

Players.PlayerRemoving:Connect(function(player)
    local profile = Profiles[player]
    if profile ~= nil then
        profile:Release()
    end
end)

return DataHandler