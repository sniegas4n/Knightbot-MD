--[[
	Config.Camera (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Config > Camera

	Caméra troisième personne. Le Shift-Lock natif est désactivé car Shift
	est utilisé pour le sprint.
]]

return {
	MinZoomDistance = 6,
	MaxZoomDistance = 32,
	DisableShiftLock = true,

	FieldOfView = 70,
	SprintFieldOfView = 78,
	FieldOfViewTweenTime = 0.25,

	-- Petit "coup" de FOV pendant l'esquive (sensation de vitesse).
	DodgeFieldOfViewKick = 6,
	DodgeKickTime = 0.12,
}
