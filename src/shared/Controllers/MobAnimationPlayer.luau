--!strict

type TrackByName = {[string]: AnimationTrack}
type AnimationByName = {[string]: Animation}

local STATE_TO_ANIMATION_NAME = table.freeze({
	Idle = "Idle",
	RoamMove = "Roam",
	Roam = "Roam",
})

local MobAnimationPlayer = {}
MobAnimationPlayer.__index = MobAnimationPlayer

local function indexAnimationsByName(animationsFolder: Instance): AnimationByName
	local indexed: AnimationByName = {}
	for _, child in ipairs(animationsFolder:GetChildren()) do
		if child:IsA("Animation") then
			indexed[string.lower(child.Name)] = child
		end
	end
	return indexed
end

local function resolveAnimationsFolder(model: Model): Instance?
	local direct = model:FindFirstChild("Animations")
	if direct ~= nil then
		return direct
	end
	return model:FindFirstChild("Animations", true)
end

local function resolveAnimator(model: Model): Animator?
	local animationController = model:FindFirstChildOfClass("AnimationController")
	if animationController == nil then
		animationController = model:FindFirstChildWhichIsA("AnimationController", true)
	end
	if animationController == nil then
		return nil
	end

	local animator = animationController:FindFirstChildOfClass("Animator")
	if animator ~= nil then
		return animator
	end

	local createdAnimator = Instance.new("Animator")
	createdAnimator.Parent = animationController
	return createdAnimator
end

function MobAnimationPlayer.new(model: Model): any
	local animationsFolder = resolveAnimationsFolder(model)
	local animator = resolveAnimator(model)
	local animationsByName = if animationsFolder ~= nil then indexAnimationsByName(animationsFolder) else {}

	local self = setmetatable({
		_model = model,
		_animator = animator,
		_animationsByName = animationsByName,
		_tracksByName = {} :: TrackByName,
		_currentState = nil :: string?,
		_currentTrack = nil :: AnimationTrack?,
	}, MobAnimationPlayer)

	return self
end

function MobAnimationPlayer:_resolveAnimationForState(stateName: string): Animation?
	local animationName = STATE_TO_ANIMATION_NAME[stateName]
	if animationName == nil then
		return nil
	end

	return self._animationsByName[string.lower(animationName)]
end

function MobAnimationPlayer:_stopCurrentTrack(fadeSeconds: number)
	local currentTrack: AnimationTrack? = self._currentTrack
	if currentTrack == nil then
		return
	end

	if currentTrack.IsPlaying then
		pcall(function()
			currentTrack:Stop(fadeSeconds)
		end)
	end
	self._currentTrack = nil
end

function MobAnimationPlayer:_getOrLoadTrackForState(stateName: string): AnimationTrack?
	local animation = self:_resolveAnimationForState(stateName)
	if animation == nil then
		return nil
	end

	local cacheKey = string.lower(animation.Name)
	local cached = self._tracksByName[cacheKey]
	if cached ~= nil then
		return cached
	end

	local animator: Animator? = self._animator
	if animator == nil then
		return nil
	end

	local ok, trackOrError = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		return nil
	end

	local track: AnimationTrack = trackOrError
	track.Looped = true
	self._tracksByName[cacheKey] = track
	return track
end

function MobAnimationPlayer:ApplyState(stateName: string)
	if self._currentState == stateName then
		local currentTrack: AnimationTrack? = self._currentTrack
		if currentTrack ~= nil and not currentTrack.IsPlaying then
			pcall(function()
				currentTrack:Play(0.1)
			end)
		end
		return
	end

	local nextTrack = self:_getOrLoadTrackForState(stateName)
	if nextTrack == nil then
		self:_stopCurrentTrack(0.1)
		self._currentState = stateName
		return
	end

	if self._currentTrack ~= nextTrack then
		self:_stopCurrentTrack(0.1)
	end

	if not nextTrack.IsPlaying then
		pcall(function()
			nextTrack:Play(0.1)
		end)
	end

	self._currentTrack = nextTrack
	self._currentState = stateName
end

function MobAnimationPlayer:Destroy()
	self:_stopCurrentTrack(0.05)

	for _, track in pairs(self._tracksByName) do
		pcall(function()
			track:Stop(0)
		end)
		pcall(function()
			track:Destroy()
		end)
	end

	table.clear(self._tracksByName)
	table.clear(self._animationsByName)
	self._animator = nil
	self._model = nil
	self._currentState = nil
end

return MobAnimationPlayer
