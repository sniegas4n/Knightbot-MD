--!nonstrict
--[[
	AppearanceOptions
	Location : ReplicatedStorage/Shared/Config/AppearanceOptions (ModuleScript)
	Purpose  : All selectable appearance values. Hairstyles are built from simple
	           parts (see HairBuilder) so the game needs no catalog asset IDs and
	           every look is original. Sizes/offsets are in "head units": they are
	           multiplied by the head's Size, so hair follows HeadScale.
	           Head-local axes: +Y up, -Z front of face, +Z back of head.
	Depends  : nothing
]]

local AppearanceOptions = {}

AppearanceOptions.SkinTones = {
	-- Sunworn
	{ name = "Sunburnt Umber", color = Color3.fromRGB(139, 94, 60) },
	{ name = "Desert Bronze", color = Color3.fromRGB(166, 116, 76) },
	{ name = "Dune Tan", color = Color3.fromRGB(196, 150, 108) },
	{ name = "Weathered Sand", color = Color3.fromRGB(214, 178, 140) },
	{ name = "Deep Mahogany", color = Color3.fromRGB(92, 58, 38) },
	-- Greyveil
	{ name = "Ash Pallor", color = Color3.fromRGB(196, 196, 190) },
	{ name = "Slate", color = Color3.fromRGB(150, 152, 152) },
	{ name = "Lichen Pale", color = Color3.fromRGB(176, 186, 168) },
	{ name = "Dusk Blue", color = Color3.fromRGB(140, 150, 168) },
	-- Ironback
	{ name = "Rust Hide", color = Color3.fromRGB(150, 82, 56) },
	{ name = "Ochre Hide", color = Color3.fromRGB(178, 132, 70) },
	{ name = "Basalt Hide", color = Color3.fromRGB(82, 76, 74) },
	{ name = "Clay Hide", color = Color3.fromRGB(160, 110, 90) },
}

AppearanceOptions.HairStyles = {
	{ name = "Shaved", parts = {} },
	{
		name = "Cropped",
		parts = {
			{ size = Vector3.new(1.04, 0.3, 1.04), offset = Vector3.new(0, 0.4, 0.02) },
		},
	},
	{
		name = "Topknot",
		parts = {
			{ size = Vector3.new(1.04, 0.28, 1.04), offset = Vector3.new(0, 0.41, 0.02) },
			{ shape = "Ball", size = Vector3.new(0.38, 0.38, 0.38), offset = Vector3.new(0, 0.7, 0.15) },
		},
	},
	{
		name = "Long",
		parts = {
			{ size = Vector3.new(1.06, 0.32, 1.06), offset = Vector3.new(0, 0.4, 0.03) },
			{ size = Vector3.new(1.04, 1.1, 0.22), offset = Vector3.new(0, -0.1, 0.48) },
		},
	},
	{
		name = "Ridge",
		parts = {
			{ size = Vector3.new(0.22, 0.4, 1.1), offset = Vector3.new(0, 0.55, 0.05) },
		},
	},
	{
		name = "Braided",
		parts = {
			{ size = Vector3.new(1.04, 0.3, 1.04), offset = Vector3.new(0, 0.4, 0.02) },
			{ shape = "Cylinder", size = Vector3.new(1.0, 0.18, 0.18), offset = Vector3.new(0.48, -0.3, 0.2), rotation = Vector3.new(0, 0, 90) },
			{ shape = "Cylinder", size = Vector3.new(1.0, 0.18, 0.18), offset = Vector3.new(-0.48, -0.3, 0.2), rotation = Vector3.new(0, 0, 90) },
		},
	},
	{
		name = "Wrapped",
		parts = {
			{ size = Vector3.new(1.14, 0.55, 1.14), offset = Vector3.new(0, 0.32, 0.05) },
			{ size = Vector3.new(1.1, 0.9, 0.24), offset = Vector3.new(0, -0.15, 0.55) },
		},
	},
}

AppearanceOptions.HairColors = {
	{ name = "Ash Black", color = Color3.fromRGB(30, 28, 26) },
	{ name = "Dust Brown", color = Color3.fromRGB(92, 64, 44) },
	{ name = "Rust Red", color = Color3.fromRGB(140, 62, 36) },
	{ name = "Bleached Straw", color = Color3.fromRGB(200, 178, 120) },
	{ name = "Iron Grey", color = Color3.fromRGB(120, 118, 112) },
	{ name = "Bone White", color = Color3.fromRGB(220, 214, 196) },
	{ name = "Ochre", color = Color3.fromRGB(176, 128, 52) },
	{ name = "Soot Blue", color = Color3.fromRGB(52, 60, 76) },
}

AppearanceOptions.ClothColors = {
	{ name = "Undyed Linen", color = Color3.fromRGB(196, 182, 150) },
	{ name = "Rust", color = Color3.fromRGB(150, 70, 40) },
	{ name = "Ochre", color = Color3.fromRGB(184, 140, 64) },
	{ name = "Ash", color = Color3.fromRGB(120, 116, 108) },
	{ name = "Indigo", color = Color3.fromRGB(52, 62, 96) },
	{ name = "Moss", color = Color3.fromRGB(86, 98, 62) },
	{ name = "Charcoal", color = Color3.fromRGB(46, 44, 42) },
	{ name = "Bone", color = Color3.fromRGB(222, 212, 188) },
	{ name = "Oxblood", color = Color3.fromRGB(98, 32, 30) },
	{ name = "Sand", color = Color3.fromRGB(212, 190, 148) },
}

-- Defaults used when a race is selected (scales come from the race definition).
AppearanceOptions.Defaults = {
	hairStyle = 2,
	hairColor = 2,
	topColor = 1,
	bottomColor = 7,
}

-- Builds a full, valid appearance table for a race definition.
function AppearanceOptions.defaultFor(raceDef)
	local d = AppearanceOptions.Defaults
	return {
		skinTone = raceDef.skinTones[1],
		hairStyle = d.hairStyle,
		hairColor = d.hairColor,
		topColor = d.topColor,
		bottomColor = d.bottomColor,
		height = raceDef.scale.height[3],
		width = raceDef.scale.width[3],
		depth = raceDef.scale.depth[3],
		head = raceDef.scale.head[3],
	}
end

return AppearanceOptions
