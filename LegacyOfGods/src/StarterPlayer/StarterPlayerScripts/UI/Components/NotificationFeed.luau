--[[
	NotificationFeed (ModuleScript) — CLIENT
	Emplacement : StarterPlayer > StarterPlayerScripts > UI > Components > NotificationFeed

	Pile de notifications en haut de l'écran (apparition / disparition
	animées, nombre maximum configurable dans Config.UI).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Create = require(script.Parent.Parent.Create)

local UI = Config.UI
local Colors = UI.Colors

local KIND_COLORS = {
	Info = Colors.PanelStroke,
	Success = Colors.Success,
	Warning = Colors.Warning,
	Error = Colors.Error,
	LevelUp = Colors.Accent,
}

local NotificationFeed = {}
NotificationFeed.__index = NotificationFeed

function NotificationFeed.new(parent: Instance)
	local self = setmetatable({}, NotificationFeed)

	self.Frame = Create("Frame", {
		Name = "Notifications",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.fromOffset(420, 200),
		Parent = parent,
	}, {
		Create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 6),
		}),
	})

	self._items = {}
	self._counter = 0
	return self
end

local function fadeOut(item: Frame, label: TextLabel, stroke: UIStroke)
	local info = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(item, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	local tween = TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 })
	tween.Completed:Once(function()
		item:Destroy()
	end)
	tween:Play()
end

function NotificationFeed:Push(text: string, kind: string?)
	if type(text) ~= "string" or text == "" then
		return
	end
	text = string.sub(text, 1, 200)
	local accent = KIND_COLORS[kind or "Info"] or KIND_COLORS.Info

	self._counter += 1

	local stroke = Create("UIStroke", { Color = accent, Thickness = 1.5, Transparency = 1 })
	local label = Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.fromOffset(8, 0),
		Font = UI.Font,
		Text = text,
		TextColor3 = Colors.Text,
		TextSize = 14,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		TextWrapped = true,
	})

	local item = Create("Frame", {
		Name = "Notification",
		BackgroundColor3 = Colors.PanelBackground,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 32),
		LayoutOrder = self._counter,
		Parent = self.Frame,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, UI.CornerRadius) }),
		stroke,
		label,
	})

	local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(item, info, { BackgroundTransparency = UI.PanelTransparency }):Play()
	TweenService:Create(stroke, info, { Transparency = 0.1 }):Play()
	TweenService:Create(label, info, { TextTransparency = 0, TextStrokeTransparency = 0.6 }):Play()

	-- Limite du nombre de notifications visibles.
	table.insert(self._items, item)
	while #self._items > UI.MaxNotifications do
		local oldest = table.remove(self._items, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	task.delay(UI.NotificationDuration, function()
		local index = table.find(self._items, item)
		if index then
			table.remove(self._items, index)
		end
		if item.Parent then
			fadeOut(item, label, stroke)
		end
	end)
end

return NotificationFeed
