--!nonstrict
--[[
	EnvironmentService
	Location : ServerScriptService/Server/Core/EnvironmentService (ModuleScript)
	Purpose  : Atmosphere and a continuous real-time day/night cycle.
	           Time only moves forward at one fixed rate - there is no pause or
	           fast-forward anywhere in the game. The server owns Lighting.ClockTime
	           (it replicates), updated once per second to keep traffic negligible.
	           Milestone 7 adds dynamic weather (dust storms, rain) here.
	Depends  : GameConfig
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local EnvironmentService = {}

local function ensure(parent, className)
	local existing = parent:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local instance = Instance.new(className)
	instance.Parent = parent
	return instance
end

function EnvironmentService.init()
	Lighting.ClockTime = GameConfig.Environment.StartClockTime
	Lighting.Brightness = 2.2
	Lighting.GeographicLatitude = 23
	Lighting.Ambient = Color3.fromRGB(40, 36, 32)
	Lighting.OutdoorAmbient = Color3.fromRGB(122, 110, 96)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4

	local atmosphere = ensure(Lighting, "Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(199, 175, 140)
	atmosphere.Decay = Color3.fromRGB(106, 92, 78)
	atmosphere.Glare = 0.4
	atmosphere.Haze = 1.6

	local grade = ensure(Lighting, "ColorCorrectionEffect")
	grade.Saturation = -0.12
	grade.Contrast = 0.08
	grade.TintColor = Color3.fromRGB(255, 244, 228)

	local rays = ensure(Lighting, "SunRaysEffect")
	rays.Intensity = 0.06
	rays.Spread = 0.6

	local clouds = ensure(workspace.Terrain, "Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.6
	clouds.Color = Color3.fromRGB(230, 220, 205)

	workspace.GlobalWind = Vector3.new(8, 0, 4)
end

function EnvironmentService.start()
	local hoursPerSecond = 24 / (GameConfig.Environment.DayLengthMinutes * 60)
	task.spawn(function()
		while true do
			local dt = task.wait(1)
			Lighting.ClockTime = (Lighting.ClockTime + dt * hoursPerSecond) % 24
		end
	end)
end

return EnvironmentService
