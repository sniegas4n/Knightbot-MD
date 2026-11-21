--[[
	Config.Animations (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Config > Animations

	Identifiants d'animations. Laissez "" tant que l'animation n'est pas
	créée : le code l'ignore proprement (aucune erreur).
	Format attendu : "rbxassetid://123456789"

	Les animations doivent appartenir au propriétaire de l'expérience
	(compte ou groupe), sinon Roblox refusera de les jouer.
]]

return {
	Dodge = {
		Forward = "",
		Backward = "",
	},
	Sprint = "",
}
