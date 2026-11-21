--[[
	HUDController (ModuleScript) — CLIENT
	Emplacement : StarterPlayer > StarterPlayerScripts > Controllers > HUDController

	Construit et met à jour le HUD principal (ScreenGui "HUD" dans PlayerGui).
	Le HUD est généré en code (pas de GUI dessinée à la main dans StarterGui) :
	versionnable, reproductible, et chaque valeur vient de Config.UI.

	Sources de données (le HUD ne fait que LIRE) :
	  - Vie          : Humanoid.Health / MaxHealth
	  - Ressources   : attributs Player Stamina, MaxStamina, Energy, MaxEnergy
	  - Progression  : attributs Player Level, Experience, ExperienceRequired
	  - Monnaies     : attributs Player Gold, Crystals, DivineShards
	  - Notifications: Remote UI_Notify
	  - Esquive      : signaux de MovementController

	Disposition (résolution de référence 1280x720, mise à l'échelle UIScale) :
	  haut-gauche  : panneau joueur (niveau, vie, énergie, endurance)
	  haut-droite  : mini-carte (provisoire), monnaies, quêtes actives
	  bas-centre   : barre de compétences (Q Z X C V) + barre d'expérience
	  haut-centre  : notifications
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared.Modules.Net)
local Maid = require(Shared.Modules.Maid)

local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Create = require(UIFolder:WaitForChild("Create"))
local Format = require(UIFolder:WaitForChild("Format"))
local ResourceBar = require(UIFolder.Components:WaitForChild("ResourceBar"))
local SkillSlot = require(UIFolder.Components:WaitForChild("SkillSlot"))
local NotificationFeed = require(UIFolder.Components:WaitForChild("NotificationFeed"))

local UI = Config.UI
local Colors = UI.Colors

local player = Players.LocalPlayer

local HUDController = {}

local InputController
local MovementController

local gui: ScreenGui
local uiScale: UIScale
local bars: { [string]: any } = {}
local skillSlots: { [string]: any } = {}
local currencyLabels: { [string]: TextLabel } = {}
local levelLabel: TextLabel
local regionLabel: TextLabel
local questBody: TextLabel
local levelBanner: TextLabel
local feed
local animatedPanels: { { Frame: GuiObject, Target: UDim2, From: UDim2 } } = {}
local characterMaid = Maid.new()
local lastStaminaWarning = 0

-- ── Utilitaires ───────────────────────────────────────────────────────────

local function attribute(name: string, default: any): any
	local value = player:GetAttribute(name)
	if value == nil then
		return default
	end
	return value
end

local function makePanel(properties: { [string]: any }): Frame
	local panel = Create("Frame", {
		BackgroundColor3 = Colors.PanelBackground,
		BackgroundTransparency = UI.PanelTransparency,
		BorderSizePixel = 0,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, UI.CornerRadius) }),
		Create("UIStroke", { Color = Colors.PanelStroke, Transparency = 0.5, Thickness = 1.5 }),
	})
	for key, value in properties do
		(panel :: any)[key] = value
	end
	return panel
end

local function registerAnimated(frame: GuiObject, offset: UDim2)
	table.insert(animatedPanels, { Frame = frame, Target = frame.Position, From = frame.Position + offset })
end

local function getRegionName(regionId: string?): string
	for _, region in Config.Regions.List do
		if region.Id == regionId then
			return region.DisplayName
		end
	end
	return "Terres inconnues"
end

-- ── Construction ──────────────────────────────────────────────────────────

