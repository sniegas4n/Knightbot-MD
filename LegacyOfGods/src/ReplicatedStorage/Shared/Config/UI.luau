--[[
	Config.UI (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Config > UI

	Thème visuel et paramètres responsives du HUD.
	Le HUD est conçu en pixels pour une résolution de référence, puis mis à
	l'échelle par un UIScale selon la taille réelle de l'écran.
]]

return {
	ReferenceResolution = Vector2.new(1280, 720),
	MinScale = 0.6,
	MaxScale = 1.4,
	TouchScaleMultiplier = 1.1, -- léger agrandissement sur mobile/tablette

	Font = Enum.Font.GothamBold,
	FontRegular = Enum.Font.Gotham,

	Colors = {
		PanelBackground = Color3.fromRGB(14, 16, 28),
		PanelStroke = Color3.fromRGB(120, 140, 255),
		BarBackground = Color3.fromRGB(30, 32, 48),
		BarTrail = Color3.fromRGB(255, 255, 255),
		Text = Color3.fromRGB(240, 240, 255),
		TextDim = Color3.fromRGB(160, 165, 200),

		Health = Color3.fromRGB(235, 60, 80),
		Energy = Color3.fromRGB(70, 150, 255),
		Stamina = Color3.fromRGB(110, 230, 120),
		Experience = Color3.fromRGB(190, 120, 255),

		Accent = Color3.fromRGB(255, 205, 90),
		Warning = Color3.fromRGB(255, 170, 60),
		Error = Color3.fromRGB(255, 80, 80),
		Success = Color3.fromRGB(110, 230, 140),
	},

	PanelTransparency = 0.25,
	CornerRadius = 8,

	BarTweenTime = 0.2,
	BarTrailDelay = 0.35,
	BarTrailTweenTime = 0.4,

	OpenAnimationTime = 0.45,

	NotificationDuration = 3,
	MaxNotifications = 4,

	-- La liste des joueurs de Roblox (en haut à droite) recouvre la mini-carte.
	-- Masquée tant qu'un menu « Joueurs » maison n'existe pas.
	HidePlayerList = true,
}
