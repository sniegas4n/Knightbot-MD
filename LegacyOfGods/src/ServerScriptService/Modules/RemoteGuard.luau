--[[
	RemoteGuard (ModuleScript) — SERVEUR
	Emplacement : ServerScriptService > Modules > RemoteGuard

	Enveloppe sécurisée pour écouter un RemoteEvent :
	  - limite de fréquence par joueur (fenêtre glissante, config Network),
	  - le handler est exécuté dans un pcall (une erreur ne casse rien),
	  - comptage des violations + expulsion optionnelle,
	  - nettoyage automatique quand le joueur quitte.

	Usage :
		RemoteGuard.OnServerEvent("Movement_RequestDodge", function(player, direction)
			...
		end)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared.Modules.Net)

local NetworkConfig = Config.Network
local DebugConfig = Config.Core.Debug

local RemoteGuard = {}

-- calls[remoteName][player] = { timestamps... }
local calls: { [string]: { [Player]: { number } } } = {}
local violations: { [Player]: number } = {}

local function registerViolation(player: Player, remoteName: string, reason: string)
	local count = (violations[player] or 0) + 1
	violations[player] = count

	if DebugConfig.LogRemoteViolations then
		warn(("[RemoteGuard] %s (%d) — %s : %s [violation #%d]"):format(player.Name, player.UserId, remoteName, reason, count))
	end

	local limit = NetworkConfig.KickAfterViolations
	if limit > 0 and count >= limit then
		player:Kick("Activité réseau anormale détectée.")
	end
end

local function checkRate(player: Player, remoteName: string, rateLimit): boolean
	if not rateLimit then
		return true
	end

	local byPlayer = calls[remoteName]
	if not byPlayer then
		byPlayer = {}
		calls[remoteName] = byPlayer
	end

	local now = os.clock()
	local history = byPlayer[player]
	if not history then
		history = {}
		byPlayer[player] = history
	end

	-- Supprime les appels sortis de la fenêtre.
	local windowStart = now - rateLimit.Per
	while history[1] and history[1] < windowStart do
		table.remove(history, 1)
	end

	if #history >= rateLimit.MaxCalls then
		return false
	end

	table.insert(history, now)
	return true
end

-- Signale une requête invalide (mauvais arguments) depuis un handler.
function RemoteGuard.Flag(player: Player, remoteName: string, reason: string)
	registerViolation(player, remoteName, reason)
end

function RemoteGuard.OnServerEvent(remoteName: string, handler: (Player, ...any) -> ())
	local remote = Net.Get(remoteName)
	if not remote then
		return nil -- Remote StudioOnly hors Studio
	end
	assert(remote:IsA("RemoteEvent"), ("[RemoteGuard] %s n'est pas un RemoteEvent"):format(remoteName))

	local definition = Net.GetDefinition(remoteName)

	return remote.OnServerEvent:Connect(function(player: Player, ...)
		if not checkRate(player, remoteName, definition.RateLimit) then
			registerViolation(player, remoteName, "limite de fréquence dépassée")
			return
		end

		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(("[RemoteGuard] Erreur dans le handler %s : %s"):format(remoteName, tostring(err)))
		end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	violations[player] = nil
	for _, byPlayer in calls do
		byPlayer[player] = nil
	end
end)

return RemoteGuard
