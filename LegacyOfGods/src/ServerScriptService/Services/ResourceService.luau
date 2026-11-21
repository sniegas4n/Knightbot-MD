--[[
	ResourceService (ModuleScript) — SERVEUR
	Emplacement : ServerScriptService > Services > ResourceService

	Ressources de combat : Stamina (endurance) et Energy (énergie).
	Valeurs AUTORITAIRES gardées dans une table serveur ; elles sont
	recopiées en attributs sur le Player pour le HUD :
		Stamina, MaxStamina, Energy, MaxEnergy

	Une SEULE boucle (Heartbeat cadencé à Config.Character.ResourceTickRate)
	gère la régénération de tous les joueurs, et publie le signal Ticked(dt)
	utilisé par MovementService pour la consommation du sprint.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Signal = require(Shared.Modules.Signal)
local Validate = require(ServerScriptService.Modules.Validate)

local ResourcesConfig = Config.Character.Resources
local RESOURCE_IDS = { "Stamina", "Energy" }
local TICK_INTERVAL = 1 / Config.Character.ResourceTickRate

type Resource = { Current: number, Max: number, LastUse: number }
type ResourceState = { [string]: Resource }

local ResourceService = {
	Ticked = Signal.new(), -- (dt)
	Depleted = Signal.new(), -- (player, resourceId)
}

local states: { [Player]: ResourceState } = {}

local function round1(value: number): number
	return math.floor(value * 10 + 0.5) / 10
end

local function replicate(player: Player, id: string, resource: Resource)
	player:SetAttribute(id, round1(resource.Current))
	player:SetAttribute("Max" .. id, resource.Max)
end

local function ensureState(player: Player): ResourceState
	local state = states[player]
	if state then
		return state
	end

	state = {}
	for _, id in RESOURCE_IDS do
		local max = ResourcesConfig[id].BaseMax
		state[id] = { Current = max, Max = max, LastUse = 0 }
	end
	states[player] = state
	return state
end

local function getResource(player: Player, id: string): Resource?
	local state = states[player]
	return state and state[id]
end

function ResourceService:Get(player: Player, id: string): (number, number)
	local resource = getResource(player, id)
	if not resource then
		return 0, 0
	end
	return resource.Current, resource.Max
end

-- Remplit toutes les ressources (apparition).
function ResourceService:Refill(player: Player)
	local state = ensureState(player)
	for id, resource in state do
		resource.Current = resource.Max
		resource.LastUse = 0
		replicate(player, id, resource)
	end
end

-- Dépense atomique : tout ou rien. Renvoie true si la dépense a eu lieu.
function ResourceService:TrySpend(player: Player, id: string, amount: number): boolean
	local resource = getResource(player, id)
	if not resource or not Validate.Number(amount, 0) then
		return false
	end
	if resource.Current < amount then
		return false
	end

	resource.Current -= amount
	resource.LastUse = os.clock()
	replicate(player, id, resource)

	if resource.Current <= 0 then
		self.Depleted:Fire(player, id)
	end
	return true
end

-- Consommation continue (sprint) : retire jusqu'à `amount`.
-- Renvoie false si la ressource est vide après la consommation.
function ResourceService:Drain(player: Player, id: string, amount: number): boolean
	local resource = getResource(player, id)
	if not resource or not Validate.Number(amount, 0) then
		return false
	end

	resource.Current = math.max(0, resource.Current - amount)
	resource.LastUse = os.clock()
	replicate(player, id, resource)

	if resource.Current <= 0 then
		self.Depleted:Fire(player, id)
		return false
	end
	return true
end

-- Modifie le maximum (Phase 2 : bonus des statistiques Endurance / Énergie).
function ResourceService:SetMax(player: Player, id: string, max: number)
	local resource = getResource(player, id)
	if not resource or not Validate.Number(max, 1) then
		return
	end
	resource.Max = max
	resource.Current = math.min(resource.Current, max)
	replicate(player, id, resource)
end

local function regenerate(dt: number)
	local now = os.clock()
	for player, state in states do
		for id, resource in state do
			if resource.Current < resource.Max then
				local settings = ResourcesConfig[id]
				if now - resource.LastUse >= settings.RegenDelay then
					resource.Current = math.min(resource.Max, resource.Current + settings.RegenPerSecond * dt)
					replicate(player, id, resource)
				end
			end
		end
	end
end

function ResourceService:Init(services)
	local PlayerStateService = services.PlayerStateService
	local CharacterService = services.CharacterService

	PlayerStateService.PlayerReady:Connect(function(player)
		ensureState(player)
		ResourceService:Refill(player)
	end)

	PlayerStateService.PlayerLeaving:Connect(function(player)
		states[player] = nil
	end)

	-- CharacterService est initialisé après nous mais existe déjà dans la table.
	if CharacterService then
		CharacterService.CharacterSpawned:Connect(function(player)
			ResourceService:Refill(player)
		end)
	end
end

function ResourceService:Start()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < TICK_INTERVAL then
			return
		end
		local elapsed = accumulator
		accumulator = 0

		-- D'abord les consommations (sprint), ensuite la régénération.
		ResourceService.Ticked:Fire(elapsed)
		regenerate(elapsed)
	end)

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return ResourceService
