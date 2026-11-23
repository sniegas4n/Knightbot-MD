--!nonstrict
--[[
	DataSchema
	Location : ServerScriptService/Server/PlayerData/DataSchema (ModuleScript)
	Purpose  : Defines the per-player save format, its version, migrations between
	           versions, reconciliation (filling in fields added by updates) and
	           validation/sanitisation before anything is written to a DataStore.

	Versioning rule: never change the meaning of an existing field. Add a new
	field (reconcile fills it in) or bump Version and add a migration.
	Depends  : StatDefinitions, RaceDefinitions, AppearanceOptions, WeaponDefinitions
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local StatDefinitions = require(Config.StatDefinitions)
local RaceDefinitions = require(Config.RaceDefinitions)
local AppearanceOptions = require(Config.AppearanceOptions)
local WeaponDefinitions = require(Config.WeaponDefinitions)

local DataSchema = {}

DataSchema.Version = 1

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = deepCopy(v)
	end
	return copy
end
DataSchema.deepCopy = deepCopy

function DataSchema.default()
	local race = RaceDefinitions.Order[1]
	return {
		schemaVersion = DataSchema.Version,
		character = {
			created = false,
			name = "",
			race = race,
			appearance = AppearanceOptions.defaultFor(RaceDefinitions.Races[race]),
		},
		stats = StatDefinitions.defaultStats(),
		loadout = {
			owned = table.clone(WeaponDefinitions.StarterLoadout),
			equipped = "Fists",
			offhandOwned = WeaponDefinitions.StarterOffhand,
			offhand = "",
		},
		currency = 50,
		-- Milestone 2 will add: vitals (hunger/thirst/fatigue), injuries, inventory.
		meta = {
			createdAt = os.time(),
			lastSaved = 0,
			saveCount = 0,
			totalPlayTime = 0,
		},
	}
end

-- Migrations: Migrations[n] converts data from version n to n + 1.
DataSchema.Migrations = {
	-- [1] = function(data) data.newField = ...; return data end,
}

function DataSchema.migrate(data)
	local version = tonumber(data.schemaVersion) or 1
	while version < DataSchema.Version do
		local migration = DataSchema.Migrations[version]
		if migration then
			data = migration(data)
		end
		version += 1
		data.schemaVersion = version
	end
	return data
end

-- Fills any missing keys from template (recursively for dictionaries).
function DataSchema.reconcile(data, template)
	for key, value in pairs(template) do
		if data[key] == nil then
			data[key] = deepCopy(value)
		elseif type(value) == "table" and type(data[key]) == "table" and #value == 0 then
			DataSchema.reconcile(data[key], value)
		end
	end
	return data
end

local function isFinite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- Repairs out-of-range values in place. Returns false + reason only for data
-- that is too broken to save (so we never overwrite a good save with garbage).
function DataSchema.sanitize(data)
	if type(data) ~= "table" then
		return false, "data is not a table"
	end
	if type(data.character) ~= "table" or type(data.stats) ~= "table" or type(data.loadout) ~= "table" then
		return false, "missing core sections"
	end

	-- Stats
	for id, info in pairs(StatDefinitions.Info) do
		local v = data.stats[id]
		if not isFinite(v) then
			data.stats[id] = info.start
		else
			data.stats[id] = math.clamp(v, 0, StatDefinitions.MaxLevel)
		end
	end
	for id in pairs(data.stats) do
		if not StatDefinitions.Info[id] then
			data.stats[id] = nil
		end
	end

	-- Character
	local character = data.character
	if not RaceDefinitions.get(character.race) then
		character.race = RaceDefinitions.Order[1]
	end
	if type(character.name) ~= "string" then
		character.name = ""
	end
	if type(character.appearance) ~= "table" then
		character.appearance = AppearanceOptions.defaultFor(RaceDefinitions.Races[character.race])
	end
	character.created = character.created == true

	-- Currency
	if not isFinite(data.currency) or data.currency < 0 then
		data.currency = 0
	end
	data.currency = math.floor(data.currency)

	-- Loadout
	local loadout = data.loadout
	if type(loadout.owned) ~= "table" then
		loadout.owned = table.clone(WeaponDefinitions.StarterLoadout)
	end
	if not WeaponDefinitions.get(loadout.equipped) or not table.find(loadout.owned, loadout.equipped) then
		loadout.equipped = "Fists"
	end
	if type(loadout.offhand) ~= "string" then
		loadout.offhand = ""
	end

	return true
end

return DataSchema
