--!nonstrict
--[[
	Combatant
	Location : ServerScriptService/Server/Combat/Combatant (ModuleScript)
	Purpose  : Server-side combat state for ONE character - player or NPC.
	           The same class is used for both, so every combat rule applies
	           identically to everyone.

	States: Idle, Attacking, Recovering, Blocking, Dodging, Staggered, Dead
	Every state change increments StateToken. Delayed callbacks (attack windups,
	timed states) capture the token and abort if it changed - that is how a
	parry or stagger interrupts an attack in progress.

	Replicated through Attributes on the character model (read by clients):
	  Stamina, MaxStamina, CombatState, WeaponId, OffhandId, Winded
	Depends  : StatDefinitions, StatMath, WeaponDefinitions
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local StatDefinitions = require(Shared.Config.StatDefinitions)
local WeaponDefinitions = require(Shared.Config.WeaponDefinitions)
local StatMath = require(Shared.Modules.StatMath)

local Combatant = {}
Combatant.__index = Combatant

function Combatant.new(model, humanoid, options)
	options = options or {}
	local self = setmetatable({}, Combatant)

	self.Model = model
	self.Humanoid = humanoid
	self.Root = model:FindFirstChild("HumanoidRootPart")
	self.Player = options.player
	self.IsNPC = options.player == nil
	self.Stats = options.stats or StatDefinitions.defaultStats()
	self.Armor = options.armor or 0 -- 0..0.8 fraction (Milestone 4 replaces with equipment)
	self.Immobile = options.immobile == true
	self.Faction = options.faction or (if options.player then "Player" else "Neutral")

	self.WeaponId = if WeaponDefinitions.get(options.weaponId) then options.weaponId else "Fists"
	self.OffhandId = nil

	self.State = "Idle"
	self.StateToken = 0

	self.MaxStamina = StatMath.maxStamina(self.Stats)
	self.Stamina = self.MaxStamina
	self.LastStaminaUse = 0
	self.StaminaSpentAccum = 0 -- converted into Endurance experience by VitalsService
	self.Winded = false
	self.Sprinting = false

	self.BlockStart = 0
	self.LastBlockEnd = 0
	self.InvulnerableUntil = 0
	self.CounterUntil = 0
	self.NextDodgeTime = 0
	self.LastDamagedAt = 0
	self.LastAttacker = nil

	self._attr = {}
	self:flushAttributes(true)
	model:SetAttribute("CombatState", "Idle")
	return self
end

function Combatant:isAlive()
	return self.State ~= "Dead"
		and self.Humanoid.Parent ~= nil
		and self.Humanoid.Health > 0
		and self.Root ~= nil
		and self.Root.Parent ~= nil
end

-- duration (optional): automatically return to Idle afterwards unless the state
-- was changed again in the meantime.
function Combatant:setState(state, duration)
	if self.State == "Dead" then
		return self.StateToken
	end
	if self.State == "Blocking" and state ~= "Blocking" then
		self.LastBlockEnd = os.clock()
	end
	self.StateToken += 1
	local token = self.StateToken
	self.State = state
	self.Model:SetAttribute("CombatState", state)

	if duration then
		task.delay(duration, function()
			if self.StateToken == token and self.State == state then
				self:setState("Idle")
			end
		end)
	end
	return token
end

function Combatant:setStamina(value)
	self.Stamina = math.clamp(value, 0, self.MaxStamina)
end

-- Spends stamina. Returns false (and spends nothing) if there isn't enough,
-- unless allowPartial is true, in which case it drains to zero.
function Combatant:spendStamina(amount, allowPartial)
	if amount <= 0 then
		return true
	end
	if self.Stamina < amount and not allowPartial then
		return false
	end
	local spent = math.min(self.Stamina, amount)
	self.Stamina -= spent
	self.StaminaSpentAccum += spent
	self.LastStaminaUse = os.clock()
	return true
end

function Combatant:refreshMaxStamina()
	local newMax = StatMath.maxStamina(self.Stats)
	if newMax ~= self.MaxStamina then
		self.MaxStamina = newMax
		self.Stamina = math.min(self.Stamina, newMax)
	end
end

function Combatant:getWeapon()
	return WeaponDefinitions.get(self.WeaponId) or WeaponDefinitions.Items.Fists
end

-- Returns the offhand definition only if the main weapon leaves a hand free.
function Combatant:getOffhand()
	if not self.OffhandId then
		return nil
	end
	local weapon = self:getWeapon()
	if weapon.hands > 1 then
		return nil
	end
	return WeaponDefinitions.get(self.OffhandId)
end

function Combatant:blockReduction()
	local offhand = self:getOffhand()
	if offhand then
		return offhand.blockReduction
	end
	return self:getWeapon().blockReduction
end

function Combatant:blockStaminaCost()
	local cost = self:getWeapon().blockStaminaCost or 12
	local offhand = self:getOffhand()
	if offhand then
		cost *= offhand.blockStaminaMultiplier or 1
	end
	return cost
end

local function setAttr(self, name, value, force)
	if force or self._attr[name] ~= value then
		self._attr[name] = value
		self.Model:SetAttribute(name, value)
	end
end

-- Pushes replicated values. Stamina is rounded so tiny regen steps don't
-- generate network traffic every tick.
function Combatant:flushAttributes(force)
	setAttr(self, "Stamina", math.floor(self.Stamina + 0.5), force)
	setAttr(self, "MaxStamina", math.floor(self.MaxStamina + 0.5), force)
	setAttr(self, "WeaponId", self.WeaponId, force)
	setAttr(self, "OffhandId", if self:getOffhand() then self.OffhandId else "", force)
	setAttr(self, "Winded", self.Winded, force)
end

return Combatant
