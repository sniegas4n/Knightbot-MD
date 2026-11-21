--[[
	CameraController (ModuleScript) — CLIENT
	Emplacement : StarterPlayer > StarterPlayerScripts > Controllers > CameraController

	La caméra troisième personne de base est celle de Roblox (fiable sur PC,
	mobile et manette). Les limites de zoom et la désactivation du Shift-Lock
	sont imposées par le serveur (CharacterService).

	Ce contrôleur ajoute :
	  - un champ de vision élargi pendant le sprint (attribut IsSprinting),
	  - un petit "coup" de FOV à l'esquive (CameraController:Kick()).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local CameraConfig = Config.Camera
local player = Players.LocalPlayer

local CameraController = {}

local currentTween: Tween?

local function getTargetFov(): number
	if player:GetAttribute("IsSprinting") == true then
		return CameraConfig.SprintFieldOfView
	end
	return CameraConfig.FieldOfView
end

local function tweenFov(fov: number, duration: number, style: Enum.EasingStyle?): Tween?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	if currentTween then
		currentTween:Cancel()
	end
	local tween = TweenService:Create(
		camera,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = fov }
	)
	currentTween = tween
	tween:Play()
	return tween
end

function CameraController:RefreshFov()
	tweenFov(getTargetFov(), CameraConfig.FieldOfViewTweenTime)
end

function CameraController:Kick()
	local tween = tweenFov(getTargetFov() + CameraConfig.DodgeFieldOfViewKick, CameraConfig.DodgeKickTime)
	if tween then
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				CameraController:RefreshFov()
			end
		end)
	end
end

function CameraController:Start()
	local function applyInstant()
		local camera = workspace.CurrentCamera
		if camera then
			camera.FieldOfView = getTargetFov()
		end
	end

	applyInstant()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(applyInstant)
	player:GetAttributeChangedSignal("IsSprinting"):Connect(function()
		CameraController:RefreshFov()
	end)
end

return CameraController
