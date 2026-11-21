--[[
	ResourceBar (ModuleScript) — CLIENT
	Emplacement : StarterPlayer > StarterPlayerScripts > UI > Components > ResourceBar

	Barre animée (vie, énergie, endurance, expérience) :
	  - remplissage interpolé (TweenService),
	  - "traînée" blanche qui rattrape le remplissage avec un délai quand la
	    valeur baisse (lecture claire des dégâts, style anime).

	local bar = ResourceBar.new({ Parent = frame, Size = UDim2.fromOffset(200, 16),
		Color = Color3.new(1, 0, 0), Label = "PV" })
	bar:Set(75, 100)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Create = require(script.Parent.Parent.Create)

local UI = Config.UI
local Colors = UI.Colors

local ResourceBar = {}
ResourceBar.__index = ResourceBar

export type Options = {
	Parent: Instance?,
	Name: string?,
	Size: UDim2,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Color: Color3,
	Label: string?,
	ShowValue: boolean?,
	TextSize: number?,
	LayoutOrder: number?,
}

function ResourceBar.new(options: Options)
	local self = setmetatable({}, ResourceBar)
	local textSize = options.TextSize or 12

	self.Frame = Create("Frame", {
		Name = options.Name or "ResourceBar",
		Size = options.Size,
		Position = options.Position or UDim2.new(),
		AnchorPoint = options.AnchorPoint or Vector2.zero,
		BackgroundColor3 = Colors.BarBackground,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = options.LayoutOrder or 0,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
		Create("UIStroke", { Color = Color3.new(0, 0, 0), Transparency = 0.4, Thickness = 1 }),
	})

	self.Trail = Create("Frame", {
		Name = "Trail",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Colors.BarTrail,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = self.Frame,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
	})

	self.Fill = Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = options.Color,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = self.Frame,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
		-- Reflet léger en haut de la barre.
		Create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(0.45, Color3.fromRGB(220, 220, 220)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 150, 150)),
			}),
		}),
	})

	if options.Label then
		Create("TextLabel", {
			Name = "Label",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(6, 0),
			Size = UDim2.new(0.5, -6, 1, 0),
			Font = UI.Font,
			Text = options.Label,
			TextColor3 = Colors.Text,
			TextSize = textSize,
			TextStrokeTransparency = 0.5,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
			Parent = self.Frame,
		})
	end

	self.ValueLabel = Create("TextLabel", {
		Name = "Value",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 0),
		Size = UDim2.new(options.Label and 0.5 or 1, -6, 1, 0),
		Font = UI.Font,
		Text = "",
		TextColor3 = Colors.Text,
		TextSize = textSize,
		TextStrokeTransparency = 0.5,
		TextXAlignment = options.Label and Enum.TextXAlignment.Right or Enum.TextXAlignment.Center,
		Visible = options.ShowValue ~= false,
		ZIndex = 4,
		Parent = self.Frame,
	})

	self._ratio = 1
	self._trailToken = 0
	self._fillTween = nil
	self._trailTween = nil

	if options.Parent then
		self.Frame.Parent = options.Parent
	end
	return self
end

function ResourceBar:_tweenTrail(ratio: number)
	if self._trailTween then
		self._trailTween:Cancel()
	end
	self._trailTween = TweenService:Create(
		self.Trail,
		TweenInfo.new(UI.BarTrailTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(ratio, 1) }
	)
	self._trailTween:Play()
end

-- Met à jour la barre. `instant` = sans animation (premier affichage).
function ResourceBar:Set(current: number, max: number, instant: boolean?)
	current = tonumber(current) or 0
	max = tonumber(max) or 0
	local ratio = if max > 0 then math.clamp(current / max, 0, 1) else 0
	local previous = self._ratio
	self._ratio = ratio

	if self.ValueLabel.Visible then
		self.ValueLabel.Text = string.format("%d / %d", math.floor(current + 0.5), math.floor(max + 0.5))
	end

	if self._fillTween then
		self._fillTween:Cancel()
	end

	if instant then
		self.Fill.Size = UDim2.fromScale(ratio, 1)
		self.Trail.Size = UDim2.fromScale(ratio, 1)
		return
	end

	self._fillTween = TweenService:Create(
		self.Fill,
		TweenInfo.new(UI.BarTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(ratio, 1) }
	)
	self._fillTween:Play()

	self._trailToken += 1
	if ratio < previous then
		-- Perte : la traînée attend puis rattrape.
		local token = self._trailToken
		task.delay(UI.BarTrailDelay, function()
			if self._trailToken == token and self.Trail.Parent then
				self:_tweenTrail(self._ratio)
			end
		end)
	else
		-- Gain : la traînée suit immédiatement.
		if self._trailTween then
			self._trailTween:Cancel()
		end
		self.Trail.Size = UDim2.fromScale(ratio, 1)
	end
end

-- Remplace le texte de valeur (ex. XP : "Niv. 5 — 120 / 400 XP").
function ResourceBar:SetText(text: string)
	self.ValueLabel.Text = text
end

-- Petite secousse horizontale (ressource insuffisante).
function ResourceBar:Shake()
	local frame = self.Frame
	local origin = self._shakeOrigin or frame.Position
	self._shakeOrigin = origin
	task.spawn(function()
		for _, offset in { 6, -6, 4, -4, 2, 0 } do
			if not frame.Parent then
				return
			end
			frame.Position = origin + UDim2.fromOffset(offset, 0)
			task.wait(0.03)
		end
		frame.Position = origin
	end)
end

function ResourceBar:Destroy()
	self.Frame:Destroy()
end

return ResourceBar
