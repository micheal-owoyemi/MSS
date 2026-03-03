local Workspace = game:GetService("Workspace")

local GameWorld = {}

local function expectFolder(instance: Instance?, expectedName: string): Folder
	if not instance then
		error(string.format("[GameWorld] Missing folder '%s'", expectedName))
	end
	if not instance:IsA("Folder") then
		error(string.format("[GameWorld] Expected '%s' to be a Folder", expectedName))
	end
	return instance
end

local function getOrCreateFolder(parent: Instance, name: string, createIfMissing: boolean?): Folder
	local folder = parent:FindFirstChild(name)
	if folder and folder:IsA("Folder") then
		return folder
	end

	if createIfMissing == true then
		if folder then
			folder:Destroy()
		end

		local created = Instance.new("Folder")
		created.Name = name
		created.Parent = parent
		return created
	end

	return expectFolder(parent:WaitForChild(name), name)
end

function GameWorld.getGameFolder(): Folder
	return expectFolder(Workspace:WaitForChild("Game"), "Game")
end

function GameWorld.getZonesFolder(): Folder
	local gameFolder = GameWorld.getGameFolder()
	return expectFolder(gameFolder:WaitForChild("Zones"), "Zones")
end

function GameWorld.getWeaponsFolder(createIfMissing: boolean?): Folder
	local gameFolder = GameWorld.getGameFolder()
	return getOrCreateFolder(gameFolder, "Weapons", createIfMissing)
end

function GameWorld.getPlayerWeaponsFolder(userId: number | string, createIfMissing: boolean?): Folder?
	if type(userId) ~= "number" and type(userId) ~= "string" then
		return nil
	end

	local weaponsFolder: Folder? = nil
	if createIfMissing == true then
		weaponsFolder = GameWorld.getWeaponsFolder(true)
	else
		local existingWeapons = GameWorld.getGameFolder():FindFirstChild("Weapons")
		if existingWeapons and existingWeapons:IsA("Folder") then
			weaponsFolder = existingWeapons
		end
	end
	if not weaponsFolder then
		return nil
	end

	local playerFolderName = tostring(userId)

	local existing = weaponsFolder:FindFirstChild(playerFolderName)
	if existing then
		if existing:IsA("Folder") then
			return existing
		end

		if createIfMissing == true then
			existing:Destroy()
		else
			return nil
		end
	end

	if createIfMissing == true then
		local created = Instance.new("Folder")
		created.Name = playerFolderName
		created.Parent = weaponsFolder
		return created
	end

	return nil
end

function GameWorld.waitForPlayerWeaponsFolder(userId: number | string): Folder?
	if type(userId) ~= "number" and type(userId) ~= "string" then
		return nil
	end

	local weaponsFolder = GameWorld.getWeaponsFolder(false)
	local folder = weaponsFolder:WaitForChild(tostring(userId))
	if folder and folder:IsA("Folder") then
		return folder
	end

	return nil
end

function GameWorld.getFXFolder(createIfMissing: boolean?): Folder
	local gameFolder = GameWorld.getGameFolder()
	return getOrCreateFolder(gameFolder, "FX", createIfMissing)
end

return GameWorld
