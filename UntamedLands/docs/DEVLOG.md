# Development Log: Untamed Lands

## 2026-11-24: Day 1 test run: 15/15 self-tests passed; thrall pose fix

**Result:** `[SelfTest] 15/15 checks passed`. The world generated 256 chunks in 10.6 s (spawn area ready in 6.5 s).
**Expected warnings (not bugs):** DataStore 403 (Studio API access off, so temporary data is used; covered on Day 3); Roblox Assistant plugin version notice (restart Studio); `rbxassetid://203785492` asset type mismatch (not referenced by our code; engine/plugin side).
**Bug:** client warned "No R15 shoulder/waist joints found" on both Sparring Thralls, so they had no attack/block poses.
**Likely cause:** they were the only rigs with an anchored HumanoidRootPart (raiders, unanchored, were fine). Anchoring conflicts with the upgraded AnimationConstraint joints.
**Fix:**
- Thralls are no longer anchored: WalkSpeed 0, JumpHeight 0, server network owner, and a tether that puts them back if shoved more than 3 studs.
- VitalsService no longer re-enables jumping on immobile combatants.
- The AnimationController warning now lists missing parts and the joint classes present, for diagnosis if this happens again.
- The SelfTest dummy check now fails if any NPC root is anchored.
**Status:** written and statically checked; waiting for re-test.

## 2026-11-23: Day-by-day plan adopted; Day 1 prepared

- Attack-pose fix confirmed working by the project owner in Studio.
- New way of working: one goal per day, tested before moving on (`LEARNING_PLAN.md`).
- **Day 1 (`days/DAY_01.md`)**: added `Server/Debug/SelfTest`, 15 automatic Studio-only checks (config data, save validation/repair, name validation, terrain determinism, spawn, preview rig, dummies, and an end-to-end combat test of hit, block and parry). Enabled via `GameConfig.Debug.RunSelfTests`.
- **Status:** written and statically checked; waiting for the Day 1 test report.

## 2026-11-23: Fix: arms did not swing during attacks (first play-test bug)

**Reported:** no arm swing for any character (players or NPCs) when attacking.
**Cause:** Roblox's Avatar Joint Upgrade (now live) builds R15 characters with `AnimationConstraint` joints instead of `Motor6D`. `AnimationController` only looked for `Motor6D`s, found none, and silently skipped every rig. Also, `C0` on the new joints cannot be changed by scripts, so the old approach could not work anyway.
**Fix:** `AnimationController` now:
- finds joints of either type (`Motor6D` or `AnimationConstraint`) by name, or by the part they move;
- layers pose offsets onto each joint's `Transform` in `RunService.PreSimulation` (after the Animator), the method Roblox recommends for procedural animation. Offsets stack on walk/idle animations and can't accumulate frame to frame;
- warns in Output if a combatant still has no usable joints after 8 seconds.
**Status:** written, not yet run in Studio.

## 2026-11-23: Milestone 1 (Foundation) written

**Summary:** Project analysis, architecture and roadmap documented (`01_PROJECT_ANALYSIS.md`). Milestone 1 implemented as a Rojo project: 37 Luau files (~5,900 lines), 1 server Script, 1 client LocalScript and everything else in ModuleScripts.

**Verification done:**
- All files pass a block/bracket balance check (custom tokenizer: function/if/do/end, brackets, strings, long comments).
- Require paths cross-checked against the folder layout.
- Remote argument order cross-checked between server senders and client listeners.

**Verification NOT done (important):**
- The code has **not been run in Roblox Studio**. Running downloaded tooling (Rojo, the Luau analyzer) was not permitted in the build environment, so there was no type-check or play-test. Expect some first-run fixes.

**Decisions:**
- UI is built in code instead of placed in StarterGui (diffable, rename-proof).
- Hair and weapons are built from parts, so there are no catalog/asset IDs and every look is original.
- Combat animations are procedural (Motor6D C0 offsets) until authored animations exist.
- Players' own Roblox avatars are not used; everyone is a character of the world.
- A temporary natural health regen (0.5 HP/s after 12 s without damage) exists until Milestone 2 medical replaces it.
- Studio without DataStore access uses temporary, never-saved data. Live servers kick instead of using blank data.

