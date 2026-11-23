--!nonstrict
--[[
	PlayerDataService
	Location : ServerScriptService/Server/PlayerData/PlayerDataService (ModuleScript)
	Purpose  : Loads, caches, autosaves and releases each player's save.
	           - Session locking: a save records which server (JobId) owns it, so
	             two servers can't both write the same player (item duplication).
	           - Retries with backoff and request-budget checks.
	           - Validation before every write; invalid data is never saved.
	           - In Studio without API access, falls back to temporary data that
	             is NEVER saved, so a test session can't wipe a real save.
	           - In live servers, if loading fails the player is kicked rather
	             than given blank data that would later overwrite their save.
	Depends  : DataSchema, GameConfig, Signal
	Public   : init(), start(), getProfile(player), waitForProfile(player, timeout),
	           saveAsync(player), ProfileLoaded (Signal)
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Signal = require(ReplicatedStorage.Shared.Modules.Signal)
local DataSchema = require(script.Parent.DataSchema)

local CONFIG = GameConfig.Data

local PlayerDataService = {}
PlayerDataService.ProfileLoaded = Signal.new()

local store = nil
local profiles = {} -- [Player] = { data, temporary, joinedAt, saving }
local loading = {} -- [Player] = true while a load is in flight
local shuttingDown = false

local function keyFor(player)
	return CONFIG.KeyPrefix .. tostring(player.UserId)
end

local function waitForBudget(requestType)
	local waited = 0
	while DataStoreService:GetRequestBudgetForRequestType(requestType) < 1 and waited < 10 do
		task.wait(0.5)
		waited += 0.5
	end
end

local function lockIsForeign(lock)
	return type(lock) == "table" and lock.jobId ~= game.JobId and type(lock.time) == "number"
end

---------------------------------------------------------------------------
-- Load
---------------------------------------------------------------------------
local function loadFromStore(player)
	local key = keyFor(player)
	for attempt = 1, CONFIG.LoadAttempts + 1 do
		local forceTakeover = attempt > CONFIG.LoadAttempts
		local lockedByOther = false

		waitForBudget(Enum.DataStoreRequestType.UpdateAsync)
		local ok, result = pcall(function()
			return store:UpdateAsync(key, function(old)
				lockedByOther = false -- the transform may run more than once
				if old ~= nil and type(old) ~= "table" then
					old = nil -- corrupted entry; start fresh rather than crash
				end
				if old and lockIsForeign(old._lock) and not forceTakeover then
					if os.time() - old._lock.time < CONFIG.SessionLockTimeout then
						lockedByOther = true
						return nil -- cancel the write; try again shortly
					end
				end
				local data = old or DataSchema.default()
				data._lock = { jobId = game.JobId, time = os.time() }
				return data
			end)
		end)

		if ok and not lockedByOther and type(result) == "table" then
			return true, result
		elseif ok and lockedByOther then
			warn(("[PlayerData] %s is locked by another server (attempt %d)"):format(player.Name, attempt))
			task.wait(CONFIG.RetryDelay)
		else
			warn(("[PlayerData] Load failed for %s (attempt %d): %s"):format(player.Name, attempt, tostring(result)))
			-- In Studio a failure is almost always "API access disabled": don't make
			-- the developer wait through every retry before falling back.
			if attempt >= CONFIG.LoadAttempts or RunService:IsStudio() then
				return false, result
			end
			task.wait(CONFIG.RetryDelay * attempt)
		end

		if not player.Parent then
			return false, "player left during load"
		end
	end
	return false, "exhausted attempts"
end

local function prepare(raw)
	raw._lock = nil
	local data = DataSchema.migrate(raw)
	DataSchema.reconcile(data, DataSchema.default())
	local ok, reason = DataSchema.sanitize(data)
	if not ok then
		return nil, reason
	end
	return data
end

local function onPlayerAdded(player)
	if profiles[player] or loading[player] then
		return
	end
	loading[player] = true

	local data, temporary = nil, false
	if store then
		local ok, raw = loadFromStore(player)
		if ok then
			local reason
			data, reason = prepare(raw)
			if not data then
				warn("[PlayerData] Save for " .. player.Name .. " failed validation: " .. tostring(reason))
			end
		end
	end

	if not data then
		if RunService:IsStudio() then
			warn("[PlayerData] Using TEMPORARY data for " .. player.Name .. " (Studio, DataStore unavailable). Progress will NOT be saved.")
			data = DataSchema.default()
			temporary = true
		else
			loading[player] = nil
			if player.Parent then
				player:Kick("Your save could not be loaded safely. Please rejoin in a moment.")
			end
			return
		end
	end

	loading[player] = nil
	if not player.Parent then
		-- Left while loading: release the lock we just took.
		if not temporary then
			profiles[player] = { data = data, temporary = false, joinedAt = os.clock(), saving = false }
			PlayerDataService.saveAsync(player, true)
			profiles[player] = nil
		end
		return
	end

	profiles[player] = { data = data, temporary = temporary, joinedAt = os.clock(), saving = false }
	PlayerDataService.ProfileLoaded:Fire(player)
end

---------------------------------------------------------------------------
-- Save
---------------------------------------------------------------------------
-- release = true removes our session lock (player leaving / server closing).
function PlayerDataService.saveAsync(player, release)
	local profile = profiles[player]
	if not profile or profile.temporary or not store then
		return false
	end
	if profile.saving then
		-- Another save is in flight; wait for it so the final (release) save still runs.
		local waited = 0
		while profile.saving and waited < 15 do
			task.wait(0.25)
			waited += 0.25
		end
	end

	local data = profile.data
	local ok, reason = DataSchema.sanitize(data)
	if not ok then
		warn("[PlayerData] Refusing to save invalid data for " .. player.Name .. ": " .. tostring(reason))
		return false
	end

	local now = os.clock()
	data.meta.totalPlayTime += now - profile.joinedAt
	profile.joinedAt = now
	data.meta.lastSaved = os.time()
	data.meta.saveCount += 1

	profile.saving = true
	local key = keyFor(player)
	local success = false
	for attempt = 1, CONFIG.SaveAttempts do
		local lostLock = false
		waitForBudget(Enum.DataStoreRequestType.UpdateAsync)
		local okCall, err = pcall(function()
			store:UpdateAsync(key, function(old)
				lostLock = false
				if type(old) == "table" and lockIsForeign(old._lock) then
					lostLock = true
					return nil -- another server owns this save now; do not overwrite
				end
				local copy = DataSchema.deepCopy(data)
				if release then
					copy._lock = nil
				else
					copy._lock = { jobId = game.JobId, time = os.time() }
				end
				return copy
			end)
		end)
		if okCall then
			if lostLock then
				warn("[PlayerData] Session lock lost for " .. player.Name .. "; save skipped.")
			else
				success = true
			end
			break
		end
		warn(("[PlayerData] Save failed for %s (attempt %d): %s"):format(player.Name, attempt, tostring(err)))
		task.wait(CONFIG.RetryDelay * attempt)
	end
	profile.saving = false
	return success
end

local function onPlayerRemoving(player)
	-- If still loading, onPlayerAdded handles the release when it finishes.
	if profiles[player] then
		PlayerDataService.saveAsync(player, true)
		profiles[player] = nil
	end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function PlayerDataService.getProfile(player)
	return profiles[player]
end

function PlayerDataService.getData(player)
	local profile = profiles[player]
	return profile and profile.data
end

function PlayerDataService.waitForProfile(player, timeout)
	local deadline = os.clock() + (timeout or 30)
	while player.Parent and os.clock() < deadline do
		local profile = profiles[player]
		if profile then
			return profile
		end
		task.wait(0.1)
	end
	return profiles[player]
end

function PlayerDataService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(CONFIG.StoreName)
	end)
	if ok then
		store = result
	else
		warn("[PlayerData] DataStore unavailable: " .. tostring(result))
	end
end

function PlayerDataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	-- Autosave, staggered so all players don't hit the DataStore at once.
	task.spawn(function()
		while not shuttingDown do
			task.wait(CONFIG.AutosaveInterval)
			local list = {}
			for player in pairs(profiles) do
				table.insert(list, player)
			end
			local gap = if #list > 0 then math.min(2, CONFIG.AutosaveInterval / (#list * 2)) else 0
			for _, player in ipairs(list) do
				if shuttingDown then
					break
				end
				if profiles[player] then
					task.spawn(PlayerDataService.saveAsync, player, false)
				end
				task.wait(gap)
			end
		end
	end)

	game:BindToClose(function()
		shuttingDown = true
		local pending = 0
		for player in pairs(profiles) do
			pending += 1
			task.spawn(function()
				PlayerDataService.saveAsync(player, true)
				pending -= 1
			end)
		end
		local waited = 0
		while pending > 0 and waited < 25 do
			task.wait(0.25)
			waited += 0.25
		end
	end)
end

return PlayerDataService
