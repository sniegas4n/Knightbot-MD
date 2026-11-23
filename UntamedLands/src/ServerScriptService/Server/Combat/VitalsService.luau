--!nonstrict
--[[
	VitalsService
	Location : ServerScriptService/Server/Combat/VitalsService (ModuleScript)
	Purpose  : ONE loop (10 Hz) for every combatant - no per-character loops.
	           - Stamina drain (sprinting) and regeneration
	           - Winded state when stamina runs out
	           - Server-owned WalkSpeed and JumpHeight (the client never decides
	             its own speed; see Known Issues for client-side speed exploits)
	           - Jump stamina cost (Humanoid.StateChanged)
	           - Converts stamina use / sprinting into Endurance / Athletics XP
	Milestone 2 extends this service with hunger, thirst, fatigue and bleeding.
	Depends  : CombatantRegistry, StatService, StatMath, GameConfig
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local StatMath = require(Shared.Modules.StatMath)

local Server = script.Parent.Parent
local Registry = require(script.Parent.CombatantRegistry)
local StatService = require(Server.Progression.StatService)

local TICK = 0.1
local MOVE = GameConfig.Movement
local STAMINA = GameConfig.Stamina

local VitalsService = {}

local stateSpeedMultiplier = {
	Blocking = MOVE.BlockingSpeedMultiplier,
	Attacking = MOVE.AttackingSpeedMultiplier,
	Recovering = MOVE.RecoveringSpeedMultiplier,
	Staggered = MOVE.StaggeredSpeedMultiplier,
}

local function onRegistered(c)
	c.Humanoid.UseJumpPower = false
	c.Humanoid.JumpHeight = MOVE.JumpHeight
	c.Humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Jumping then
			c:spendStamina(STAMINA.JumpCost, true)
			StatService.addExperience(c, "Athletics", 0.15)
		end
	end)
end

local function tickCombatant(c, dt, now)
	if not c:isAlive() then
		return
	end
	c:refreshMaxStamina()

	local velocity = c.Root.AssemblyLinearVelocity
	local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 3
	local sprinting = c.Sprinting and not c.Winded and moving and c.State == "Idle" and c.Stamina > 0

	if sprinting then
		c:spendStamina(STAMINA.SprintDrainPerSecond * dt, true)
		StatService.addExperience(c, "Athletics", 0.5 * dt)
	elseif now - c.LastStaminaUse >= STAMINA.RegenDelay and c.State ~= "Blocking" and c.State ~= "Attacking" then
		c:setStamina(c.Stamina + StatMath.staminaRegen(c.Stats) * dt)
	end

	if c.Stamina <= 0.5 then
		c.Winded = true
	elseif c.Winded and c.Stamina >= c.MaxStamina * STAMINA.WindedRecoverFraction then
		c.Winded = false
	end

	-- Slow recovery while out of combat (players only; replaced in Milestone 2).
	local humanoid = c.Humanoid
	if c.Player and humanoid.Health < humanoid.MaxHealth and now - c.LastDamagedAt >= GameConfig.Player.NaturalRegenDelay then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + GameConfig.Player.NaturalRegenPerSecond * dt)
	end

	-- Endurance improves with stamina actually spent.
	if c.StaminaSpentAccum >= 10 then
		StatService.addExperience(c, "Endurance", c.StaminaSpentAccum * 0.02)
		c.StaminaSpentAccum = 0
	end

	if not c.Immobile then
		local speed = if sprinting then StatMath.runSpeed(c.Stats) else StatMath.walkSpeed(c.Stats)
		speed *= stateSpeedMultiplier[c.State] or 1
		if c.Winded then
			speed *= 0.85
		end
		speed = math.floor(speed * 10 + 0.5) / 10
		if c.Humanoid.WalkSpeed ~= speed then
			c.Humanoid.WalkSpeed = speed
		end

		local canJump = c.Stamina >= STAMINA.JumpCost and (c.State == "Idle" or c.State == "Blocking")
		local jumpHeight = if canJump then MOVE.JumpHeight else 0
		if c.Humanoid.JumpHeight ~= jumpHeight then
			c.Humanoid.JumpHeight = jumpHeight
		end
	end

	c:flushAttributes(false)
end

function VitalsService.init()
	Registry.Registered:Connect(onRegistered)
end

function VitalsService.start()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < TICK then
			return
		end
		local step = accumulator
		accumulator = 0
		local now = os.clock()
		for _, c in pairs(Registry.all()) do
			local ok, err = pcall(tickCombatant, c, step, now)
			if not ok then
				warn("[Vitals] tick error: " .. tostring(err))
			end
		end
	end)
end

return VitalsService
