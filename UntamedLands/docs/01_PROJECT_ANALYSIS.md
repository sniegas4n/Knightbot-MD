# Untamed Lands: Project Analysis, Architecture & Roadmap

This is the "first task" document: what we are building, what Roblox can and cannot do, how the project is structured, and the order we build it in.

---

## 1. Project analysis

**Untamed Lands** is an original open-world survival RPG on Roblox. It takes systemic ideas from Kenshi: a harsh world that runs whether or not you are watching, stats that grow only through use, limb injuries, and a world you can settle in. It differs from Kenshi in three ways:

| Kenshi | Untamed Lands |
|---|---|
| Squad control, pause, fast-forward | **One character per player**, real time only, no pause or time controls |
| Single-player | **Multiplayer first**: solo means "alone on a server" |
| Click-to-attack auto combat | **Directly controlled third-person combat** (timing, blocking, parrying, dodging) |

Everything (world, peoples, factions, weapons, UI, lore) is original. Kenshi is a reference for *system design only*.

### The core loop
Explore → gather/hunt/loot → survive (food, water, rest, wounds) → craft/trade → build/settle → fight factions and other players → grow your character by doing → repeat in a world that keeps changing.

### Design pillars
1. **The world doesn't wait.** One continuous clock. No pause, ever.
2. **You become what you do.** No classes; every stat rises through use with diminishing returns.
3. **Combat is dangerous and readable.** Positioning, stamina, timing and equipment beat raw level.
4. **The server is the truth.** Clients ask; the server decides.
5. **Ship working systems.** A small system that works beats a big one that doesn't.

---

## 2. Roblox technical limitations (and how we design around them)

| Limitation | Impact | Our approach |
|---|---|---|
| **Server players**: max ~100 per server (we target **12-20**). Every server is a separate world instance. | No single shared MMO world. | Each server is its own frontier. Persistent *player* data is global (DataStore). Persistent *world* data (settlements) is per "world slot", see §8 Multiplayer. |
| **Server memory** (~6.25 GB documented ceiling, practically far less is safe) and **CPU** (single Luau main thread) | Can't simulate hundreds of full NPCs or giant terrain at runtime. | Simulation LOD: full AI only near players, abstract simulation elsewhere. Terrain sized to budget. |
| **Terrain** is a voxel grid (4-stud voxels), not an unlimited mesh. Huge maps cost memory on server *and* client. | A "Kenshi-sized" map is impossible. | Target worlds of ~2-4k studs square (runtime) or up to ~8k (Studio-pregenerated). Density and travel time create the sense of scale. |
| **No offline play**. Every experience runs on Roblox servers. | "Solo" = a server with one player. | Solo players can join a private server (later: reserved servers) and play alone. |
| **Network**: remotes are not free; ~50 KB/s per player is a sensible ceiling. Physics replication is automatic but owned by the client for its own character. | Clients can lie about their own movement (speed/teleport hacks). | Server-side movement sanity checks (Milestone 6). All *outcomes* (damage, items, currency) are server-only. |
| **DataStore limits**: per-key size 4 MB, request budgets (~60 + 10×players per minute per type), throttling. | Can't save every change instantly. | Cached profile in memory, autosave every 120 s, save on leave and on shutdown, UpdateAsync with session locking. |
| **MemoryStoreService** is fast but temporary (max 45 days, size quotas). | Not for permanent data. | Cross-server state such as world events, server browser and trade-listing caches. |
| **Character rig**: the default character is rebuilt on respawn; you can't "remove an arm" from the default controller and keep it working. | Dismemberment is hard. | Milestone 7: limbs become visual parts you can detach while the HumanoidRootPart-driven controller keeps running. Gameplay effects (speed, combat penalties) are stats, not physics. |
| **Animations** must be uploaded assets owned by the experience creator/group. | Can't ship animations from code. | Milestone 1 uses **procedural joint poses** (pure code). Authored animations replace them later without API changes. |
| **Text filtering** is mandatory for any player-written text shown to others. | Character names must be filtered. | `TextService:FilterStringAsync` on the server before a name is accepted. |
| **StreamingEnabled**: clients only have nearby parts. | Client code can't assume a model exists. | Every client lookup is nil-safe; server never relies on client-side instances. |
| **Mobile/console** players | Must fit small screens and touch. | Gamepad supported now; touch controls and UI scaling in Milestone 8. |

---

## 3. Recommended architecture

**Service/Controller architecture with a single entry point per side.**