---

## Feature status

### Completed (written, awaiting first play-test)
- [x] Rojo project structure and service/controller architecture
- [x] Net layer: central remotes, per-player rate limits, safe handlers
- [x] Over-the-shoulder camera (mouse lock, zoom, collision, gamepad, shake)
- [x] Walk / run / jump / dodge with server-owned speed & jump height
- [x] Stamina, winded state, health, placeholder out-of-combat regen
- [x] Character creation (name filter, 3 peoples, skin, 7 hairstyles, colours, 4 proportions, live preview)
- [x] Runtime procedural terrain (seed, chunked WriteVoxels, biomes, ridged mountains, water, spawn plateau)
- [x] Combat: light/heavy, directional swings, block, parry→counter, guard break, stagger, armor, cleave, reach validation, interrupts
- [x] Weapons: Fists, Rusted Machete, Bone Spear, Scrap Maul, Hide Buckler
- [x] Use-based progression for 5 attributes + 13 skills (decimal levels, diminishing returns)
- [x] DataStore persistence: session lock, retries, budget checks, versioning/migrations, reconcile, sanitize, autosave, BindToClose
- [x] NPCs: sparring thralls (regenerating), Dust Raiders (chase/attack/block/leash), dormant when no player is near
- [x] PvP with waystone safe zone
- [x] Day/night cycle, atmosphere, clouds, wind

### Not started / planned
- [ ] Milestone 2: hunger, thirst, fatigue/sleep, temperature, inventory, body-part injuries, bleeding, medicine, food spoilage
- [ ] Milestone 3: Studio World Generator plugin (preview, save/load configs, rivers, lakes, caves, ruins, resources, vegetation, spawn markers)
- [ ] Milestone 4: gathering, crafting, armor & equipment visuals, building, storage, ranged weapons
- [ ] Milestone 5: factions, jobs/routines, merchants, economy, raids, background simulation, pathfinding
- [ ] Milestone 6: movement anti-cheat, lag-compensated hits, player trading, world-slot persistence, MemoryStore features
- [ ] Milestone 7: dismemberment, prosthetics, scars/tattoos, authored animations, SFX/music, weather
- [ ] Milestone 8: mobile controls, profiling, compliance, cosmetic monetization hooks
- [ ] Mobile touch controls (keyboard/mouse and gamepad only for now)

---

## Known issues / risks

| ID | Severity | Description | Plan |
|---|---|---|---|
| K1 | High | Untested in Studio (see above) | First play-test, then fix |
| K2 | Medium | Clients own their character physics, so speed/teleport exploits are possible. The server sets WalkSpeed but doesn't yet verify actual movement. | Milestone 6: server movement validation |
| K3 | Medium | Melee hits use the server's view of positions (no lag compensation). High-ping players may see "hits" that miss. | Milestone 6: position history rewind |
| K4 | Low | Jump stamina relies on `Humanoid.StateChanged` firing on the server for client-owned characters, which can occasionally be missed. JumpHeight = 0 at low stamina still enforces the limit. | Re-evaluate in M6 |
| K5 | Low | Character-creation preview shows height exactly, but width/depth/head only approximately (applied on the real character). | M7 advanced customization |
| K6 | Low | NPC walk/run animation IDs are Roblox's default R15 IDs; they may need replacing (see `NPCAnimator`). | Replace with authored animations in M7 |
| K7 | Low | Character creation can't be repeated (one character per account). | Add "abandon character" flow later (M8) |
| K8 | Low | `AttackStarted` uses the attacker's distance to each player; players outside 250 studs never see the swing (intended), but a lot of spectators will multiply remote traffic. | Fine at 20 players; review in M6 |
| K9 | Info | HumanoidDescription scale values outside Roblox's avatar ranges may be clamped by the engine, reducing body variety. | Verify in play-test; adjust ranges |
