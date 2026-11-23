--!nonstrict
--[[
	CharacterCreationController
	Location : StarterPlayer/StarterPlayerScripts/Client/Controllers/CharacterCreationController
	Purpose  : The character creation screen: name, people (race), skin tone,
	           hairstyle, hair colour, clothing dyes and body proportions, with a
	           live 3D preview (ViewportFrame + WorldModel). Drag the preview to
	           rotate it.
	           The UI only builds a request. The server re-validates everything
	           (AppearanceService.sanitize) and filters the name.
	Preview limits: colours, hair and overall height are previewed exactly.
	Width/depth/head sliders only take full effect on the real character
	(HumanoidDescription scaling is applied server-side).
	Depends  : UIKit, Net, RaceDefinitions, AppearanceOptions, HairBuilder,
	           CameraController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RaceDefinitions = require(Shared.Config.RaceDefinitions)
local AppearanceOptions = require(Shared.Config.AppearanceOptions)
local HairBuilder = require(Shared.Modules.HairBuilder)
local Net = require(Shared.Modules.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local player = Players.LocalPlayer
local C = UIKit.Colors

local CharacterCreationController = {}

local controllers = nil
local gui = nil
local state = nil
local refreshers = {}
local preview = nil -- { viewport, worldModel, rig, rotation }

local SKIN_PARTS = {
	Head = true, LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
	RightUpperArm = true, RightLowerArm = true, RightHand = true,
}
local TOP_PARTS = { UpperTorso = true, LowerTorso = true }
local BOTTOM_PARTS = {
	LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
	RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}

local connections = {}

-- Global input listeners are tracked so close() can disconnect them.
local function listen(signal, fn)
	table.insert(connections, signal:Connect(fn))
end

local function raceDef()
	return RaceDefinitions.Races[state.race]
end

local function cycle(index, count, step)
	return (index - 1 + step) % count + 1
end

---------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------
local function refreshPreview()
	if not preview or not preview.rig then
		return
	end
	local rig = preview.rig
	local a = state.appearance
	local oldHair = rig:FindFirstChild("Hair")
	if oldHair then
		oldHair:Destroy()
	end

	pcall(function()
		rig:ScaleTo(a.height)
	end)
	rig:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, preview.rotation, 0))

	local skin = AppearanceOptions.SkinTones[a.skinTone].color
	local top = AppearanceOptions.ClothColors[a.topColor].color
	local bottom = AppearanceOptions.ClothColors[a.bottomColor].color
	for _, part in ipairs(rig:GetDescendants()) do
		if part:IsA("BasePart") then
			if SKIN_PARTS[part.Name] then
				part.Color = skin
			elseif TOP_PARTS[part.Name] then
				part.Color = top
			elseif BOTTOM_PARTS[part.Name] then
				part.Color = bottom
			end
		end
	end

	local head = rig:FindFirstChild("Head")
	if head then
		local hair = HairBuilder.build(head, a.hairStyle, AppearanceOptions.HairColors[a.hairColor].color, false)
		if hair then
			hair.Parent = rig
		end
	end
end

local function buildPreview(parent)
	local viewport = UIKit.create("ViewportFrame", {
		Name = "Preview",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0.97, 0, 0.5, 0),
		Size = UDim2.fromScale(0.45, 0.8),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.3,
		Ambient = Color3.fromRGB(150, 140, 125),
		LightColor = Color3.fromRGB(255, 240, 220),
		LightDirection = Vector3.new(-1, -1, -1),
		Parent = parent,
	}, { UIKit.corner(8), UIKit.stroke(C.Border) })

	local worldModel = UIKit.create("WorldModel", { Parent = viewport })
	local camera = UIKit.create("Camera", {
		FieldOfView = 30,
		CFrame = CFrame.lookAt(Vector3.new(0, 0.4, -13), Vector3.new(0, -0.2, 0)),
		Parent = viewport,
	})
	viewport.CurrentCamera = camera

	local hint = UIKit.label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -20, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 13,
		TextColor3 = C.TextDim,
		Text = "Drag to rotate",
		Parent = viewport,
	})

	preview = { viewport = viewport, worldModel = worldModel, rig = nil, rotation = 0 }

	-- Drag to rotate.
	local dragging, lastX = false, 0
	viewport.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, lastX = true, input.Position.X
		end
	end)
	listen(UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			preview.rotation += (input.Position.X - lastX) * 0.01
			lastX = input.Position.X
			if preview.rig then
				preview.rig:PivotTo(CFrame.Angles(0, preview.rotation, 0))
			end
		end
	end)
	listen(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	-- The rig is created by the server (CharacterService) once per server.
	task.spawn(function()
		local assets = ReplicatedStorage:WaitForChild("Assets")
		local template = assets:WaitForChild("PreviewRig", 20)
		if not template or not preview then
			hint.Text = "Preview unavailable"
			return
		end
		local rig = template:Clone()
		rig.Parent = worldModel
		preview.rig = rig
		refreshPreview()
	end)
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function rowFrame(list, height, order)
	return UIKit.create("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = list,
	})
