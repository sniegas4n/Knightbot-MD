--!nonstrict
--[[
	CombatController
	Location : StarterPlayer/StarterPlayerScripts/Client/Controllers/CombatController
	Purpose  : Combat input -> server requests. The client only ASKS; the server
	           decides hits, damage, blocks and parries.

	Controls (keyboard & mouse)
	  Left click       light attack
	  R                heavy attack
	  Right mouse hold block (raise it just before a hit lands to parry)
	  1 / 2 / 3 / 4    equip loadout slot
	  5                toggle buckler (one-handed weapons and fists only)
	Attack direction comes from the mouse movement just before clicking:
	  move left = swing from the right, move right = swing from the left,
	  move up = overhead, move down = thrust, no movement = weapon default.
	Gamepad: R2 light, R1 heavy, L2 block, D-pad left/right cycles weapons.

	The local swing animation plays immediately (prediction); the server's
	AttackStarted broadcast animates everyone else.
	Depends  : Net, WeaponDefinitions, StatMath, CameraController,
	           AnimationController, HUDController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponDefinitions = require(Shared.Config.WeaponDefinitions)
local Net = require(Shared.Modules.Net)
local StatMath = require(Shared.Modules.StatMath)

local player = Players.LocalPlayer

local CombatController = {}

local controllers = nil
local blockHeld = false
local localBusyUntil = 0
local latestStats = nil
local currentSlot = 1

local SLOT_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
}
local DIRECTION_THRESHOLD = 6 -- pixels of mouse travel to count as a directional swing

local function getCharacter()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character
end

local function pickDirection(weapon)
	local motion = controllers.Camera.getRecentMotion(0.2)
	local ax, ay = math.abs(motion.X), math.abs(motion.Y)
	if math.max(ax, ay) < DIRECTION_THRESHOLD then
		return weapon.defaultDirection
	end
	if ax > ay then
		return if motion.X > 0 then "Left" else "Right"
	end
	return if motion.Y < 0 then "Overhead" else "Thrust"
end

local function attack(kind)
	local character = getCharacter()
	if not character then
		return
	end
	local state = character:GetAttribute("CombatState")
	if state ~= "Idle" and state ~= "Blocking" then
		return
	end
	if os.clock() < localBusyUntil then
		return
	end

	local weapon = WeaponDefinitions.get(character:GetAttribute("WeaponId")) or WeaponDefinitions.Items.Fists
	local spec = WeaponDefinitions.getAttack(weapon, kind)
	if not spec then
		return
	end
	if (character:GetAttribute("Stamina") or 0) < spec.staminaCost * 0.5 then
		return
	end
	if kind == "Heavy" and character:GetAttribute("Winded") then
		return
	end

	local speed = StatMath.attackSpeedMultiplier(latestStats, weapon)
	local windup, recovery = spec.windup * speed, spec.recovery * speed
	local direction = pickDirection(weapon)
	localBusyUntil = os.clock() + (windup + recovery) * 0.9

	Net.fireServer("RequestAttack", kind, direction)
	controllers.Animation.playAttack(character, kind, direction, windup, recovery)
end

local function setBlock(on)
	blockHeld = on
	Net.fireServer("SetBlocking", on)
end

local function equipSlot(slot)
	currentSlot = slot
	Net.fireServer("EquipSlot", slot)
end

local function aimingAllowed(input)
	-- Mouse-driven combat only while the cursor is locked (not in menus).
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 then
		return controllers.Camera.isCursorLocked()
	end
	return true
end

function CombatController.init(allControllers)
	controllers = allControllers

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not aimingAllowed(input) then
			return
		end
		local key = input.KeyCode
		if input.UserInputType == Enum.UserInputType.MouseButton1 or key == Enum.KeyCode.ButtonR2 then
			attack("Light")
		elseif key == Enum.KeyCode.R or key == Enum.KeyCode.ButtonR1 then
			attack("Heavy")
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 or key == Enum.KeyCode.ButtonL2 then
			setBlock(true)
		elseif SLOT_KEYS[key] then
			equipSlot(SLOT_KEYS[key])
		elseif key == Enum.KeyCode.Five then
			Net.fireServer("ToggleOffhand")
		elseif key == Enum.KeyCode.DPadRight then
			equipSlot(currentSlot % #WeaponDefinitions.StarterLoadout + 1)
		elseif key == Enum.KeyCode.DPadLeft then
			equipSlot((currentSlot - 2) % #WeaponDefinitions.StarterLoadout + 1)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
			if blockHeld then
				setBlock(false)
			end
		end
	end)

	Net.on("AttackStarted", function(model, _weaponId, kind, direction, windup, recovery)
		if typeof(model) ~= "Instance" or model == player.Character then
			return -- own swing was already predicted locally
		end
		controllers.Animation.playAttack(model, kind, direction, windup, recovery)
	end)

	Net.on("CombatFeedback", function(info)
		controllers.HUD.showCombatFeedback(info)
		if info.victim and (info.result == "Hit" or info.result == "GuardBreak") then
			controllers.Camera.shake(if info.result == "GuardBreak" then 0.06 else 0.035, 0.25)
		end
	end)

	Net.on("StatsUpdated", function(stats)
		latestStats = stats
		controllers.HUD.setStats(stats)
	end)
end

function CombatController.onCharacterAdded(character)
	localBusyUntil = 0
	-- Keep holding block across attacks: when we return to Idle with the button
	-- still held, ask the server to raise the guard again.
	character:GetAttributeChangedSignal("CombatState"):Connect(function()
		if blockHeld and character:GetAttribute("CombatState") == "Idle" then
			Net.fireServer("SetBlocking", true)
		end
	end)
	local weaponId = character:GetAttribute("WeaponId")
	local slot = weaponId and table.find(WeaponDefinitions.StarterLoadout, weaponId)
	if slot then
		currentSlot = slot
	end
end

return CombatController
