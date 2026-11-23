--!nonstrict
--[[
	NPCDefinitions
	Location : ReplicatedStorage/Shared/Config/NPCDefinitions (ModuleScript)
	Purpose  : NPC templates and Milestone 1 spawn points.
	           Spawn offsets are relative to the world spawn waystone; Y is ignored
	           (NPCs are placed on the terrain surface).
	Depends  : nothing
]]

local NPCDefinitions = {}

NPCDefinitions.Templates = {
	SparringDummy = {
		displayName = "Sparring Thrall",
		behavior = "Dummy",
		faction = "Neutral",
		maxHealth = 400,
		armor = 0.1,
		weapon = "Fists",
		stats = {},
		regenDelay = 4,
		respawnTime = 10,
		appearance = {
			skin = Color3.fromRGB(150, 120, 90),
			top = Color3.fromRGB(110, 96, 70),
			bottom = Color3.fromRGB(80, 70, 56),
			height = 1.0,
			width = 1.05,
		},
	},

	DustRaider = {
		displayName = "Dust Raider",
		behavior = "Raider",
		faction = "DustRaiders",
		maxHealth = 85,
		armor = 0.05,
		weapon = "RustedMachete",
		stats = { Blades = 6, Strength = 9, Endurance = 8, Defense = 4 },
		aggroRange = 45,
		leashRange = 90,
		blockChance = 0.35,
		heavyChance = 0.2,
		aggression = 0.8, -- higher = attacks more often
		respawnTime = 45,
		appearance = {
			skin = Color3.fromRGB(150, 104, 70),
			top = Color3.fromRGB(120, 60, 40),
			bottom = Color3.fromRGB(60, 50, 42),
			height = 1.0,
			width = 0.95,
		},
	},
}

NPCDefinitions.SpawnPoints = {
	{ template = "SparringDummy", offset = Vector3.new(16, 0, -10) },
	{ template = "SparringDummy", offset = Vector3.new(22, 0, -2) },
	{ template = "DustRaider", offset = Vector3.new(110, 0, 70) },
	{ template = "DustRaider", offset = Vector3.new(-130, 0, 90) },
	{ template = "DustRaider", offset = Vector3.new(70, 0, -150) },
}

return NPCDefinitions
