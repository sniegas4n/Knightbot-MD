--[[
	PlayerStateService (ModuleScript) — SERVEUR
	Emplacement : ServerScriptService > Services > PlayerStateService

	Propriétaire UNIQUE des profils joueurs en mémoire.

	Phase 1 : le profil est créé avec les valeurs par défaut (pas de sauvegarde).
	Phase 2 : ce service deviendra PlayerDataService (DataStore, verrou de
	          session, retry, autosave, migrations) SANS changer son interface :
	          GetProfile / Replicate / PlayerReady / PlayerLeaving.

	Réplication : les valeurs publiques sont copiées en ATTRIBUTS sur l'objet
	Player (Level, Experience, ExperienceRequired, StatPoints, Gold, Crystals,
	DivineShards, DataLoaded). Le client les LIT, il ne peut pas les modifier
	côté serveur (un changement d'attribut fait par le client ne réplique pas).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared.Modules.Signal)
local ProgressionFormulas = require(Shared.Modules.ProgressionFormulas)

local Progression = Config.Progression

export type Profile = {
	DataVersion: number,
	Level: number,
	Experience: number,
	StatPoints: number,
	Stats: { [string]: number },
	Currencies: { [string]: number },
}

local PlayerStateService = {
	PlayerReady = Signal.new(), -- (player, profile)
	PlayerLeaving = Signal.new(), -- (player, profile)
}

local profiles: { [Player]: Profile } = {}

local function createDefaultProfile(): Profile
	local stats = {}
	for _, stat in Progression.Stats do
		stats[stat.Id] = 0
	end

	local currencies = {}
	for id, definition in Config.Economy.Currencies do
		currencies[id] = definition.StartingAmount
	end

	return {
		DataVersion = Config.Core.DataVersion,
		Level = Progression.StartLevel,
		Experience = 0,
		StatPoints = Progression.StartingStatPoints,
		Stats = stats,
		Currencies = currencies,
	}
end

function PlayerStateService:GetProfile(player: Player): Profile?
	return profiles[player]
end

function PlayerStateService:IsReady(player: Player): boolean
	return profiles[player] ~= nil
end

-- Recopie les valeurs publiques du profil en attributs.
-- `section` (optionnel) : "Progression" | "Currencies" pour limiter l'écriture.
function PlayerStateService:Replicate(player: Player, section: string?)
	local profile = profiles[player]
	if not profile then
		return
	end

	if section == nil or section == "Progression" then
		player:SetAttribute("Level", profile.Level)
		player:SetAttribute("Experience", profile.Experience)
		player:SetAttribute("ExperienceRequired", ProgressionFormulas.ExperienceToNextLevel(profile.Level))
		player:SetAttribute("StatPoints", profile.StatPoints)
	end

	if section == nil or section == "Currencies" then
		for id, amount in profile.Currencies do
			player:SetAttribute(id, amount)
		end
	end
end

local function onPlayerAdded(player: Player)
	if profiles[player] then
		return
	end

	-- Phase 2 : ici, chargement asynchrone depuis DataStoreService avec
	-- verrou de session. Le joueur n'apparaît qu'une fois le profil prêt.
	local profile = createDefaultProfile()

	if player.Parent ~= Players then
		return -- le joueur est parti pendant le chargement
	end

	profiles[player] = profile
	PlayerStateService:Replicate(player)
	player:SetAttribute("DataLoaded", true)

	PlayerStateService.PlayerReady:Fire(player, profile)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end

	PlayerStateService.PlayerLeaving:Fire(player, profile)
	-- Phase 2 : sauvegarde finale + libération du verrou de session ici.
	profiles[player] = nil
end

function PlayerStateService:Init(_services)
	-- Aucune dépendance : c'est le premier service chargé.
end

function PlayerStateService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Joueurs déjà présents (fréquent en test Studio).
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	game:BindToClose(function()
		-- Phase 2 : sauvegarde de tous les profils avant l'arrêt du serveur.
		for _, player in Players:GetPlayers() do
			onPlayerRemoving(player)
		end
	end)
end

return PlayerStateService
