--[[
	ServerMain (Script) — SERVEUR
	Emplacement : ServerScriptService > ServerMain

	Unique point d'entrée serveur. Il :
	  1. crée les Remotes (Net.Setup),
	  2. charge chaque service de ServerScriptService > Services dans l'ordre
	     défini par LOAD_ORDER,
	  3. appelle Service:Init(services) sur tous (câblage, AUCUNE attente),
	  4. puis Service:Start() sur tous (connexions, boucles).

	Ajouter un service : créer le ModuleScript dans Services, puis ajouter
	son nom dans LOAD_ORDER (après ses dépendances).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared.Modules.Net)

local ServicesFolder = ServerScriptService:WaitForChild("Services")

local LOAD_ORDER = {
	"PlayerStateService", -- profils joueurs (DataStore en Phase 2)
	"EconomyService", -- monnaies
	"LevelService", -- niveaux / XP
	"ResourceService", -- endurance / énergie
	"CharacterService", -- apparition, Humanoid, états (stun, i-frames)
	"MovementService", -- sprint, esquive
	"DebugService", -- outils de test (Studio uniquement)
}

print(("[ServerMain] %s v%s — démarrage"):format(Config.Core.GameName, Config.Core.Version))

Net.Setup()

local services = {}
local ordered = {}

for _, name in LOAD_ORDER do
	local module = ServicesFolder:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		warn(("[ServerMain] Service introuvable : %s"):format(name))
		continue
	end

	local ok, service = pcall(require, module)
	if not ok then
		warn(("[ServerMain] Échec du chargement de %s : %s"):format(name, tostring(service)))
		continue
	end

	services[name] = service
	table.insert(ordered, { Name = name, Service = service })
end

-- Init : chaque service récupère ses dépendances. Ne doit pas attendre.
for _, entry in ordered do
	if type(entry.Service.Init) == "function" then
		local ok, err = pcall(entry.Service.Init, entry.Service, services)
		if not ok then
			warn(("[ServerMain] Init de %s a échoué : %s"):format(entry.Name, tostring(err)))
		end
	end
end

-- Start : dans l'ordre, chacun dans son thread.
for _, entry in ordered do
	if type(entry.Service.Start) == "function" then
		task.spawn(function()
			local ok, err = pcall(entry.Service.Start, entry.Service)
			if not ok then
				warn(("[ServerMain] Start de %s a échoué : %s"):format(entry.Name, tostring(err)))
			end
		end)
	end
end

print(("[ServerMain] %d service(s) démarré(s)"):format(#ordered))
