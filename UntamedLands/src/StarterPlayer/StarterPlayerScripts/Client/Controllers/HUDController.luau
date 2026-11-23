--!nonstrict
--[[
	HUDController
	Location : StarterPlayer/StarterPlayerScripts/Client/Controllers/HUDController
	Purpose  : In-game HUD built from code:
	           - health and stamina bars, combat state, equipped weapon
	           - centre crosshair while the mouse is locked
	           - notification feed (Notify remote)
	           - floating combat text (damage, Blocked, PARRY, Dodged...)
	           - stats panel (C) and controls help (H)
	           - death overlay and a Studio "temporary data" warning
	           The HUD only DISPLAYS replicated values; it never changes them.
	Depends  : UIKit, Net, StatDefinitions, WeaponDefinitions, CameraController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StatDefinitions = require(Shared.Config.StatDefinitions)
local WeaponDefinitions = require(Shared.Config.WeaponDefinitions)
local Net = require(Shared.Modules.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local player = Players.LocalPlayer
local C = UIKit.Colors

local HUDController = {}

local controllers = nil
local gui, healthFill, staminaFill, healthText, staminaText, stateLabel, weaponLabel, nameLabel
local crosshair, feed, statsPanel, statsList, helpPanel, deathOverlay, tempWarning
local currentStats = nil

local STATE_TEXT = {
	Idle = "",
	Attacking = "Attacking",
	Recovering = "Recovering",
	Blocking = "Guarding",
	Dodging = "Evading",
	Staggered = "STAGGERED",
	Dead = "",
}

local FEEDBACK_STYLE = {
	Hit = { color = C.Text },
	Blocked = { color = Color3.fromRGB(150, 170, 190), prefix = "Blocked " },
	GuardBreak = { color = C.AccentBright, text = "GUARD BROKEN" },
	Parried = { color = Color3.fromRGB(230, 200, 110), text = "PARRY!" },
	Dodged = { color = C.TextDim, text = "Evaded" },
}

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
local function buildVitals()
	local panel = UIKit.create("Frame", {
		Name = "Vitals",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.new(0, 300, 0, 92),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.25,
		Parent = gui,
	}, { UIKit.corner(6), UIKit.stroke(C.Border, 1, 0.4), UIKit.padding(8) })

	nameLabel = UIKit.label({
		Size = UDim2.new(1, 0, 0, 18),
		Font = UIKit.Fonts.Title,
		TextSize = 18,
		Text = "",
		Parent = panel,
	})

	local healthBar
	healthBar, healthFill = UIKit.bar({ Position = UDim2.new(0, 0, 0, 24), Size = UDim2.new(1, 0, 0, 16), Parent = panel }, C.Health)
	healthText = UIKit.label({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 12, Font = UIKit.Fonts.Bold, ZIndex = 3, Parent = healthBar })

	local staminaBar
	staminaBar, staminaFill = UIKit.bar({ Position = UDim2.new(0, 0, 0, 46), Size = UDim2.new(1, 0, 0, 12), Parent = panel }, C.Stamina)
	staminaText = UIKit.label({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 11, Font = UIKit.Fonts.Bold, ZIndex = 3, Parent = staminaBar })

	stateLabel = UIKit.label({
		Position = UDim2.new(0, 0, 0, 62),
		Size = UDim2.new(1, 0, 0, 14),
		TextSize = 13,
		TextColor3 = C.AccentBright,
		Text = "",
		Parent = panel,
	})

	weaponLabel = UIKit.label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.new(0, 360, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = UIKit.Fonts.Title,
		TextSize = 20,
		TextStrokeTransparency = 0.6,
		Parent = gui,
	})
end

local function buildCrosshair()
	crosshair = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(4, 4),
		BackgroundColor3 = C.Text,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = gui,
	}, { UIKit.corner(2) })
end

local function buildFeed()
	feed = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.new(0, 420, 0, 140),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UIKit.create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 4),
		}),
	})
end

local function buildStatsPanel()
	statsPanel = UIKit.create("Frame", {
		Name = "Stats",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.new(0, 280, 0, 470),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = gui,
	}, { UIKit.corner(6), UIKit.stroke(C.Border), UIKit.padding(10) })

	UIKit.label({ Size = UDim2.new(1, 0, 0, 24), Text = "CHARACTER", Font = UIKit.Fonts.Title, TextSize = 22, Parent = statsPanel })
	statsList = UIKit.create("Frame", {
		Position = UDim2.new(0, 0, 0, 30),
		Size = UDim2.new(1, 0, 1, -30),
		BackgroundTransparency = 1,
		Parent = statsPanel,
	}, { UIKit.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }) })
