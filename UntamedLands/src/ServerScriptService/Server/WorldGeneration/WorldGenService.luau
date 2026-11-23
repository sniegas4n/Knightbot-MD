--!nonstrict
--[[
	WorldGenService
	Location : ServerScriptService/Server/WorldGeneration/WorldGenService (ModuleScript)
	Purpose  : Runs terrain generation at server start (Milestone 1 "Runtime" mode)
	           and owns world-level queries: spawn point, surface height, safe zone.

	Runtime generation: chunks are generated nearest-first, one chunk per frame,
	so the server never freezes. Players are held in character creation / spawn
	until the spawn area is ready (waitForSpawnArea).
	Pregenerated mode: terrain already exists in the place file (Milestone 3
	plugin output); the server only builds the spawn waystone.

	Seed override: set a number attribute "WorldSeed" on Workspace in Studio.
	Depends  : TerrainGenerator, GameConfig
	Public   : init(), start(), waitForSpawnArea(), waitForCompletion(),
	           getSpawnPosition(), getSurfaceHeight(x, z), isInSafeZone(pos),
	           getGenerator()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local TerrainGenerator = require(script.Parent.TerrainGenerator)

local WorldGenService = {}

local settings = nil
local generator = nil
local spawnPosition = Vector3.zero
local spawnReady = false
local complete = false

local function buildSpawnSite()
	local worldFolder = workspace:FindFirstChild("World")

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Waystone"
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.Anchored = true
	spawn.Material = Enum.Material.Slate
	spawn.Color = Color3.fromRGB(104, 98, 90)
	spawn.Neutral = true
	spawn.Duration = 0 -- no spawn forcefield
	spawn.CFrame = CFrame.new(spawnPosition + Vector3.new(0, 0.5, 0))
	spawn.Parent = worldFolder

	-- A ring of weathered standing stones marks the safe zone around the spawn.
	local rng = Random.new(settings.Seed)
	local stones = 7
	for i = 1, stones do
		local angle = (i / stones) * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local radius = GameConfig.Combat.SafeZoneRadius
		local height = rng:NextNumber(6, 11)
		local stone = Instance.new("Part")
		stone.Name = "StandingStone"
		stone.Anchored = true
		stone.Size = Vector3.new(rng:NextNumber(2.5, 3.5), height, rng:NextNumber(1.5, 2.5))
		stone.Material = Enum.Material.Rock
		stone.Color = Color3.fromRGB(118, 108, 96)
		local base = spawnPosition + Vector3.new(math.cos(angle) * radius, height / 2 - 1, math.sin(angle) * radius)
		stone.CFrame = CFrame.lookAt(base, spawnPosition + Vector3.new(0, height / 2 - 1, 0))
			* CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), 0, math.rad(rng:NextNumber(-6, 6)))
		stone.Parent = worldFolder
	end

	workspace:SetAttribute("SpawnPosition", spawnPosition)
	workspace:SetAttribute("SafeZoneRadius", GameConfig.Combat.SafeZoneRadius)
end

local function markSpawnReady()
	if spawnReady then
		return
	end
	buildSpawnSite()
	spawnReady = true
end

local function generateRuntime()
	local terrain = workspace.Terrain
	terrain:Clear()

	local size = settings.ChunkSize
	local r = settings.RadiusInChunks
	local chunks = {}
	for cx = -r, r - 1 do
		for cz = -r, r - 1 do
			local centre = Vector2.new((cx + 0.5) * size, (cz + 0.5) * size)
			table.insert(chunks, { cx = cx, cz = cz, distance = centre.Magnitude })
		end
	end
	table.sort(chunks, function(a, b)
		return a.distance < b.distance
	end)

	local started = os.clock()
	for index, chunk in ipairs(chunks) do
		local ok, err = pcall(generator.generateChunk, generator, terrain, chunk.cx, chunk.cz)
		if not ok then
			warn(("[WorldGen] Chunk %d,%d failed: %s"):format(chunk.cx, chunk.cz, tostring(err)))
		end
		local nextChunk = chunks[index + 1]
		if not spawnReady and (nextChunk == nil or nextChunk.distance > settings.SpawnAreaRadius) then
			markSpawnReady()
			print(("[WorldGen] Spawn area ready after %.2fs"):format(os.clock() - started))
		end
		task.wait() -- one chunk per frame keeps the server responsive
	end
	print(("[WorldGen] Generated %d chunks (seed %d) in %.2fs"):format(#chunks, settings.Seed, os.clock() - started))
end

function WorldGenService.init()
	settings = table.clone(GameConfig.World)
	local seedOverride = workspace:GetAttribute("WorldSeed")
	if type(seedOverride) == "number" then
		settings.Seed = math.floor(seedOverride)
	end
	generator = TerrainGenerator.new(settings)
	spawnPosition = Vector3.new(0, generator:getSpawnHeight(), 0)
end

function WorldGenService.start()
	task.spawn(function()
		if settings.Mode == "Runtime" then
			generateRuntime()
		else
			-- Pregenerated: use the real surface under the origin as the spawn.
			local height = WorldGenService.getSurfaceHeight(0, 0)
			spawnPosition = Vector3.new(0, height, 0)
			markSpawnReady()
		end
		complete = true
	end)
end

function WorldGenService.waitForSpawnArea()
	while not spawnReady do
		task.wait(0.2)
	end
end

function WorldGenService.waitForCompletion()
	while not complete do
		task.wait(0.5)
	end
end

function WorldGenService.getSpawnPosition()
	return spawnPosition
end

function WorldGenService.getGenerator()
	return generator
end

-- Raycasts the real terrain; falls back to the noise function if nothing is hit.
function WorldGenService.getSurfaceHeight(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.IgnoreWater = true
	local top = settings.MaxY + 20
	local result = workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, -(top - settings.MinY + 20), 0), params)
	if result then
		return result.Position.Y
	end
	return generator:sampleHeight(x, z)
end

function WorldGenService.isInSafeZone(position)
	local flat = Vector3.new(position.X - spawnPosition.X, 0, position.Z - spawnPosition.Z)
	return flat.Magnitude <= GameConfig.Combat.SafeZoneRadius
end

return WorldGenService
