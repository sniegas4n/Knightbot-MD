--!nonstrict
--[[
	Main (LocalScript)
	Location : StarterPlayer/StarterPlayerScripts/Client/Main
	Purpose  : The ONLY client LocalScript. Initialises every controller, forwards
	           CharacterAdded to them, then asks the server for the session state
	           (load finished? needs character creation?).
	All other client code lives in ModuleScripts under Controllers/ and UI/.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Modules.Net)

local player = Players.LocalPlayer
local Controllers = script.Parent:WaitForChild("Controllers")

local controllers = {
	Camera = require(Controllers.CameraController),
	Animation = require(Controllers.AnimationController),
	HUD = require(Controllers.HUDController),
	Movement = require(Controllers.MovementController),
	Combat = require(Controllers.CombatController),
	Creation = require(Controllers.CharacterCreationController),
}
local ORDER = { "Camera", "Animation", "HUD", "Movement", "Combat", "Creation" }

-- Our own HUD replaces the default health bar; there is no Roblox backpack.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

for _, name in ipairs(ORDER) do
	controllers[name].init(controllers)
end

local function onCharacterAdded(character)
	for _, name in ipairs(ORDER) do
		local controller = controllers[name]
		if controller.onCharacterAdded then
			task.spawn(controller.onCharacterAdded, character)
		end
	end
end
player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

task.spawn(function()
	local session = nil
	for _ = 1, 10 do
		local ok, result = pcall(Net.invoke, "GetSessionState")
		if ok and type(result) == "table" and result.ready then
			session = result
			break
		end
		task.wait(2)
	end
	if not session then
		controllers.HUD.notify("Could not reach your save. Please rejoin.")
		return
	end
	if session.temporary then
		controllers.HUD.setTemporaryWarning(true)
	end
	if session.needsCreation then
		controllers.Creation.open()
	else
		controllers.HUD.notify(("Welcome back, %s."):format(session.name or "wanderer"))
	end
end)