- **Server**: one `Script` (`Main`) requires ModuleScript **services**. Each service exposes `init()` (connect, no yielding) and `start()` (begin loops). Services call each other directly through `require`; the dependency graph has no cycles.
- **Client**: one `LocalScript` (`Main`) requires ModuleScript **controllers** (`init(controllers)`, `onCharacterAdded(character)`).
- **Shared**: configuration (pure data) and pure helper modules used by both sides.
- **Networking**: all remotes are declared in one module (`Net`). It creates them on the server, rate-limits every client→server remote and wraps handlers in `pcall`. Handlers validate types with `Validate`.
- **Data-driven content**: weapons, races, NPCs, stats and appearance are tables in `Shared/Config`. New content means a new table entry, not new code.
- **One loop per system, not per entity**: stamina for every combatant is one 10 Hz loop; every NPC thinks in one scheduler.
- **Attributes for replicated state** (`Stamina`, `CombatState`, `WeaponId`...) instead of per-change remotes.

### Why not a framework (Knit etc.)?
It isn't needed at this size, and plain modules are easier for you to read and edit in Studio. The `init/start` convention gives the same structure without a dependency.

### Tooling
- **Rojo** syncs these files into Studio (recommended, keeps everything in git).
- The manual path (copying scripts into Studio) is documented in `02_MILESTONE_1_GUIDE.md`.

---

## 4. Folder structure

```
UntamedLands/
├─ default.project.json             Rojo mapping (files → Roblox instances)
├─ docs/
│  ├─ 01_PROJECT_ANALYSIS.md        this document
│  ├─ 02_MILESTONE_1_GUIDE.md       setup, wiring, testing for Milestone 1
│  └─ DEVLOG.md                     dev log, feature status, known bugs
└─ src/
   ├─ ReplicatedStorage/Shared/
   │  ├─ Config/                    pure data
   │  │  ├─ GameConfig              all tuning numbers
   │  │  ├─ StatDefinitions         attributes & skills
   │  │  ├─ RaceDefinitions         Sunworn, Greyveil, Ironback
   │  │  ├─ AppearanceOptions       skin/hair/cloth palettes, hairstyles
   │  │  ├─ WeaponDefinitions       weapon catalogue
   │  │  └─ NPCDefinitions          NPC templates & spawns
   │  └─ Modules/                   shared logic
   │     ├─ Net                     remotes, rate limiting
   │     ├─ Validate                remote argument checks
   │     ├─ Signal                  Lua events
   │     ├─ StatMath                stat → gameplay formulas
   │     ├─ HairBuilder             part-built hairstyles
   │     ├─ WeaponModelBuilder      part-built weapons, hand welds
   │     └─ DodgeMotion             dodge velocity burst
   ├─ ServerScriptService/Server/
   │  ├─ Main (Script)              bootstrap
   │  ├─ Core/                      CharacterService, AppearanceService, EnvironmentService
   │  ├─ PlayerData/                PlayerDataService, DataSchema
   │  ├─ Combat/                    Combatant, CombatantRegistry, CombatService, VitalsService
   │  ├─ Progression/               StatService
   │  ├─ WorldGeneration/           TerrainGenerator, WorldGenService
   │  └─ NPCs/                      NPCService, NPCAnimator
   │   (future: Survival/, Inventory/, Crafting/, Building/, Factions/, Economy/)
   └─ StarterPlayer/
      ├─ StarterPlayerScripts/Client/
      │  ├─ Main (LocalScript)      bootstrap
      │  ├─ Controllers/            Camera, Movement, Combat, Animation, HUD, CharacterCreation
      │  └─ UI/UIKit                UI helpers + visual identity
      └─ StarterCharacterScripts/
         └─ Health (Script)         disables default regen
```

Created at runtime (not in source):
- `ReplicatedStorage/Remotes`: all RemoteEvents/RemoteFunctions (by `Net`)
- `ReplicatedStorage/Assets/PreviewRig`: character-creation preview model
- `Workspace/World`, `NPCs`, `Resources`, `PlayerBuildings`

**Changes from your proposed structure, and why:**
- UI is built in code under `Client/` instead of hand-made in `StarterGui`. It's diffable and reviewable, and nothing breaks if a frame is renamed in Studio. The `StarterGui` folders you listed map to client controllers 1:1.
- Remotes are generated by `Net` instead of placed by hand. This removes the most common "remote not found" bug.
- `ServerStorage` stays empty until Milestone 4 brings real asset models (buildings, items).

### Module responsibility & dependency table

