# Untamed Lands: Day-by-Day Plan

We build this game one small, finished step at a time, so you learn as you go and nothing breaks in ways you can't follow.

## The rules
1. **One goal per day.** A "day" is one work session. Take two real days if you want; there is no deadline.
2. **Nothing moves forward until it's tested.** Every day ends with a test checklist. If something fails, we fix it *that day*.
3. **The self-test must stay green.** Every Play in Studio prints `[SelfTest] N/N checks passed`. Each new feature adds its own checks.
4. **You touch the code every day.** Each day includes a small hands-on exercise, so you understand the code, not just copy it.
5. **Small changes.** Each day changes a few files at most, so when something breaks we know where to look.

## How each day works
| Step | Who | What |
|---|---|---|
| 1. Goal | me | What we're building today and why |
| 2. Code | me | New/changed files, each explained, written and statically checked |
| 3. Sync | you | Rojo syncs the files into Studio (or copy the changed files) |
| 4. Learn | you | Short code tour: "open this file, notice this" |
| 5. Exercise | you | One small change you make yourself |
| 6. Test | you | Press Play, check the SelfTest output, run the checklist |
| 7. Report | you → me | "All green", or paste the red/FAIL lines and describe what you saw |
| 8. Fix | me | Repairs until the checklist passes. Only then: next day |

---

## Phase 1: A solid foundation (Days 1-3)
The Milestone 1 code exists but has only been partly tested. We confirm every part works before building on it.

| Day | Goal | You learn |
|---|---|---|
| **1** | **Health check: automatic self-test + project tour** | How the project is organised; Script vs LocalScript vs ModuleScript; how to read Output |
| 2 | Combat & raiders verified; tune combat feel | How the server decides a hit; RemoteEvents; why the client can't be trusted |
| 3 | Saving verified in a published place | DataStores, session locks, why we never save from the client |

## Phase 2: A bigger, better map (Days 4-10)
| Day | Goal | You learn |
|---|---|---|
| 4 | Double the world (1 km → 2 km), measure generation time and memory | Chunks, voxels, performance budgets (Developer Console) |
| 5 | Biomes v2: distinct desert / scrubland / grassland / badlands regions | Noise layers, seeds, blending |
| 6 | Lakes and rivers | Carving terrain, water voxels |
| 7 | Rocks and dead trees scattered by biome | Instance budgets, deterministic placement with `Random` |
| 8 | World Generator **Studio plugin** v1: Generate / Preview / Regenerate in edit mode | Writing plugins, edit-time vs runtime generation |
| 9 | Plugin v2: settings panel + save/load configurations | Plugin UI, plugin settings |
| 10 | Grow to ~4 km with the plugin; ruins and points of interest | Streaming, landmarks for navigation |

## Phase 3: AI NPCs that actually function (Days 11-18)
| Day | Goal | You learn |
|---|---|---|
| 11 | NPC "brain" framework: a reusable state machine; port the raider to it | State machines, separating *deciding* from *doing* |
| 12 | Pathfinding: NPCs walk around rocks and up hills | PathfindingService, waypoints, stuck detection |
| 13 | Senses: sight cone, line of sight, hearing combat noise | Raycasts, dot products, perception |
| 14 | Combat AI v2: spacing, flanking, retreat when hurt, use of dodge | Utility scoring ("pick the best action") |
| 15 | Daily routines tied to the day/night clock: work, eat, sleep | Schedules, time-driven behaviour |
| 16 | Factions & relationships: who is hostile to whom, reputation | Data-driven relationships |
| 17 | Groups: patrols and raider bands that move together | Squad leaders and followers |
| 18 | Simulation LOD: 50+ NPCs without lag (active / nearby / abstract) | Profiling with the MicroProfiler |

## Later phases (planned day-by-day when we get there)
- **Survival:** hunger, thirst, sleep, inventory, injuries, bleeding, medicine
- **Crafting & building:** gathering, recipes, stations, settlement building, ownership
- **Economy & factions:** merchants, prices, trading between players
- **Advanced:** dismemberment, prosthetics, authored animations, weather, sound
- **Release:** mobile controls, polish, anti-exploit hardening, compliance

Progress is recorded in `DEVLOG.md` at the end of each day.