local function buildPlayerPanel()
	local panel = makePanel({
		Name = "PlayerPanel",
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(300, 92),
		Parent = gui,
	})

	local badge = Create("Frame", {
		Name = "LevelBadge",
		Position = UDim2.fromOffset(10, 14),
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = Colors.BarBackground,
		Parent = panel,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Create("UIStroke", { Color = Colors.Accent, Thickness = 2 }),
		Create("TextLabel", {
			Name = "Caption",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.new(1, 0, 0, 12),
			Font = UI.FontRegular,
			Text = "NIV.",
			TextColor3 = Colors.TextDim,
			TextSize = 11,
		}),
	})

	levelLabel = Create("TextLabel", {
		Name = "Level",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 32),
		Font = UI.Font,
		Text = "1",
		TextColor3 = Colors.Accent,
		TextScaled = true,
		Parent = badge,
	}, {
		Create("UITextSizeConstraint", { MaxTextSize = 26 }),
	})

	Create("TextLabel", {
		Name = "PlayerName",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(84, 6),
		Size = UDim2.fromOffset(206, 18),
		Font = UI.Font,
		Text = player.DisplayName,
		TextColor3 = Colors.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = panel,
	})

	bars.Health = ResourceBar.new({
		Parent = panel,
		Name = "HealthBar",
		Position = UDim2.fromOffset(84, 28),
		Size = UDim2.fromOffset(206, 20),
		Color = Colors.Health,
		Label = "PV",
		TextSize = 12,
	})
	bars.Energy = ResourceBar.new({
		Parent = panel,
		Name = "EnergyBar",
		Position = UDim2.fromOffset(84, 52),
		Size = UDim2.fromOffset(206, 14),
		Color = Colors.Energy,
		Label = "ÉNERGIE",
		TextSize = 10,
	})
	bars.Stamina = ResourceBar.new({
		Parent = panel,
		Name = "StaminaBar",
		Position = UDim2.fromOffset(84, 70),
		Size = UDim2.fromOffset(206, 14),
		Color = Colors.Stamina,
		Label = "ENDURANCE",
		TextSize = 10,
	})

	registerAnimated(panel, UDim2.fromOffset(-360, 0))
end

local function buildRightColumn()
	-- Mini-carte provisoire (la vraie carte arrive avec la Phase 4 / Monde).
	local mapPanel = Create("Frame", {
		Name = "MapPanel",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(150, 164),
		Parent = gui,
	})

	local minimap = makePanel({
		Name = "Minimap",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(140, 140),
		Parent = mapPanel,
	})
	minimap:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)

	Create("Frame", {
		Name = "PlayerDot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(10, 10),
		BackgroundColor3 = Colors.Accent,
		Parent = minimap,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
	})

	Create("TextLabel", {
		Name = "North",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(20, 16),
		Font = UI.Font,
		Text = "N",
		TextColor3 = Colors.TextDim,
		TextSize = 12,
		Parent = minimap,
	})

	regionLabel = Create("TextLabel", {
		Name = "Region",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 18),
		Font = UI.Font,
		Text = getRegionName(Config.Regions.DefaultRegionId),
		TextColor3 = Colors.Text,
		TextSize = 13,
		TextStrokeTransparency = 0.5,
		Parent = mapPanel,
	})

	-- Monnaies
	local currencyPanel = makePanel({
		Name = "Currencies",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 184),
		Size = UDim2.fromOffset(150, 84),
		Parent = gui,
	})
	Create("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = currencyPanel,
	})
	Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
		Parent = currencyPanel,
	})

	for id, definition in Config.Economy.Currencies do
		local row = Create("Frame", {
			Name = id,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 22),
			LayoutOrder = definition.Order,
			Parent = currencyPanel,
		})
		Create("Frame", {
			Name = "Icon",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = definition.Color,
			Rotation = 45, -- losange
			Parent = row,
		}, {
			Create("UICorner", { CornerRadius = UDim.new(0, 2) }),
		})
		Create("TextLabel", {
			Name = "Name",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(20, 0),
			Size = UDim2.new(0.55, -20, 1, 0),
			Font = UI.FontRegular,
			Text = definition.DisplayName,
			TextColor3 = Colors.TextDim,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})
		currencyLabels[id] = Create("TextLabel", {
			Name = "Amount",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.45, 1),
			Font = UI.Font,
			Text = "0",
			TextColor3 = definition.Color,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})
	end

	-- Quêtes actives
	local questPanel = makePanel({
		Name = "QuestTracker",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 280),
		Size = UDim2.fromOffset(220, 96),
		Parent = gui,
	})
	Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 18),
		Font = UI.Font,
		Text = "QUÊTES ACTIVES",
		TextColor3 = Colors.Accent,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = questPanel,
	})
	questBody = Create("TextLabel", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 28),
		Size = UDim2.new(1, -20, 1, -34),
		Font = UI.FontRegular,
		Text = "Aucune quête active.\nParlez aux habitants du Royaume d'Aether.",
		TextColor3 = Colors.TextDim,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = questPanel,
	})

	registerAnimated(mapPanel, UDim2.fromOffset(360, 0))
	registerAnimated(currencyPanel, UDim2.fromOffset(360, 0))
	registerAnimated(questPanel, UDim2.fromOffset(360, 0))