| Module | Responsibility | Depends on |
|---|---|---|
| Net | define/create remotes, rate-limit, safe handlers | – |
| Validate | type/value checks | – |
| StatMath | formulas | GameConfig |
| PlayerDataService | load/save/lock profiles | DataSchema, GameConfig, Signal |
| DataSchema | default/migrate/reconcile/sanitize | Stat/Race/Appearance/Weapon defs |
| StatService | use-based XP, push stats | PlayerDataService, StatMath, Net |
| WorldGenService | run generation, spawn site, world queries | TerrainGenerator, GameConfig |
| TerrainGenerator | deterministic sampling & voxel writing | – |
| EnvironmentService | lighting, day/night | GameConfig |
| Combatant | per-character combat state | Stat/Weapon defs, StatMath |
| CombatantRegistry | model ↔ combatant, tags | Signal |
| CombatService | attacks, blocks, parries, dodges, equip | Registry, StatService, WorldGen, PlayerData, Net |
| VitalsService | stamina, speed, jump, natural regen | Registry, StatService |
| AppearanceService | validate creation, build descriptions, hair | Race/Appearance defs, HairBuilder |
| CharacterService | join → create → spawn → respawn | most of the above |
| NPCService / NPCAnimator | NPC spawn, AI, LOD | Combat*, WorldGen, AppearanceService |
| Client controllers | input, camera, visuals, UI | Net, Shared config |

---

## 5. Development roadmap

Each milestone ends with something **playable and tested** before the next begins.

| # | Milestone | Key deliverables | Exit criteria |
|---|---|---|---|
| **1** | **Foundation** *(this delivery)* | Rojo project, camera, movement (walk/run/jump/dodge), stamina, health, character creation, runtime terrain, real-time combat (light/heavy/directional/block/parry/dodge/stagger), 4 weapons + shield, use-based stats, DataStore persistence with session locks, sparring dummies, hostile raiders | 2 players can create characters, fight raiders and each other outside the safe zone; stats persist across rejoin |
| 2 | Survival | Hunger, thirst, fatigue/sleep, temperature/exposure; inventory v1 (stacks, weight, slots); food/water items; body-part damage model (7 parts) with bleeding & basic treatment; replace natural regen | A player can starve, bleed out, bandage, and recover |
| 3 | World generation | **Studio plugin** generator with UI: seed, size, biomes, mountains, rivers, lakes, caves, ruins, resources, vegetation, settlement/NPC spawn markers, difficulty zones; preview/regenerate/save/load configs; chunk-based; runtime + pregenerated modes | Same seed + settings reproduce the same world; a 4k×4k world generates in Studio without timeouts |
| 4 | Crafting & building | Resource nodes (mine/chop/gather/hunt), refining, stations, recipes with time & quality, durability; equipment visuals & armor; building placement (grid/rotate/upgrade/dismantle), storage, ownership & permissions; bows/crossbows | Gather → craft a weapon → build a walled hut with a chest that persists |
| 5 | NPCs & world simulation | Factions (territory, reputation, alliances), jobs and routines, merchants, patrols, raids, hunting, background (abstract) simulation, world events, PathfindingService | Factions trade, patrol and raid without players nearby; reputation changes outcomes |
| 6 | Multiplayer & persistence hardening | Server-side movement anti-cheat, lag-compensated hit validation, player trading UI, shared settlements, world-slot persistence, MemoryStore cross-server features | Exploit test checklist passes; settlement survives server restart |
| 7 | Advanced systems | Dismemberment & prosthetics, scars/tattoos/advanced customization, authored animations & SFX, weather, performance pass | Lose an arm, fit a prosthetic, keep fighting |
| 8 | Release prep | Profiling (MicroProfiler, memory), mobile UI/touch controls, onboarding, compliance (age rating, text filtering audit), monetization *hooks* (cosmetic only) | Stable 20-player soak test, no P1 bugs |

**Monetization prep (no monetization yet):** cosmetic-only. Planned hooks: `PlayerData.cosmetics` (owned cosmetic IDs), a `CosmeticsService` that checks game passes via `MarketplaceService:UserOwnsGamePassAsync`, and `ProcessReceipt` for future developer products (e.g. name change, extra character slot). Nothing that affects survival or combat will ever be sold.

---

## 6. The most difficult systems (ranked)

