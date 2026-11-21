--[[
	Create (ModuleScript) — CLIENT
	Emplacement : StarterPlayer > StarterPlayerScripts > UI > Create

	Fabrique d'instances déclarative pour construire l'interface en code.

	Create("Frame", { Name = "Panel", Size = UDim2.fromOffset(100, 50) }, {
		Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
	})

	La propriété Parent est appliquée en DERNIER (bonne pratique Roblox :
	on configure l'objet avant de l'insérer dans l'arbre).
]]

local function Create(className: string, properties: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil

	if properties then
		for key, value in properties do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end

	if children then
		for _, child in children do
			child.Parent = instance
		end
	end

	if parent then
		instance.Parent = parent
	end
	return instance
end

return Create
