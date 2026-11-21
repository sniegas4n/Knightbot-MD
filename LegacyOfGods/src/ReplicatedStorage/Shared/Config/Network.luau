--[[
	Config.Network (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Config > Network

	Registre de TOUS les Remotes du jeu. Le serveur les crée automatiquement
	au démarrage dans ReplicatedStorage > Remotes (voir Shared > Modules > Net).
	Ne créez jamais de RemoteEvent à la main dans Studio.

	Convention de nom : <Domaine>_<Action>
		- Client -> Serveur : <Domaine>_Request<Action>
		- Serveur -> Client : <Domaine>_<Évènement>

	RateLimit = { MaxCalls, Per } : au plus MaxCalls appels par fenêtre de
	Per secondes et par joueur. Au-delà, l'appel est ignoré et compté comme
	une violation.

	StudioOnly = true : le Remote n'existe que dans Roblox Studio.
]]

return {
	FolderName = "Remotes",

	Remotes = {
		Movement_RequestSprint = {
			Type = "RemoteEvent",
			RateLimit = { MaxCalls = 12, Per = 1 },
		},
		Movement_RequestDodge = {
			Type = "RemoteEvent",
			RateLimit = { MaxCalls = 5, Per = 1 },
		},
		UI_Notify = {
			Type = "RemoteEvent", -- Serveur -> Client uniquement
		},
		Debug_Command = {
			Type = "RemoteEvent",
			RateLimit = { MaxCalls = 10, Per = 1 },
			StudioOnly = true,
		},
	},

	-- Au-delà de ce nombre de violations (spam) sur une session, le joueur
	-- est expulsé. 0 = jamais d'expulsion automatique (journalisation seule).
	KickAfterViolations = 0,
}