end

local function addSelector(list, order, title, getText, onStep)
	local row = rowFrame(list, 34, order)
	UIKit.label({ Size = UDim2.new(0.35, 0, 1, 0), Text = title, TextSize = 15, TextColor3 = C.TextDim, Parent = row })
	local prev = UIKit.button("<", { Position = UDim2.new(0.35, 0, 0, 2), Size = UDim2.new(0, 30, 0, 30), Parent = row })
	local value = UIKit.label({
		Position = UDim2.new(0.35, 34, 0, 0),
		Size = UDim2.new(0.65, -68, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = UIKit.Fonts.Bold,
		TextSize = 15,
		Parent = row,
	})
	local nextButton = UIKit.button(">", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.new(0, 30, 0, 30), Parent = row })

	local function refresh()
		value.Text = getText()
	end
	prev.Activated:Connect(function()
		onStep(-1)
		CharacterCreationController.refresh()
	end)
	nextButton.Activated:Connect(function()
		onStep(1)
		CharacterCreationController.refresh()
	end)
	table.insert(refreshers, refresh)
end

local function addSlider(list, order, title, key)
	local row = rowFrame(list, 40, order)
	local label = UIKit.label({ Size = UDim2.new(1, 0, 0, 18), TextSize = 14, TextColor3 = C.TextDim, Parent = row })
	local track = UIKit.create("Frame", {
		Position = UDim2.new(0, 0, 0, 24),
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = C.Backdrop,
		Parent = row,
	}, { UIKit.corner(4), UIKit.stroke(C.Border, 1, 0.4) })
	local fill = UIKit.create("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Parent = track }, { UIKit.corner(4) })
	local knob = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = C.Text,
		ZIndex = 3,
		Parent = track,
	}, { UIKit.corner(7) })

	local function range()
		return raceDef().scale[key]
	end
	local function refresh()
		local r = range()
		local value = math.clamp(state.appearance[key], r[1], r[2])
		state.appearance[key] = value
		local alpha = if r[2] > r[1] then (value - r[1]) / (r[2] - r[1]) else 0.5
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		label.Text = ("%s  %d%%"):format(title, math.floor(value * 100 + 0.5))
	end
	local function setFromX(x)
		local r = range()
		local alpha = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		state.appearance[key] = math.floor((r[1] + (r[2] - r[1]) * alpha) * 100 + 0.5) / 100
		CharacterCreationController.refresh()
	end

	local dragging = false
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	listen(UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	listen(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	table.insert(refreshers, refresh)
end

---------------------------------------------------------------------------
-- Screen
---------------------------------------------------------------------------
function CharacterCreationController.refresh()
	for _, refresh in ipairs(refreshers) do
		refresh()
	end
	refreshPreview()
end

local function setRace(id)
	state.race = id
	local def = raceDef()
	local a = state.appearance
	if not table.find(def.skinTones, a.skinTone) then
		a.skinTone = def.skinTones[1]
	end
	for _, key in ipairs({ "height", "width", "depth", "head" }) do
		a[key] = def.scale[key][3]
	end
end

function CharacterCreationController.open()
	if gui then
		return
	end
	refreshers = {}
	local firstRace = RaceDefinitions.Order[1]
	state = {
		name = "",
		race = firstRace,
		appearance = AppearanceOptions.defaultFor(RaceDefinitions.Races[firstRace]),
	}
	controllers.Camera.setCursorFree("CharacterCreation", true)

	gui = UIKit.create("ScreenGui", {
		Name = "CharacterCreation",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})

	local backdrop = UIKit.create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Backdrop,
		Parent = gui,
	}, {
		UIKit.create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.fromRGB(58, 44, 32), Color3.fromRGB(12, 10, 8)),
		}),
	})

	UIKit.label({
		Position = UDim2.new(0.03, 0, 0.03, 0),
		Size = UDim2.new(0.5, 0, 0, 44),
		Font = UIKit.Fonts.Title,
		TextSize = 40,
		Text = "UNTAMED LANDS",
		Parent = backdrop,
	})
	UIKit.label({
		Position = UDim2.new(0.03, 0, 0.03, 46),
		Size = UDim2.new(0.5, 0, 0, 22),
		TextSize = 16,
		TextColor3 = C.TextDim,
		Text = "Who walks out of the dust?",
		Parent = backdrop,
	})

	local panel = UIKit.create("Frame", {
		Position = UDim2.new(0.03, 0, 0.03, 80),
		Size = UDim2.new(0.46, 0, 0.97, -170),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.15,
		Parent = backdrop,
	}, { UIKit.corner(8), UIKit.stroke(C.Border), UIKit.create("UISizeConstraint", { MaxSize = Vector2.new(480, math.huge) }) })

	local list = UIKit.create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	}, {
		UIKit.padding(12),
		UIKit.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
	})

	-- Name
	local nameRow = rowFrame(list, 56, 1)
	UIKit.label({ Size = UDim2.new(1, 0, 0, 18), Text = "Name", TextSize = 15, TextColor3 = C.TextDim, Parent = nameRow })
	local nameBox = UIKit.create("TextBox", {
		Position = UDim2.new(0, 0, 0, 22),
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = C.Backdrop,
		Font = UIKit.Fonts.Bold,
		TextSize = 16,
		TextColor3 = C.Text,
		PlaceholderText = "3-20 letters",
		PlaceholderColor3 = C.TextDim,
		Text = "",
		ClearTextOnFocus = false,
		Parent = nameRow,
	}, { UIKit.corner(4), UIKit.stroke(C.Border), UIKit.padding(6) })
	nameBox:GetPropertyChangedSignal("Text"):Connect(function()
		if #nameBox.Text > 20 then
			nameBox.Text = nameBox.Text:sub(1, 20)
		end
		state.name = nameBox.Text
	end)

	-- People
	addSelector(list, 2, "People", function()
		return raceDef().displayName
	end, function(step)
		local index = table.find(RaceDefinitions.Order, state.race) or 1
		setRace(RaceDefinitions.Order[cycle(index, #RaceDefinitions.Order, step)])
	end)
	local raceDescription = UIKit.label({
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = 13,
		TextColor3 = C.TextDim,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 3,
		Parent = list,
	})
	table.insert(refreshers, function()
		local def = raceDef()
		local mods = {}
		for stat, delta in pairs(def.statModifiers) do
			table.insert(mods, ("%s %+d"):format(stat, delta))
		end
		table.sort(mods)
		raceDescription.Text = def.description .. "\n" .. table.concat(mods, ", ")
	end)

	addSelector(list, 4, "Skin", function()
		return AppearanceOptions.SkinTones[state.appearance.skinTone].name
	end, function(step)
		local tones = raceDef().skinTones
		local index = table.find(tones, state.appearance.skinTone) or 1
		state.appearance.skinTone = tones[cycle(index, #tones, step)]
	end)

	addSelector(list, 5, "Hair", function()
		return AppearanceOptions.HairStyles[state.appearance.hairStyle].name
	end, function(step)
		state.appearance.hairStyle = cycle(state.appearance.hairStyle, #AppearanceOptions.HairStyles, step)
	end)

	addSelector(list, 6, "Hair colour", function()
		return AppearanceOptions.HairColors[state.appearance.hairColor].name
	end, function(step)
		state.appearance.hairColor = cycle(state.appearance.hairColor, #AppearanceOptions.HairColors, step)
	end)

	addSelector(list, 7, "Tunic", function()
		return AppearanceOptions.ClothColors[state.appearance.topColor].name
	end, function(step)
		state.appearance.topColor = cycle(state.appearance.topColor, #AppearanceOptions.ClothColors, step)
	end)

	addSelector(list, 8, "Trousers", function()
		return AppearanceOptions.ClothColors[state.appearance.bottomColor].name
	end, function(step)
		state.appearance.bottomColor = cycle(state.appearance.bottomColor, #AppearanceOptions.ClothColors, step)
	end)

	addSlider(list, 9, "Height", "height")
	addSlider(list, 10, "Build", "width")
	addSlider(list, 11, "Bulk", "depth")
	addSlider(list, 12, "Head", "head")

	-- Footer
	local errorLabel = UIKit.label({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.03, 0, 1, -24),
		Size = UDim2.new(0.46, -190, 0, 44),
		TextSize = 14,
		TextColor3 = C.Bad,
		Text = "",
		Parent = backdrop,
	})
	local beginButton = UIKit.button("WALK INTO THE WASTES", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.03, 0, 1, -76),
		Size = UDim2.new(0, 260, 0, 48),
		BackgroundColor3 = C.Accent,
		Font = UIKit.Fonts.Title,
		TextSize = 20,
		Parent = backdrop,
	})

	local submitting = false
	beginButton.Activated:Connect(function()
		if submitting then
			return
		end
		submitting = true
		errorLabel.Text = ""
		beginButton.Text = "..."
		local payload = {
			name = state.name,
			race = state.race,
			appearance = table.clone(state.appearance),
		}
		local ok, result = pcall(Net.invoke, "SubmitCharacter", payload)
		if ok and type(result) == "table" and result.ok then
			CharacterCreationController.close()
			return
		end
		errorLabel.Text = if ok and type(result) == "table" and result.message then result.message else "The server did not answer. Try again."
		beginButton.Text = "WALK INTO THE WASTES"
		submitting = false
	end)

	buildPreview(backdrop)
	CharacterCreationController.refresh()
end

function CharacterCreationController.close()
	if gui then
		gui:Destroy()
		gui = nil
	end
	preview = nil
	refreshers = {}
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	connections = {}
	controllers.Camera.setCursorFree("CharacterCreation", false)
end

function CharacterCreationController.init(allControllers)
	controllers = allControllers
end

return CharacterCreationController
