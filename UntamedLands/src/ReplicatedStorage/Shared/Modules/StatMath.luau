--!nonstrict
--[[
	StatMath
	Location : ReplicatedStorage/Shared/Modules/StatMath (ModuleScript)
	Purpose  : Pure formulas that turn stats into gameplay numbers. Shared so the
	           client can predict (e.g. HUD) while the server stays authoritative.
	           Stats matter, but modestly: weapon choice, stamina, timing and
	           positioning should decide most fights.
	Depends  : GameConfig
]]

local GameConfig = require(script.Parent.Parent.Config.GameConfig)

local StatMath = {}

local function level(stats, id, default)
	local value = stats and stats[id]
	if type(value) ~= "number" then
		return default
	end
	return value
end

function StatMath.maxStamina(stats)
	local cfg = GameConfig.Stamina
	local endurance = level(stats, "Endurance", 10)
	return cfg.BaseMax + math.max(0, endurance - 10) * cfg.MaxPerEnduranceLevel
end

function StatMath.staminaRegen(stats)
	local endurance = level(stats, "Endurance", 10)
	return GameConfig.Stamina.RegenPerSecond * (1 + math.max(0, endurance - 10) * 0.01)
end

function StatMath.walkSpeed(stats)
	local athletics = level(stats, "Athletics", 1)
	return GameConfig.Movement.WalkSpeed * (1 + (athletics - 1) * 0.0015)
end

function StatMath.runSpeed(stats)
	local athletics = level(stats, "Athletics", 1)
	return GameConfig.Movement.RunSpeed * (1 + (athletics - 1) * 0.004)
end

function StatMath.dodgeCooldown(stats)
	local agility = level(stats, "Agility", 10)
	return GameConfig.Movement.DodgeCooldown * math.clamp(1 - (agility - 10) * 0.004, 0.6, 1.2)
end

-- Damage multiplier from the attacker's skill with the weapon and Strength.
function StatMath.damageMultiplier(stats, weapon)
	local skill = level(stats, weapon.skill, 1)
	local strength = level(stats, "Strength", 10)
	local skillFactor = 1 + (skill - 1) * 0.01
	local strengthFactor = 1 + (strength - 10) * 0.01 * (weapon.strengthScaling or 0.5)
	return math.max(0.2, skillFactor * strengthFactor)
end

-- Attack timing multiplier (<1 = faster). Capped so skill never trivialises timing.
function StatMath.attackSpeedMultiplier(stats, weapon)
	local skill = level(stats, weapon.skill, 1)
	return 1 - math.min(0.25, (skill - 1) * 0.003)
end

-- Diminishing returns: higher levels gain less from the same activity.
function StatMath.experienceGain(currentLevel, amount)
	local p = GameConfig.Progression
	return amount * p.ExperienceScale * p.GlobalRate / (1 + currentLevel * p.DiminishPerLevel)
end

return StatMath
