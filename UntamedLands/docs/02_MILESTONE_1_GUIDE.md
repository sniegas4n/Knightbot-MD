# Milestone 1: Foundation (setup, wiring and testing)

> **Status: written, not yet run.** This code was written without access to Roblox Studio and has **not been executed**. It was checked for block/bracket balance and cross-checked by reading, but expect a short round of fixes in your first play-test. Report any Output errors and we'll fix them before Milestone 2.

## What Milestone 1 contains

| Feature | Where |
|---|---|
| Over-the-shoulder camera, mouse-lock aiming, zoom, collision, gamepad look | `CameraController` |
| Walk / run (stamina) / jump (stamina) / dodge (i-frames) | `MovementController`, `VitalsService`, `CombatService.dodge` |
| Health, stamina, winded state, slow out-of-combat recovery | `VitalsService`, HUD |
| Character creation: name (filtered), 3 original peoples, skin, 7 hairstyles, hair colour, clothing dyes, 4 body sliders, live preview | `CharacterCreationController`, `AppearanceService`, `CharacterService` |
| Runtime procedural terrain (seeded, chunked, biomes, mountains, water) | `TerrainGenerator`, `WorldGenService` |
| Real-time combat: light/heavy, 4 swing directions, block, parry→counter, guard break, stagger, armor, cleave, safe zone | `CombatService`, `Combatant` |
| Weapons: fists, machete, spear, maul, buckler (data-driven, part-built visuals) | `WeaponDefinitions`, `WeaponModelBuilder` |
| Use-based progression (no classes) | `StatService`, `StatMath` |
| Persistence with session locking, retries, validation, versioning | `PlayerDataService`, `DataSchema` |
| NPCs: sparring thralls + hostile Dust Raiders (same combat engine) | `NPCService`, `NPCAnimator` |
| Day/night cycle and atmosphere (no time controls) | `EnvironmentService` |

---

## 1. Installing into Roblox Studio

