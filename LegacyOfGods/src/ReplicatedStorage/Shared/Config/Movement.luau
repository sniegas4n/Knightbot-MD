--[[
	Config.Movement (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Config > Movement
]]

return {
	Sprint = {
		SpeedMultiplier = 1.6, -- WalkSpeed = BaseWalkSpeed * SpeedMultiplier
		StaminaCostPerSecond = 18,
		MinStaminaToStart = 10,
		-- Vitesse horizontale minimale (studs/s) pour considérer que le
		-- joueur court réellement (on ne consomme pas d'endurance à l'arrêt).
		MinMovingSpeed = 2,
	},

	Dodge = {
		StaminaCost = 25,
		Cooldown = 0.8, -- secondes
		Distance = 14, -- studs parcourus
		Duration = 0.22, -- durée du dash (secondes)
		InvulnerabilityDuration = 0.25, -- i-frames accordées par le serveur
		AllowInAir = false,
		-- Tolérance réseau : le serveur accepte une esquive légèrement plus
		-- tôt que le cooldown (latence / gigue).
		ServerCooldownTolerance = 0.1,
	},
}
