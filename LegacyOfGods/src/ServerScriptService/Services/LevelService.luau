--[[
	LevelService (ModuleScript) — SERVEUR
	Emplacement : ServerScriptService > Services > LevelService

	Gestion de l'expérience et des niveaux. Seul ce service modifie
	profile.Level / profile.Experience / profile.StatPoints (gain par niveau).

	Phase 1 : AddExperience + passage de niveaux multiples + points de stats.
	Phase 2 : distribution des points (Remote validé), bonus de statistiques.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared.Modules.Signal)
local ProgressionFormulas = require(Shared.Modules.ProgressionFormulas)
local Validate = require(ServerScriptService.Modules.Validate)
local Notifier = require(ServerScriptService.Modules.Notifier)

local Progression = Config.Progression

local LevelService = {
	LevelUp = Signal.new(), -- (player, newLevel, levelsGained)
	ExperienceGained = Signal.new(), -- (player, amount, source)
}

local PlayerStateService

-- Ajoute de l'XP. `source` sert au journal / aux quêtes ("Combat", "Quest"...).
-- Renvoie le nombre de niveaux gagnés.
function LevelService:AddExperience(player: Player, amount: number, source: string?): number
	local profile = PlayerStateService:GetProfile(player)
	if not profile then
		return 0
	end
	if not Validate.Number(amount, 0) or amount <= 0 then
		warn(("[LevelService] Montant d'XP invalide pour %s : %s"):format(player.Name, tostring(amount)))
		return 0
	end
	if ProgressionFormulas.IsMaxLevel(profile.Level) then
		return 0
	end

	-- Phase 3+ : multiplicateurs individuels (Game Pass, événements, prestige).
	local finalAmount = math.floor(math.min(amount, Progression.MaxExperiencePerGain) * Progression.GlobalExperienceMultiplier)
	if finalAmount <= 0 then
		return 0
	end

	profile.Experience += finalAmount

	local levelsGained = 0
	while not ProgressionFormulas.IsMaxLevel(profile.Level) do
		local required = ProgressionFormulas.ExperienceToNextLevel(profile.Level)
		if profile.Experience < required then
			break
		end
		profile.Experience -= required
		profile.Level += 1
		profile.StatPoints += Progression.StatPointsPerLevel
		levelsGained += 1
	end

	if ProgressionFormulas.IsMaxLevel(profile.Level) then
		profile.Experience = 0
	end

	PlayerStateService:Replicate(player, "Progression")
	self.ExperienceGained:Fire(player, finalAmount, source or "Unknown")

	if levelsGained > 0 then
		self.LevelUp:Fire(player, profile.Level, levelsGained)
		Notifier.Send(player, ("Niveau %d atteint ! +%d points de statistiques"):format(
			profile.Level,
			levelsGained * Progression.StatPointsPerLevel
		), "LevelUp")
	end

	return levelsGained
end

-- Réservé aux outils d'administration / debug.
function LevelService:SetLevel(player: Player, level: number)
	local profile = PlayerStateService:GetProfile(player)
	if not profile or not Validate.Integer(level, Progression.StartLevel, Progression.MaxLevel) then
		return
	end
	local delta = level - profile.Level
	profile.Level = level
	profile.Experience = 0
	if delta > 0 then
		profile.StatPoints += delta * Progression.StatPointsPerLevel
	end
	PlayerStateService:Replicate(player, "Progression")
end

function LevelService:GetLevel(player: Player): number
	local profile = PlayerStateService:GetProfile(player)
	return profile and profile.Level or Progression.StartLevel
end

function LevelService:Init(services)
	PlayerStateService = services.PlayerStateService
end

return LevelService
