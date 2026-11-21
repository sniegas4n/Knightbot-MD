--[[
	ProgressionFormulas (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Modules > ProgressionFormulas

	Formules pures (sans effet de bord) partagées client/serveur.
	Le serveur s'en sert pour CALCULER, le client uniquement pour AFFICHER.
]]

local Config = require(script.Parent.Parent:WaitForChild("Config"))

local Progression = Config.Progression
local Curve = Progression.ExperienceCurve

local ProgressionFormulas = {}

-- Cache : la courbe ne change pas pendant une session.
local requiredCache: { [number]: number } = {}

function ProgressionFormulas.ClampLevel(level: number): number
	return math.clamp(math.floor(level), Progression.StartLevel, Progression.MaxLevel)
end

function ProgressionFormulas.IsMaxLevel(level: number): boolean
	return level >= Progression.MaxLevel
end

-- XP nécessaire pour passer de `level` à `level + 1`.
-- Renvoie 0 au niveau maximum.
function ProgressionFormulas.ExperienceToNextLevel(level: number): number
	level = ProgressionFormulas.ClampLevel(level)
	if ProgressionFormulas.IsMaxLevel(level) then
		return 0
	end

	local cached = requiredCache[level]
	if cached then
		return cached
	end

	local value = math.floor(Curve.Base * level ^ Curve.Exponent + Curve.Linear * level)
	value = math.max(value, 1)
	requiredCache[level] = value
	return value
end

-- XP totale accumulée pour atteindre `level` depuis le niveau de départ.
-- Utile pour les classements et le prestige.
function ProgressionFormulas.TotalExperienceForLevel(level: number): number
	level = ProgressionFormulas.ClampLevel(level)
	local total = 0
	for l = Progression.StartLevel, level - 1 do
		total += ProgressionFormulas.ExperienceToNextLevel(l)
	end
	return total
end

return ProgressionFormulas
