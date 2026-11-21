--[[
	Config.Regions (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Config > Regions

	Registre des régions du monde ouvert. Ajouter une région = ajouter une
	entrée ici + un dossier Workspace > Zones > <Id> (Phase 4).

	RecommendedLevel est INDICATIF : il sert à afficher un niveau de danger,
	jamais à bloquer l'accès.
]]

return {
	DefaultRegionId = "region_aether",

	List = {
		{
			Id = "region_aether",
			DisplayName = "Royaume d'Aether",
			RecommendedLevel = { Min = 1, Max = 30 },
			ThemeColor = Color3.fromRGB(120, 200, 255),
		},
		{
			Id = "region_eldoria",
			DisplayName = "Forêt d'Eldoria",
			RecommendedLevel = { Min = 20, Max = 60 },
			ThemeColor = Color3.fromRGB(90, 200, 110),
		},
		{
			Id = "region_solkar",
			DisplayName = "Désert de Solkar",
			RecommendedLevel = { Min = 50, Max = 100 },
			ThemeColor = Color3.fromRGB(235, 185, 90),
		},
		{
			Id = "region_frost",
			DisplayName = "Royaume de glace",
			RecommendedLevel = { Min = 90, Max = 150 },
			ThemeColor = Color3.fromRGB(180, 230, 255),
		},
		{
			Id = "region_volcanic",
			DisplayName = "Terres volcaniques",
			RecommendedLevel = { Min = 140, Max = 220 },
			ThemeColor = Color3.fromRGB(255, 100, 60),
		},
		{
			Id = "region_shadow",
			DisplayName = "Royaume des ombres",
			RecommendedLevel = { Min = 200, Max = 300 },
			ThemeColor = Color3.fromRGB(150, 90, 220),
		},
		{
			Id = "region_celestial",
			DisplayName = "Domaine céleste",
			RecommendedLevel = { Min = 300, Max = 500 },
			ThemeColor = Color3.fromRGB(255, 235, 150),
		},
	},
}
