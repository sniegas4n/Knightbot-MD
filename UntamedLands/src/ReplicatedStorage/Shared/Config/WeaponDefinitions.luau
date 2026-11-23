--!nonstrict
--[[
	WeaponDefinitions
	Location : ReplicatedStorage/Shared/Config/WeaponDefinitions (ModuleScript)
	Purpose  : Data-driven weapon catalogue. The combat engine never hard-codes a
	           weapon: add a new entry here and it works for players and NPCs.

	Fields
	  skill            : StatDefinitions id trained by using this weapon
	  hands            : 0 (unarmed), 1 (allows an offhand shield) or 2
	  reach            : hitbox length in studs measured from the root part
	  arcWidth         : hitbox width in studs
	  maxTargets       : how many enemies one swing can hit (cleave)
	  strengthScaling  : how much Strength above 10 increases damage
	  blockReduction   : fraction of damage removed when blocking with this weapon
	  blockStaminaCost : stamina lost per blocked hit (before multipliers)
	  defaultDirection : direction used when the player gives no mouse motion
	  directionalBonus : damage multiplier per attack direction
	  light / heavy    : damage, staminaCost, windup, recovery, stagger, guardDamage
	  model            : part-built visual. Parts are in weapon space where the
	                     grip is the origin and the business end points along -Z.

	Ranged weapons (bows, crossbows) will use kind = "Ranged" and are handled by a
	separate RangedService in Milestone 4. The fields above stay valid for melee.
	Depends  : nothing
]]

local WeaponDefinitions = {}

WeaponDefinitions.Directions = { Left = true, Right = true, Overhead = true, Thrust = true }
WeaponDefinitions.AttackKinds = { Light = "light", Heavy = "heavy" }

local RUST = Color3.fromRGB(122, 74, 48)
local IRON = Color3.fromRGB(96, 94, 90)
local WOOD = Color3.fromRGB(94, 66, 42)
local BONE = Color3.fromRGB(214, 204, 178)
local HIDE = Color3.fromRGB(120, 86, 58)

