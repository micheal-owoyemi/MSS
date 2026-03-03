local WeaponReplicationPayload = {}

local function parseStateFields(data: any): (string?, Vector3?, Vector3?)
	if type(data) ~= "table" then
		return nil, nil, nil
	end

	local uuid = type(data.uuid) == "string" and data.uuid or nil
	local position = typeof(data.position) == "Vector3" and data.position or nil
	local orientation = typeof(data.orientation) == "Vector3" and data.orientation or nil

	return uuid, position, orientation
end

function WeaponReplicationPayload.parseState(data: any): (string?, Vector3?, Vector3?)
	local uuid, position, orientation = parseStateFields(data)
	if not (uuid and position and orientation) then
		return nil, nil, nil
	end

	return uuid, position, orientation
end

function WeaponReplicationPayload.parseBroadcastState(data: any): (number?, string?, Vector3?, Vector3?)
	local userId = tonumber(type(data) == "table" and data.id or nil)
	local uuid, position, orientation = parseStateFields(data)
	if not (userId and uuid and position and orientation) then
		return nil, nil, nil, nil
	end

	return userId, uuid, position, orientation
end

function WeaponReplicationPayload.create(
	userId: number,
	uuid: string,
	position: Vector3,
	orientation: Vector3
): { [string]: any }?
	if type(uuid) ~= "string" or uuid == "" then
		return nil
	end
	if type(tonumber(userId)) ~= "number" then
		return nil
	end
	if typeof(position) ~= "Vector3" or typeof(orientation) ~= "Vector3" then
		return nil
	end

	return {
		id = math.floor(userId),
		uuid = uuid,
		position = position,
		orientation = orientation,
	}
end

function WeaponReplicationPayload.fromWeaponModel(
	userId: number,
	uuid: string,
	weaponModel: Model
): { [string]: any }?
	if typeof(weaponModel) ~= "Instance" or not weaponModel:IsA("Model") then
		return nil
	end

	local primaryPart = weaponModel.PrimaryPart
	if not primaryPart then
		return nil
	end

	return WeaponReplicationPayload.create(userId, uuid, primaryPart.Position, primaryPart.Orientation)
end

function WeaponReplicationPayload.toCFrame(position: Vector3, orientation: Vector3): CFrame
	return CFrame.new(position)
		* CFrame.Angles(
			math.rad(orientation.X),
			math.rad(orientation.Y),
			math.rad(orientation.Z)
		)
end

return WeaponReplicationPayload
