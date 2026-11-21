--[[
	DebugService (ModuleScript) — SERVEUR
	Emplacement : ServerScriptService > Services > DebugService

	Outils de test. INACTIF hors de Roblox Studio (vérification
	RunService:IsStudio() côté serveur : un client ne peut pas le contourner,
	et le Remote Debug_Command n'est même pas créé en production).

	Deux façons de l'utiliser en Play Solo :
	  1. Touches F6 à F9 (DebugController côté client).
	  2. Chat : /xp 500   /level 50   /gold 1000   /crystals 50   /shards 5
	            /damage 30   /heal   /stun 2   /energy 40
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RemoteGuard = require(ServerScriptService.Modules.RemoteGuard)
local Validate = require(ServerScriptService.Modules.Validate)
local Notifier = require(ServerScriptService.Modules.Notifier)

local ENABLED = RunService:IsStudio() and Config.Core.Debug.Enabled

local DebugService = {}

local services

local COMMANDS: { [string]: (Player, number?) -> () } = {
	xp = function(player, value)
		services.LevelService:AddExperience(player, value or 250, "Debug")
	end,
	level = function(player, value)
		services.LevelService:SetLevel(player, math.floor(value or 10))
	end,
	gold = function(player, value)
		services.EconomyService:Add(player, "Gold", math.floor(value or 1000), "Debug")
	end,
	crystals = function(player, value)
		services.EconomyService:Add(player, "Crystals", math.floor(value or 50), "Debug")
	end,
	shards = function(player, value)
		services.EconomyService:Add(player, "DivineShards", math.floor(value or 5), "Debug")
	end,
	damage = function(player, value)
		local humanoid = services.CharacterService:GetAliveHumanoid(player)
		if humanoid then
			humanoid:TakeDamage(value or 20)
		end
	end,
	heal = function(player)
		local humanoid = services.CharacterService:GetAliveHumanoid(player)
		if humanoid then
			humanoid.Health = humanoid.MaxHealth
		end
	end,
	stun = function(player, value)
		if player.Character then
			services.CharacterService:Stun(player.Character, value or 2)
		end
	end,
	energy = function(player, value)
		services.ResourceService:TrySpend(player, "Energy", value or 30)
	end,
}

local function run(player: Player, command: any, value: any)
	if not Validate.String(command, 20) then
		return
	end
	if value ~= nil and not Validate.Number(value, -1e9, 1e12) then
		return
	end

	local handler = COMMANDS[string.lower(command)]
	if not handler then
		Notifier.Send(player, "Commande inconnue : " .. command, "Warning")
		return
	end
	handler(player, value)
end

function DebugService:Init(allServices)
	services = allServices
	if not ENABLED then
		return
	end

	-- Connecté dans Init (et non Start) pour ne rater aucun joueur.
	-- Commandes de chat : "/xp 500"
	services.PlayerStateService.PlayerReady:Connect(function(player)
		player.Chatted:Connect(function(message)
			local command, value = string.match(message, "^/(%a+)%s*(%-?[%d%.]*)$")
			if command then
				run(player, command, tonumber(value))
			end
		end)
	end)
end

function DebugService:Start()
	if not ENABLED then
		return
	end

	warn("[DebugService] Outils de debug ACTIFS (Studio uniquement)")

	RemoteGuard.OnServerEvent("Debug_Command", run)
end

return DebugService
