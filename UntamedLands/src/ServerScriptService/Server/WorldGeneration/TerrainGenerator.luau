--!nonstrict
--[[
	TerrainGenerator
	Location : ServerScriptService/Server/WorldGeneration/TerrainGenerator (ModuleScript)
	Purpose  : Deterministic, seed-based terrain sampling and chunk writing.
	           This module has NO side effects except generateChunk(), so the same
	           code can be reused by the Milestone 3 Studio plugin (edit-time
	           generation) and by the server (runtime generation).

	How it works
	  1. Random.new(seed) produces fixed noise offsets -> same seed, same world.
	  2. sampleHeight(x, z) mixes fractal Perlin noise (math.noise is
	     deterministic) with a ridged "mountain" layer gated by a mask layer.
	  3. A moisture layer chooses desert vs. scrub vs. grassland materials.
	  4. generateChunk() fills one ChunkSize x ChunkSize column of voxels with
	     Terrain:WriteVoxels - one engine call per chunk, which is far cheaper
	     than thousands of FillBlock calls.
	Depends  : nothing (settings are passed to new())
]]

local TerrainGenerator = {}
TerrainGenerator.__index = TerrainGenerator

local MAT = Enum.Material

local function smoothstep(edge0, edge1, x)
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

function TerrainGenerator.new(settings)
	local self = setmetatable({}, TerrainGenerator)
	self.settings = settings
	local rng = Random.new(settings.Seed)
	local function offset()
		return Vector3.new(rng:NextNumber(-5000, 5000), rng:NextNumber(-5000, 5000), rng:NextNumber(0, 100))
	end
	self.offsets = {
		height = offset(),
		mountain = offset(),
		mask = offset(),
		moisture = offset(),
		detail = offset(),
	}
	self.spawnHeight = settings.WaterLevel + settings.SpawnHeightAboveWater
	assert(settings.ChunkSize % settings.VoxelResolution == 0, "ChunkSize must be a multiple of VoxelResolution")
	assert(settings.MinY % 4 == 0 and settings.MaxY % 4 == 0, "MinY/MaxY must be multiples of 4")
	return self
end

-- Fractal Brownian motion. Returns roughly -0.5..0.5.
function TerrainGenerator:fbm(x, z, offset, scale, octaves)
	local s = self.settings
	local total, amplitude, frequency, norm = 0, 1, scale, 0
	for i = 1, octaves or s.Octaves do
		total += math.noise(x * frequency + offset.X, z * frequency + offset.Y, offset.Z + i * 1.731) * amplitude
		norm += amplitude
		amplitude *= s.Persistence
		frequency *= s.Lacunarity
	end
	return total / norm
end

function TerrainGenerator:getSpawnHeight()
	return self.spawnHeight
end

function TerrainGenerator:sampleMoisture(x, z)
	return self:fbm(x, z, self.offsets.moisture, self.settings.MoistureScale, 3)
end

function TerrainGenerator:sampleHeight(x, z)
	local s = self.settings
	local base = self:fbm(x, z, self.offsets.height, s.NoiseScale)
	local ridgeNoise = self:fbm(x, z, self.offsets.mountain, s.MountainScale, 3)
	local ridge = math.max(0, 1 - math.abs(ridgeNoise) * 4) ^ 2
	local mask = smoothstep(-0.02, 0.12, self:fbm(x, z, self.offsets.mask, s.MountainScale * 0.6, 2))
	local detail = self:fbm(x, z, self.offsets.detail, s.NoiseScale * 6, 2)

	local h = s.BaseHeight + base * s.HeightAmplitude + ridge * mask * s.MountainStrength + detail * 6

	-- Flatten and blend a plateau around the spawn point.
	local distance = math.sqrt(x * x + z * z)
	if distance < s.SpawnBlendRadius then
		local t = smoothstep(s.SpawnFlatRadius, s.SpawnBlendRadius, distance)
		h = self.spawnHeight + (h - self.spawnHeight) * t
	end
	return math.clamp(h, s.MinY + 8, s.MaxY - 8)
end

-- Returns surface material for a column. slope = max height change per stud.
function TerrainGenerator:surfaceMaterial(x, z, height, slope)
	local s = self.settings
	local moisture = self:sampleMoisture(x, z)

	if slope > 1.3 then
		return MAT.Rock
	end
	if height > s.WaterLevel + 110 then
		return if slope > 0.6 then MAT.Basalt else MAT.Rock
	end
	if height < s.WaterLevel + 2 then
		return if moisture > 0.05 then MAT.Mud else MAT.Sand
	end
	if slope > 0.8 then
		return if moisture < -0.05 then MAT.Sandstone else MAT.Slate
	end
	if moisture < -0.06 then
		return MAT.Sand
	elseif moisture < 0.04 then
		return MAT.Ground
	elseif moisture < 0.12 then
		return MAT.Grass
	end
	return MAT.LeafyGrass
end

function TerrainGenerator:getBiome(x, z)
	local moisture = self:sampleMoisture(x, z)
	if moisture < -0.06 then
		return "Desert"
	elseif moisture < 0.04 then
		return "Scrubland"
	end
	return "Grassland"
end

-- Writes one chunk. cx/cz are chunk indices (chunk 0,0 starts at world 0,0).
function TerrainGenerator:generateChunk(terrain, cx, cz)
	local s = self.settings
	local res = s.VoxelResolution
	local size = s.ChunkSize
	local x0, z0 = cx * size, cz * size
	local nx = size // res
	local ny = (s.MaxY - s.MinY) // res

	-- Height cache with a 1-voxel border so slope can be measured at the edges.
	local heights = {}
	for i = 0, nx + 1 do
		local column = {}
		for k = 0, nx + 1 do
			column[k] = self:sampleHeight(x0 + (i - 0.5) * res, z0 + (k - 0.5) * res)
		end
		heights[i] = column
	end

	local materials, occupancy = {}, {}
	for i = 1, nx do
		local matX, occX = {}, {}
		for j = 1, ny do
			matX[j] = {}
			occX[j] = {}
		end
		materials[i] = matX
		occupancy[i] = occX

		for k = 1, nx do
			local h = heights[i][k]
			local slope = math.max(
				math.abs(h - heights[i - 1][k]),
				math.abs(h - heights[i + 1][k]),
				math.abs(h - heights[i][k - 1]),
				math.abs(h - heights[i][k + 1])
			) / res
			local wx, wz = x0 + (i - 0.5) * res, z0 + (k - 0.5) * res
			local surface = self:surfaceMaterial(wx, wz, h, slope)
			local subsurface = if surface == MAT.Sand then MAT.Sandstone else MAT.Ground

			for j = 1, ny do
				local yBottom = s.MinY + (j - 1) * res
				local fill = math.clamp((h - yBottom) / res, 0, 1)
				if fill > 0 then
					local depth = h - (yBottom + res * 0.5)
					local material
					if depth > 12 then
						material = MAT.Rock
					elseif depth > 3 then
						material = subsurface
					else
						material = surface
					end
					matX[j][k] = material
					occX[j][k] = fill
				elseif yBottom < s.WaterLevel then
					matX[j][k] = MAT.Water
					occX[j][k] = math.clamp((s.WaterLevel - yBottom) / res, 0, 1)
				else
					matX[j][k] = MAT.Air
					occX[j][k] = 0
				end
			end
		end
	end

	local region = Region3.new(Vector3.new(x0, s.MinY, z0), Vector3.new(x0 + size, s.MaxY, z0 + size))
	terrain:WriteVoxels(region, res, materials, occupancy)
end

return TerrainGenerator