WeaponDefinitions.Items = {
	Fists = {
		id = "Fists",
		displayName = "Bare Fists",
		kind = "Melee",
		skill = "Unarmed",
		hands = 0,
		reach = 4.5,
		arcWidth = 4,
		maxTargets = 1,
		strengthScaling = 0.6,
		blockReduction = 0.35,
		blockStaminaCost = 14,
		defaultDirection = "Thrust",
		directionalBonus = {},
		light = { damage = 7, staminaCost = 6, windup = 0.18, recovery = 0.32 },
		heavy = { damage = 15, staminaCost = 16, windup = 0.45, recovery = 0.6, stagger = true, guardDamage = 1.6 },
		model = nil,
	},

	RustedMachete = {
		id = "RustedMachete",
		displayName = "Rusted Machete",
		kind = "Melee",
		skill = "Blades",
		hands = 1,
		reach = 6,
		arcWidth = 6,
		maxTargets = 2,
		strengthScaling = 0.5,
		blockReduction = 0.6,
		blockStaminaCost = 12,
		defaultDirection = "Right",
		directionalBonus = { Thrust = 0.8, Overhead = 1.1 },
		light = { damage = 13, staminaCost = 9, windup = 0.26, recovery = 0.38 },
		heavy = { damage = 26, staminaCost = 22, windup = 0.6, recovery = 0.75, stagger = true, guardDamage = 1.8 },
		model = {
			grip = CFrame.new(0, -0.15, 0),
			parts = {
				{ name = "Handle", size = Vector3.new(0.25, 0.25, 1.0), offset = CFrame.new(0, 0, 0.2), color = WOOD, material = "Wood" },
				{ name = "Guard", size = Vector3.new(0.18, 0.55, 0.12), offset = CFrame.new(0, 0, -0.32), color = IRON, material = "Metal" },
				{ name = "Blade", size = Vector3.new(0.1, 0.42, 2.6), offset = CFrame.new(0, 0.04, -1.68), color = RUST, material = "CorrodedMetal" },
			},
		},
	},

	BoneSpear = {
		id = "BoneSpear",
		displayName = "Bone-Tipped Spear",
		kind = "Melee",
		skill = "Spears",
		hands = 2,
		reach = 9.5,
		arcWidth = 3,
		maxTargets = 1,
		strengthScaling = 0.35,
		blockReduction = 0.45,
		blockStaminaCost = 15,
		defaultDirection = "Thrust",
		directionalBonus = { Thrust = 1.2, Left = 0.75, Right = 0.75, Overhead = 0.85 },
		light = { damage = 11, staminaCost = 8, windup = 0.3, recovery = 0.45 },
		heavy = { damage = 24, staminaCost = 20, windup = 0.65, recovery = 0.8, stagger = true, guardDamage = 1.5 },
		model = {
			grip = CFrame.new(0, -0.15, 0),
			parts = {
				{ name = "Shaft", size = Vector3.new(0.2, 0.2, 8.5), offset = CFrame.new(0, 0, -2.25), color = WOOD, material = "Wood" },
				{ name = "Binding", size = Vector3.new(0.28, 0.28, 0.5), offset = CFrame.new(0, 0, -6.3), color = HIDE, material = "Fabric" },
				{ name = "Tip", size = Vector3.new(0.14, 0.4, 1.3), offset = CFrame.new(0, 0, -7.1), color = BONE, material = "Slate" },
			},
		},
	},

	ScrapMaul = {
		id = "ScrapMaul",
		displayName = "Scrap Maul",
		kind = "Melee",
		skill = "HeavyWeapons",
		hands = 2,
		reach = 7,
		arcWidth = 7,
		maxTargets = 3,
		strengthScaling = 1.0,
		blockReduction = 0.55,
		blockStaminaCost = 10,
		defaultDirection = "Overhead",
		directionalBonus = { Thrust = 0.6, Overhead = 1.15 },
		light = { damage = 20, staminaCost = 16, windup = 0.5, recovery = 0.7 },
		heavy = { damage = 42, staminaCost = 32, windup = 1.0, recovery = 1.1, stagger = true, guardDamage = 2.6 },
		model = {
			grip = CFrame.new(0, -0.15, 0),
			parts = {
				{ name = "Haft", size = Vector3.new(0.25, 0.25, 4.2), offset = CFrame.new(0, 0, -1.1), color = WOOD, material = "Wood" },
				{ name = "Head", size = Vector3.new(1.0, 1.0, 1.4), offset = CFrame.new(0, 0, -3.4), color = IRON, material = "CorrodedMetal" },
				{ name = "Spike", size = Vector3.new(0.3, 0.3, 0.6), offset = CFrame.new(0, 0.55, -3.4) * CFrame.Angles(math.rad(90), 0, 0), color = RUST, material = "CorrodedMetal" },
			},
		},
	},

	Buckler = {
		id = "Buckler",
		displayName = "Hide Buckler",
		kind = "Shield",
		isOffhand = true,
		blockReduction = 0.85,
		blockStaminaMultiplier = 0.6,
		model = {
			hand = "LeftHand",
			grip = CFrame.new(-0.3, 0, 0),
			parts = {
				{ name = "Disc", shape = "Cylinder", size = Vector3.new(0.22, 2.3, 2.3), offset = CFrame.new(), color = HIDE, material = "Fabric" },
				{ name = "Boss", shape = "Ball", size = Vector3.new(0.6, 0.6, 0.6), offset = CFrame.new(-0.12, 0, 0), color = IRON, material = "Metal" },
			},
		},
	},
}

-- Ownership for Milestone 1 (before the inventory exists). Slot order = hotkeys 1..4.
WeaponDefinitions.StarterLoadout = { "Fists", "RustedMachete", "BoneSpear", "ScrapMaul" }
WeaponDefinitions.StarterOffhand = "Buckler"

function WeaponDefinitions.get(id)
	if type(id) ~= "string" then
		return nil
	end
	return WeaponDefinitions.Items[id]
end

function WeaponDefinitions.getAttack(weapon, kind)
	local key = WeaponDefinitions.AttackKinds[kind]
	if not key or not weapon then
		return nil
	end
	return weapon[key]
end

return WeaponDefinitions
