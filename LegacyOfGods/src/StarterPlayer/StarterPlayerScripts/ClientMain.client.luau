--[[
	ClientMain (LocalScript) — CLIENT
	Emplacement : StarterPlayer > StarterPlayerScripts > ClientMain

	Unique point d'entrée client. Même cycle que ServerMain :
	  require de chaque contrôleur -> Init(controllers) -> Start().

	Les scripts de StarterPlayerScripts ne sont exécutés qu'UNE fois par
	session (pas à chaque réapparition) : les contrôleurs gèrent eux-mêmes
	CharacterAdded.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local ControllersFolder = script.Parent:WaitForChild("Controllers")

local LOAD_ORDER = {
	"InputController",
	"CameraController",
	"MovementController",
	"HUDController",
	"DebugController",
}

local controllers = {}
local ordered = {}

for _, name in LOAD_ORDER do
	local module = ControllersFolder:WaitForChild(name, 10)
	if not module or not module:IsA("ModuleScript") then
		warn(("[ClientMain] Contrôleur introuvable : %s"):format(name))
		continue
	end

	local ok, controller = pcall(require, module)
	if not ok then
		warn(("[ClientMain] Échec du chargement de %s : %s"):format(name, tostring(controller)))
		continue
	end

	controllers[name] = controller
	table.insert(ordered, { Name = name, Controller = controller })
end

for _, entry in ordered do
	if type(entry.Controller.Init) == "function" then
		local ok, err = pcall(entry.Controller.Init, entry.Controller, controllers)
		if not ok then
			warn(("[ClientMain] Init de %s a échoué : %s"):format(entry.Name, tostring(err)))
		end
	end
end

for _, entry in ordered do
	if type(entry.Controller.Start) == "function" then
		task.spawn(function()
			local ok, err = pcall(entry.Controller.Start, entry.Controller)
			if not ok then
				warn(("[ClientMain] Start de %s a échoué : %s"):format(entry.Name, tostring(err)))
			end
		end)
	end
end

if Config.Core.Debug.Verbose then
	print(("[ClientMain] %d contrôleur(s) démarré(s)"):format(#ordered))
end