1. **Dismemberment with a working controller (M7).** Roblox characters depend on joints. Plan: keep the R15 rig, hide the real limb (`Transparency = 1`, `CanCollide = false`), spawn a detached physics copy for the visual, then apply gameplay penalties through stats and animations. Prosthetics are accessories welded in place of the hidden limb. Never destroy joints on a living player.
2. **Background world simulation at scale (M5).** We can't run hundreds of NPC brains. Plan: three LOD tiers. *Active* NPCs near players run full AI. *Nearby* NPCs run cheap state machines at a low tick rate. *Abstract* groups exist only as data and advance with coarse timesteps ("caravan moved 400 studs, traded 20 iron"). They become real models when a player approaches.
3. **Fair melee combat over latency (M1 → M6).** The server sees the attacker and target ~100 ms in the past. Milestone 1 uses server-side box sweeps with a reach tolerance. Milestone 6 adds position history (rewind targets by the attacker's ping) for fairer hits.
4. **Procedural terrain inside voxel limits (M3).** Must be chunked, deterministic and budgeted (see §7).
5. **Persistence of shared, mutable world state (M4/M6).** Settlements are owned by many players, may be edited from several servers, and must survive crashes. See §8.
6. **Economy balance (M5).** Regional supply/demand can spiral. Prices need clamping and data-driven tuning.

---

## 7. How procedural terrain generation works

**Core idea:** terrain = a deterministic function of `(seed, settings, x, z)`.

1. `Random.new(seed)` creates fixed offsets for several noise layers. `math.noise` (Perlin) is deterministic, so the same seed and settings always produce the same terrain.
2. Layers (implemented in `TerrainGenerator`):
   - **Base height**: fractal noise (fBm, several octaves) for rolling land.
   - **Mountains**: *ridged* noise (`1 - |noise|`) sharpened, then gated by a large-scale **mask** so mountains form ranges instead of covering everything.
   - **Detail**: small high-frequency bumps.
   - **Moisture**: picks desert / scrub / grassland surface materials.
   - **Slope**: cliffs become rock; steep sand becomes sandstone.
   - **Spawn plateau**: terrain is smoothly flattened around the spawn.
   - *(Milestone 3)* rivers via carved flow paths, lakes via basins below water level, caves via 3D noise subtraction, ruins/resources/settlements/NPC spawns via seeded Poisson-disc placement per biome.
3. **Chunking:** the world is split into 64×64-stud columns. Each chunk computes heights once, builds `materials[x][y][z]` and `occupancy[x][y][z]` arrays, and makes **one** `Terrain:WriteVoxels` call. Partial occupancy at the surface gives smooth slopes.
4. **Time slicing:** chunks generate nearest-first, one per frame (`task.wait()`), so the server never freezes. Players spawn once the spawn area is ready.

### Studio generation vs runtime generation

| | **Studio (edit time, M3 plugin)** | **Runtime (server start, M1 default)** |
|---|---|---|
| When | Once, in Studio, by you | Every time a server starts |
| World size | Larger (several thousand studs) | Smaller (default 1024×1024; seconds to generate) |
| Startup time | Instant (terrain saved in the place) | A few seconds before players can spawn |
| Hand editing | Yes: sculpt, place towns and dungeons on top | No: overwritten each start |
| Different worlds per server | No (one place = one world) | Yes (seed per server / world slot) |
| Place file size | Grows with terrain | Small |
| Studio timeouts | Plugin must yield between chunks (it will) | N/A |

**Recommended use:** build the *main* hand-polished world in Studio with the plugin (`World.Mode = "Pregenerated"`). Use runtime generation for procedural *expeditions* or private-server worlds where each seed is a fresh map.

**Honest limits:** Roblox terrain is not an infinite procedural mesh. Unloading terrain chunks on the server mostly helps CPU, not memory, while players are spread out. StreamingEnabled already streams terrain to clients. So we keep worlds bounded and use runtime chunk generation for *creation*, not continuous infinite streaming.

---

## 8. How multiplayer is supported from the start

Milestone 1 is already multiplayer. There is no "single-player mode" to port later.

- **Server authority:** combat outcomes, stamina, speed, jump height, equipment, stats and saves are computed on the server only. The client sends **intent** (`RequestAttack("Light", "Overhead")`), never results.
- **Every remote is validated** (types, ranges, ownership) and **rate-limited** per player per remote.
- **Same rules for players and NPCs:** both are `Combatant`s, so PvE and PvP share one engine.
- **PvP rules:** enabled, but no player-vs-player damage inside the waystone safe zone. Factions and outlaw status come in M5.
- **Replication strategy:** state lives in Attributes (cheap, automatic). Events that need animation (`AttackStarted`) go only to players within 250 studs.
- **Persistence model:**
  - **Per player (DataStore, global):** character, appearance, stats, loadout/inventory, currency, survival stats, injuries, prosthetics. Session-locked so two servers can't write the same save.
  - **Per world slot (DataStore, M4/M6):** settlements, buildings, storage contents, world seed/config. Each server binds to one world slot (public world A/B/C, or a private server's own slot). One server owns a slot at a time (lock), so writes never conflict.
  - **Per server (memory only):** NPC positions, active fights, dropped loot, temporary events. These regenerate on restart.
  - **Cross-server (MemoryStore, M6):** world-event broadcasts, server browser, trade listings.
- **Solo play:** join a private server (or an empty public one). The game logic is identical.
- **Capacity targets:** 12-20 players per server, ≤60 active NPCs near players, world ≤ ~4k studs runtime.