end

local function buildBottomBar()
	local bottom = Create("Frame", {
		Name = "BottomBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(540, 90),
		Parent = gui,
	})

	local skillBar = Create("Frame", {
		Name = "SkillBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(1, 0, 0, 56),
		Parent = bottom,
	}, {
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
	})

	-- Q (esquive) est fonctionnel ; Z X C V seront branchés par le combat.
	local SLOTS = {
		{ Action = "Dodge", Key = "Q", Name = "Esquive" },
		{ Action = "Skill1", Name = "—" },
		{ Action = "Skill2", Name = "—" },
		{ Action = "Skill3", Name = "—" },
		{ Action = "Ultimate", Name = "Ultime", Accent = Colors.Accent },
	}
	for index, slot in SLOTS do
		skillSlots[slot.Action] = SkillSlot.new({
			Parent = skillBar,
			Key = slot.Key or InputController:GetKeyLabel(slot.Action),
			Name = slot.Name,
			Accent = slot.Accent,
			LayoutOrder = index,
		})
	end

	bars.Experience = ResourceBar.new({
		Parent = bottom,
		Name = "ExperienceBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 16),
		Color = Colors.Experience,
		TextSize = 11,
	})

	registerAnimated(bottom, UDim2.fromOffset(0, 160))
end

local function buildOverlays()
	feed = NotificationFeed.new(gui)

	levelBanner = Create("TextLabel", {
		Name = "LevelUpBanner",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.32),
		Size = UDim2.fromOffset(600, 70),
		Font = UI.Font,
		Text = "",
		TextColor3 = Colors.Accent,
		TextSize = 44,
		TextStrokeColor3 = Color3.fromRGB(80, 40, 0),
		TextStrokeTransparency = 0.2,
		TextTransparency = 1,
		Visible = false,
		Parent = gui,
	}, {
		Create("UIScale", { Name = "PopScale", Scale = 1 }),
	})
end

-- ── Mise à jour des données ───────────────────────────────────────────────

local function refreshResource(id: string, instant: boolean?)
	local bar = bars[id]
	if bar then
		bar:Set(attribute(id, 0), attribute("Max" .. id, 100), instant)
	end
end

local function refreshExperience(instant: boolean?)
	local level = attribute("Level", 1)
	local experience = attribute("Experience", 0)
	local required = attribute("ExperienceRequired", 0)

	levelLabel.Text = tostring(level)

	if required <= 0 then
		bars.Experience:Set(1, 1, instant)
		bars.Experience:SetText(("Niv. %d — NIVEAU MAXIMUM"):format(level))
	else
		bars.Experience:Set(experience, required, instant)
		bars.Experience:SetText(("Niv. %d — %s / %s XP (%d%%)"):format(
			level,
			Format.Compact(experience),
			Format.Compact(required),
			math.floor(experience / required * 100)
		))
	end
end

local function refreshCurrency(id: string)
	local label = currencyLabels[id]
	if label then
		label.Text = Format.Compact(attribute(id, 0))
	end
end

local function showLevelUp(text: string)
	levelBanner.Text = text
	levelBanner.Visible = true
	levelBanner.TextTransparency = 0
	levelBanner.TextStrokeTransparency = 0.2

	local popScale = levelBanner:FindFirstChild("PopScale") :: UIScale
	popScale.Scale = 0.4
	TweenService:Create(popScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	task.delay(1.6, function()
		local fade = TweenService:Create(
			levelBanner,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		)
		fade.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				levelBanner.Visible = false
			end
		end)
		fade:Play()
	end)
end

local function bindCharacter(character: Model)
	characterMaid:Clean()

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	local function refreshHealth(instant: boolean?)
		bars.Health:Set(humanoid.Health, humanoid.MaxHealth, instant)
	end

	refreshHealth(true)
	characterMaid:Give(humanoid.HealthChanged:Connect(function()
		refreshHealth(false)
	end))
	characterMaid:Give(humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		refreshHealth(false)
	end))

	for _, slot in skillSlots do
		slot:ClearCooldown()
	end
