--[[
	Notifier (ModuleScript) — SERVEUR
	Emplacement : ServerScriptService > Modules > Notifier

	Envoie une notification texte au HUD d'un joueur (Remote UI_Notify).
	Kind : "Info" | "Success" | "Warning" | "Error" | "LevelUp"
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Modules.Net)

local Notifier = {}

function Notifier.Send(player: Player, text: string, kind: string?)
	if not player or not player.Parent then
		return
	end
	Net.Get("UI_Notify"):FireClient(player, {
		Text = text,
		Kind = kind or "Info",
	})
end

return Notifier
