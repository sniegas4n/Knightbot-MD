--!nonstrict
--[[
	RaceDefinitions
	Location : ReplicatedStorage/Shared/Config/RaceDefinitions (ModuleScript)
	Purpose  : Original playable peoples of the Untamed Lands.
	           statModifiers are applied ONCE when the character is created.
	           skinTones are indices into AppearanceOptions.SkinTones.
	           scale ranges are { min, max, default } for HumanoidDescription scales.
	Depends  : nothing
]]

local RaceDefinitions = {}

RaceDefinitions.Order = { "Sunworn", "Greyveil", "Ironback" }

RaceDefinitions.Races = {
	Sunworn = {
		displayName = "Sunworn",
		description = "Caravan-born folk of the salt flats. Their bodies are tempered by heat and endless marches.",
		statModifiers = { Endurance = 2, Athletics = 3 },
		healthMultiplier = 1.0,
		skinTones = { 1, 2, 3, 4, 5 },
		scale = {
			height = { 0.9, 1.1, 1.0 },
			width = { 0.85, 1.1, 1.0 },
			depth = { 0.85, 1.1, 1.0 },
			head = { 0.92, 1.08, 1.0 },
		},
	},
	Greyveil = {
		displayName = "Greyveil",
		description = "Pale descendants of those who sheltered underground when the sky burned. Keen-eyed and quiet, but frail.",
		statModifiers = { Perception = 3, Stealth = 4, Strength = -1 },
		healthMultiplier = 0.9,
		skinTones = { 6, 7, 8, 9 },
		scale = {
			height = { 0.95, 1.15, 1.06 },
			width = { 0.78, 1.0, 0.88 },
			depth = { 0.8, 1.0, 0.9 },
			head = { 0.92, 1.08, 1.0 },
		},
	},
	Ironback = {
		displayName = "Ironback",
		description = "Broad, dense-boned people of the mountain quarries. Hard to kill and slow to tire, but heavy on their feet.",
		statModifiers = { Strength = 3, Endurance = 2, Agility = -2 },
		healthMultiplier = 1.15,
		skinTones = { 10, 11, 12, 13 },
		scale = {
			height = { 0.85, 1.0, 0.92 },
			width = { 1.05, 1.3, 1.18 },
			depth = { 1.0, 1.25, 1.12 },
			head = { 0.95, 1.12, 1.05 },
		},
	},
}

function RaceDefinitions.get(id)
	if type(id) ~= "string" then
		return nil
	end
	return RaceDefinitions.Races[id]
end

return RaceDefinitions