### Option A: Rojo (recommended)
1. Install Rojo 7.4+ (https://rojo.space) and the Rojo Studio plugin.
2. In a terminal:
   ```bash
   cd UntamedLands
   ```
   ```bash
   rojo serve
   ```
3. Open a **new Baseplate** in Studio. **Delete the Baseplate part** (and the default SpawnLocation if present).
4. In the Rojo plugin, click **Connect**. All scripts appear in their services.
5. To produce a place file instead: `rojo build -o UntamedLands.rbxlx`, then open it.

### Option B: Manual copy
Create these objects in Studio (the name must match exactly; the type is in brackets). Paste each file's contents.

| Studio location | Object | Source file |
|---|---|---|
| ReplicatedStorage | `Shared` (Folder) → `Config` (Folder), `Modules` (Folder) | – |
| ReplicatedStorage.Shared.Config | `GameConfig`, `StatDefinitions`, `RaceDefinitions`, `AppearanceOptions`, `WeaponDefinitions`, `NPCDefinitions` (ModuleScripts) | `src/ReplicatedStorage/Shared/Config/*.luau` |
| ReplicatedStorage.Shared.Modules | `Net`, `Validate`, `Signal`, `StatMath`, `HairBuilder`, `WeaponModelBuilder`, `DodgeMotion` (ModuleScripts) | `src/ReplicatedStorage/Shared/Modules/*.luau` |
| ServerScriptService | `Server` (Folder) containing `Main` (**Script**) | `Server/Main.server.luau` |
| ServerScriptService.Server | Folders `Core`, `PlayerData`, `Combat`, `Progression`, `WorldGeneration`, `NPCs` with their ModuleScripts | `src/ServerScriptService/Server/<Folder>/*.luau` |
| StarterPlayer.StarterPlayerScripts | `Client` (Folder) containing `Main` (**LocalScript**), Folders `Controllers` and `UI` with ModuleScripts | `src/StarterPlayer/StarterPlayerScripts/Client/...` |
| StarterPlayer.StarterCharacterScripts | `Health` (**Script**, intentionally empty) | `StarterCharacterScripts/Health.server.luau` |

File-suffix rule: `X.server.luau` → Script, `X.client.luau` → LocalScript, `X.luau` → ModuleScript named `X`.

### Required Studio settings (both options)
1. **Game Settings → Avatar → Avatar Type: R15.** (Combat poses and hair target R15 joints.)
2. **Workspace → StreamingEnabled: true** (Rojo sets this; check it).
3. **Players → CharacterAutoLoads: false** (Rojo sets this; `Main` also sets it at runtime).
4. **Lighting → Technology: Future** (recommended for the atmosphere; optional).
5. To test saving: publish the place, then **Game Settings → Security → Enable Studio Access to API Services**. Without this the game runs in **test mode**: temporary data, a red warning, nothing saved (by design, so a test can never wipe a real save).
6. Optional: add a Number attribute `WorldSeed` to Workspace to change the world.

---

## 2. How the scripts connect

```
SERVER                                              CLIENT
Main.server ─ init() then start() for each:         Main.client ─ init(controllers), CharacterAdded fan-out
 PlayerDataService  (load/lock/save)                 CameraController     (aim, zoom, shake, mouse history)
 StatService        (XP, StatsUpdated)               AnimationController  (procedural poses, tag "Combatant")
 WorldGenService    (terrain, Waystone spawn)        HUDController        (bars, feed, stats, damage text)
 EnvironmentService (lighting, clock)                MovementController   (sprint, dodge)
 CombatService      (remotes → attack/block/dodge)   CombatController     (attacks, block, equip)
 VitalsService      (stamina/speed/jump 10 Hz)       CharacterCreationController (UI + preview)
 CharacterService   (session, creation, spawn)
 NPCService         (dummies, raiders, AI loop)
```

**Join sequence**
1. `PlayerDataService` loads (and locks) the save.
2. The client calls `GetSessionState` (RemoteFunction). The server waits for the profile and answers `{needsCreation, temporary, name}`.
3. New player: the creation UI opens and sends `SubmitCharacter(payload)`. The server runs `AppearanceService.sanitize` and `TextService` filtering, applies race stat modifiers, saves, then calls `CharacterService.spawn`.
4. `spawn` waits for the spawn area to generate, then calls `LoadCharacterWithHumanoidDescription`. On `CharacterAdded` it sets up hair, health, the `Combatant`, the registry tag and the weapons.
5. On death: respawn after 6 s at the Waystone.

**Attack sequence:** see the header of `CombatService.luau`. In short: client intent → server validates → `AttackStarted` broadcast (for animation) → windup → server box sweep → dodge/parry/block/hit → `CombatFeedback` to the people involved → recovery.

**Replicated character Attributes** (set by the server, read by clients): `Stamina`, `MaxStamina`, `CombatState`, `WeaponId`, `OffhandId`, `Winded`.

---

## 3. Controls

| Input | Action |
|---|---|
| WASD / Space | move / jump (costs stamina) |
| Left Shift (hold) | run (drains stamina) |
| Left click | light attack |
| R | heavy attack (staggers on hit; strong vs guards) |
| Right mouse (hold) | guard. Raise it **just before** a hit lands to **parry** (attacker staggered, your next hit within 1 s deals ×1.5) |
| Mouse flick before attacking | swing direction: sideways / up = overhead / down = thrust |
| Q | dodge (i-frames) in movement direction, backwards if standing |
| 1-4 | Fists / Rusted Machete / Bone Spear / Scrap Maul |
| 5 | toggle Hide Buckler (only with fists or one-handed weapons) |
| C / H / Left Alt | character stats / help / free cursor |
| Gamepad | R2 light, R1 heavy, L2 guard, B dodge, L3 run toggle, D-pad weapons |

---

## 4. Test plan

Run each test and tick it off. **Studio → Test → Play** for solo; **Test → Clients and Servers (2 players)** for multiplayer.

### A. Startup
- [ ] Output shows `[UntamedLands] Server started`, then `[WorldGen] Spawn area ready...`, then `[WorldGen] Generated 256 chunks...`.
- [ ] No red errors in Output (server or client).
- [ ] Terrain: hills, water in low areas, sand/grass/rock variation, flat plateau with a stone slab and a ring of standing stones.

### B. Character creation
- [ ] The creation screen appears with a rotating preview (drag it).
- [ ] Changing People changes skin options and slider defaults. Colours and hair update in the preview.
- [ ] Names: `ab` is rejected (too short), `Zed99` is rejected (digits), `Kara Dune` is accepted.
- [ ] After "Walk into the wastes" you spawn on the Waystone with your name above your head, chosen colours, hair and a weapon.

### C. Movement & stamina
- [ ] Shift-run is faster and drains the stamina bar. At 0 the bar turns red ("WINDED") and you slow down until it refills to 25%.
- [ ] Jumping costs stamina. With very low stamina you can't jump.
- [ ] Q dodges in your movement direction. It won't fire with < 22 stamina.

### D. Combat (sparring thralls next to the spawn)
- [ ] Left click swings (arm animation plays) and damage numbers appear on the thrall.
- [ ] Each weapon (1-4) shows its model in hand. The spear hits from further away; the maul is slow and hits several thralls.
- [ ] R heavy attack does roughly double damage and costs more stamina.
- [ ] Flicking the mouse up before clicking gives an overhead swing; down gives a thrust.
- [ ] After a few minutes, `C` shows Blades/Strength etc. rising and the feed shows "Blades increased to 2".

### E. Combat vs raiders (walk ~120 studs out; red-shirted "Dust Raider")
- [ ] The raider approaches, attacks and sometimes guards ("Blocked N").
- [ ] Blocking their swing: you take reduced damage and lose stamina. If you run out of stamina, "GUARD BROKEN" and you are staggered.
- [ ] Raising the guard right before their swing lands: "PARRY!" and the raider freezes briefly.
- [ ] A well-timed dodge shows "Evaded".
- [ ] Run away past ~90 studs from its home: it returns home.
- [ ] Die: "YOU HAVE FALLEN", then you respawn after about 6 s. The raider respawns about 45 s after being killed.

### F. Multiplayer (Clients and Servers, 2 players)
- [ ] Each player sees the other's swings animate and weapons in hand.
- [ ] Inside the standing-stone ring, hitting the other player shows "The waystone's peace holds here" and does no damage.
- [ ] Outside the ring, PvP damage works, including blocking/parrying each other.

### G. Persistence (published place with API access enabled)
- [ ] Create a character, raise a stat, leave, rejoin: no creation screen, same name and appearance, stats kept, same weapon equipped.
- [ ] In Output: no `[PlayerData]` warnings during normal play.

---

## 5. Potential bugs & where to look

| Symptom | Likely cause | Fix |
|---|---|---|
| Characters spawn R6 / arms don't animate / hair floats | Avatar Type isn't R15 | Game Settings → Avatar → R15 |
| Stuck on "..." after creating | `LoadCharacterWithHumanoidDescription` failed | Check Output for `[Character]` warnings; the code falls back to `LoadCharacter` |
| Arms don't swing; Output says "No R15 shoulder/waist joints found" | Rig isn't R15 or uses unexpected joint names | Check Avatar Type is R15; send the warning text |
| Preview says "Preview unavailable" | `CreateHumanoidModelFromDescription` failed (asset service hiccup) | Rejoin; check the Output warning |
| Raiders slide without walking animation | Default animation IDs didn't load | Replace IDs in `NPCAnimator.AnimationIds` (see that file's header) |
| Can't hit anything | Hitbox sees nothing: check that target parts have `CanQuery = true` | Don't set `CanQuery = false` on character body parts |
| Red "TEST MODE" warning | DataStore unavailable (unpublished place or API access off) | Expected in tests; see setup step 5 |
| Camera jitters on steep slopes | root CFrame is set every frame | Lower sensitivity; M6 adds smoothing |
| "Rate limit hit" warnings | Remote spam (auto-clicker or a bug) | Expected protection; investigate if it happens in normal play |

---

## 6. Configuration quick reference
All tuning lives in `ReplicatedStorage/Shared/Config/GameConfig`:
- Movement and stamina costs: `GameConfig.Movement`, `GameConfig.Stamina`
- Parry window, PvP toggle, safe zone radius: `GameConfig.Combat`
- World seed, size (`RadiusInChunks`), heights, water: `GameConfig.World`
- Day length: `GameConfig.Environment.DayLengthMinutes`
- Faster progression for testing: `GameConfig.Progression.GlobalRate = 10`
- Weapons: `WeaponDefinitions` (copy an entry to add a weapon)
- NPC stats and spawns: `NPCDefinitions`
