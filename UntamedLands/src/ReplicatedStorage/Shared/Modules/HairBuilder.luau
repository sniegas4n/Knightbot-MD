--!nonstrict
--[[
	HairBuilder
	Location : ReplicatedStorage/Shared/Modules/HairBuilder (ModuleScript)
	Purpose  : Builds a part-based hairstyle on a head.
	           weld = true  -> parts are welded (live characters, server side)
	           weld = false -> parts are anchored (character creation preview)
	           Returns a Model named "Hair" (unparented) or nil for "Shaved".
	Depends  : AppearanceOptions
]]

local AppearanceOptions = require(script.Parent.Parent.Config.AppearanceOptions)

local HairBuilder = {}

local function rotationOf(spec)
	local r = spec.rotation
	if not r then
		return CFrame.identity
	end
	return CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
end

function HairBuilder.build(head, styleIndex, color, weld)
	local style = AppearanceOptions.HairStyles[styleIndex]
	if not style or not head or #style.parts == 0 then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = "Hair"
	local headSize = head.Size

	for index, spec in ipairs(style.parts) do
		local part = Instance.new("Part")
		part.Name = "HairPart" .. index
		if spec.shape then
			part.Shape = Enum.PartType[spec.shape]
		end
		part.Size = spec.size * headSize
		part.Color = color
		part.Material = Enum.Material.Fabric
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false

		local offset = CFrame.new(spec.offset * headSize) * rotationOf(spec)
		part.CFrame = head.CFrame * offset

		if weld then
			part.Anchored = false
			local joint = Instance.new("Weld")
			joint.Part0 = head
			joint.Part1 = part
			joint.C0 = offset
			joint.Parent = part
		else
			part.Anchored = true
		end
		part.Parent = model
	end

	return model
end

return HairBuilder
