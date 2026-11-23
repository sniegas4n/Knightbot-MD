# Untamed Lands: Daily Plan

We build the game one small goal per day. A day is **done** only when its test checklist passes. If something breaks, the next day becomes a fix day. That's normal and counts as progress.

## How each day works (about 1 hour)
1. **Learn (10 min):** the idea behind today's goal, in plain words.
2. **Build (30-40 min):** small pieces of code, each explained. You make at least one change yourself.
3. **Test (10 min):** run the checklist in Studio and report the results.
4. **Recap (5 min):** what you learned, plus an optional mini-challenge.

## Rules
- One goal per day. No skipping ahead while something is broken.
- After every finished day, keep a backup: commit to GitHub, or copy the project folder.
- Short on time? Do half a day. Small steady steps beat big rushed ones.

---

## Phase 1: A bigger world (Days 1-5)
| Day | Goal | You'll learn |
|---|---|---|
| 1 | Project tour + double the map size | How the project is organised, config files, seeds |
| 2 | Scatter rocks, dead trees and shrubs (seeded) | Creating instances from code, seeded randomness, performance |
| 3 | Ruins and landmarks placed on flat ground | Searching terrain, reusing builder functions |
| 4 | World edge + performance check | Developer Console, memory, StreamingEnabled |
| 5 | Buffer / fix day | Debugging with Output and print statements |

## Phase 2: NPCs that feel alive (Days 6-14)
| Day | Goal | You'll learn |
|---|---|---|
| 6 | Rewrite the raider brain as a clear state machine (Idle, Patrol, Chase, Fight, Return) | State machines, the cleanest way to write AI |
| 7 | Pathfinding around hills and obstacles | PathfindingService, waypoints, getting unstuck |
| 8 | Sight and hearing: vision cone, line of sight, running makes noise; search the last-known position | Raycasting, dot products |
| 9 | Raider camps on the map (tents, campfire, patrol routes) | Combining world generation with AI |
| 10 | Group behaviour: raise the alarm, flee when badly hurt | Communication between NPCs |
| 11 | Neutral wanderers who travel between places and flee danger | Different behaviours on the same engine |
| 12 | Factions v1: who hates whom, NPCs fighting NPCs | Data-driven relationships |
| 13 | NPC budget: spawn near players, sleep far away | Optimisation and simulation LOD |
| 14 | Buffer / fix day | |

## Phase 3: Survival (Days 15-24)
Pick-up items → inventory panel → hunger and thirst → eating and drinking → wells and water → body-part injuries → bleeding and bandages → sleep and fatigue → buffer.

## Later phases (planned in detail when we get there)
- Phase 4: crafting and gathering
- Phase 5: building and settlements
- Phase 6: traders and economy
- Phase 7: Studio world-generator plugin
- Phase 8: dismemberment and prosthetics
- Phase 9: polish (animations, sound, weather)
- Phase 10: release prep

---

## Progress
| Day | Status | Notes |
|---|---|---|
| 0 | ✅ Done | Milestone 1 foundation running; arm swing fixed |
| 1 | ⏳ Next | |
