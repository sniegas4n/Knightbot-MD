--[[
	Config.Progression (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Config > Progression

	Toute la courbe de progression est ici. La formule elle-même est dans
	Shared > Modules > ProgressionFormulas (partagée client/serveur pour que
	l'affichage de la barre d'XP corresponde exactement au calcul serveur).

	XP nécessaire pour passer du niveau L au niveau L+1 :
		floor(Base * L ^ Exponent + Linear * L)
]]

return {
	StartLevel = 1,
	MaxLevel = 500,

	ExperienceCurve = {
		Base = 100,
		Exponent = 1.55,
		Linear = 50,
	},

	-- Multiplicateur global d'XP (événements double XP, etc.).
	GlobalExperienceMultiplier = 1,

	-- Garde-fou : quantité maximale d'XP acceptée en un seul gain.
	MaxExperiencePerGain = 10_000_000,

	StatPointsPerLevel = 3,
	StartingStatPoints = 0,

	-- Définition des statistiques (utilisées en Phase 2).
	-- Id = clé stable sauvegardée. Ne JAMAIS renommer un Id existant.
	Stats = {
		{ Id = "Strength", DisplayName = "Force", Description = "Augmente les dégâts physiques." },
		{ Id = "Defense", DisplayName = "Défense", Description = "Réduit les dégâts subis." },
		{ Id = "Agility", DisplayName = "Agilité", Description = "Vitesse et récupération des esquives." },
		{ Id = "Energy", DisplayName = "Énergie", Description = "Énergie maximale et puissance magique." },
		{ Id = "Endurance", DisplayName = "Endurance", Description = "Vie et endurance maximales." },
	},
}
