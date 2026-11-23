--!nonstrict
--[[
	AppearanceService
	Location : ServerScriptService/Server/Core/AppearanceService (ModuleScript)
	Purpose  : Validates character-creation requests and turns saved appearance
	           data into a real R15 character.
	           - sanitize(): strict server-side validation of everything the
	             client submitted (the client UI is only a suggestion).
	           - buildDescription(): HumanoidDescription (scales + body colours).
	           - applyExtras(): things a HumanoidDescription can't express
	             (part-built hair). Milestone 7 adds scars, tattoos and
	             prosthetics here.
	Players' own Roblox avatars are deliberately NOT used: everyone in the world
	is a character of the Untamed Lands.
	Depends  : RaceDefinitions, AppearanceOptions, HairBuilder, Validate
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local RaceDefinitions = require(Shared.Config.RaceDefinitions)
local AppearanceOptions = require(Shared.Config.AppearanceOptions)
local HairBuilder = require(Shared.Modules.HairBuilder)
local Validate = require(Shared.Modules.Validate)

local AppearanceService = {}

AppearanceService.NameMin = 3
AppearanceService.NameMax = 20

local function cleanName(raw)
	local name = raw:gsub("^%s+", "")
	name = name:gsub("%s+$", "")
	name = name:gsub("%s+", " ")
	return name
end

-- Returns sanitized { name, race, appearance } or nil, errorMessage.
-- Name filtering (TextService) is done separately by CharacterService because it yields.
function AppearanceService.sanitize(payload)
	if not Validate.isPlainTable(payload) then
		return nil, "Invalid request."
	end
	if not Validate.isString(payload.name, 64) then
		return nil, "Choose a name."
	end
	local name = cleanName(payload.name)
	if #name < AppearanceService.NameMin or #name > AppearanceService.NameMax then
		return nil, ("Names must be %d-%d letters."):format(AppearanceService.NameMin, AppearanceService.NameMax)
	end
	if not name:match("^%a[%a '%-]*$") then
		return nil, "Names may only use letters, spaces, apostrophes and hyphens."
	end

	local raceDef = RaceDefinitions.get(payload.race)
	if not raceDef then
		return nil, "Choose a people."
	end

	local a = payload.appearance
	if not Validate.isPlainTable(a) then
		return nil, "Invalid appearance."
	end

	local function index(value, count)
		return Validate.isInteger(value, 1, count)
	end
	if not (Validate.isInteger(a.skinTone, 1, #AppearanceOptions.SkinTones) and table.find(raceDef.skinTones, a.skinTone)) then
		return nil, "That skin tone isn't available for this people."
	end
	if not index(a.hairStyle, #AppearanceOptions.HairStyles)
		or not index(a.hairColor, #AppearanceOptions.HairColors)
		or not index(a.topColor, #AppearanceOptions.ClothColors)
		or not index(a.bottomColor, #AppearanceOptions.ClothColors)
	then
		return nil, "Invalid appearance option."
	end

	local function scale(value, range)
		local v = Validate.clampNumber(value, range[1], range[2], range[3])
		return math.floor(v * 100 + 0.5) / 100
	end

	return {
		name = name,
		race = payload.race,
		appearance = {
			skinTone = a.skinTone,
			hairStyle = a.hairStyle,
			hairColor = a.hairColor,
			topColor = a.topColor,
			bottomColor = a.bottomColor,
			height = scale(a.height, raceDef.scale.height),
			width = scale(a.width, raceDef.scale.width),
			depth = scale(a.depth, raceDef.scale.depth),
			head = scale(a.head, raceDef.scale.head),
		},
	}
end

local function colorOf(list, index, fallback)
	local entry = list[index]
	return if entry then entry.color else fallback
end

function AppearanceService.buildDescription(characterData)
	local a = characterData.appearance
	local desc = Instance.new("HumanoidDescription")
	desc.HeightScale = a.height or 1
	desc.WidthScale = a.width or 1
	desc.DepthScale = a.depth or 1
	desc.HeadScale = a.head or 1
	desc.BodyTypeScale = 0
	desc.ProportionScale = 0

	local skin = colorOf(AppearanceOptions.SkinTones, a.skinTone, Color3.fromRGB(166, 116, 76))
	local top = colorOf(AppearanceOptions.ClothColors, a.topColor, Color3.fromRGB(196, 182, 150))
	local bottom = colorOf(AppearanceOptions.ClothColors, a.bottomColor, Color3.fromRGB(46, 44, 42))
	desc.HeadColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.TorsoColor = top
	desc.LeftLegColor = bottom
	desc.RightLegColor = bottom
	return desc
end

-- Simple description for NPCs (template.appearance from NPCDefinitions).
function AppearanceService.buildNPCDescription(appearance)
	local desc = Instance.new("HumanoidDescription")
	desc.HeightScale = appearance.height or 1
	desc.WidthScale = appearance.width or 1
	desc.BodyTypeScale = 0
	desc.ProportionScale = 0
	desc.HeadColor = appearance.skin
	desc.LeftArmColor = appearance.skin
	desc.RightArmColor = appearance.skin
	desc.TorsoColor = appearance.top
	desc.LeftLegColor = appearance.bottom
	desc.RightLegColor = appearance.bottom
	return desc
end

function AppearanceService.applyExtras(character, characterData)
	local head = character:WaitForChild("Head", 10)
	if not head then
		return
	end
	local old = character:FindFirstChild("Hair")
	if old then
		old:Destroy()
	end
	local a = characterData.appearance
	local hairColor = colorOf(AppearanceOptions.HairColors, a.hairColor, Color3.fromRGB(92, 64, 44))
	local hair = HairBuilder.build(head, a.hairStyle, hairColor, true)
	if hair then
		hair.Parent = character
	end
end

return AppearanceService