end

local function buildHelpPanel()
	helpPanel = UIKit.create("Frame", {
		Name = "Help",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 16, 0, 60),
		Size = UDim2.new(0, 290, 0, 250),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.2,
		Visible = true,
		Parent = gui,
	}, { UIKit.corner(6), UIKit.stroke(C.Border, 1, 0.4), UIKit.padding(10) })

	UIKit.label({
		Size = UDim2.fromScale(1, 1),
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = 14,
		RichText = true,
		Text = table.concat({
			"<b>WASD</b> move   <b>Space</b> jump   <b>Shift</b> run",
			"<b>Left click</b> light attack   <b>R</b> heavy",
			"<b>Right mouse</b> hold to guard (raise late to parry)",
			"<b>Q</b> dodge   <b>1-4</b> weapons   <b>5</b> buckler",
			"Flick the mouse before attacking to choose",
			"the swing: sideways, up (overhead), down (thrust)",
			"<b>Alt</b> free cursor   <b>C</b> character   <b>H</b> this help",
			"",
			"Sparring thralls stand by the waystone.",
			"Dust raiders roam beyond the standing stones.",
		}, "\n"),
		Parent = helpPanel,
	})
end

local function buildDeathOverlay()
	deathOverlay = UIKit.create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	UIKit.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(0.8, 0, 0, 60),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = UIKit.Fonts.Title,
		TextSize = 42,
		TextColor3 = C.Bad,
		Text = "YOU HAVE FALLEN",
		ZIndex = 21,
		Parent = deathOverlay,
	})
end

local function buildTempWarning()
	tempWarning = UIKit.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12),
		Size = UDim2.new(0, 300, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 13,
		TextColor3 = C.Bad,
		Text = "TEST MODE: DataStore unavailable - progress will not be saved.",
		Visible = false,
		Parent = gui,
	})
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function HUDController.notify(text)
	if not feed then
		return
	end
	local label = UIKit.label({
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = UIKit.Fonts.Bold,
		TextSize = 16,
		TextStrokeTransparency = 0.5,
		Text = text,
		LayoutOrder = math.floor(os.clock() * 100),
		Parent = feed,
	})
	local children = {}
	for _, child in ipairs(feed:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(children, child)
		end
	end
	if #children > 5 then
		table.sort(children, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		children[1]:Destroy()
	end
	task.delay(5, function()
		if label.Parent then
			local tween = TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 })
			tween:Play()
			tween.Completed:Wait()
			label:Destroy()
		end
	end)
end

