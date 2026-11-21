--[[
	Config.Core (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Config > Core

	Paramètres généraux du projet.
]]

return {
	GameName = "LEGACY OF GODS",
	Version = "0.1.0", -- Version du code (affichée en debug)

	-- Version du schéma des données joueur. À incrémenter à chaque changement
	-- de structure du profil (Phase 2 : migrations automatiques).
	DataVersion = 1,

	Debug = {
		-- Les outils de debug (commandes, touches F6-F9) ne fonctionnent
		-- QUE dans Roblox Studio, même si Enabled = true.
		Enabled = true,
		LogRemoteViolations = true,
		Verbose = false,
	},
}
