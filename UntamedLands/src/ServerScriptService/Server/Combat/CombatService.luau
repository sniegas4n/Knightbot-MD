--!nonstrict
--[[
	CombatService
	Location : ServerScriptService/Server/Combat/CombatService (ModuleScript)
	Purpose  : Authoritative melee combat for players AND NPCs.

	Flow of an attack
	  1. Client presses attack -> plays a predicted swing locally and sends
	     RequestAttack(kind, direction). The client sends NOTHING about targets
	     or damage.
	  2. Server validates (alive, state, stamina), spends stamina, enters
	     "Attacking" and tells nearby clients (AttackStarted) to animate it.
	  3. After the weapon's windup, the server sweeps a box in front of the
	     attacker (GetPartBoundsInBox) and resolves each target:
	       dodge i-frames -> "Dodged"
	       block raised within ParryWindow -> "Parried" (attacker staggered,
	         defender gets a counter window)
	       block facing the attacker -> "Blocked" (reduced damage, stamina
	         drain; 0 stamina -> "GuardBreak")
	       otherwise -> "Hit" (heavy attacks stagger)
	     Armor then reduces the final damage.
	  4. Attacker enters "Recovering" (cannot act) then returns to Idle.
	A stagger/parry during the windup changes the attacker's StateToken, which
	cancels step 3 - interrupts are real, not cosmetic.

	Depends  : Combatant, CombatantRegistry, StatService, WorldGenService,
	           PlayerDataService, Net, Validate, WeaponDefinitions, StatMath,
	           WeaponModelBuilder, DodgeMotion, GameConfig
	Public   : init(), start(), attack(c, kind, direction), setBlocking(c, on),
	           dodge(c, direction), equip(c, weaponId), setOffhand(c, id|nil)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local WeaponDefinitions = require(Shared.Config.WeaponDefinitions)
local Net = require(Shared.Modules.Net)
local Validate = require(Shared.Modules.Validate)
local StatMath = require(Shared.Modules.StatMath)
local WeaponModelBuilder = require(Shared.Modules.WeaponModelBuilder)
local DodgeMotion = require(Shared.Modules.DodgeMotion)

local Server = script.Parent.Parent
local Registry = require(script.Parent.CombatantRegistry)
local StatService = require(Server.Progression.StatService)
local WorldGenService = require(Server.WorldGeneration.WorldGenService)
local PlayerDataService = require(Server.PlayerData.PlayerDataService)

local COMBAT = GameConfig.Combat
local MOVE = GameConfig.Movement

local CombatService = {}
local rng = Random.new()

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function sendFeedback(attacker, target, result, damage)
	local payload = {
		result = result,
		attacker = attacker.Model,
		target = target.Model,
		damage = math.floor((damage or 0) + 0.5),
		position = target.Root.Position,
	}
	if attacker.Player then
		Net.fireClient("CombatFeedback", attacker.Player, payload)
	end
	if target.Player then
		local victimPayload = table.clone(payload)
		victimPayload.victim = true
		Net.fireClient("CombatFeedback", target.Player, victimPayload)
	end
end

local function isFacing(defender, attacker)
	local offset = attacker.Root.Position - defender.Root.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude < 0.05 then
		return true
	end
	local look = defender.Root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.05 then
		return true
	end
	return flatLook.Unit:Dot(flat.Unit) >= COMBAT.BlockFacingDot
end

-- Faction / PvP rules. Milestone 5 replaces the NPC branch with FactionService.
local function canDamage(attacker, target)
	if attacker == target then
		return false
	end
	if attacker.Player and target.Player then
		if not COMBAT.PvPEnabled then
			return false
		end
		if WorldGenService.isInSafeZone(attacker.Root.Position) or WorldGenService.isInSafeZone(target.Root.Position) then
			return false, "SafeZone"
		end
		return true
	end
	if attacker.IsNPC and target.IsNPC then
		return attacker.Faction ~= target.Faction and attacker.Faction ~= "Neutral" and target.Faction ~= "Neutral"
	end
	return true
end

local function updateEquippedVisuals(c)
	local weapon = c:getWeapon()
	WeaponModelBuilder.attach(c.Model, weapon, "MainHand")
	WeaponModelBuilder.attach(c.Model, c:getOffhand(), "OffHand")
	c:flushAttributes(true)
end

---------------------------------------------------------------------------
-- Damage resolution
---------------------------------------------------------------------------
local function onKilled(attacker, target)
	local weapon = attacker:getWeapon()
	StatService.addExperience(attacker, weapon.skill, 6)
	if attacker.Player then
		Net.fireClient("Notify", attacker.Player, ("%s falls."):format(target.Humanoid.DisplayName))
	end
end

local function applyHit(attacker, target, weapon, attack, kind, direction)
	local now = os.clock()

	if now < target.InvulnerableUntil then
		StatService.addExperience(target, "Agility", 1.5)
		sendFeedback(attacker, target, "Dodged", 0)
		return
	end

	local damage = attack.damage
		* StatMath.damageMultiplier(attacker.Stats, weapon)
		* (weapon.directionalBonus[direction] or 1)
	if now < attacker.CounterUntil then
		damage *= COMBAT.CounterDamageMultiplier
		attacker.CounterUntil = 0
	end
	damage *= 1 + rng:NextNumber(-COMBAT.DamageVariance, COMBAT.DamageVariance)

	local result = "Hit"
	if target.State == "Blocking" and isFacing(target, attacker) then
		local raisedFor = now - target.BlockStart
		if target.BlockStart > 0 and raisedFor <= COMBAT.ParryWindow then
			attacker:setState("Staggered", COMBAT.ParryStaggerTime)
			target.CounterUntil = now + COMBAT.CounterWindow
			StatService.addExperience(target, "Defense", 3)
			sendFeedback(attacker, target, "Parried", 0)
			return
		end

		local reduction = target:blockReduction()
		if kind == "Heavy" then
			reduction *= 0.75 -- heavy blows partly break through a guard
		end
		target:spendStamina(target:blockStaminaCost() * (attack.guardDamage or 1), true)
		StatService.addExperience(target, "Defense", 1)
		if target.Stamina <= 0 then
			target:setState("Staggered", COMBAT.GuardBreakStaggerTime)
			damage *= 0.75
			result = "GuardBreak"
		else
			damage *= 1 - reduction
			result = "Blocked"
		end
	end

	damage *= 1 - math.clamp(target.Armor, 0, 0.8)
	damage = math.max(0, damage)

	target.LastDamagedAt = now
	target.LastAttacker = attacker
	target.Humanoid:TakeDamage(damage)

	if result == "Hit" and attack.stagger and target:isAlive() then
		target:setState("Staggered", COMBAT.HeavyHitStaggerTime)
	end

	StatService.addExperience(attacker, weapon.skill, if result == "Hit" then 2 else 1)
	if kind == "Heavy" then
		StatService.addExperience(attacker, "Strength", 0.6)
	end
	if result == "Hit" then
		StatService.addExperience(target, "Endurance", 0.4)
	end

	sendFeedback(attacker, target, result, damage)

	if target.Humanoid.Health <= 0 then
		onKilled(attacker, target)
	end
end

local function resolveSwing(c, weapon, attack, kind, direction)
	local root = c.Root
	local reach = weapon.reach
	local width = weapon.arcWidth
	local lateral = 0
	if direction == "Left" then
		lateral = -width * 0.15
	elseif direction == "Right" then
		lateral = width * 0.15
	end

	local boxCFrame = root.CFrame * CFrame.new(lateral, 0, -reach / 2)
	local boxSize = Vector3.new(width, 7, reach)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { c.Model }

	local seen, targets = {}, {}
	for _, part in ipairs(workspace:GetPartBoundsInBox(boxCFrame, boxSize, params)) do
		local target = Registry.fromPart(part)
		if target and not seen[target] and target:isAlive() then
			seen[target] = true
			table.insert(targets, target)
		end
	end

	table.sort(targets, function(a, b)
		return (a.Root.Position - root.Position).Magnitude < (b.Root.Position - root.Position).Magnitude
	end)

	local hits = 0
	for _, target in ipairs(targets) do
		if hits >= weapon.maxTargets then
			break
		end
		local distance = (target.Root.Position - root.Position).Magnitude
		if distance <= reach + COMBAT.ReachTolerance + 2 then
			local allowed, reason = canDamage(c, target)
			if allowed then
				hits += 1
				applyHit(c, target, weapon, attack, kind, direction)
			elseif reason == "SafeZone" and c.Player then
				Net.fireClient("Notify", c.Player, "The waystone's peace holds here. No bloodshed.")
			end
		end
	end
end

---------------------------------------------------------------------------
-- Public actions (used by remotes and by NPC AI)
---------------------------------------------------------------------------
function CombatService.attack(c, kind, direction)
	if not c:isAlive() then
		return false
	end
	if c.State ~= "Idle" and c.State ~= "Blocking" then
		return false
	end
	local weapon = c:getWeapon()
	local attack = WeaponDefinitions.getAttack(weapon, kind)
	if not attack then
		return false
	end
	if kind == "Heavy" and c.Winded then
		return false
	end
	-- You may start an attack with half the cost; it drains you to zero.
	if c.Stamina < attack.staminaCost * 0.5 then
		return false
	end
	if not WeaponDefinitions.Directions[direction] then
		direction = weapon.defaultDirection
	end

	c:spendStamina(attack.staminaCost, true)
	local speed = StatMath.attackSpeedMultiplier(c.Stats, weapon)
	local windup = attack.windup * speed
	local recovery = attack.recovery * speed

	local token = c:setState("Attacking")
	Net.fireNearby("AttackStarted", c.Root.Position, COMBAT.AttackBroadcastRadius, c.Model, weapon.id, kind, direction, windup, recovery)

	task.delay(windup, function()
		if c.StateToken ~= token or not c:isAlive() then
			return -- interrupted (staggered, parried, died...)
		end
		resolveSwing(c, weapon, attack, kind, direction)
		if c.StateToken == token then
			c:setState("Recovering", recovery)
		end
	end)
	return true
end

function CombatService.setBlocking(c, on)
	if not c:isAlive() then
		return
	end
	local now = os.clock()
	if on then
		if c.State == "Idle" then
			c:setState("Blocking")
			-- Spamming block to fish for parries grants no parry window.
			if now - c.LastBlockEnd < COMBAT.BlockReraiseLockout then
				c.BlockStart = 0
			else
				c.BlockStart = now
			end
		end
	elseif c.State == "Blocking" then
		c:setState("Idle")
	end
end

function CombatService.dodge(c, direction)
	if not c:isAlive() then
		return false
	end
	if c.State ~= "Idle" and c.State ~= "Blocking" then
		return false
	end
	local now = os.clock()
	if now < c.NextDodgeTime then
		return false
	end
	if not c:spendStamina(GameConfig.Stamina.DodgeCost, false) then
		return false
	end

	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.1 then
		flat = -c.Root.CFrame.LookVector
	end
	flat = Vector3.new(flat.X, 0, flat.Z).Unit

	c.NextDodgeTime = now + StatMath.dodgeCooldown(c.Stats)
	c.InvulnerableUntil = now + MOVE.DodgeInvulnerability
	c:setState("Dodging", MOVE.DodgeDuration + 0.1)
	StatService.addExperience(c, "Agility", 0.5)

	-- Players move themselves (they own their physics); the server moves NPCs.
	if c.IsNPC then
		DodgeMotion.apply(c.Root, flat, MOVE.DodgeSpeed, MOVE.DodgeDuration)
	end
	return true
end

function CombatService.equip(c, weaponId)
	local weapon = WeaponDefinitions.get(weaponId)
	if not weapon or weapon.isOffhand or not c:isAlive() then
		return false
	end
	if c.State ~= "Idle" then
		return false
	end
	c.WeaponId = weaponId
	updateEquippedVisuals(c)
	return true
end

function CombatService.setOffhand(c, offhandId)
	if offhandId ~= nil then
		local def = WeaponDefinitions.get(offhandId)
		if not def or not def.isOffhand then
			return false
		end
	end
	c.OffhandId = offhandId
	updateEquippedVisuals(c)
	return true
end

-- Called once when a combatant spawns, bypassing the Idle check.
function CombatService.initializeLoadout(c, weaponId, offhandId)
	if WeaponDefinitions.get(weaponId) and not WeaponDefinitions.get(weaponId).isOffhand then
		c.WeaponId = weaponId
	end
	if offhandId and WeaponDefinitions.get(offhandId) then
		c.OffhandId = offhandId
	end
	updateEquippedVisuals(c)
end

---------------------------------------------------------------------------
-- Remote handlers
---------------------------------------------------------------------------
function CombatService.init()
	Net.connect("RequestAttack", function(player, kind, direction)
		if not Validate.isKeyOf(kind, WeaponDefinitions.AttackKinds) then
			return
		end
		if direction ~= nil and not Validate.isKeyOf(direction, WeaponDefinitions.Directions) then
			direction = nil
		end
		local c = Registry.forPlayer(player)
		if c then
			CombatService.attack(c, kind, direction)
		end
	end)

	Net.connect("SetBlocking", function(player, on)
		if not Validate.isBoolean(on) then
			return
		end
		local c = Registry.forPlayer(player)
		if c then
			CombatService.setBlocking(c, on)
		end
	end)

	Net.connect("RequestDodge", function(player, direction)
		if not Validate.isVector3(direction, 2) then
			return
		end
		local c = Registry.forPlayer(player)
		if c then
			CombatService.dodge(c, direction)
		end
	end)

	Net.connect("SetSprinting", function(player, on)
		if not Validate.isBoolean(on) then
			return
		end
		local c = Registry.forPlayer(player)
		if c then
			c.Sprinting = on
		end
	end)

	Net.connect("EquipSlot", function(player, slot)
		if not Validate.isInteger(slot, 1, 9) then
			return
		end
		local c = Registry.forPlayer(player)
		local data = PlayerDataService.getData(player)
		if not c or not data then
			return
		end
		local weaponId = data.loadout.owned[slot]
		if weaponId and CombatService.equip(c, weaponId) then
			data.loadout.equipped = weaponId
		end
	end)

	Net.connect("ToggleOffhand", function(player)
		local c = Registry.forPlayer(player)
		local data = PlayerDataService.getData(player)
		if not c or not data or c.State ~= "Idle" then
			return
		end
		local owned = data.loadout.offhandOwned
		if not WeaponDefinitions.get(owned) then
			return
		end
		local newOffhand = if c.OffhandId then nil else owned
		if CombatService.setOffhand(c, newOffhand) then
			data.loadout.offhand = newOffhand or ""
			if newOffhand and c:getWeapon().hands > 1 then
				Net.fireClient("Notify", player, "Your weapon needs both hands; the buckler stays on your back.")
			end
		end
	end)
end

function CombatService.start() end

return CombatService