function HUDController.showCombatFeedback(info)
	if type(info) ~= "table" then
		return
	end
	local style = FEEDBACK_STYLE[info.result] or FEEDBACK_STYLE.Hit
	local text = style.text or ((style.prefix or "") .. tostring(info.damage or 0))
	local color = style.color
	if info.victim and info.result == "Hit" then
		color = C.Bad
	end

	local target = typeof(info.target) == "Instance" and info.target or nil
	local adornee = target and target:FindFirstChild("Head")
	if not adornee then
		return -- target not streamed in on this client
	end

	local billboard = UIKit.create("BillboardGui", {
		Adornee = adornee,
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(160, 40),
		StudsOffset = Vector3.new(math.random(-10, 10) / 10, 2, 0),
		LightInfluence = 0,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local label = UIKit.label({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = UIKit.Fonts.Title,
		TextSize = if info.result == "Hit" then 26 else 22,
		TextColor3 = color,
		TextStrokeTransparency = 0.3,
		Text = text,
		Parent = billboard,
	})
	TweenService:Create(billboard, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = billboard.StudsOffset + Vector3.new(0, 2.5, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1, function()
		billboard:Destroy()
	end)
end

local function statRow(id, value, order)
	local info = StatDefinitions.Info[id]
	local row = UIKit.create("Frame", {
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = statsList,
	})
	UIKit.label({ Size = UDim2.new(0.6, 0, 1, 0), TextSize = 14, Text = info.displayName, Parent = row })
	UIKit.label({
		Position = UDim2.new(0.6, 0, 0, 0),
		Size = UDim2.new(0.4, 0, 1, 0),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = UIKit.Fonts.Bold,
		Text = ("%d  <font color=\"#9e927e\">(%d%%)</font>"):format(math.floor(value), math.floor((value % 1) * 100)),
		RichText = true,
		Parent = row,
	})
end

local function sectionHeader(text, order)
	UIKit.label({
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 14,
		TextColor3 = C.AccentBright,
		Font = UIKit.Fonts.Bold,
		Text = text,
		LayoutOrder = order,
		Parent = statsList,
	})
end

function HUDController.setStats(stats)
	currentStats = stats
	if not statsList or not statsPanel.Visible then
		return
	end
	for _, child in ipairs(statsList:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	local order = 0
	sectionHeader("ATTRIBUTES", order)
	for _, id in ipairs(StatDefinitions.Attributes) do
		order += 1
		statRow(id, stats[id] or 0, order)
	end
	order += 1
	sectionHeader("SKILLS", order)
	for _, id in ipairs(StatDefinitions.Skills) do
		order += 1
		statRow(id, stats[id] or 0, order)
	end
end

function HUDController.setTemporaryWarning(visible)
	if tempWarning then
		tempWarning.Visible = visible
	end
end

---------------------------------------------------------------------------
-- Per-frame update
---------------------------------------------------------------------------
local function update()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	gui.Enabled = character ~= nil and humanoid ~= nil
	if not humanoid then
		return
	end

	local health = math.max(0, humanoid.Health)
	healthFill.Size = UDim2.fromScale(math.clamp(health / humanoid.MaxHealth, 0, 1), 1)
	healthText.Text = ("%d / %d"):format(math.ceil(health), math.floor(humanoid.MaxHealth + 0.5))

	local stamina = character:GetAttribute("Stamina") or 0
	local maxStamina = character:GetAttribute("MaxStamina") or 100
	staminaFill.Size = UDim2.fromScale(math.clamp(stamina / math.max(1, maxStamina), 0, 1), 1)
	staminaFill.BackgroundColor3 = if character:GetAttribute("Winded") then C.Bad else C.Stamina
	staminaText.Text = if character:GetAttribute("Winded") then "WINDED" else tostring(math.floor(stamina))

	stateLabel.Text = STATE_TEXT[character:GetAttribute("CombatState") or "Idle"] or ""
	nameLabel.Text = humanoid.DisplayName

	local weapon = WeaponDefinitions.get(character:GetAttribute("WeaponId"))
	local offhand = WeaponDefinitions.get(character:GetAttribute("OffhandId"))
	local weaponText = weapon and weapon.displayName or ""
	if offhand then
		weaponText ..= "  +  " .. offhand.displayName
	end
	weaponLabel.Text = weaponText

	crosshair.Visible = controllers.Camera.isCursorLocked()

	local dead = humanoid.Health <= 0
	if dead and not deathOverlay.Visible then
		deathOverlay.Visible = true
		deathOverlay.BackgroundTransparency = 1
		TweenService:Create(deathOverlay, TweenInfo.new(1.5), { BackgroundTransparency = 0.35 }):Play()
	elseif not dead and deathOverlay.Visible then
		deathOverlay.Visible = false
	end
end

function HUDController.init(allControllers)
	controllers = allControllers
	gui = UIKit.create("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	buildVitals()
	buildCrosshair()
	buildFeed()
	buildStatsPanel()
	buildHelpPanel()
	buildDeathOverlay()
	buildTempWarning()

	-- Notifications must still show before the character exists, so the feed
	-- lives in its own always-enabled ScreenGui.
	local feedGui = UIKit.create("ScreenGui", {
		Name = "Notifications",
		ResetOnSpawn = false,
		DisplayOrder = 20,
		Parent = player.PlayerGui,
	})
	feed.Parent = feedGui
	tempWarning.Parent = feedGui

	Net.on("Notify", function(text)
		if type(text) == "string" then
			HUDController.notify(text)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.C then
			statsPanel.Visible = not statsPanel.Visible
			controllers.Camera.setCursorFree("StatsPanel", statsPanel.Visible)
			if statsPanel.Visible and currentStats then
				HUDController.setStats(currentStats)
			end
		elseif input.KeyCode == Enum.KeyCode.H then
			helpPanel.Visible = not helpPanel.Visible
		end
	end)

	RunService.RenderStepped:Connect(update)
end

function HUDController.onCharacterAdded()
	-- Hide the help panel automatically after a while on first spawn.
	task.delay(25, function()
		if helpPanel then
			helpPanel.Visible = false
		end
	end)
end

return HUDController
