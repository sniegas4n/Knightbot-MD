--[[
	DebugController (ModuleScript) — CLIENT
	Emplacement : StarterPlayer > StarterPlayerScripts > Controllers > DebugController

	Raccourcis de test (Studio uniquement, le serveur vérifie aussi) :
	  F6 : +250 XP      F7 : +1000 Or
	  F8 : -20 PV       F9 : étourdissement 2 s
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared.Modules.Net)

local DebugController = {}

local BINDINGS = {
	[Enum.KeyCode.F6] = { "xp", 250 },
	[Enum.KeyCode.F7] = { "gold", 1000 },
	[Enum.KeyCode.F8] = { "damage", 20 },
	[Enum.KeyCode.F9] = { "stun", 2 },
}

function DebugController:Start()
	if not (RunService:IsStudio() and Config.Core.Debug.Enabled) then
		return
	end

	local remote = Net.Get("Debug_Command")
	if not remote then
		return
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		local binding = BINDINGS[input.KeyCode]
		if binding then
			remote:FireServer(binding[1], binding[2])
		end
	end)
end

return DebugController
