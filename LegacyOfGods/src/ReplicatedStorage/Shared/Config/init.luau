--[[
	Config (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Config

	Point d'entrée UNIQUE de toute la configuration du jeu.
	Chaque enfant (ModuleScript) couvre un domaine. Aucune valeur d'équilibrage
	ne doit être écrite en dur ailleurs : on lit toujours Config.<Domaine>.<Clé>.

	Les tables sont gelées (table.freeze récursif) : toute tentative de
	modification à l'exécution lève une erreur, ce qui évite qu'un script
	modifie accidentellement l'équilibrage pour tout le serveur.

	Ce module est partagé client/serveur : N'Y METTEZ JAMAIS de secret
	(clés, identifiants de produits sensibles, logique anti-triche).
]]

local function deepFreeze<T>(t: T): T
	if type(t) == "table" and not table.isfrozen(t :: any) then
		for _, value in t :: any do
			if type(value) == "table" then
				deepFreeze(value)
			end
		end
		table.freeze(t :: any)
	end
	return t
end

local Config = {
	Core = require(script.Core),
	Character = require(script.Character),
	Movement = require(script.Movement),
	Camera = require(script.Camera),
	Progression = require(script.Progression),
	Economy = require(script.Economy),
	Regions = require(script.Regions),
	Input = require(script.Input),
	Animations = require(script.Animations),
	UI = require(script.UI),
	Network = require(script.Network),
}

return deepFreeze(Config)
