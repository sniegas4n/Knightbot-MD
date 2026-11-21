--[[
	Config.Character (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Config > Character

	Valeurs de base du personnage et de ses ressources.
	Les bonus de statistiques (Endurance, Énergie...) viendront s'ajouter à
	ces bases en Phase 2 via LevelService / StatService.
]]

return {
	BaseMaxHealth = 100,
	BaseWalkSpeed = 16,
	JumpHeight = 7.2, -- Humanoid.UseJumpPower = false

	RespawnTime = 5, -- secondes avant réapparition après la mort

	Resources = {
		Stamina = {
			BaseMax = 100,
			RegenPerSecond = 22,
			RegenDelay = 1.0, -- secondes sans dépense avant de régénérer
		},
		Energy = {
			BaseMax = 100,
			RegenPerSecond = 5,
			RegenDelay = 1.5,
		},
	},

	-- Fréquence (Hz) de la boucle serveur unique qui gère régénération et
	-- consommation continue (sprint). 10 Hz suffit largement et reste léger.
	ResourceTickRate = 10,
}
