--!nonstrict
--[[
	StatDefinitions
	Location : ReplicatedStorage/Shared/Config/StatDefinitions (ModuleScript)
	Purpose  : Every attribute and skill a character can have. There are no classes:
	           every stat improves only by doing the related activity.
	           Levels are stored as decimals (e.g. 12.37) so progress is continuous.
	Depends  : nothing
]]

local StatDefinitions = {}

StatDefinitions.MaxLevel = 100

StatDefinitions.Attributes = { "Strength", "Agility", "Endurance", "Intelligence", "Perception" }

StatDefinitions.Skills = {
	"Unarmed",
	"Blades",
	"Spears",
	"Blunt",
	"HeavyWeapons",
	"Polearms",
	"Daggers",
	"Archery",
	"Crossbows",
	"Defense",
	"Stealth",
	"Athletics",
	"Crafting",
}

StatDefinitions.Info = {
	Strength = { displayName = "Strength", category = "Attribute", start = 10, description = "Raw power. Raises damage, especially with heavy weapons." },
	Agility = { displayName = "Agility", category = "Attribute", start = 10, description = "Quickness. Shortens dodge cooldown." },
	Endurance = { displayName = "Endurance", category = "Attribute", start = 10, description = "Stamina pool and resilience." },
	Intelligence = { displayName = "Intelligence", category = "Attribute", start = 10, description = "Learning, research and medicine (later milestones)." },
	Perception = { displayName = "Perception", category = "Attribute", start = 10, description = "Awareness and ranged accuracy (later milestones)." },

	Unarmed = { displayName = "Unarmed", category = "Skill", start = 1, description = "Fighting with fists." },
	Blades = { displayName = "Blades", category = "Skill", start = 1, description = "Swords, machetes and cleavers." },
	Spears = { displayName = "Spears", category = "Skill", start = 1, description = "Spears and pikes." },
	Blunt = { displayName = "Blunt", category = "Skill", start = 1, description = "Clubs and maces." },
	HeavyWeapons = { displayName = "Heavy Weapons", category = "Skill", start = 1, description = "Mauls and great blades." },
	Polearms = { displayName = "Polearms", category = "Skill", start = 1, description = "Glaives and long hafted blades." },
	Daggers = { displayName = "Daggers", category = "Skill", start = 1, description = "Knives and short blades." },
	Archery = { displayName = "Archery", category = "Skill", start = 1, description = "Bows (Milestone 4+)." },
	Crossbows = { displayName = "Crossbows", category = "Skill", start = 1, description = "Crossbows (Milestone 4+)." },
	Defense = { displayName = "Defense", category = "Skill", start = 1, description = "Blocking and parrying." },
	Stealth = { displayName = "Stealth", category = "Skill", start = 1, description = "Moving unseen (Milestone 5+)." },
	Athletics = { displayName = "Athletics", category = "Skill", start = 1, description = "Running speed. Improves by running." },
	Crafting = { displayName = "Crafting", category = "Skill", start = 1, description = "Making things (Milestone 4+)." },
}

function StatDefinitions.isStat(id)
	return type(id) == "string" and StatDefinitions.Info[id] ~= nil
end

function StatDefinitions.defaultStats()
	local stats = {}
	for id, info in pairs(StatDefinitions.Info) do
		stats[id] = info.start
	end
	return stats
end

return StatDefinitions
