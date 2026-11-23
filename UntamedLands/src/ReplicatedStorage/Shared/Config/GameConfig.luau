--!nonstrict
--[[
	GameConfig
	Location : ReplicatedStorage/Shared/Config/GameConfig (ModuleScript)
	Purpose  : Central tuning values shared by server and client.
	           Server code is authoritative; the client only reads these values
	           for prediction (e.g. "do I have enough stamina to try a dodge?").
	Depends  : nothing
]]

local GameConfig = {}

GameConfig.Version = "0.1.0-milestone1"

GameConfig.Movement = {
	WalkSpeed = 12,
	RunSpeed = 22,
	BlockingSpeedMultiplier = 0.55,
	AttackingSpeedMultiplier = 0.6,
	RecoveringSpeedMultiplier = 0.75,
	StaggeredSpeedMultiplier = 0.3,
	JumpHeight = 7.2,
	DodgeSpeed = 44,
	DodgeDuration = 0.22, -- seconds the dodge velocity is applied
	DodgeInvulnerability = 0.3, -- seconds of i-frames granted by the server
	DodgeCooldown = 0.75,
}

GameConfig.Stamina = {
	BaseMax = 100,
	MaxPerEnduranceLevel = 2, -- per Endurance level above 10
	RegenPerSecond = 18,
	RegenDelay = 0.9, -- seconds after spending stamina before regen starts
	SprintDrainPerSecond = 11,
	JumpCost = 12,
	DodgeCost = 22,
	WindedRecoverFraction = 0.25, -- must regain 25% of max to stop being winded
}

GameConfig.Combat = {
	ParryWindow = 0.22, -- block raised this recently when hit = parry
	BlockReraiseLockout = 0.3, -- re-raising a block this quickly grants no parry window
	CounterWindow = 1.0,
	CounterDamageMultiplier = 1.5,
	ParryStaggerTime = 1.1,
	GuardBreakStaggerTime = 1.4,
	HeavyHitStaggerTime = 0.5,
	BlockFacingDot = 0.25, -- target must roughly face the attacker for a block to count
	DamageVariance = 0.1,
	PvPEnabled = true,
	SafeZoneRadius = 40, -- no player-vs-player damage near the spawn waystone
	ReachTolerance = 3, -- extra studs allowed for latency when validating hits
	AttackBroadcastRadius = 250,
}

GameConfig.Player = {
	BaseMaxHealth = 100,
	RespawnDelay = 6,
	-- Placeholder until Milestone 2's injury/medical system replaces it.
	NaturalRegenPerSecond = 0.5,
	NaturalRegenDelay = 12, -- seconds without taking damage
}

GameConfig.Progression = {
	GlobalRate = 1.0, -- multiply all stat gains (useful for testing)
	ExperienceScale = 0.05,
	DiminishPerLevel = 0.1,
}

GameConfig.Data = {
	StoreName = "UntamedLands_PlayerData_v1",
	KeyPrefix = "player_",
	AutosaveInterval = 120,
	SessionLockTimeout = 1800, -- seconds before a stale lock may be taken over
	LoadAttempts = 5,
	RetryDelay = 4,
	SaveAttempts = 4,
}

GameConfig.World = {
	-- "Runtime"      : the server generates terrain on start (Milestone 1 default)
	-- "Pregenerated" : terrain was built in Studio (Milestone 3 plugin); the server keeps it
	Mode = "Runtime",
	Seed = 1337,
	ChunkSize = 64, -- studs, must be a multiple of VoxelResolution
	RadiusInChunks = 8, -- generates a (2R x 2R) chunk square => 1024 x 1024 studs
	VoxelResolution = 4, -- Roblox terrain voxels are always 4 studs
	MinY = -32,
	MaxY = 192,
	BaseHeight = 24,
	HeightAmplitude = 70,
	WaterLevel = 14,
	NoiseScale = 1 / 360,
	Octaves = 4,
	Persistence = 0.5,
	Lacunarity = 2.0,
	MountainScale = 1 / 700,
	MountainStrength = 95,
	MoistureScale = 1 / 650,
	SpawnHeightAboveWater = 10,
	SpawnFlatRadius = 45,
	SpawnBlendRadius = 110,
	SpawnAreaRadius = 200, -- chunks whose centres are inside this are generated first
}

GameConfig.Environment = {
	DayLengthMinutes = 24, -- one full in-game day in real minutes (no fast-forward exists)
	StartClockTime = 8.5,
}

GameConfig.Debug = {
	RunSelfTests = true, -- Studio only: automatic PASS/FAIL checks in Output on every Play
}

GameConfig.NPC = {
	ThinkInterval = 0.2,
	ActiveRange = 220, -- NPCs with no player inside this range go dormant
	CorpseLifetime = 12,
}

return GameConfig
