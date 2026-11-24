--!nonstrict
--[[
	SelfTest
	Location : ServerScriptService/Server/Debug/SelfTest (ModuleScript)
	Purpose  : Automatic checks that run every time you press Play IN STUDIO
	           (never in live servers). Results appear in Output:
	               [SelfTest] PASS  Weapon definitions are valid
	               [SelfTest] FAIL  ... -> reason
	               [SelfTest] 15/15 checks passed
	           If anything FAILs, copy the FAIL lines and send them over.

	HOW A TEST WORKS (worth learning!)
	  test("name", function()
	      expect(somethingTrue, "message shown if it is false")
	  end)
	  - test() runs the function inside pcall, so one failing check can never
	    stop the others or break the game.
	  - expect() raises an error with your message when the condition is false.
	  Adding a new check = adding one more test(...) block.

	Turn off with GameConfig.Debug.RunSelfTests = false.
	Depends  : most services (read-only use, except the combat test which
	           creates two temporary dummies far above the map and removes them)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local WeaponDefinitions = require(Shared.Config.WeaponDefinitions)
local RaceDefinitions = require(Shared.Config.RaceDefinitions)
local AppearanceOptions = require(Shared.Config.AppearanceOptions)
local StatDefinitions = require(Shared.Config.StatDefinitions)
local NPCDefinitions = require(Shared.Config.NPCDefinitions)
local Net = require(Shared.Modules.Net)
local StatMath = require(Shared.Modules.StatMath)

local Server = script.Parent.Parent
local DataSchema = require(Server.PlayerData.DataSchema)
local TerrainGenerator = require(Server.WorldGeneration.TerrainGenerator)
local WorldGenService = require(Server.WorldGeneration.WorldGenService)
local AppearanceService = require(Server.Core.AppearanceService)
local Combatant = require(Server.Combat.Combatant)
local Registry = require(Server.Combat.CombatantRegistry)
local CombatService = require(Server.Combat.CombatService)

local SelfTest = {}

local passed, failed = 0, 0

local function expect(condition, message)
	if not condition then
		error(message, 0) -- level 0: show only our message, not a file/line
	end
end

local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("[SelfTest] PASS  " .. name)
	else
		failed += 1
		warn("[SelfTest] FAIL  " .. name .. " -> " .. tostring(err))
	end
end

-- Waits until check() returns true or the timeout passes. Returns the last result.
local function waitUntil(check, timeout)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		if check() then
			return true
		end
		task.wait(0.1)
	end
	return check()
end

---------------------------------------------------------------------------
-- 1. Data & configuration checks (fast, no world needed)
---------------------------------------------------------------------------
local function configTests()
	test("Every remote exists with the right type", function()
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		expect(folder, "ReplicatedStorage.Remotes is missing")
		for name, def in pairs(Net.Definitions) do
			local remote = folder:FindFirstChild(name)
			expect(remote, "missing remote " .. name)
			local className = if def.kind == "Function" then "RemoteFunction" else "RemoteEvent"
			expect(remote:IsA(className), name .. " should be a " .. className)
		end
	end)

	test("Weapon definitions are valid", function()
		for id, weapon in pairs(WeaponDefinitions.Items) do
			expect(weapon.id == id, id .. ": id field does not match its key")
			if weapon.isOffhand then
				expect(weapon.blockReduction > 0 and weapon.blockReduction < 1, id .. ": blockReduction must be between 0 and 1")
			else
				expect(StatDefinitions.Info[weapon.skill], id .. ": unknown skill " .. tostring(weapon.skill))
				expect(WeaponDefinitions.Directions[weapon.defaultDirection], id .. ": bad defaultDirection")
				expect(weapon.reach > 0 and weapon.maxTargets >= 1, id .. ": reach/maxTargets invalid")
				for _, kind in ipairs({ "light", "heavy" }) do
					local attack = weapon[kind]
					expect(attack, id .. ": missing " .. kind .. " attack")
					expect(attack.damage > 0 and attack.windup > 0 and attack.recovery > 0, id .. ": " .. kind .. " numbers must be positive")
				end
			end
		end
		for _, id in ipairs(WeaponDefinitions.StarterLoadout) do
			expect(WeaponDefinitions.get(id), "StarterLoadout contains unknown weapon " .. id)
		end
	end)

	test("Race definitions are valid", function()
		for _, id in ipairs(RaceDefinitions.Order) do
			local race = RaceDefinitions.Races[id]
			expect(race, "Order lists unknown race " .. id)
			for _, tone in ipairs(race.skinTones) do
				expect(AppearanceOptions.SkinTones[tone], id .. ": skin tone " .. tone .. " does not exist")
			end
			for key, range in pairs(race.scale) do
				expect(range[1] <= range[3] and range[3] <= range[2], id .. ": " .. key .. " default is outside min..max")
			end
			for stat in pairs(race.statModifiers) do
				expect(StatDefinitions.Info[stat], id .. ": unknown stat modifier " .. stat)
			end
		end
	end)

	test("Save data: a new save passes validation", function()
		local ok, reason = DataSchema.sanitize(DataSchema.default())
		expect(ok, tostring(reason))
	end)

	test("Save data: missing fields are filled in (reconcile)", function()
		local data = DataSchema.default()
		data.stats.Blades = nil
		data.meta = nil
		DataSchema.reconcile(data, DataSchema.default())
		expect(data.stats.Blades == StatDefinitions.Info.Blades.start, "Blades was not restored")
		expect(type(data.meta) == "table", "meta was not restored")
	end)

	test("Save data: broken values are repaired (sanitize)", function()
		local data = DataSchema.default()
		data.stats.Strength = 0 / 0 -- NaN, a classic exploit/corruption value
		data.currency = -50
		data.loadout.equipped = "WeaponThatDoesNotExist"
		local ok = DataSchema.sanitize(data)
		expect(ok, "sanitize rejected repairable data")
		expect(data.stats.Strength == StatDefinitions.Info.Strength.start, "NaN Strength was not repaired")
		expect(data.currency == 0, "negative currency was not repaired")
		expect(data.loadout.equipped == "Fists", "unknown weapon was not replaced by Fists")
	end)

	test("Stat formulas behave sensibly", function()
		expect(StatMath.experienceGain(1, 1) > StatMath.experienceGain(50, 1), "higher levels should gain less")
		local multiplier = StatMath.damageMultiplier(StatDefinitions.defaultStats(), WeaponDefinitions.Items.RustedMachete)
		expect(math.abs(multiplier - 1) < 1e-6, "a brand-new character should deal exactly base damage, got x" .. multiplier)
	end)

	test("Character creation validation accepts good and rejects bad input", function()
		local race = RaceDefinitions.Races.Sunworn
		local function payload(name, skinTone)
			local appearance = AppearanceOptions.defaultFor(race)
			appearance.skinTone = skinTone or appearance.skinTone
			return { name = name, race = "Sunworn", appearance = appearance }
		end
		expect(AppearanceService.sanitize(payload("Kara Dune")), "'Kara Dune' should be accepted")
		expect(not AppearanceService.sanitize(payload("ab")), "'ab' (too short) should be rejected")
		expect(not AppearanceService.sanitize(payload("Zed99")), "'Zed99' (digits) should be rejected")
		expect(not AppearanceService.sanitize(payload("Kara Dune", 6)), "a Greyveil skin tone on a Sunworn should be rejected")
		expect(not AppearanceService.sanitize("not a table"), "non-table payload should be rejected")
	end)
end

---------------------------------------------------------------------------
-- 2. World checks
---------------------------------------------------------------------------
local function worldTests()
	test("Terrain generation is deterministic (same seed = same world)", function()
		local settings = table.clone(GameConfig.World)
		local a, b = TerrainGenerator.new(settings), TerrainGenerator.new(settings)
		local otherSettings = table.clone(settings)
		otherSettings.Seed += 1
		local c = TerrainGenerator.new(otherSettings)
		local differs = false
		for _, point in ipairs({ { 300, 120 }, { -250, 410 }, { 512, -512 }, { -90, -333 } }) do
			local x, z = point[1], point[2]
			expect(a:sampleHeight(x, z) == b:sampleHeight(x, z), ("height differs at %d,%d for the same seed"):format(x, z))
			if a:sampleHeight(x, z) ~= c:sampleHeight(x, z) then
				differs = true
			end
		end
		expect(differs, "a different seed produced identical terrain")
	end)

	test("Spawn waystone exists and sits on the terrain", function()
		WorldGenService.waitForSpawnArea()
		local world = workspace:FindFirstChild("World")
		expect(world and world:FindFirstChild("Waystone"), "Workspace.World.Waystone is missing")
		local spawn = WorldGenService.getSpawnPosition()
		local ground = WorldGenService.getSurfaceHeight(spawn.X + 5, spawn.Z + 5)
		expect(math.abs(ground - spawn.Y) < 3, ("ground near spawn is at %.1f, expected about %.1f"):format(ground, spawn.Y))
	end)

	test("Character-creation preview rig was built", function()
		local assets = ReplicatedStorage:WaitForChild("Assets")
		expect(assets:WaitForChild("PreviewRig", 20), "ReplicatedStorage.Assets.PreviewRig missing after 20s")
	end)

	test("Sparring dummies spawned and registered", function()
		local wanted = 0
		for _, spawnPoint in ipairs(NPCDefinitions.SpawnPoints) do
			if NPCDefinitions.Templates[spawnPoint.template].behavior == "Dummy" then
				wanted += 1
			end
		end
		local function count()
			local n = 0
			local folder = workspace:FindFirstChild("NPCs")
			for model, c in pairs(Registry.all()) do
				if c.IsNPC and c.Immobile and folder and model:IsDescendantOf(folder) then
					n += 1
				end
			end
			return n
		end
		waitUntil(function()
			return count() >= wanted
		end, 30)
		expect(count() >= wanted, ("expected %d dummies, found %d"):format(wanted, count()))
		for model, c in pairs(Registry.all()) do
			if c.IsNPC and model:IsDescendantOf(workspace.NPCs) then
				-- Anchored roots break upgraded R15 joints on clients (no attack poses).
				expect(not c.Root.Anchored, model.Name .. " has an anchored root part")
			end
		end
	end)
end

---------------------------------------------------------------------------
-- 3. Combat end-to-end: two temporary fighters high above the map
---------------------------------------------------------------------------
local function makeFighter(name, position, facing, faction)
	local model = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end
	model.Name = name
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	root.Anchored = true
	model:PivotTo(CFrame.lookAt(position, Vector3.new(facing.X, position.Y, facing.Z)))
	model.Parent = workspace
	local c = Combatant.new(model, humanoid, { faction = faction, immobile = true, weaponId = "Fists" })
	Registry.register(c)
	return c
end

local function combatTests()
	local attacker, target
	local ok, err = pcall(function()
		local base = WorldGenService.getSpawnPosition() + Vector3.new(0, 80, 400)
		attacker = makeFighter("SelfTest_Attacker", base, base + Vector3.new(0, 0, -3), "SelfTestA")
		target = makeFighter("SelfTest_Target", base + Vector3.new(0, 0, -3), base, "SelfTestB")
	end)
	if not ok then
		test("Combat test fighters could be created", function()
			error(tostring(err), 0)
		end)
		return
	end

	local light = WeaponDefinitions.Items.Fists.light
	local function waitIdle(c)
		return waitUntil(function()
			return c.State == "Idle"
		end, 3)
	end
	local function heal()
		target.Humanoid.Health = target.Humanoid.MaxHealth
	end

	local fullDamage = 0
	test("Combat: a light attack damages the target", function()
		heal()
		local before = target.Humanoid.Health
		expect(CombatService.attack(attacker, "Light", "Thrust"), "the server refused the attack")
		task.wait(light.windup + 0.3)
		fullDamage = before - target.Humanoid.Health
		expect(fullDamage > 0, "target took no damage (hitbox missed?)")
	end)

	test("Combat: a blocked attack deals less damage", function()
		expect(fullDamage > 0, "skipped: the previous combat test failed")
		expect(waitIdle(attacker), "attacker never returned to Idle")
		heal()
		CombatService.setBlocking(target, true)
		task.wait(GameConfig.Combat.ParryWindow + 0.3) -- too late for a parry: a normal block
		local before = target.Humanoid.Health
		expect(CombatService.attack(attacker, "Light", "Thrust"), "the server refused the attack")
		task.wait(light.windup + 0.3)
		local blockedDamage = before - target.Humanoid.Health
		CombatService.setBlocking(target, false)
		expect(blockedDamage < fullDamage * 0.85, ("blocked hit did %.1f, unblocked did %.1f"):format(blockedDamage, fullDamage))
	end)

	test("Combat: a well-timed block parries and staggers the attacker", function()
		expect(waitIdle(attacker), "attacker never returned to Idle")
		task.wait(GameConfig.Combat.BlockReraiseLockout + 0.2)
		heal()
		CombatService.setBlocking(target, true) -- raised right before the hit lands
		expect(CombatService.attack(attacker, "Light", "Thrust"), "the server refused the attack")
		task.wait(light.windup + 0.1)
		CombatService.setBlocking(target, false)
		expect(attacker.State == "Staggered", "attacker state is " .. attacker.State .. ", expected Staggered")
		expect(target.Humanoid.Health == target.Humanoid.MaxHealth, "a parried hit should do no damage")
	end)

	for _, c in ipairs({ attacker, target }) do
		Registry.unregister(c.Model)
		c.Model:Destroy()
	end
end

---------------------------------------------------------------------------
function SelfTest.run()
	task.wait(1) -- let every service finish start()
	print("[SelfTest] Running checks (Studio only)...")
	configTests()
	worldTests()
	combatTests()
	local total = passed + failed
	if failed == 0 then
		print(("[SelfTest] %d/%d checks passed"):format(passed, total))
	else
		warn(("[SelfTest] %d of %d checks FAILED - copy the FAIL lines above"):format(failed, total))
	end
end

return SelfTest
