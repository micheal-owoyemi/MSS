local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataWeapons = require(ReplicatedStorage.Shared.Data.Data_Weapons)

local WeaponData = {}

function WeaponData.getDefinition(weaponType: string, weaponName: string): { [string]: any }?
	if type(weaponType) ~= "string" or weaponType == "" then
		return nil
	end
	if type(weaponName) ~= "string" or weaponName == "" then
		return nil
	end

	local byType = DataWeapons[weaponType]
	if type(byType) ~= "table" then
		return nil
	end

	local definition = byType[weaponName]
	if type(definition) ~= "table" then
		return nil
	end

	return definition
end

function WeaponData.getDamage(weaponType: string, weaponName: string, fallback: number?): number
	local definition = WeaponData.getDefinition(weaponType, weaponName)
	local damage = definition and definition.Damage
	local numericDamage = tonumber(damage)
	if type(numericDamage) == "number" then
		return numericDamage
	end

	return tonumber(fallback) or 0
end

function WeaponData.getImage(weaponType: string, weaponName: string, fallback: string?): string
	local definition = WeaponData.getDefinition(weaponType, weaponName)
	if not definition then
		return fallback or ""
	end

	local image = definition.Image or definition.Thumbnail
	if image == nil then
		return fallback or ""
	end

	return tostring(image)
end

function WeaponData.getSpacing(): number
	return tonumber(DataWeapons.Spacing) or 5
end

function WeaponData.getMaxClimbHeight(): number
	return tonumber(DataWeapons.MaxClimbHeight) or 6
end

return WeaponData