end

-- ── Responsive ────────────────────────────────────────────────────────────

local function updateScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local reference = UI.ReferenceResolution
	local scale = math.min(viewport.X / reference.X, viewport.Y / reference.Y)
	if InputController:IsTouchDevice() then
		scale *= UI.TouchScaleMultiplier
	end
	uiScale.Scale = math.clamp(scale, UI.MinScale, UI.MaxScale)
end

local function playOpenAnimation()
	for index, entry in animatedPanels do
		entry.Frame.Position = entry.From
		local tween = TweenService:Create(
			entry.Frame,
			TweenInfo.new(UI.OpenAnimationTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, (index - 1) * 0.06),
			{ Position = entry.Target }
		)
		tween:Play()
	end
end

-- ── API publique ──────────────────────────────────────────────────────────

function HUDController:Notify(text: string, kind: string?)
	if feed then
		feed:Push(text, kind)
	end
end

-- Phase 4 (QuestService) : liste de chaînes à afficher.
function HUDController:SetQuests(lines: { string })
	if #lines == 0 then
		questBody.Text = "Aucune quête active."
	else
		questBody.Text = table.concat(lines, "\n")
	end
end

function HUDController:GetSkillSlot(actionId: string)
	return skillSlots[actionId]
end

-- ── Cycle de vie ──────────────────────────────────────────────────────────

function HUDController:Init(controllers)
	InputController = controllers.InputController
	MovementController = controllers.MovementController
end

function HUDController:Start()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)

	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("HUD")
	if existing then
		existing:Destroy()
	end

	gui = Create("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1,
	})
	uiScale = Create("UIScale", { Name = "ResponsiveScale", Parent = gui })

	buildPlayerPanel()
	buildRightColumn()
	buildBottomBar()
	buildOverlays()

	if InputController:IsTouchDevice() then
		for _, slot in skillSlots do
			slot:SetKeyVisible(false)
		end
	end

	gui.Parent = playerGui

	-- Échelle responsive
	updateScale()
	local function watchCamera()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		end
		updateScale()
	end
	watchCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)

	-- Ressources & progression
	for _, id in { "Stamina", "Energy" } do
		refreshResource(id, true)
		player:GetAttributeChangedSignal(id):Connect(function()
			refreshResource(id)
		end)
		player:GetAttributeChangedSignal("Max" .. id):Connect(function()
			refreshResource(id)
		end)
	end

	refreshExperience(true)
	local lastLevel = attribute("Level", 1)
	player:GetAttributeChangedSignal("Experience"):Connect(function()
		refreshExperience(false)
	end)
	player:GetAttributeChangedSignal("ExperienceRequired"):Connect(function()
		refreshExperience(false)
	end)
	player:GetAttributeChangedSignal("Level"):Connect(function()
		local level = attribute("Level", 1)
		-- Au passage de niveau, la barre repart de zéro sans animation inverse.
		refreshExperience(level ~= lastLevel)
		lastLevel = level
	end)

	for id in Config.Economy.Currencies do
		refreshCurrency(id)
		player:GetAttributeChangedSignal(id):Connect(function()
			refreshCurrency(id)
		end)
	end

	player:GetAttributeChangedSignal("RegionId"):Connect(function()
		regionLabel.Text = getRegionName(player:GetAttribute("RegionId"))
	end)

	-- Personnage (vie)
	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end

	-- Esquive
	if MovementController then
		MovementController.Dodged:Connect(function(cooldown)
			skillSlots.Dodge:StartCooldown(cooldown)
		end)
		MovementController.DodgeRefused:Connect(function(reason)
			if reason == "Stamina" then
				bars.Stamina:Shake()
				local now = os.clock()
				if now - lastStaminaWarning > 1.5 then
					lastStaminaWarning = now
					HUDController:Notify("Endurance insuffisante", "Warning")
				end
			end
		end)
	end

	-- Notifications serveur
	Net.Get("UI_Notify").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or type(payload.Text) ~= "string" then
			return
		end
		if payload.Kind == "LevelUp" then
			showLevelUp(("NIVEAU %d !"):format(attribute("Level", 1)))
		end
		HUDController:Notify(payload.Text, payload.Kind)
	end)

	playOpenAnimation()
end

return HUDController
