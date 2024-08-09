local PlayerProfile = {}
PlayerProfile.__index = PlayerProfile

local PlayerProfiles = {}

-- SERVICES
local HTTPService = game:GetService('HttpService')

function PlayerProfile.new(profile, player, replica)
    local self = setmetatable({
        Profile = profile,
        Replica = replica,
        _player = player,
    }, PlayerProfile)

    PlayerProfiles[player] = self
    return self
end

function PlayerProfile:giveCoins(amount)
    if not self:IsActive() then
        return
    end
    local currentCoins = self:getCoins()
    self.Replica:SetValue({'Coins'}, currentCoins + amount)
end

function PlayerProfile:getCoins()
    if not self:IsActive() then
        return
    end

    return self.Profile.Data.Coins
end

function PlayerProfile:addWeapon(weaponObject)
    if not self:IsActive() then
        return
    end

    local weaponData = {
        weaponName = weaponObject.weaponName,
        weaponType = weaponObject.weaponType
    }
    local UUID = HTTPService:GenerateGUID(false)
    self.Replica:SetValue({'Weapons', UUID}, weaponData)
    print(self.Replica.Data)
end

function PlayerProfile:addZone(zone)
    if not self:IsActive() then
        return
    end

    self.Profile.Data.Zone[zone] = true
end

function PlayerProfile:IsActive()
    return PlayerProfiles[self._player] ~= nil
end

function PlayerProfile:Release()
    PlayerProfiles[self._player] = nil
end



return {PlayerProfiles = PlayerProfiles, PlayerProfile = PlayerProfile}
 -- To return both PlayerProfiles as well as the object