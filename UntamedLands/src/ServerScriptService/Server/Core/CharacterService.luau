--!nonstrict
--[[
	CharacterService
	Location : ServerScriptService/Server/Core/CharacterService (ModuleScript)
	Purpose  : Owns the player lifecycle from join to respawn.
	  join -> profile loads -> (no character? client shows creation UI)
	       -> SubmitCharacter validated + name filtered -> saved -> spawn
	  spawn -> LoadCharacterWithHumanoidDescription -> hair, health, Combatant,
	           weapons -> death -> respawn after RespawnDelay
	Also builds ReplicatedStorage/Assets/PreviewRig for the creation screen.
	Players.CharacterAutoLoads is false: nothing spawns without this service.
	Depends  : PlayerDataService, AppearanceService, Combatant, CombatantRegistry,
	           CombatService, StatService, WorldGenService, Net, RaceDefinitions,
	           GameConfig
	Public   : init(), start(), spawn(player)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local RaceDefinitions = require(Shared.Config.RaceDefinitions)
local StatDefinitions = require(Shared.Config.StatDefinitions)
local Net = require(Shared.Modules.Net)

local Server = script.Parent.Parent
local PlayerDataService = require(Server.PlayerData.PlayerDataService)
local StatService = require(Server.Progression.StatService)
local WorldGenService = require(Server.WorldGeneration.WorldGenService)
local Combatant = require(Server.Combat.Combatant)
local Registry = require(Server.Combat.CombatantRegistry)
local CombatService = require(Server.Combat.CombatService)
local AppearanceService = require(script.Parent.AppearanceService)

local CharacterService = {}

local spawning = {} -- [Player] = true while LoadCharacter is running
local submitting = {} -- [Player] = true while a creation request is processed

---------------------------------------------------------------------------
-- Name filtering (required by Roblox for any user-written text shown to others)
---------------------------------------------------------------------------
local function filterName(player, name)
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(name, player.UserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		return false, "The name filter is unavailable right now. Try again."
	end
	if result ~= name then
		return false, "That name is not allowed."
	end
	return true
end

---------------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------------
function CharacterService.spawn(player)
	if spawning[player] or not player.Parent then
		return
	end
	local data = PlayerDataService.getData(player)
	if not data or not data.character.created then
		return
	end
	spawning[player] = true
	WorldGenService.waitForSpawnArea()

	if player.Parent then
		local description = AppearanceService.buildDescription(data.character)
		local ok, err = pcall(function()
			player:LoadCharacterWithHumanoidDescription(description)
		end)
		if not ok then
			warn("[Character] LoadCharacterWithHumanoidDescription failed: " .. tostring(err) .. " - falling back to LoadCharacter")
			pcall(function()
				player:LoadCharacter()
			end)
		end
	end
	spawning[player] = nil
end

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local data = PlayerDataService.getData(player)
	if not humanoid or not root or not data then
		return
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		warn("[Character] Character is not R15. Set Game Settings > Avatar > Avatar Type to R15.")
	end

	local raceDef = RaceDefinitions.get(data.character.race) or RaceDefinitions.Races.Sunworn
	humanoid.DisplayName = data.character.name
	humanoid.MaxHealth = math.floor(GameConfig.Player.BaseMaxHealth * raceDef.healthMultiplier + 0.5)
	humanoid.Health = humanoid.MaxHealth

	AppearanceService.applyExtras(character, data.character)

	local c = Combatant.new(character, humanoid, {
		player = player,
		stats = data.stats, -- live reference: progression immediately affects combat
		faction = "Player",
	})
	Registry.register(c)
	local offhand = if data.loadout.offhand ~= "" then data.loadout.offhand else nil
	CombatService.initializeLoadout(c, data.loadout.equipped, offhand)

	humanoid.Died:Connect(function()
		c:setState("Dead")
		Net.fireClient("Notify", player, "You have fallen. The wastes keep turning without you...")
		task.delay(GameConfig.Player.RespawnDelay, function()
			if player.Parent and player.Character == character then
				CharacterService.spawn(player)
			end
		end)
	end)

	StatService.pushStats(player)
end

---------------------------------------------------------------------------
-- Character creation
---------------------------------------------------------------------------
local function applyRaceModifiers(stats, raceDef)
	for statId, delta in pairs(raceDef.statModifiers) do
		if StatDefinitions.Info[statId] then
			stats[statId] = math.clamp((stats[statId] or StatDefinitions.Info[statId].start) + delta, 1, StatDefinitions.MaxLevel)
		end
	end
end

local function handleSubmit(player, payload)
	local profile = PlayerDataService.getProfile(player)
	if not profile then
		return { ok = false, message = "Your save is still loading." }
	end
	if profile.data.character.created then
		return { ok = false, message = "You already have a character." }
	end
	if submitting[player] then
		return { ok = false, message = "Please wait..." }
	end
	submitting[player] = true

	local sanitized, err = AppearanceService.sanitize(payload)
	if not sanitized then
		submitting[player] = nil
		return { ok = false, message = err }
	end

	local allowed, filterErr = filterName(player, sanitized.name)
	if not allowed then
		submitting[player] = nil
		return { ok = false, message = filterErr }
	end
	if not player.Parent or profile.data.character.created then
		submitting[player] = nil
		return { ok = false, message = "You already have a character." }
	end

	local data = profile.data
	data.character = {
		created = true,
		name = sanitized.name,
		race = sanitized.race,
		appearance = sanitized.appearance,
	}
	applyRaceModifiers(data.stats, RaceDefinitions.get(sanitized.race))
	submitting[player] = nil

	task.spawn(PlayerDataService.saveAsync, player, false)
	task.spawn(CharacterService.spawn, player)
	return { ok = true }
end

local function handleSessionState(player)
	local profile = PlayerDataService.waitForProfile(player, 30)
	if not profile then
		return { ready = false }
	end
	return {
		ready = true,
		needsCreation = not profile.data.character.created,
		temporary = profile.temporary,
		name = profile.data.character.name,
	}
end

---------------------------------------------------------------------------
-- Preview rig for the creation screen (built once per server)
---------------------------------------------------------------------------
local function createPreviewRig()
	local assets = ReplicatedStorage:WaitForChild("Assets")
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if not ok or not rig then
		warn("[Character] Could not create preview rig: " .. tostring(rig))
		return
	end
	rig.Name = "PreviewRig"
	for _, descendant in ipairs(rig:GetDescendants()) do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end
	local root = rig:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = true
	end
	rig.Parent = assets
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	player.CharacterRemoving:Connect(function(character)
		Registry.unregister(character)
	end)

	local profile = PlayerDataService.waitForProfile(player, 90)
	if profile and profile.data.character.created then
		CharacterService.spawn(player)
	end
end

function CharacterService.init()
	Net.handle("GetSessionState", handleSessionState)
	Net.handle("SubmitCharacter", handleSubmit)
end

function CharacterService.start()
	Players.CharacterAutoLoads = false
	task.spawn(createPreviewRig)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		spawning[player] = nil
		submitting[player] = nil
		if player.Character then
			Registry.unregister(player.Character)
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

return CharacterService
