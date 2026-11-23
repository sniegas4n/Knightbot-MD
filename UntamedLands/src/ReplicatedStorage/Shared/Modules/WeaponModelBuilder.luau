--!nonstrict
--[[
	WeaponModelBuilder
	Location : ReplicatedStorage/Shared/Modules/WeaponModelBuilder (ModuleScript)
	Purpose  : Builds a weapon's visual model from its definition and welds it to a
	           hand. Uses Weld (explicit C0) rather than WeldConstraint so the result
	           never depends on the arm's current animated pose.
	           Visual parts are Massless and have CanQuery = false, so they never
	           affect movement or combat hit detection.
	           slotName : "MainHand" or "OffHand". Calling attach with a nil weapon
	           removes whatever is in that slot.
	Depends  : nothing (weapon definitions are passed in)
]]

local WeaponModelBuilder = {}

function WeaponModelBuilder.attach(character, weaponDef, slotName)
	local modelName = slotName .. "Model"
	local existing = character:FindFirstChild(modelName)
	if existing then
		existing:Destroy()
	end
	if not weaponDef or not weaponDef.model then
		return nil
	end

	local spec = weaponDef.model
	local handName = spec.hand or (if slotName == "OffHand" then "LeftHand" else "RightHand")
	local hand = character:FindFirstChild(handName)
	if not hand or not hand:IsA("BasePart") then
		return nil
	end

	local grip = spec.grip or CFrame.identity
	local model = Instance.new("Model")
	model.Name = modelName

	for _, partSpec in ipairs(spec.parts) do
		local part = Instance.new("Part")
		part.Name = partSpec.name or "Piece"
		if partSpec.shape then
			part.Shape = Enum.PartType[partSpec.shape]
		end
		part.Size = partSpec.size
		part.Color = partSpec.color or Color3.new(0.5, 0.5, 0.5)
		part.Material = Enum.Material[partSpec.material or "SmoothPlastic"]
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.Anchored = false

		local offset = grip * (partSpec.offset or CFrame.identity)
		part.CFrame = hand.CFrame * offset

		local joint = Instance.new("Weld")
		joint.Part0 = hand
		joint.Part1 = part
		joint.C0 = offset
		joint.Parent = part

		part.Parent = model
	end

	model.Parent = character
	return model
end

return WeaponModelBuilder
