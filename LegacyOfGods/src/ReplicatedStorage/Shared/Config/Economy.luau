--[[
	Config.Economy (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Config > Economy

	Les Id (Gold, Crystals, DivineShards) sont aussi les noms des attributs
	répliqués sur le joueur et les clés sauvegardées. Ne jamais les renommer.
]]

return {
	Currencies = {
		Gold = {
			DisplayName = "Or",
			StartingAmount = 100,
			MaxAmount = 1_000_000_000_000,
			Color = Color3.fromRGB(255, 200, 60),
			Order = 1,
		},
		Crystals = {
			DisplayName = "Cristaux",
			StartingAmount = 0,
			MaxAmount = 100_000_000,
			Color = Color3.fromRGB(90, 200, 255),
			Order = 2,
		},
		DivineShards = {
			DisplayName = "Éclats divins",
			StartingAmount = 0,
			MaxAmount = 1_000_000,
			Color = Color3.fromRGB(255, 120, 220),
			Order = 3,
		},
	},
}
