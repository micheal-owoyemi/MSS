local CoinDropEffect = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameWorld = require(ReplicatedStorage.Shared.Utilities.GameWorld)

function CoinDropEffect.spawn(originCFrame: CFrame, coinAmount: number, player: Player)
	local coinTemplate = ReplicatedStorage.Shared:WaitForChild("Assets").VFX.CoinDrop:Clone()

	local coinInstances = math.max(1, math.floor((tonumber(coinAmount) or 0) / 10))
	local spawnedCoins = {}

	for _ = 1, coinInstances do
		local coin = coinTemplate:Clone()
		coin.CFrame = originCFrame
		coin.Parent = GameWorld.getFXFolder(true)

		local randomX = { math.random(-10, -2), math.random(2, 10) }
		local randomZ = { math.random(-10, -2), math.random(2, 10) }
		coin.AssemblyLinearVelocity = Vector3.new(
			randomX[math.random(1, 2)],
			math.random(50, 100),
			randomZ[math.random(1, 2)]
		)

		table.insert(spawnedCoins, coin)
	end

	task.wait()

	for _, coin in ipairs(spawnedCoins) do
		CoinDropEffect.goToPlayer(player, coin)
	end
end

function CoinDropEffect.goToPlayer(player: Player, coinInstance: BasePart)
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
	local magnitude = (humanoidRootPart.Position - coinInstance.Position).Magnitude

	if coinInstance:IsA("Part") and coinInstance.Name == "CoinDrop" then
		coinInstance.CanCollide = false

		local tweenInfo = TweenInfo.new(magnitude * 0.01, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		local tween = TweenService:Create(coinInstance, tweenInfo, { Position = humanoidRootPart.Position })
		tween:Play()
		tween.Completed:Connect(function()
			coinInstance:Destroy()
		end)
		task.wait()
	end
end

return CoinDropEffect
