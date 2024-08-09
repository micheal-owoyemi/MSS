local WeaponClass = {}
WeaponClass.__index = WeaponClass
-- SERVICES
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- MODULES
local WeaponConfig = require(ReplicatedStorage.Shared.Configs.WeaponConfig)

-- FUNCTIONS
function WeaponClass.new(weaponType, weaponName)
    local self = setmetatable({
        weaponDMG = WeaponConfig[weaponType][weaponName].Damage,
        weaponType = weaponType,
        weaponName = weaponName
    }, WeaponClass)

    return self
end

return WeaponClass