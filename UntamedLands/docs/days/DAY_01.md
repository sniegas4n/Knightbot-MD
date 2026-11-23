# Day 1: Health check (automatic self-test + project tour)

**Goal:** confirm the Milestone 1 foundation works, using automatic tests, and get comfortable finding your way around the project.

**Time:** about 45-60 minutes.

---

## 1. What's new today
| File | What it is |
|---|---|
| `ServerScriptService/Server/Debug/SelfTest` (new ModuleScript) | 15 automatic checks that run every time you press Play in Studio |
| `Shared/Config/GameConfig` (1 line added) | `GameConfig.Debug.RunSelfTests = true` switch |
| `Server/Main` (6 lines added) | Starts the self-test, in Studio only |

The self-test checks: all remotes exist, weapon/race data is valid, saves can be validated and repaired, stat formulas, name validation, terrain determinism, the spawn, the preview rig, the dummies, and a **real combat test** (two temporary fighters high above the map: hit, block, parry).

## 2. Sync
Rojo is connected, so the files appear automatically. Check that `ServerScriptService → Server → Debug → SelfTest` exists in the Explorer.

## 3. Test: run the self-test
1. Open **View → Output** (keep it open from now on).
2. Press **Play**.
3. Wait about 15 seconds. You should see lines like:
   ```
   [SelfTest] Running checks (Studio only)...
   [SelfTest] PASS  Every remote exists with the right type
   ...
   [SelfTest] 15/15 checks passed
   ```
4. **Report back:** either "15/15 passed", or copy every `FAIL` line and any red error text.

## 4. Learn: a 10-minute code tour
Open these in order. You don't need to understand every line; just notice the things listed.

1. **`ServerScriptService/Server/Main`**: the *only* server Script. Notice it does nothing except `require` services and call `init()` then `start()` on each. All the real code lives in ModuleScripts.
   - *Script* = runs on the server. *LocalScript* = runs on one player's computer. *ModuleScript* = a library that only runs when something `require`s it.
2. **`Shared/Config/WeaponDefinitions`**: weapons are just tables of numbers. The combat code reads these; no weapon is hard-coded anywhere. This is called *data-driven design*.
3. **`Shared/Modules/Net`**: every RemoteEvent is listed in one table at the top. Notice `rate = 8`: the server ignores more than 8 attack requests per second from one player (anti-spam).
4. **`Server/Combat/CombatService`**: read only the big comment at the top ("Flow of an attack"). Notice step 1: the client sends *what it wants to do*, never *what it hit*.
5. **`Server/Debug/SelfTest`**: read the "HOW A TEST WORKS" comment. You'll be writing one yourself in the exercise.

## 5. Exercise: make a change yourself
**Part A: tune a number and see the effect.**
1. Open `Shared/Config/WeaponDefinitions`. Find `RustedMachete` → `light` → `damage = 13`.
2. Change it to `damage = 40`. Save (Rojo syncs it).
3. Press Play, equip the machete (key **2**) and hit a sparring thrall. The numbers should be about 3× bigger.
4. **Change it back to 13.**

**Part B: write your first test.**
In `Server/Debug/SelfTest`, find `local function configTests()` and add this block just before its final `end`:
```lua
	test("My first test: the maul is the slowest weapon", function()
		local maul = WeaponDefinitions.Items.ScrapMaul
		local machete = WeaponDefinitions.Items.RustedMachete
		expect(maul.heavy.windup > machete.heavy.windup, "the maul should wind up slower than the machete")
	end)
```
Press Play. The total should now be **16/16**. For a moment, try changing `>` to `<` to see what a FAIL looks like, then change it back.

## 6. Day 1 checklist (all must be ticked)
- [ ] Output shows `[SelfTest] 16/16 checks passed` (15 + your test)
- [ ] No red errors in Output
- [ ] Character creation works and you spawn on the waystone
- [ ] Hitting a thrall shows damage numbers; the machete change was visible and has been reverted
- [ ] You can explain in one sentence why the client sends "I attack" instead of "I hit for 13 damage"

When everything is ticked, tell me **"Day 1 done"** and paste the last SelfTest line. Day 2: combat and raiders, verified and tuned.
