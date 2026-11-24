--!nonstrict
--[[
	NPCService
	Location : ServerScriptService/Server/NPCs/NPCService (ModuleScript)
	Purpose  : Milestone 1 NPCs that prove the combat engine works for non-players:
	           - SparringDummy : stands still, regenerates, never fights back
	           - DustRaider    : chases, blocks, attacks and returns home
	           NPCs are ordinary Combatants and use exactly the same
	           CombatService.attack / setBlocking calls as players.

	Performance: ONE scheduler loop thinks for all NPCs every ThinkInterval.
	NPCs with no player within ActiveRange go dormant (skip thinking). This is
	simulation "level of detail" step one; Milestone 5 adds abstract background
	simulation for NPCs far from every player.
	Depends  : Combatant, CombatantRegistry, CombatService, WorldGenService,
	           AppearanceService, NPCAnimator, NPCDefinitions, GameConfig
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local NPCDefinitions = require(Shared.Config.NPCDefinitions)
local StatDefinitions = require(Shared.Config.StatDefinitions)

local Server = script.Parent.Parent
local Combatant = require(Server.Combat.Combatant)
local Registry = require(Server.Combat.CombatantRegistry)
local CombatService = require(Server.Combat.CombatService)
local WorldGenService = require(Server.WorldGeneration.WorldGenService)
local AppearanceService = require(Server.Core.AppearanceService)
local NPCAnimator = require(script.Parent.NPCAnimator)

local CONFIG = GameConfig.NPC
local DIRECTIONS = { "Left", "Right", "Overhead", "Thrust" }

local NPCService = {}

local npcs = {} -- array of active NPC records
local rng = Random.new()
local npcFolder = nil

---------------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------------
local function buildStats(template)
	local stats = StatDefinitions.defaultStats()
	for id, value in pairs(template.stats or {}) do
		if StatDefinitions.Info[id] then
			stats[id] = value
		end
	end
	return stats
end

local function spawnNPC(spawnPoint)
	local template = NPCDefinitions.Templates[spawnPoint.template]
	if not template then
		warn("[NPC] Unknown template " .. tostring(spawnPoint.template))
		return
	end

	local description = AppearanceService.buildNPCDescription(template.appearance)
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[NPC] Failed to build rig: " .. tostring(model))
		return
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy() -- remove client Animate scripts; NPCAnimator handles movement
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		model:Destroy()
		return
	end

	model.Name = template.displayName
	humanoid.DisplayName = template.displayName
	humanoid.MaxHealth = template.maxHealth
	humanoid.Health = template.maxHealth

	local spawnCentre = WorldGenService.getSpawnPosition()
	local x, z = spawnCentre.X + spawnPoint.offset.X, spawnCentre.Z + spawnPoint.offset.Z
	local ground = WorldGenService.getSurfaceHeight(x, z)
	local home = Vector3.new(x, ground, z)
	local hipOffset = humanoid.HipHeight + root.Size.Y / 2
	local homeCFrame = CFrame.new(home + Vector3.new(0, hipOffset + 0.5, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	model:PivotTo(homeCFrame)

	-- Dummies are NOT anchored: an anchored root breaks the joints of
	-- upgraded (AnimationConstraint) rigs on clients. Instead they cannot walk
	-- or jump, and thinkDummy() puts them back if they get shoved away.
	local immobile = template.behavior == "Dummy"
	if immobile then
		humanoid.WalkSpeed = 0
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = 0
	end
	model.Parent = npcFolder
	pcall(function()
		root:SetNetworkOwner(nil) -- the server simulates NPC physics, never a player
	end)

	local c = Combatant.new(model, humanoid, {
		stats = buildStats(template),
		armor = template.armor,
		immobile = immobile,
		faction = template.faction,
		weaponId = template.weapon,
	})
	Registry.register(c)
	CombatService.initializeLoadout(c, template.weapon, nil)

	local record = {
		template = template,
		spawnPoint = spawnPoint,
		model = model,
		humanoid = humanoid,
		root = root,
		combatant = c,
		home = home,
		homeCFrame = homeCFrame,
		animator = NPCAnimator.new(humanoid),
		nextAttack = 0,
		blockUntil = 0,
		reactedToken = setmetatable({}, { __mode = "k" }), -- weak: forgets despawned targets
		dead = false,
	}
	table.insert(npcs, record)

	humanoid.Died:Connect(function()
		record.dead = true
		c:setState("Dead")
		record.animator:stopAll()
		Registry.unregister(model)
		task.delay(CONFIG.CorpseLifetime, function()
			if model.Parent then
				model:Destroy()
			end
		end)
		task.delay(template.respawnTime or 30, function()
			local index = table.find(npcs, record)
			if index then
				table.remove(npcs, index)
			end
			spawnNPC(spawnPoint)
		end)
	end)
end

---------------------------------------------------------------------------
-- Brains
---------------------------------------------------------------------------
local function nearestPlayerCombatant(position, range)
	local best, bestDistance = nil, range
	for _, player in ipairs(Players:GetPlayers()) do
		local c = Registry.forPlayer(player)
		if c and c:isAlive() then
			local distance = (c.Root.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = c, distance
			end
		end
	end
	return best, bestDistance
end

local function thinkDummy(npc, now)
	local c = npc.combatant
	local humanoid = npc.humanoid
	-- Tether: if players shove the dummy more than 3 studs, put it back.
	if (npc.root.Position - npc.homeCFrame.Position).Magnitude > 3 then
		npc.model:PivotTo(npc.homeCFrame)
		npc.root.AssemblyLinearVelocity = Vector3.zero
	end
	if humanoid.Health < humanoid.MaxHealth and now - c.LastDamagedAt > (npc.template.regenDelay or 4) then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * 0.25)
	end
end

local function thinkRaider(npc, now, dt)
	local c = npc.combatant
	local template = npc.template
	local root = npc.root
	local humanoid = npc.humanoid

	local target = nil
	if (root.Position - npc.home).Magnitude < template.leashRange then
		target = nearestPlayerCombatant(root.Position, template.aggroRange)
	end

	if not target then
		c.Sprinting = false
		if c.State == "Blocking" then
			CombatService.setBlocking(c, false)
		end
		if (root.Position - npc.home).Magnitude > 6 then
			humanoid:MoveTo(npc.home)
		end
		if humanoid.Health < humanoid.MaxHealth then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 3 * dt)
		end
		return
	end

	local offset = target.Root.Position - root.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local distance = flat.Magnitude
	local weapon = c:getWeapon()
	local idealRange = weapon.reach * 0.7

	if distance > idealRange then
		c.Sprinting = distance > 18
		if c.State == "Blocking" then
			CombatService.setBlocking(c, false)
		end
		humanoid:MoveTo(target.Root.Position)
		return
	end

	-- In range: stop, face the target, fight.
	c.Sprinting = false
	humanoid:MoveTo(root.Position)
	if distance > 0.1 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
	end

	-- React once to each attack the target starts.
	local reacted = npc.reactedToken[target] == target.StateToken
	if target.State == "Attacking" and not reacted then
		npc.reactedToken[target] = target.StateToken
		if c.State == "Idle" and c.Stamina > 20 and rng:NextNumber() < template.blockChance then
			CombatService.setBlocking(c, true)
			npc.blockUntil = now + 0.8
			return
		end
	end

	if c.State == "Blocking" then
		if now >= npc.blockUntil then
			CombatService.setBlocking(c, false)
		end
		return
	end

	if c.State == "Idle" and now >= npc.nextAttack then
		local kind = if rng:NextNumber() < template.heavyChance and c.Stamina > 40 then "Heavy" else "Light"
		local direction = DIRECTIONS[rng:NextInteger(1, #DIRECTIONS)]
		if CombatService.attack(c, kind, direction) then
			npc.nextAttack = now + rng:NextNumber(0.6, 1.4) / template.aggression
		end
	end
end

local function playerPositions()
	local positions = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			table.insert(positions, root.Position)
		end
	end
	return positions
end

local function isNearAnyPlayer(position, positions)
	for _, p in ipairs(positions) do
		if (p - position).Magnitude <= CONFIG.ActiveRange then
			return true
		end
	end
	return false
end

local function step(dt)
	local now = os.clock()
	local positions = playerPositions()
	for _, npc in ipairs(npcs) do
		if not npc.dead and npc.combatant:isAlive() then
			local active = isNearAnyPlayer(npc.root.Position, positions)
			if active then
				local ok, err = pcall(function()
					if npc.template.behavior == "Raider" then
						thinkRaider(npc, now, dt)
					else
						thinkDummy(npc, now)
					end
				end)
				if not ok then
					warn("[NPC] think error: " .. tostring(err))
				end
			end
			local velocity = npc.root.AssemblyLinearVelocity
			npc.animator:update(Vector3.new(velocity.X, 0, velocity.Z).Magnitude)
		end
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function NPCService.init()
	npcFolder = workspace:WaitForChild("NPCs")
end

function NPCService.start()
	task.spawn(function()
		WorldGenService.waitForSpawnArea()
		for _, spawnPoint in ipairs(NPCDefinitions.SpawnPoints) do
			if NPCDefinitions.Templates[spawnPoint.template].behavior == "Dummy" then
				spawnNPC(spawnPoint)
			end
		end
		WorldGenService.waitForCompletion()
		for _, spawnPoint in ipairs(NPCDefinitions.SpawnPoints) do
			if NPCDefinitions.Templates[spawnPoint.template].behavior ~= "Dummy" then
				spawnNPC(spawnPoint)
			end
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= CONFIG.ThinkInterval then
			local stepDt = accumulator
			accumulator = 0
			step(stepDt)
		end
	end)
end

return NPCService
