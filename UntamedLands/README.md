# Untamed Lands

An original open-world survival RPG for **Roblox**, inspired by the systemic design of Kenshi. Every player controls one character in a persistent, real-time, multiplayer world with no pause or fast-forward.

> Current state: **Milestone 1 (Foundation) written, not yet play-tested.** See `docs/DEVLOG.md`.

## Quick start
```bash
cd UntamedLands
```
```bash
rojo serve
```
Then, in Studio: open an empty Baseplate, delete the Baseplate part, connect the Rojo plugin, set **Avatar Type = R15**, and press Play.
Full instructions (including manual copy without Rojo): `docs/02_MILESTONE_1_GUIDE.md`.

## Documents
- `docs/LEARNING_PLAN.md`: day-by-day plan (start here); daily guides in `docs/days/`
- `docs/01_PROJECT_ANALYSIS.md`: analysis, Roblox limitations, architecture, folder structure, roadmap, hardest systems, terrain generation, multiplayer design
- `docs/02_MILESTONE_1_GUIDE.md`: setup, how scripts connect, controls, test plan, troubleshooting
- `docs/DEVLOG.md`: development log, completed and unfinished features, known bugs

## Layout
```
src/ReplicatedStorage/Shared       config (data) + shared modules
src/ServerScriptService/Server     server services (Main = only Script)
src/StarterPlayer/...Client        client controllers (Main = only LocalScript)
```
