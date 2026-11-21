--[[
	CharacterService (ModuleScript) — SERVEUR
	Emplacement : ServerScriptService > Services > CharacterService

	Responsabilités :
	  - faire apparaître le personnage UNIQUEMENT quand le profil est prêt
	    (Players.CharacterAutoLoads = false),
	  - configurer le Humanoid (vie, vitesse, saut) depuis la config,
	  - réapparition après la mort,
	  - états temporaires du personnage (attributs sur le Model) :
	        Invulnerable (i-frames), Stunned (étourdissement),
	  - calcul CENTRALISÉ de la WalkSpeed (base, sprint, étourdissement).

	Les autres services ne modifient jamais Humanoid.WalkSpeed directement :
	ils appellent CharacterService:RefreshWalkSpeed(player).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared.Modules.Signal)
local Maid = require(Shared.Modules.Maid)

local CharacterConfig = Config.Character
local CameraConfig = Config.Camera
local MovementConfig = Config.Movement

local PLAYER_CHARACTER_TAG = "PlayerCharacter"
local HUMANOID_TIMEOUT = 10

local CharacterService = {
	CharacterSpawned = Signal.new(), -- (player, character, humanoid)
	CharacterDied = Signal.new(), -- (player, character)
}

local playerMaids: { [Player]: any } = {}
local characterMaids: { [Player]: any } = {}

-- Jetons des états temporaires : seul le dernier appel peut terminer l'état.
-- Table à clés faibles : les personnages détruits sont libérés.
local stateTokens: { [Model]: { [string]: number } } = setmetatable({}, { __mode = "k" }) :: any

local function getAliveHumanoid(character: Model?): Humanoid?
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

-- Active un attribut booléen pendant `duration` secondes.
-- Un nouvel appel prolonge/remplace l'état sans que l'ancien ne le coupe.
local function setTimedState(character: Model, attribute: string, duration: number, onEnd: (() -> ())?)
	local tokens = stateTokens[character]
	if not tokens then
		tokens = {}
		stateTokens[character] = tokens
	end

	local token = (tokens[attribute] or 0) + 1
	tokens[attribute] = token
	character:SetAttribute(attribute, true)

	task.delay(duration, function()
		if tokens[attribute] == token and character.Parent then
			character:SetAttribute(attribute, false)
			if onEnd then
				onEnd()
			end
		end
	end)
end

function CharacterService:GetAliveHumanoid(player: Player): Humanoid?
	return getAliveHumanoid(player.Character)
end

function CharacterService:IsAlive(player: Player): boolean
	return getAliveHumanoid(player.Character) ~= nil
end

function CharacterService:IsInvulnerable(character: Model): boolean
	return character:GetAttribute("Invulnerable") == true
end

function CharacterService:IsStunned(character: Model): boolean
	return character:GetAttribute("Stunned") == true
end

function CharacterService:SetInvulnerable(character: Model, duration: number)
	setTimedState(character, "Invulnerable", duration)
end

function CharacterService:Stun(character: Model, duration: number)
	local player = Players:GetPlayerFromCharacter(character)
	setTimedState(character, "Stunned", duration, function()
		if player then
			CharacterService:RefreshWalkSpeed(player)
		end
	end)
	if player then
		self:RefreshWalkSpeed(player)
	end
end

-- Recalcule la vitesse à partir de tous les modificateurs connus.
function CharacterService:RefreshWalkSpeed(player: Player)
	local character = player.Character
	local humanoid = getAliveHumanoid(character)
	if not character or not humanoid then
		return
	end

	local stunned = character:GetAttribute("Stunned") == true

	local speed = CharacterConfig.BaseWalkSpeed
	if player:GetAttribute("IsSprinting") == true then
		speed *= MovementConfig.Sprint.SpeedMultiplier
	end
	if stunned then
		speed = 0
	end
	-- Phase 3 : bonus d'Agilité, ralentissements (Œil du Temps), etc.

	humanoid.WalkSpeed = speed
	-- Étourdi = ni marche ni saut.
	humanoid.JumpHeight = if stunned then 0 else CharacterConfig.JumpHeight
end

local function onCharacterAdded(player: Player, character: Model)
	if characterMaids[player] then
		characterMaids[player]:Clean()
	end
	local maid = Maid.new()
	characterMaids[player] = maid

	local humanoid = character:WaitForChild("Humanoid", HUMANOID_TIMEOUT)
	if not humanoid or not humanoid:IsA("Humanoid") then
		warn(("[CharacterService] Humanoid introuvable pour %s"):format(player.Name))
		return
	end
	if player.Character ~= character then
		return -- remplacé entre-temps
	end

	humanoid.MaxHealth = CharacterConfig.BaseMaxHealth
	humanoid.Health = humanoid.MaxHealth
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = CharacterConfig.JumpHeight

	character:SetAttribute("Invulnerable", false)
	character:SetAttribute("Stunned", false)
	player:SetAttribute("IsSprinting", false)
	CollectionService:AddTag(character, PLAYER_CHARACTER_TAG)

	CharacterService:RefreshWalkSpeed(player)

	maid:Give(humanoid.Died:Connect(function()
		CharacterService.CharacterDied:Fire(player, character)

		task.delay(CharacterConfig.RespawnTime, function()
			-- On ne réapparaît que si le joueur est toujours là et que rien
			-- d'autre ne l'a déjà fait réapparaître.
			if player.Parent == Players and player.Character == character then
				player:LoadCharacter()
			end
		end)
	end))

	CharacterService.CharacterSpawned:Fire(player, character, humanoid)
end

local function setupPlayer(player: Player)
	if playerMaids[player] then
		return
	end
	local maid = Maid.new()
	playerMaids[player] = maid

	-- Caméra troisième personne + désactivation du Shift-Lock (Shift = sprint).
	player.CameraMinZoomDistance = CameraConfig.MinZoomDistance
	player.CameraMaxZoomDistance = CameraConfig.MaxZoomDistance
	if CameraConfig.DisableShiftLock then
		player.DevEnableMouseLock = false
	end

	maid:Give(player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end))

	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	else
		player:LoadCharacter()
	end
end

local function cleanupPlayer(player: Player)
	if characterMaids[player] then
		characterMaids[player]:Clean()
		characterMaids[player] = nil
	end
	if playerMaids[player] then
		playerMaids[player]:Clean()
		playerMaids[player] = nil
	end
end

function CharacterService:Init(services)
	-- Doit être fait le plus tôt possible. Réglez aussi ces propriétés dans
	-- Studio (voir INSTALLATION) au cas où un joueur arriverait avant ce script.
	Players.CharacterAutoLoads = false
	Players.RespawnTime = CharacterConfig.RespawnTime
	StarterPlayer.EnableMouseLockOption = not CameraConfig.DisableShiftLock

	services.PlayerStateService.PlayerReady:Connect(setupPlayer)
	services.PlayerStateService.PlayerLeaving:Connect(cleanupPlayer)
end

function CharacterService:Start()
	Players.PlayerRemoving:Connect(cleanupPlayer)
end

return CharacterService
