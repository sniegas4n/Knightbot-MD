--[[
	MovementService (ModuleScript) — SERVEUR
	Emplacement : ServerScriptService > Services > MovementService

	Sprint et esquive, validés côté serveur.

	Sprint (Remote Movement_RequestSprint(active: boolean)) :
	  le serveur vérifie l'endurance, active l'attribut Player.IsSprinting,
	  ajuste la vitesse (via CharacterService) et consomme l'endurance à
	  chaque tick tant que le joueur se déplace réellement.

	Esquive (Remote Movement_RequestDodge(direction: Vector3)) :
	  le CLIENT effectue le dash immédiatement (réactivité), le SERVEUR valide
	  cooldown + endurance et accorde seul les frames d'invulnérabilité.
	  Un client qui triche peut se déplacer (c'est vrai de tout jeu Roblox,
	  les déplacements étant physiquement gérés par le client), mais il ne
	  peut obtenir ni invulnérabilité ni esquive gratuite.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared.Modules.Signal)
local RemoteGuard = require(ServerScriptService.Modules.RemoteGuard)
local Validate = require(ServerScriptService.Modules.Validate)

local SprintConfig = Config.Movement.Sprint
local DodgeConfig = Config.Movement.Dodge

local MovementService = {
	Dodged = Signal.new(), -- (player, direction)
}

local CharacterService
local ResourceService

local sprinting: { [Player]: boolean } = {}
local lastDodgeTime: { [Player]: number } = {}

local function stopSprint(player: Player)
	if not sprinting[player] then
		return
	end
	sprinting[player] = nil
	player:SetAttribute("IsSprinting", false)
	CharacterService:RefreshWalkSpeed(player)
end

local function startSprint(player: Player)
	if sprinting[player] then
		return
	end
	local character = player.Character
	if not character or not CharacterService:IsAlive(player) or CharacterService:IsStunned(character) then
		return
	end
	local stamina = ResourceService:Get(player, "Stamina")
	if stamina < SprintConfig.MinStaminaToStart then
		return
	end

	sprinting[player] = true
	player:SetAttribute("IsSprinting", true)
	CharacterService:RefreshWalkSpeed(player)
end

local function onSprintRequest(player: Player, active: any)
	if not Validate.Boolean(active) then
		RemoteGuard.Flag(player, "Movement_RequestSprint", "argument invalide")
		return
	end
	if active then
		startSprint(player)
	else
		stopSprint(player)
	end
end

local function onDodgeRequest(player: Player, direction: any)
	if not Validate.Vector3(direction, 10) then
		RemoteGuard.Flag(player, "Movement_RequestDodge", "direction invalide")
		return
	end

	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 then
		return
	end

	local character = player.Character
	if not character or not CharacterService:IsAlive(player) or CharacterService:IsStunned(character) then
		return
	end

	local now = os.clock()
	local last = lastDodgeTime[player]
	if last and now - last < DodgeConfig.Cooldown - DodgeConfig.ServerCooldownTolerance then
		return -- trop tôt : ignoré (latence ou spam)
	end

	if not ResourceService:TrySpend(player, "Stamina", DodgeConfig.StaminaCost) then
		return
	end

	lastDodgeTime[player] = now
	CharacterService:SetInvulnerable(character, DodgeConfig.InvulnerabilityDuration)
	MovementService.Dodged:Fire(player, flat.Unit)
end

-- Appelé à chaque tick de ResourceService.
local function onTick(dt: number)
	for player in sprinting do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if not root or not CharacterService:IsAlive(player) or CharacterService:IsStunned(character :: Model) then
			stopSprint(player)
			continue
		end

		local velocity = (root :: BasePart).AssemblyLinearVelocity
		local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

		if horizontalSpeed >= SprintConfig.MinMovingSpeed then
			if not ResourceService:Drain(player, "Stamina", SprintConfig.StaminaCostPerSecond * dt) then
				stopSprint(player)
			end
		end
	end
end

local function cleanup(player: Player)
	sprinting[player] = nil
	lastDodgeTime[player] = nil
end

function MovementService:IsSprinting(player: Player): boolean
	return sprinting[player] == true
end

function MovementService:Init(services)
	CharacterService = services.CharacterService
	ResourceService = services.ResourceService

	ResourceService.Ticked:Connect(onTick)
	CharacterService.CharacterDied:Connect(stopSprint)
	CharacterService.CharacterSpawned:Connect(function(player)
		sprinting[player] = nil
	end)
	services.PlayerStateService.PlayerLeaving:Connect(cleanup)
end

function MovementService:Start()
	RemoteGuard.OnServerEvent("Movement_RequestSprint", onSprintRequest)
	RemoteGuard.OnServerEvent("Movement_RequestDodge", onDodgeRequest)
end

return MovementService
