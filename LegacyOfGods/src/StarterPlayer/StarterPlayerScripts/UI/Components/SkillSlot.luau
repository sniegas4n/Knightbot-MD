--[[
	SkillSlot (ModuleScript) — CLIENT
	Emplacement : StarterPlayer > StarterPlayerScripts > UI > Components > SkillSlot

	Case de compétence du HUD avec touche, nom, icône et recharge animée.
	Utilisée dès maintenant pour l'esquive (Q) ; les compétences Z/X/C/V
	seront branchées par le système de combat (Phase 1-B / Phase 3).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Create = require(script.Parent.Parent.Create)

local UI = Config.UI
local Colors = UI.Colors

local SkillSlot = {}
SkillSlot.__index = SkillSlot

export type Options = {
	Parent: Instance?,
	Key: string,
	Name: string,
	Size: number?,
	LayoutOrder: number?,
	Accent: Color3?,
	Image: string?,
}

function SkillSlot.new(options: Options)
	local self = setmetatable({}, SkillSlot)
	local size = options.Size or 56

	self.Frame = Create("Frame", {
		Name = "Slot_" .. options.Key,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Colors.PanelBackground,
		BackgroundTransparency = UI.PanelTransparency,
		BorderSizePixel = 0,
		LayoutOrder = options.LayoutOrder or 0,
		ClipsDescendants = true,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, UI.CornerRadius) }),
		Create("UIStroke", {
			Color = options.Accent or Colors.PanelStroke,
			Thickness = 1.5,
			Transparency = 0.2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})

	self.Icon = Create("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.6, 0.6),
		Image = options.Image or "",
		Parent = self.Frame,
	})

	self.NameLabel = Create("TextLabel", {
		Name = "SkillName",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.new(1, -4, 0, 12),
		Font = UI.FontRegular,
		Text = options.Name,
		TextColor3 = Colors.TextDim,
		TextScaled = true,
		ZIndex = 3,
		Parent = self.Frame,
	}, {
		Create("UITextSizeConstraint", { MaxTextSize = 11 }),
	})

	self.KeyLabel = Create("TextLabel", {
		Name = "Key",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.fromOffset(18, 18),
		Font = UI.Font,
		Text = options.Key,
		TextColor3 = Colors.Accent,
		TextSize = 12,
		ZIndex = 4,
		Parent = self.Frame,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
	})

	self.Overlay = Create("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = self.Frame,
	})

	self.CooldownText = Create("TextLabel", {
		Name = "CooldownText",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = UI.Font,
		Text = "",
		TextColor3 = Colors.Text,
		TextSize = 16,
		TextStrokeTransparency = 0.4,
		ZIndex = 6,
		Parent = self.Frame,
	})

	self._cooldownConnection = nil

	if options.Parent then
		self.Frame.Parent = options.Parent
	end
	return self
end

function SkillSlot:SetKeyVisible(visible: boolean)
	self.KeyLabel.Visible = visible
end

function SkillSlot:SetName(name: string)
	self.NameLabel.Text = name
end

function SkillSlot:IsOnCooldown(): boolean
	return self._cooldownConnection ~= nil
end

-- Affiche une recharge de `duration` secondes (voile qui descend + compteur).
function SkillSlot:StartCooldown(duration: number)
	if duration <= 0 then
		return
	end
	self:ClearCooldown()

	local endsAt = os.clock() + duration
	self.Overlay.Size = UDim2.fromScale(1, 1)

	self._cooldownConnection = RunService.RenderStepped:Connect(function()
		local remaining = endsAt - os.clock()
		if remaining <= 0 then
			self:ClearCooldown()
			return
		end
		self.Overlay.Size = UDim2.fromScale(1, remaining / duration)
		self.CooldownText.Text = if remaining >= 1 then tostring(math.ceil(remaining)) else string.format("%.1f", remaining)
	end)
end

function SkillSlot:ClearCooldown()
	if self._cooldownConnection then
		self._cooldownConnection:Disconnect()
		self._cooldownConnection = nil
	end
	self.Overlay.Size = UDim2.fromScale(1, 0)
	self.CooldownText.Text = ""
end

function SkillSlot:Destroy()
	self:ClearCooldown()
	self.Frame:Destroy()
end

return SkillSlot
