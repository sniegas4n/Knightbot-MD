--!nonstrict
--[[
	MovementController
	Location : StarterPlayer/StarterPlayerScripts/Client/Controllers/MovementController
	Purpose  : Sprint and dodge input.
	           Walking/jumping use Roblox's default control scripts; the SERVER
	           sets WalkSpeed and JumpHeight from stamina, stats and combat state.
	           Sprint: hold Left Shift (gamepad: click left stick to toggle).
	           Dodge : Q (gamepad: B) - direction comes from movement keys,
	                   backwards if standing still. The dodge burst is applied
	                   locally right away (the client owns its character's
	                   physics); the server validates stamina/cooldown and grants
	                   the invulnerability frames.
	Depends  : Net, DodgeMotion, GameConfig
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Modules.Net)
local DodgeMotion = require(Shared.Modules.DodgeMotion)

local player = Players.LocalPlayer
local MOVE = GameConfig.Movement

local MovementController = {}

local sprinting = false
local nextDodge = 0

local function setSprinting(on)
	if sprinting == on then
		return
	end
	sprinting = on
	Net.fireServer("SetSprinting", on)
end

local function tryDodge()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	if now < nextDodge then
		return
	end
	if (character:GetAttribute("Stamina") or 0) < GameConfig.Stamina.DodgeCost then
		return
	end
	local state = character:GetAttribute("CombatState")
	if state ~= "Idle" and state ~= "Blocking" then
		return
	end

	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = -root.CFrame.LookVector
	end
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.1 then
		return
	end
	direction = direction.Unit

	-- Slightly shorter than the server cooldown; the server has the final word.
	nextDodge = now + MOVE.DodgeCooldown * 0.6
	Net.fireServer("RequestDodge", direction)
	DodgeMotion.apply(root, direction, MOVE.DodgeSpeed, MOVE.DodgeDuration)
end

function MovementController.init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift then
			setSprinting(true)
		elseif input.KeyCode == Enum.KeyCode.ButtonL3 then
			setSprinting(not sprinting)
		elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonB then
			tryDodge()
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift then
			setSprinting(false)
		end
	end)
end

function MovementController.onCharacterAdded()
	-- The server creates a fresh Combatant (Sprinting = false) on every spawn.
	if sprinting then
		sprinting = false
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			setSprinting(true)
		end
	end
end

return MovementController
