# FstreliBiciklina3D
Mostly vibe coded Godot game

## Testing rule
- **One command runs every check: `python tools/run_checks.py`** (on Windows, double click `tools\run_checks.bat`). It finds Godot by itself and remembers the path after the first time, so there is no path to type. It runs every `tools/*_check.gd`, each with its own empty save folder (your real settings, scores, meta coins and saved run are never touched), prints PASSED or FAILED for each one with the lines that explain a failure, kills a check that hangs, and writes `check_logs/summary.txt` and one log per check (send `summary.txt` back when something fails). `python tools/run_checks.py unlocks xp` runs only the checks whose name contains those words, `--list` lists them, `--full` uses the bigger seed and arena counts of the slow ones, `--lint` also runs gdlint and gdformat, `--godot PATH` sets the Godot path, `--help` shows the rest. Exit code 0 = everything passed.
- **While building an item, run only the checks that cover the code it touched** (for example `python tools/run_checks.py pickup rider`), not the whole suite, which takes about 14 minutes. The whole suite is for the gate items (B7.3, E3.1) and for when the owner asks for it. Decided with the owner on 2026-10-27.
- A new check is a file `tools/<name>_check.gd` that prints its problems and ends with `quit(0)` or `quit(1)`. The runner finds it by its name, so nothing else needs editing, and **a `.bat` is no longer needed**: this replaces the old rule that every check gets its own `.bat` next to it. The old `tools\run_*_check.bat` files still work and can be deleted later (item A2.7); notes below that name one are talking about the same check.
- Many item notes below say "written in a session without Godot, only gdformat and gdlint were run, so run the .bat once". On 2026-10-27 the whole suite was run headless with Godot 4.7 (results under "Roadmap audit" in the Early Alpha Roadmap): 41 of the 44 checks passed and the other three are listed there with their causes. What those items still wait for is the **in-game check** by a person, which no script can do.

## Roadmap history
- The long notes written after ticked roadmap items (what was built, decisions, checks run, what still waits for an in-game check) are in [`docs/ROADMAP_HISTORY.md`](docs/ROADMAP_HISTORY.md), grouped under the same milestone and section headings as here. A ticked item below keeps only its title.
- **Rule for new notes:** when an item is ticked, write its note (what was built, decisions, checks run, what still waits for an in-game check) in `docs/ROADMAP_HISTORY.md`, under the same milestone and section heading, with the item title as the entry heading. The README line keeps only the checkbox and the title, so the README stays short. Notes on open items that are still being worked on can stay in the README until the item is ticked.

## Running from the Godot editor
- The game starts in a 1280x720 window (the base size in `project.godot`). Fullscreen is built in: F11, or the FULLSCREEN row in the settings, and the choice is saved.
- If the game runs inside the editor's embedded game view, fullscreen and other window changes do not work there, because the game is not its own window. Turn off the editor's embedded game window option (in the game view toolbar) so the game runs in a separate window, or run an exported build.

## Secrets and credentials (this repository is public)
> **WARNING: never commit or push secrets.** Everything in this repository, including every old commit, is visible to the whole internet, and deleting a secret in a later commit does not remove it from the history. Once a key has been pushed, treat it as stolen and replace it.
- Never commit: API keys (including the game-to-website key from Milestone N), passwords, login or refresh tokens, Django `SECRET_KEY`, database or server credentials, SSH keys, `.env` files, code signing certificates, Godot encryption keys (`script_encryption_key` and the save encryption key), or a player's save and settings files.
- Keep secrets outside the repository: in environment variables or an untracked local file (for example `secrets.local.cfg` or `.env`, listed in `.gitignore` before the file is created), and in GitHub Actions secrets for CI. The repository only holds a template with fake values (for example `secrets.example.cfg`).
- Check before every commit: run `git status` and `git diff --staged` and read what is going in. If a key was pushed by mistake, tell the owner right away, replace the key first (the old one is burned), and only then clean the history.
- Godot warning: `export_presets.cfg` is tracked. If PCK encryption is ever switched on, its key is written into that file, so keep the key out of the tracked file (set it with the `GODOT_SCRIPT_ENCRYPTION_KEY` environment variable at export time, and leave the key field empty in the repository).
- The same rule applies to anyone working on this repository, including AI coding sessions: do not paste real keys into prompts, code, commit messages, docs or screenshots.
- The plan for automatic checks (secret scanning, push protection, a pre-commit hook and a CI check) is in "Keeping secrets out of the public repository" in Milestone N.

# Early Alpha Roadmap

> **Goal:** the smallest set of changes that turns the current build into a **playable, progressable roguelite**: a player starts a run, makes real choices on the way, wins or loses it, spends what they earned, and starts the next run with something different. Written on 2026-10-26 after reading the whole roadmap, `docs/`, `data/` and the run flow in `scripts/main.gd`, and after looking at the open branches. Anything that is not on this list waits until after the alpha (see "Not in the early alpha" at the end). An item here that also exists in a milestone below is the same work: tick both. Every item follows the testing rule above (a check with a `.bat` wherever it can be checked).

## The loop the alpha has to deliver

```
TITLE -> LOADOUT -> RUN: map (pick a node) -> fight -> upgrade pick -> map -> ... -> mid boss -> ... -> final boss
      ^                                                                                              |
      |                                          RUN SUMMARY (coins, XP) <---------------------------+
      +------------ UNLOCKS (spend coins) <-------------+
```

## Where the game stands today

**Works end to end:** a 10-floor run map from a seed, one generated arena per run, rounds with riders, caches, extraction and an ambush, a mid boss and a final boss, upgrade and shop screens, a run summary with meta coins and XP, the Unlocks page (buying), the Loadout page (starting perk), Continue, Daily Run, local leaderboard and challenges.

**What makes it feel scattered** (each one is an item below):

1. **The map nodes are labels.** Shop, rest, event and elite nodes all play the same ordinary round (Milestone D "Map Nodes" is all open), and the upgrade and shop screens come after *every* round whatever the node, so choosing a node changes almost nothing. The rain modifier is carried by the node but has no effect.
2. **What you earn barely changes the next run.** Only starting perks do anything. The six shop-item unlocks now change the shop (C3: an item stays out of every shop until it is bought), the weapon unlocks wait for Milestone C, and a level is only a number.
3. **Two branches are not merged.** `milestone-c/weapon-slots` (weapon slots, weapon choice on the Loadout page, the Dart Nerf Pistol; 21 files) and `roadmap/level-rewards` (XP about 7 times slower, so levels take many runs; its numbers contradict the "level 5 takes one or two runs" assumption of the melee lock on the weapons branch).
4. **Nobody has measured difficulty or length.** "Balance pass for the 10-round curve", "Tune round length", "Playtest the objectives" and "Playtest and balance" on the 144 m arena are all open, against a target of 20 to 30 minutes a run.
5. **The end of a run is a dead end.** The run summary only offers CLICK TO CONTINUE; spending the coins and starting the next run is a hunt through about ten title buttons.
6. **Some drops, upgrades and shop items do nothing for the weapon you hold** (added on 2026-10-27, from the owner). The starting Dart Nerf Pistol holds one dart, so ammo drops, the ammo reward of a cache, FREE DARTS and the other ammo-related offers have little or nothing to act on (B9).

### Built but not used by the game yet

> Found by reading the roadmap against the code on 2026-10-27, so that finished work does not get left out. Each of these is ticked (or partly ticked) in the milestones below but does nothing in play, or only part of what its item suggests. Each one also carries a **BUILT, NOT USED YET** (or **PARTLY BUILT**) marker at its own item. The right-hand column says which alpha item connects it.

| Built | What is missing | Alpha item |
|---|---|---|
| XP and levels (earned, saved, shown on the title screen and the run summary) | a level does not unlock or change anything, on purpose for the alpha (decided in C4, done) | after the alpha |
| Map node types `elite`, `shop`, `rest` and `event` (generated, drawn, named on the map screen) | the shop node is a screen since B2 and the rest node since B3; elite and normal still play the same ordinary round, and the `seed` that rest and event nodes carry is never read. Only the elite's harder content (10 to 12 riders, 40 % armoured) takes effect | B1, B3, B4 |
| The `rain` round modifier | the node carries it (`round_modifiers`), but nothing draws or does rain | B5 (switched off) |
| Weapon slots, the Dart Nerf Pistol, weapon choice on the Loadout page | built on `milestone-c/weapon-slots` and not merged, so `main` has none of it | A1 |
| The four weapon unlocks marked `planned` | the weapons do not exist; the Unlocks page shows them as SOON | after the alpha |
| `reload_started` and `reload_interrupted` signals | nothing listens to them (the slide and tilt follow `g.loading`); the sound and jolt on `reload_finished` are placeholders | after the alpha |
| The navigation grid cost (`ArenaGen.nav_cost`) | only a check calls it. There is no path search: riders and bosses steer by look-ahead and can get stuck in a dead end | after the alpha (rider variety) |
| The SHAKE AND FLASH setting (`fx_scale`) | covers camera shake, the hit flash and the damage flash only; the other screen effects do not exist yet | Milestone F10 |
| The outline code in `scripts/toon.gd` (`Toon.ENABLED = false`) | dead code until F12 removes it | Milestone F12 |
| The roundabout arena and all the street-coordinate code | only reachable with `--roundabout`, but every rider, boss and pedestrian function still carries both paths, and `arena_check` guards the roundabout against a golden file | decide after the alpha |

### Working order

> Work **one checkbox at a time**, in this order, not in the A to E order of the lists below (the lists group the work by topic; this is the order that keeps the game playable and every step checkable). Each checkbox gets its own branch (`roadmap/<id>-<short-name>`, for example `roadmap/b5-cut-event-and-rain`) built from an up-to-date `main`, and ends with: the headless checks of the code it touched (`python tools/run_checks.py <name>`, which Claude can run itself; the whole suite only at the gate items), the owner's in-game check, a tick in the list below (and in the milestone item it belongs to), and then the next one. The boxes live only in the lists below; this list only gives the order. The numbers in brackets are the sub-items to do in that step.

1. **A1** (A1.1 to A1.6): merge the weapon slots branch first, because B and C build on it and a late merge means conflicts in `main.gd` and the loadout code.
2. **A2** (A2.2 to A2.7): the one-command check runner already exists (A2.1, done); now turn the red checks green and let CI run them, so every later step can be proven with one command.
3. **A3 and A4**, and **E2.1 to E2.3**: three runs of the current build with the times written down (A3), a frame-time reading of the generated arena (A4), and a first export of the Windows build as a smoke test (E2). All three are "before" measurements or early warnings; finding an export problem now is cheaper than at the end. E2 is repeated at the gate (E2.4).
4. **C1, then C2**: the starting loadout (pistol and melee) and the Dart Gun as the first thing to buy. Small, since the pistol is already on the merged branch, and it makes the starting state real before anything is built around it.
5. **B5, B2, B1, B3, B4, B6, B7**, in this order: B5 is a data change and shrinks the map first; **B2 (the shop node) comes before B1** so the game never goes through a stretch where the shop has been removed from the rounds and does not exist yet; then B1 takes the shop out of the normal round loop, B3 and B4 add the rest and elite rewards, and B6 and B7 make the choices readable and prove the whole map.
6. **B8** (drops stay where the rider fell): a change to how the game plays, so it comes before the balance work of D, which has to measure the game with it. It touches only `scripts/pickups.gd` and its check, so it can be built at any point after B7. **B9** (offers and drops that do nothing for the weapon in hand, added 2026-10-27) goes right after B8 and **before C3 and D**: C3's shop filter and B9's test both live where the shop pool, the upgrade cards and the drops are decided (`shop_ok`, `upgrade_ok`, `drop_kill`), so build them one after the other, and D has to measure the game with them.
7. **C3, C4, C5**: the shop filter for unlocks, the level decision written down, and the run summary that leads on. They come after B because C3 and C5 change the screens B has just fixed.
8. **D1, D2, D3**: round length, then difficulty, then the coin economy, in that order, because each one changes the numbers the next one measures. Everything that changes play comes before this on purpose.
9. **E1, E5, E3, E2.4, E4**: first-run hints (they point at screens that now exist), a reset-progress button (testers need fresh saves), the soak test, the second export, and the version and notes.

### A. Foundation

- [x] **A1. Merge `milestone-c/weapon-slots`.** Everything in B and C builds on the slots and the weapon choice. Done when `main` has the three slots, the weapon choice on the Loadout page and the pistol, and the checks of A1.2 pass.
  - [x] A1.1 Read the branch diff against `main` (21 files: `scripts/weapon_slots.gd`, `models.gd`, `player.gd`, `run_save.gd`, `shop.gd`, `weapons.gd`, `docs/SAVE_FILES.md`, `data/weapons.json`, the new tools and `.bat` files) and write down what looks wrong: leftover debug, a commit with the message `.`, behaviour that changes the game when it should not (the notes say the game plays exactly as before).
  - [x] A1.2 Run the checks on the branch: `python tools/run_checks.py weapon_slots dart_pistol loadout run_save`, then the whole suite (`python tools/run_checks.py`), and compare with the list of results under "Roadmap audit" (a check that passes on `main` and fails on the branch is the branch's fault). Claude can do this part itself; the owner is only needed from A1.3.
  - [x] A1.3 The owner plays a short run on the branch: the Loadout page with its three weapon slots, the pistol in the slot (one dart per pull), a run saved and continued from the title screen, and an old `run.json` from before the branch still loading.
  - [x] A1.4 Fix what A1.1 to A1.3 found, each fix its own small commit on the branch.
  - [x] A1.5 Merge the branch into `main` (a pull request the owner merges), then run the whole suite on `main` and confirm nothing that passed before is red.
  - [x] A1.6 Reconcile the README after the merge. This was left out of this audit on purpose: the weapons branch edits the lines around it, and editing them here would make the merge conflict. (1) Milestone B "Unlock additional weapons in shop pool" and Milestone I "Unlock and buy new weapons with meta currency (adds them to the shop pool)" say the opposite of the branch's decision (weapons are bought, then chosen on the Loadout page, and never in the shop pool); reword both. (2) `data/README.md` still says a weapon unlock "joins the shop pool". (3) Milestone I "Starting loadout" and the branch's "Melee weapon is locked at the start" item change with C1.
- [x] **A2. Every check passes on `main`, with one command.** An alpha built on red checks cannot be trusted. Done when `python tools/run_checks.py` ends with ALL PASSED on the owner's machine and in CI.
  - [x] A2.1 One universal runner: `tools/run_checks.py` (with `tools\run_checks.bat` for a double click on Windows), described under "Testing rule". It finds Godot by itself and remembers it, finds every `tools/*_check.gd`, gives each its own empty save folder, kills a check that hangs, prints PASSED or FAILED with the reason and writes `check_logs/summary.txt`. It replaces the earlier plan of 14 new `.bat` files and a `run_all_checks.bat`. Run on Linux with Godot 4.7 against all 44 checks (results under "Roadmap audit"); **not yet run on Windows**, which is the next sub-item.
  - [x] A2.1b The owner runs `tools\run_checks.bat` once on Windows: it should find Godot without a path, and print its results. Also check that your real saves were not touched (the runner points `APPDATA` at a temporary folder, which is how Godot finds `user://` on Windows; this was only tested on Linux): look at the modified time of `%APPDATA%\Godot\app_userdata\Fstreli Biciklina 3D\` before and after.
  - [x] A2.2 Fix `scores_reset_check`
  - [x] A2.3 Fix `arena_style_title_check`
  - [x] A2.4 `arena_generated_check` is too slow to run by default
  - [x] A2.5 After A1, run the whole suite on `main` and fix whatever turns red (the weapons branch changes loadout, run save and shop).
  - [x] A2.6 CI runs the checks. `.github/workflows/ci.yml` only lints, checks the format and loads the project for 120 frames; none of the 44 checks run on a pull request, so nothing stops a change that turns them red (which is how A2.2 and A2.3 got through). Add a job that runs `python tools/run_checks.py` with the Godot binary the `load` job already downloads. Also look at whether `gdlint` and `gdformat --check` should cover `tools/*.gd` (they only cover `scripts/` and `tools/viewer/` now; `python tools/run_checks.py --lint` runs the same two commands locally). **Status 2026-10-27:** the `checks` job and the `tools/` lint scope are written in `.github/workflows/ci.yml`.
  - [x] A2.7 Optional cleanup, after A2.1b: delete the 30 old `tools\run_*_check.bat` files (and `play_*.bat` stay). Many item notes below quote those names, so do it together with the README split suggested under "Roadmap audit".
- [x] **A3. Baseline of the current build** (new, not in a milestone). Before anything changes the feel of a run, measure it, so that D1 to D3 have a "before". Done when the numbers are in the table of A3.2.
  - [x] A3.1 The owner plays three runs of `main` (after A1) from a fresh save (close the game, delete the folder `%APPDATA%\Godot\app_userdata\Fstreli Biciklina 3D\`; E5 adds a button for this later) and keeps the console output: the `[run timer]` line of every round, the total time, the floor where each run ended and why (riders, a civilian, a boss), the coins and XP on the summary, and what felt slow, unfair or confusing; everything seems fine and the game is pretty difficult, which is good.
  - [x] A3.2 Put the numbers in a small table under D (round times, run time, floor reached, coins per run) and leave it there; D1 to D3 add an "after" column; run length seems good ([run timer] round 1: 1:14 fighting, run so far 1:14 (+0:08 in shops),[run timer] round 3: 1:20 fighting, run so far 2:34 (+0:26 in shops))
- [x] **A4. Frame time on the generated arena** (new; Milestone K "Performance pass for the bigger arena" is open and the arena is 8 to 12 times the roundabout, so nobody knows how it runs on a weak machine; an alpha that stutters on the first laptop it meets is not playable, and slow frames would also spoil the playtests of D1 and D2). Done when the numbers are written down and either fine or fixed.
  - [x] A4.1 `tools/baseline.gd` measures the generated arena, not the roundabout
  - [x] A4.2 The owner runs it (`tools\run_baseline.bat`) on the development laptop at 1280x720 for HIGH, MEDIUM and LOW and for each of the six arena styles' worst case (the park is the biggest, about 15,300 triangles).
  - [x] A4.3 Compare with the old numbers in `docs/baseline_f1/README.md` (HIGH 1 % low 142 fps or better on Forward+). Goal: 1 % lows at or above 60 fps on HIGH and no hitch when a round starts.
  - [x] A4.4 If it is below the goal, take the cheap knobs first (`MAX_LAMP_LIGHTS` in `scripts/lighting.gd`, shadow size, the arena `cells` in `data/arena_rules.json`, particle counts) and measure again; anything bigger stays in Milestone K.

### B. A run with real choices (Milestone D "Map Nodes")

- [x] **B2. Shop node is a screen, not a round** (built on branch `roadmap/b2-shop-node-screen`, checked by the owner in B2.6): it skips the arena, opens the shop screen with the node's seeded offers and goes back to the map (Milestone D "Shop").
  - [x] B2.1 In `pick_node` / `start_round` (`scripts/main.gd`) a node of type `shop` does not start a round: no riders, no extraction point, no ambush; it calls `shop_sys.enter_shop()` and the floor and round number still go up by one.
  - [x] B2.2 The offers are already seeded: `build_shop` draws through `offer_shuffle`, which uses the run seed and the round number (the floor), so the same shop node gives the same shop and the Daily Run gives everybody the same shops. The node's own `seed` in its `content` is not needed for this and stays unused. The heal stays always on sale.
  - [x] B2.3 `leave_shop` in `scripts/shop.gd` goes to the map screen after a shop node (not to an upgrade pick) and the map checkpoint is saved.
  - [x] B2.4 A shop node is not a cleared round: no round XP, no `challenges.on_round_cleared`, no entry in `round_times`, nothing counted as a perfect round; its time goes into `shop_time`.
  - [x] B2.5 Extend `tools/map_walk_check.gd`: walking onto a shop node opens the shop, leaving it gives the map, and the round counter went up by one.
  - [x] B2.6 The owner plays a run and takes a shop node.
- [x] **B5. Cut what has no effect from the alpha map**
  - [x] B5.1 In `data/map_rules.json` set the `event` type weight to 0 (if the generator does not accept a weight of 0, use `"max_per_map": 0`) and describe the change in `docs/MAP_GENERATION.md`.
  - [x] B5.2 Set the `rain` modifier weight to 0 in the same file.
  - [x] B5.3 Run `python tools/run_checks.py map` (this picks `map_check`, `map_viewer_check` and `map_walk_check`); if a check insists on events or on rain, change the check to match and say why.
  - [x] B5.4 Look at 20 seeds in the map viewer (`tools/viewer/map_viewer.tscn`): no event node and no rain, and floors 4 and 9 still hold a shop and a rest each.
- [x] **B1. The loop after a cleared round (decided with the owner).** (Built on branch `roadmap/b1-upgrade-then-map`, which starts from the B2 branch; checked by the owner in B1.5.) Today every round goes clear, upgrade, shop, map. Decided: **an upgrade pick (1 of 3) after every fight, and the shop only at shop nodes**, so a shop node is worth choosing and the cash from a round has something to wait for. The shop moving to nodes changes the economy (Milestone G rules item), so the prices are checked in D2.
  - [x] B1.1 After a fight node (normal, elite, boss) the flow becomes clear screen, upgrade pick, map: `pick_upgrade` goes on to `next_round()` and not to `enter_shop()` (`scripts/shop.gd`). Do the same in `enter_upgrade`: when the upgrade pool is empty (every upgrade bought out) it currently falls through to `enter_shop()`, which after B1 must go to the map instead.
  - [x] B1.2 Cash now waits for a shop node: show the cash on the map screen (`_draw_map_screen` in `scripts/hud.gd`) so the player knows what they can spend.
  - [x] B1.3 Keep the run timer true: the upgrade screen still counts as `shop_time`, and the `[run timer]` line still adds up.
  - [x] B1.4 Update the checks that walk this flow (`tools/map_walk_check.gd`, `round_clear_check.gd`, `generated_run_check.gd`, `run_save_check.gd`) to the new order and run them.
  - [x] B1.5 The owner plays two runs and notes whether cash piles up uselessly or the shop nodes feel too poor; the notes go to D2.
- [x] **B3. Rest node is a screen with one choice** (built on branch `roadmap/b3-rest-node`, checked by the owner in B3.5): refill hearts to full, or take one extra upgrade pick (Milestone D "Rest stop"). Hearts max at 3 and every cleared round already gives one back, so the heal alone is never a real choice.
  - [x] B3.1 New state `rest` with a screen of two options, REFILL HEARTS and EXTRA UPGRADE, in the style of the shop screen (keyboard, mouse and gamepad), drawn in `scripts/hud.gd`, wired in `scripts/input.gd`.
  - [x] B3.2 REFILL sets the hearts to `MAXHEARTS` and goes back to the map; EXTRA UPGRADE opens one upgrade pick and then the map.
  - [x] B3.3 Like the shop node it is not a cleared round (see B2.4), and the map checkpoint is the map screen, so quitting on the rest screen and continuing gives the map with the same hearts (the same known loophole as for rounds, not guarded against).
  - [x] B3.4 `tools/rest_node_check.gd` (the runner finds it, no `.bat`): both options, the hearts, the counters, the keys and the screen at two window sizes.
  - [x] B3.5 The owner plays a run to floor 4 and takes the rest node.
- [x] **B4. Elite node pays for its risk**: it is already a harder fight (10 to 12 riders, 40 % armoured); make it also pay something the others do not, a second upgrade pick (Milestone D "Elite encounter"). **Status 2026-10-27:** built on branch `roadmap/b4-elite-extra-upgrade`, waits for the owner's run (B4.4). `shop_sys.enter_upgrade` now owes one extra pick when the node just cleared is an elite (`g.upgrade_extra`); `after_upgrade` opens the second screen through `show_upgrade` with the shuffle part `"upgrade2"` (`g.upgrade_part`), so its offers differ from the first and are still the same for the same seed (Daily Run). The rest node's EXTRA UPGRADE stays one pick, an empty upgrade pool skips the extra pick, and a new run clears a pick that was owed. A run without a map has no elite nodes, so nothing changes there.
  - [x] B4.1 Clearing an elite node gives two upgrade picks in a row, the second with fresh offers. `offer_shuffle` is seeded by the run seed, the round and a part name (`"upgrade"` in `enter_upgrade`), so a second pick in the same round would show the same three offers: give the second one its own part name.
  - [x] B4.2 The clear screen says so (for example ELITE CLEARED - EXTRA UPGRADE). The round clear screen shows ELITE CLEARED - EXTRA UPGRADE and the prompt CLICK TO PICK 2 UPGRADES; the two upgrade screens say UPGRADE 1 OF 2 and EXTRA UPGRADE (2 OF 2).
  - [x] B4.3 Extend `tools/node_setup_check.gd` or add a small check: an elite clear gives two picks, a normal one gives one. New `tools/elite_upgrade_check.gd` (the runner finds it); `tools/map_walk_check.gd` now expects two picks after an elite node on its walks. Run with `python tools/run_checks.py elite_upgrade rest_node map_walk round_clear generated_run run_save node_setup`: all 7 passed (Godot 4.7, Linux).
  - [x] B4.4 The owner plays and takes an elite node.
- [x] **B6. The map screen says what each node does** (one line for the highlighted node: SHOP spend your cash, REST heal or upgrade, ELITE harder and pays more, BOSS). Without it the choice is blind. **Status 2026-10-27:** built on branch `roadmap/b6-map-node-lines`, which starts from the B4 branch (`roadmap/b4-elite-extra-upgrade`, so the elite line says two upgrades) and waits for the owner's look (B6.3). The lines are in `MAP_LINES` in `scripts/hud.gd` (the boss has two, mid and final); the event node has none because it is switched off in the alpha.
  - [x] B6.1 One line per node type under the map, for the highlighted node, in `_draw_map_screen` (`scripts/hud.gd`). It sits in the info panel on the right under the node's name (wrapped to at most 3 rows) and the ROUND line moved down to make room. The stale footer "(NODE TYPES DO NOT CHANGE THE ROUND YET)" was removed, because shop, rest and elite nodes now do change the round.
  - [x] B6.2 It fits clear of the map and the style line at 1280x720 and 1920x1080 (the same kind of layout check as in `tools/map_walk_check.gd`). New `tools/map_node_lines_check.gd` (the runner finds it): every node type on the maps has a line, the rows fit the panel, the panel is clear of the nodes, and the rows sit clear of the style line, the ROUND line and the cash line at both sizes; it also draws the screen with every choice highlighted. Run with `python tools/run_checks.py map_node_lines map_walk map_viewer`: all 3 passed (Godot 4.7, Linux).
  - [x] B6.3 The owner looks at it in a run and in fullscreen.
- [x] **B7. Every node type works, and the run still continues** (the mid boss on floor 5 and the final boss on floor 10 already work; this is the proof for the whole map). Done when a run has walked every node type through B2 to B4 and the run save (`scripts/run_save.gd`) still continues from the map screen.
  - [x] B7.1 Play or script a run that takes a normal, an elite, a shop, a rest and a boss node. *Script written, not run yet:* `tools/node_types_run_check.gd` finds a seed with a path through all five types and walks it from floor 1 to the final boss (also the rest stop's EXTRA UPGRADE and the final boss win). Written in a session without Godot (gdformat and gdlint pass): run `python tools/run_checks.py node_types` once, then tick this and B7.2.
  - [x] B7.2 After each of them, quit to the title and CONTINUE: the map screen comes back with the same hearts, cash and perks. *Same script, not run yet:* after every node it does `abandon_run` then `continue_run` and compares hearts, cash, perks, upgrades, packs, score, round and map position; it also quits on the shop and rest screens (continues from the map before that node) and checks a won final boss leaves nothing to CONTINUE.
  - [x] B7.3 `python tools/run_checks.py` is green.
- [x] **B8. Drops stay where the rider fell** (new, decided with the owner; not in a milestone). Today `spawn_pickup` in `scripts/pickups.gd` throws every drop to a spot 2.2 to 4.8 m from the *player* (`landing_spot`), so the loot flies to you and there is no reason to move. Instead a drop comes down around the place where the rider was eliminated, so the player has to walk to it, into the open, and that makes the game harder. Done when a kill's drops lie where it happened and the player has to go and get them.
  - [x] B8.1 A drop lands within a short distance of the kill position (a first guess is 0.5 to 2 m; several drops from one kill fan out so they do not lie on top of each other), on ground a pickup may lie on (`clamp_walk(..., "pickup")`). On open ground the way from the kill to the spot crosses no wall (`way_clear` already does that test for the old spot); if no direction works the drop lies on the kill position itself, kept off the wall. The one second arc from the rider to the spot stays. This holds for every caller of `spawn_pickup`: rider kills (`drop_kill`), caches (`objective.gd`) and `maybe_drop`.
  - [x] B8.2 The roundabout follows the same rule (it used one direction from the player, 2.2 to 4.8 m, as before; that is replaced, not kept as a second path). `arena_check` guards the arena geometry, not the drops, so it is not affected.
  - [x] B8.3 The lifetime of a drop: now that it can lie far from the player, 6 s until it blinks and 8 s until it vanishes (`update_pickups`) may be too short to walk to it across a 144 m arena. Pick the numbers by playing (the first guess is a few seconds longer, with the blinking in the last 3 s), and look at the limit of 6 drops on the field (`g.pickups.size() >= 6`): if kills in a fight now use it up and new drops are lost, raise it or drop the oldest.
  - [x] B8.4 The magnet upgrade (POCKET MAGNET, `g.up["magnet"]`) **stays as it is**: a landed drop is pulled towards the player only when the player is within `3.5 + 3.0 * level` m of it, at 6.5 m/s. That is the reward for owning it (and the reason C3 is worth doing); it must not pull drops from further away, and a drop still in flight is never pulled.
  - [x] B8.5 Update `tools/pickup_placement_check.gd` to the new rule: a spot is within the chosen distance of the *kill*, not of the player (the old 8 m player distance and the roundabout "one direction, 2.2 to 4.8 m from the player" lines change), it is ground a pickup may lie on, the way from the kill crosses no wall, a player standing far away gets drops near the kill and not near themselves, and a pickup near the player is pulled only with the magnet. Run `python tools/run_checks.py pickup` and the checks that touch the changed code (`rider`, `round_clear`), not the whole suite.
  - [x] B8.6 Update the places that describe the old behaviour: the comment above `landing_spot`, the Milestone K item "Pedestrians, cheerleaders and pickups placed on generated arenas" if it says drops land by the player, and `data/README.md` if it mentions it.
  - [x] B8.7 The owner plays two runs and notes whether going for the drops is worth the risk, whether they time out too soon, and whether the fight became too hard (the notes go to D2).
- [x] **B9. Offers and drops make sense for the weapon in your hands** (new, from the owner on 2026-10-27; not in a milestone). Some things the game drops, offers as an upgrade or sells do nothing for the next round. The starting Dart Nerf Pistol holds one dart (`start_clip` 1 and `max_clip` 4 in `data/weapons.json`), so anything about ammo has little or nothing to act on. The game already does this right for hearts (`drop_kill` only drops one when you are hurt, `maybe_drop` turns a heart into cash at full hearts, `shop_ok` offers PATCH UP only when hurt); B9 gives every other drop, upgrade card and shop item the same test. Done when nothing is dropped, offered or sold that cannot change the next round for the loadout the player holds, and a check keeps it that way when a weapon or an item is added.
  - **Known so far** (found by reading the code on 2026-10-27, not by playing; each one is to be confirmed, and B9.1 finds the rest):
    - AMMO drops (+2 darts, +4 with SCAVENGER), the ammo reward of a cache (2 of the 9 entries of `REWARDS` in `scripts/objective.gd`) and every other dart refund (COUNTER, MATADOR, HEADHUNTER) go through `add_shells` in `scripts/combat.gd`, which stops at the size of the clip. With the pistol that is one dart, so they do nothing while it is loaded. SALVAGE, SCAVENGER and the duo SCRAPYARD only change ammo drops.
    - FREE DARTS ("Your first 12 darts next round cost no ammo", `pending["free"]`) and SLIDE SHOT / QUICK DRAW skip the magazine: with a one-dart clip that is worth something different than with the dart gun's six, and nobody has decided what it should be worth.
    - EXTENDED CLIP says "+2 darts per clip" in `data/items.json`, but the pistol's `clip_step` is 1 (the stat line on the card, `upgrade_stat`, shows the real step).
    - LAST SHELL ("the last dart in your clip hits twice as hard") is always on with a one-dart clip, because every dart is the last one.
    - **Checked by the B9.1 audit (2026-10-28):** all four hold, with two corrections: ammo is not literally nothing with the pistol (an empty pistol that picks up ammo skips a 0.55 s reload; with the dart in the gun it does nothing), and FREE DARTS is not weaker with the pistol, it saves about 6.6 s of reloading against 4.8 s with the dart gun. The audit found more: COUNTER, MATADOR, SALVAGE, SCRAPYARD, HEADHUNTER and SNIPER, the cash entries that only pay while a shop node is ahead, and DEADEYE, which only works against bosses.
  - [x] B9.1 Audit every drop, upgrade card, shop item and perk or duo: what does it need to matter, and what does it do with the pistol and with the dart gun (the table is in `data/README.md`, "Does it matter for what you hold?").
  - [x] B9.2 The owner decides, for each entry that fails the test: stop offering it (as for hearts), make it scale with the weapon (for example an ammo drop that refills a share of the clip, or FREE DARTS counted in clips and not in 12 darts), or change its text or effect for that weapon. The decisions go into the table of B9.1.
  - [x] B9.3 One test in one place: a function that answers "can this drop, card or shelf item change the next round for what the player holds now?". It can read the weapon and the player's state (clip size, hearts, perks), not only the weapon. A first idea to decide while building: an optional `needs` key on the entries of `data/items.json`, `data/perks.json` and the drop table, read by that one function, where an entry without it always passes. Call it where the game decides: `drop_kill`, `maybe_drop` and the cache reward draw, `enter_upgrade` and `upgrade_ok`, `shop_ok` and `build_shop`, and the perk part of the shop pool. The hearts rule becomes its first case and stops being a special case. *Built:* `scripts/needs.gd` (`Needs.ok`, with the needs `clip_min`, `hurt`, `shop_ahead`, `boss_ahead`), `needs` on PATCH UP, six perks and six duos in the data files, `DROP_NEEDS` in `scripts/content.gd`, and `node_type_ahead` in `scripts/main.gd`; a drop that fails is turned into cash by `matter_drop` when cash matters, otherwise not dropped. The EXTENDED CLIP text of B9.2 came with B9.5, and the case of a drop whose cash replacement also fails (no shop ahead) is settled in B9.4: nothing is dropped.
  - [x] B9.4 Keep the draws fair and the shelves full: the test only changes what is in the pool, never the random draws (the same rule as C3.2), so the same seed and the same loadout give everybody the same offers, the Daily Run included. A drop that is filtered out becomes cash, the way a heart does at full hearts; the shop still shows its four items and the upgrade screen its three, or goes on to the map when nothing is left (the empty pool case of B1.1). *Checked, no code needed beyond B9.3:* the test draws no random number, the offers still come from the seeded `offer_shuffle`, so the same seed and loadout give the same offers; a scratch run over 12 seeds, both weapons, every floor and random loadouts (240 states) always gave a shop of 4 and an upgrade screen of 3, none that fails its needs, and none that changed when built twice (the permanent check is B9.5). The five packs have no needs, so the shop never has fewer than five candidates. A kill's separate drop chances (`drop_kill`) skip a failing drop, as they always skipped a heart at full hearts; the one-of-the-table draws (boss drops, cache rewards) turn it into cash, and into nothing on the last floor, where no shop is ahead for cash to pay at.
  - [x] B9.5 `tools/offer_sense_check.gd` (the runner finds it, no `.bat`): for every weapon in `data/weapons.json` as the primary weapon, over many seeds and rounds, no drop, upgrade card or shop item that fails the test is ever produced, and the shelves stay full. Add a case for each example under "Known so far", so a new weapon or item that does nothing is caught by the check and not by a player. *Built:* the check goes through every weapon in `PRIMARY_WEAPONS` (so a new one is covered when it is added), 10 seeds each (60 with `--full`), every floor of the map, random clips, hearts and perks, and asks the shop, the upgrade screen, `drop_kill`, `maybe_drop` and the cache rewards; it also has a case for each example under "Known so far" and each B9.2 decision. Making the EXTENDED CLIP case pass took the one code change B9.2 had left: `item_desc` in `scripts/shop.gd` gives the card the weapon's real step (+1 dart with the pistol, +2 with the dart gun). Checked by breaking each rule in turn (the ammo need, the text, a boss need): each time the check failed.
  - [x] B9.6 Update the checks that count drops, upgrade cards or shop items, and run only those (`python tools/run_checks.py <names>`, as the testing rule says), not the whole suite. *Done:* the checks that read drops, cards or shelves are `map_walk_check`, `elite_upgrade_check`, `rest_node_check`, `node_types_run_check`, `objective_check`, `pickup_placement_check`, `rider_check`, `round_clear_check`, `dart_pistol_check` and `reload_check`. Only `map_walk_check` encoded the old rule (a shop that is "not empty", a heal on sale "when hurt" through `shop_ok`): it now wants exactly four items, each one passing the test, and names the heal's `needs`. The others already counted what is still true (three upgrade offers, an empty pool going on to the map). All of them and `offer_sense_check` pass (`python tools/run_checks.py map_walk elite_upgrade rest_node node_types objective pickup rider round_clear offer_sense dart_pistol reload`).
  - [x] B9.7 Describe the rule in `data/README.md` (what `needs` means, and that a new item or perk has to say what it needs). *Done:* the section "What an entry needs to matter" in `data/README.md`, with the four keys, where `needs` goes, what the game does with a failing entry, and the rule for new content; the `items.json` and `perks.json` sections point to it.
  - [x] B9.8 The owner plays two runs from a fresh save and notes every drop, card or shop item that still did nothing; the notes go to D2.

### C. Progression that changes the next run (Milestones B, C and I)

- [x] **C1. Starting loadout: Dart Nerf Pistol and the melee weapon** (Milestone I "Starting loadout", the pistol's "Make it the starting primary weapon"). *Decided with the owner, a change from the weapons branch:* the branch also locks the melee weapon until level 5; the melee weapon **stays owned from the start**, and the lock is dropped from the alpha (it needs a level rule, a "no melee" empty slot and HUD changes). The weapons branch's "Melee weapon is locked at the start" item and the Milestone I starting loadout wording are to be updated to match when it is merged.
  - [x] C1.1 `PRIMARY_DEFAULT` is `dart_pistol`; the Loadout page lists the pistol first; an old saved run without `primary` still loads as the dart gun
  - [x] C1.2 Update the README: the melee lock moved to "Not in the early alpha", and Milestone I "Starting loadout" names the pistol and the melee weapon
  - [x] C1.3 Update the expectations of the checks to the new default and run them
  - [x] C1.4 The owner plays a run with the pistol and notes how a clip of 1 feels; the notes go to D2.
- [x] **C2. First weapon unlock: the Dart Gun** (built on branch `roadmap/c2-dart-gun-unlock`, checked by the owner in C2.5) becomes a buyable `weapon` entry in `data/unlocks.json` (tier 3 of the price curve, 250 coins, as a first guess), so the first purchases change how the player shoots. The pistol's in-run upgrades (clip, pump, reload) already work on it; the dedicated five-tier upgrade path waits.
  - [x] C2.1 Add the `dart_gun` entry to `data/unlocks.json` (kind `weapon`, tier 3, name and text written in the entry) and describe it in `data/README.md`.
  - [x] C2.2 The dart gun is no longer owned from the first run: `weapon_owned` in `scripts/main.gd` holds it back until it is bought, and the Loadout page lists it only once owned.
  - [x] C2.3 The Unlocks page shows it as buyable with its price and not as SOON; fix the expectations of `tools/unlocks_check.gd`, `unlocks_page_check.gd` and `unlocks_buy_check.gd` (the number of unlocks and of planned weapons changes).
  - [x] C2.4 Buy it, choose it on the Loadout page, start a run: the run has the dart gun in the primary slot (a case in `tools/loadout_check.gd`).
  - [x] C2.5 The owner buys it with real coins and plays a run with it.
- [x] **C3. Owning a shop-item unlock matters**: unowned shop items leave the shop pool (the "shop filter" item of Milestone I, see `data/README.md`). Decided with the owner: the Daily Run and custom seeds use the same filter as a normal run, matching the loadout decision on the weapons branch.
  - [x] C3.1 Where the shop pool is built (`scripts/shop.gd`, `scripts/items.gd`) leave out the six items that are unlocks (POCKET MAGNET, HYPE PACK, LUCKY CHARM, HYPE MACHINE, SHIELD PACK, THICK SKIN) until they are owned; the heal and every item not in `data/unlocks.json` stay. *Built:* `shop_item_owned(id)` in `scripts/main.gd` (the same pattern as `weapon_owned`) answers false for an item that `data/unlocks.json` lists as a `shop_item` unlock until `meta.owns` it, true for everything else; `shop_ok` in `scripts/shop.gd` returns false when it says no, and `build_shop` only reads `shop_ok`. The heal is not an unlock, so it stays. Decided with the owner afterwards: the upgrade cards are filtered too, in `upgrade_ok` (which `shop_ok` also uses for the tier items), so an unlock is neither sold nor offered as a card until it is bought.
  - [x] C3.2 The Daily Run and custom seeds use the same filter, and the seeded offers stay the same for everybody with the same unlocks (the filter must not change the random draws that pick offers, only what is in the pool). *Built, no extra code:* the filter is the same for a normal run, a Daily Run and a custom seed, and it only changes which items are in the pool before `offer_shuffle` (seeded by run seed, round and part), so no random draw changes.
  - [x] C3.3 Remove the "has no effect yet" lines in `data/README.md` and make the Unlocks page text match. *Done:* the "no effect yet" line and the "Decide that when the shop filter is built" paragraph in `data/README.md` (now the C3 decision), the `shop_item` row, the header comment of `scripts/unlocks.gd`, and the lines in this README. The Unlocks page text "JOINS THE SHOP" already matched and is unchanged.
  - [x] C3.4 `tools/unlocks_check.gd` or a new check: a fresh save's shop has none of the six, a bought one appears. *Built:* new `tools/shop_filter_check.gd` (the runner finds it, no `.bat`): exactly six `shop_item` unlocks; on a fresh save none is sold or on a shelf over 5 seeds, 5 floors and 4 rerolls in a normal run, a Daily Run and a custom seed; everything else still sold and the shelf keeps four items; owning one brings back that one only; the same state gives the same shelf. It fails without the fix. Run with `python tools/run_checks.py shop_filter unlocks offer_sense map_walk node_types rest_node elite_upgrade round_clear generated_run run_save loadout`: all passed (Godot 4.7, Linux).
  - [x] C3.5 The owner checks on a fresh save and after one purchase. A thinner early shop feeds into D2.
- [x] **C4. What a level does (decided with the owner):** for the alpha "a number only, shown on the title and the summary" (Milestone I "Decide whether a level unlocks anything"). Then merge or drop `roadmap/level-rewards`; its XP numbers only matter once a level does something. (Verified 2026-10-28, note in `docs/ROADMAP_HISTORY.md`.)
  - [x] C4.1 Tick Milestone I "Decide whether a level unlocks anything" with the answer: for the alpha a level is only shown; the first use of levels comes after the alpha.
  - [x] C4.2 The owner decides on `roadmap/level-rewards` (XP about 7 times slower): merge it as the new XP numbers, or drop the branch. If merged, `python tools/run_checks.py xp` passes and the "about 1,000 to 1,500 XP for a won run" note in `data/README.md` is corrected. (Merged earlier as PR #97; `xp_check` passes.)
- [x] **C5. The end of a run leads on**: the run summary gets NEW RUN and UNLOCKS buttons (UNLOCKS highlighted when the new coins can buy something that was out of reach), and the title menu puts the loop first (CONTINUE, PLAY, LOADOUT, UNLOCKS, then the rest). Done when a player can go from a lost run to the next one in two clicks, with coins spent on the way.
  - [x] C5.1 Buttons on the run summary: NEW RUN, UNLOCKS and TITLE, with mouse, keyboard and gamepad, drawn clear of the table and the unlock lines at 1280x720 and 1920x1080 (`_draw_run_summary` in `scripts/hud.gd`). Built on branch `roadmap/c5-1-summary-buttons` (starts from the C4 branch); checked by the new `tools/summary_buttons_check.gd`. NEW RUN and UNLOCKS leave for the title until C5.3. The owner's look comes with C5.5.
  - [x] C5.2 UNLOCKS is the selected button when `g.new_unlocks` is not empty, otherwise NEW RUN is. (`summary_default_sel()` in `scripts/main.gd`, used by `game_over`, `win_run` and the lost-round path of `end_round` right after `meta.award_run()`; covered by `_check_default_button` in `tools/summary_buttons_check.gd`, which was written but not run in the session that built it, so run `python tools/run_checks.py summary_buttons` first.)
  - [x] C5.3 NEW RUN starts the next run the way RESTART RUN does (a normal run gets a new seed, a Daily Run and a custom seed replay theirs); UNLOCKS opens the page and Esc goes back to the summary's buttons or the title menu, decide which while building it. (Decided: Esc goes back to the title menu, with UNLOCKS highlighted; `restart_run()` in `scripts/main.gd` is shared with the pause menu's RESTART RUN, `open_unlocks_from_summary()` is in `scripts/input.gd`; reasons in `docs/ROADMAP_HISTORY.md`. The new `_check_actions` in `tools/summary_buttons_check.gd` was written but not run in the session that built it, so run `python tools/run_checks.py summary_buttons` first.)
  - [x] C5.4 Reorder the title menu: CONTINUE, PLAY, LOADOUT, UNLOCKS, then DAILY RUN, CUSTOM SEED, CHALLENGES, HIGH SCORES, CONTROLS, SETTINGS, QUIT, and update the checks that look buttons up by position. (Only the order of `TITLE_ITEMS` in `scripts/hud.gd` changed. No check needed an edit: they find entries by id, and the few that use a number rely on PLAY being 0 or on QUIT being last, which still holds. That was read from the code, not run: run `python tools/run_checks.py run_save unlocks_page loadout seed_page challenges controls_page scores_reset unlocks_buy` first.)
  - [x] C5.5 Checks for the summary buttons and the new order, then the owner goes from a lost run to the next run through the buttons.

### D. Difficulty and length (Milestones "Recommended Roguelite Structure", I and K)

- [x] **D1. Tune round length on the 144 m arena** (the playtest items under Milestone K: objectives, riders and pickups, rider speed and sightlines). Use the run timer that is already there (the `[run timer]` lines and the summary). Target: a 10-round run takes 20 to 30 minutes including the map, upgrade and shop screens, so about 2 minutes a fight. Done when five runs from the owner land inside that range.
  - [x] D1.1 Read the A3 table and the five new runs against the target: which rounds are too long and why (the walk to the extraction point, riders that take long to arrive, too few riders).
  - [x] D1.2 Pick one knob at a time: riders per node (`content.riders.count` in `data/map_rules.json`), rider speed, the extraction distance and cache spots (`scripts/arena_generated.gd`, `scripts/objective.gd`), the arena size (`cells` in `data/arena_rules.json`), or the ambush sizes (`scripts/ambush.gd`).
  - [x] D1.3 Change it, play three runs, record the times in the table; repeat until the average sits in the range.
  - [x] D1.4 Tick the open playtest items of Milestone K that this covers ("Playtest the objectives", "Riders and pickups on the bigger arena", "Playtest and balance"), each with a short note of what was changed.
- [ ] **D2. Balance pass with the starting loadout** (Milestone "Balance pass for the 10-round difficulty curve", Milestone I "Balance pass"): rider speed, boss health, final boss health, the shop prices after B1, cash from caches. First guess at the goal, to correct by playing: from a fresh save the first runs end between floors 2 and 7, one reaches the mid boss, and with three or four unlocks the final boss is reachable (winning it is allowed to stay hard).
  - [ ] D2.1 A developer-only way to start with a given number of coins and owned unlocks (for example a command line argument), so "with three or four unlocks" can be tested without grinding; it never touches the normal save and never ships enabled.
  - [ ] D2.2 List the knobs in one place of `data/README.md`: rider speed by round, boss health, the final boss, shop and upgrade prices, `CACHE_CASH` and `CACHE_SCORE`, hearts.
  - [ ] D2.3 Five runs from a fresh save with the pistol: record the floor reached and why each run ended; collect the notes from B1.5, C1.4 and C3.5.
  - [ ] D2.4 Adjust one number at a time and play again until the first runs end between floors 2 and 7 and one reaches the mid boss.
  - [ ] D2.5 Repeat with three or four unlocks (D2.1): the final boss is reachable.
  - [ ] D2.6 Tick the two balance items in the milestones with a short note of what was changed.
- [x] **D3. The meta economy fits the loop**: the first purchase is within one or two runs, the cheapest tier first (60 coins is the current guess), and the whole alpha unlock list costs roughly 15 to 25 runs of coins. Tune the price curve in `data/unlocks.json` and the coin rates in `scripts/meta.gd`; a run that is quit pays nothing, which stays.
  - Decided with the owner on 2026-10-27 after the A3 playtest (a run lost in round 2 paid 400+ coins and bought the dart gun at once): a complete run pays about 40 coins, a run lost early a few, the dart gun (250) takes 6 to 7 complete runs. Done in `scripts/meta.gd` (2 per round cleared, 3 mid boss, 8 final boss, score 1 per 100,000 capped at 5) and `data/challenges.json` (2, 2, 1, 1, 4). The price curve is unchanged, so buying all 21 listed unlocks (4,290 coins) is about 107 complete runs: D3.3 decides whether the upper tiers get cheaper.
  - [x] D3.1 From the runs of D2 write down the coins a run pays by outcome (lost early, lost late, won), including boss and challenge coins.
  - [x] D3.2 Total the price of every unlock (all 25, the dart gun included) and divide by the coins of an average run.
  - [x] D3.3 Adjust the price curve or the coin rates until the first purchase is within one or two runs and the whole list lands in the 15 to 25 run range.
  - [x] D3.4 Write the final numbers into `data/README.md`, and update `tools/unlocks_check.gd` if it checks the first price against a short run.

### E. Alpha gate

- [ ] **E2. Windows export tested**: export `build/windows/FB3D.exe` (Milestone E "Configure Windows export presets" was never run), start it from a clean folder and check that settings, scores, meta and the run save land in `user://` and load again. Done early as a smoke test (E2.1 to E2.3, right after A2) and again at the gate (E2.4).
  - [x] E2.1 Project > Export > Windows Desktop > Export Project: `build/windows/FB3D.exe` appears inside the project folder; note any export error.
  - [x] E2.2 Start the exe from a clean folder: the title screen, the window icon and title (FB3D), fullscreen on F11, one short round.
  - [x] E2.3 Quit and start again: settings, high scores, meta coins and a saved run are still there (`user://`, which on Windows is `%APPDATA%\Godot\app_userdata\Fstreli Biciklina 3D\`, see `docs/SAVE_FILES.md`).
  - [ ] E2.4 Repeat E2.1 to E2.3 with the finished alpha build.
- [ ] **E1. First-run hints**, not a tutorial: a one-line prompt the first time the player sees the map screen, the upgrade screen, the shop, the rest screen, the extraction point opening and a cache. The "seen" flags live in the settings file and a setting turns the hints off. Done when someone who has never seen the game can finish round 1 without being told anything (Milestone E "Short tutorial" stays open).
  - [x] E1.1 Store which hints were shown in the settings file, with a default and a safe load (`scripts/settings.gd`, `docs/SAVE_FILES.md`). Built on branch `roadmap/e1-1-hint-flags`: `[hints]` in `settings.cfg` holds one true/false for each of the six ids (`HINT_IDS`: map, upgrade, shop, rest, extract, cache); a missing section or key, or a value that is not true/false, loads as not seen; `Settings.hint_seen(id)` and `mark_hint_seen(id)` (true only the first time) are what E1.2 and E1.3 will call. No version bump (a new field with a default). Settings, not progress: RESET ALL PROGRESS keeps the flags, so a reset does not show the hints again (documented in `docs/SAVE_FILES.md`). New `tools/hint_flags_check.gd` (the runner finds it). Written in a session without Godot (gdformat and gdlint pass): run `python tools/run_checks.py hint_flags settings_nav progress_reset` once.
  - [x] E1.2 One hint line, drawn bottom centre, shown for a few seconds and never blocking input. Built on branch `roadmap/e1-2-hint-line` (made from `roadmap/e1-1-hint-flags`, so merge E1.1 first): `Settings.show_hint(text)` puts a line up for `HINT_SECONDS` (5 s, the last `HINT_FADE` 0.8 s fading out) and a second hint replaces the first; `Settings.hint_once(id, text)` is the call E1.3 makes: it shows the text only the first time that id comes up and saves the flag (an id that is not one of the six shows nothing); `hint_alpha()` is what the HUD reads. State is `hint_txt` and `hint_t0` in `scripts/main.gd`. `_draw_hint`, `hint_rect`, `hint_fs` and `hint_y` in `scripts/hud.gd` draw a dark strip with the text, centred: in a round 118 px (at 720p) above the bottom edge, above the dash bar and the FREE DARTS line; on the map, upgrade, shop and rest screens at 86.5 % of the height, between the cards and the bottom prompt. The font shrinks when a line would not fit the window, and the pause menu and the settings pages are drawn over the line. It is only drawn: no click area, no key, no pause, no slowdown. Not done on purpose: nothing calls it yet (E1.3), the HINTS ON / OFF setting (E1.4) is not read, and the run summary (buttons at 88.5 %) is not a hint screen, so a hint is not meant to be up there. `HINT_MAX_CHARS` (90) is the length E1.3 texts stay under. New `tools/hint_line_check.gd` (found by `python tools/run_checks.py hint_line`) checks the timing and the fade, replacing, `hint_once` (first time only, flag saved, unknown id), that picking a map node and a running round are not affected, the strip inside the window and clear of the bottom HUD at three window sizes with a very long line, and drawing at two sizes; each of four deliberate breakages (no fade, `hint_once` always showing, strip too low, no font shrink) made it fail. Run here with Godot 4.7-stable headless: `hint_line`, `hint_flags`, `settings_nav` and 14 HUD-related checks (`summary_buttons`, `controls_page`, `pause_map`, `game_title`, `map_walk`, `round_clear`, `generated_run`, `unlocks_page`, `loadout`, `progress_reset`, `focus_pause`, `version`, `rest_node`, `shop_filter`) passed, gdformat and gdlint 4.5.0 clean. Waiting for an in-game look (headless cannot draw): the line cannot be seen until E1.3 calls it, so E1.3 is the first time to judge it in play.
  - [x] E1.3 Hook the six triggers (the first map screen, upgrade screen, shop, rest screen, the extraction point opening, the first cache within sense range), each shown once. Built on branch `roadmap/e1-1-hint-flags` (same branch as E1.1 and E1.2): the six lines are `Settings.HINT_TEXTS` (73, 73, 75, 73, 69 and 67 characters, under `HINT_MAX_CHARS`), and `Settings.trigger_hint(id)` shows one the first time only (`hint_once`). The calls: `map` at the end of `enter_map()` in `scripts/main.gd` (so also when a saved run is continued, the first time), `upgrade` in `show_upgrade()` and only when there is a pick to make (a bought-out pool goes straight on and keeps the flag), `shop` in `enter_shop()`, `rest` in `enter_rest()` (`scripts/shop.gd`), `extract` in `begin_extraction()` and `cache` in `update()` as soon as an untaken cache is inside `SENSE_RANGE` (45 m) (`scripts/objective.gd`). The roundabout has no caches or extraction point, so it never shows those two. The extra upgrade of a rest stop opens the upgrade screen, so it can show the `upgrade` hint. Not done on purpose: the HINTS ON / OFF setting (E1.4) is not read yet, so every trigger shows its line until that row exists. New `tools/hint_triggers_check.gd` (`python tools/run_checks.py hint_triggers`) checks the six texts (all present, one line, not shared, inside the window at three sizes), each trigger (its own line, only its own flag, saved to `settings.cfg`), a second time (nothing shown and the line on screen kept, also after the flags are loaded again), a cache out of range, an upgrade screen with no offers, and the roundabout; five deliberate breakages (cache range too small, extraction hint removed, upgrade hint with no offers, shop hint every time, rest showing the shop text) each made it fail. Run here with Godot 4.7-stable headless: `hint_triggers` and 21 related checks passed (22 of 22), gdformat and gdlint 4.5.0 clean. Waiting for an in-game look (headless cannot draw): this is the first time the hint line can be seen in play, so judge the wording, how long it stays and the position on each screen.
  - [ ] E1.4 A HINTS ON / OFF row in the settings.
  - [ ] E1.5 A check for the flags, the setting and the drawing at two window sizes.
  - [ ] E1.6 Someone who has not played it (not the owner) plays round 1 with no help; note where they got stuck.
- [x] **E5. Reset progress in the settings, with a confirmation**
  - [x] E5.1 A reset-progress entry that opens a confirmation with NO selected first and a YES that ignores input for 0.3 s
  - [x] E5.2 YES wipes the saved progress
  - [x] E5.3 Document it in `docs/SAVE_FILES.md` and add a check
- [ ] **E3. Soak test**: three complete runs from the exe (one lost, one won or a final boss reached, one quit and continued) with nothing in the console that is an error, and no save file corrupted.
  - [ ] E3.1 `python tools/run_checks.py --full` ends with ALL PASSED on the alpha candidate, and CI is green.
  - [ ] E3.2 Three runs from the exe: one lost, one that reaches the final boss (or is won), one quit to the title and continued.
  - [ ] E3.3 Read the Godot log of those runs (`user://logs`): no script errors; fix each one found.
  - [ ] E3.4 Open the save files after the runs (`settings.cfg`, `scores.json`, `meta.json`, `run.json`): all readable, nothing damaged.
- [ ] **E4. Ship notes**: set `config/version` to `0.2.0`, and add a short `docs/ALPHA_NOTES.md`: how to run it, the controls, what is in and what is not, known issues, and where to send feedback.
  - [ ] E4.1 `config/version` in `project.godot` to `0.2.0` (the one place the version is written), and `tools/version_check.gd` still passes.
  - [ ] E4.2 Write `docs/ALPHA_NOTES.md`: how to run it, the controls (point to the Controls page), what is in and what is not (the "Not in the early alpha" list below), known issues, where to send feedback.
  - [ ] E4.3 Optional, the owner decides: tag the commit `v0.2.0-alpha` on GitHub.

### Not in the early alpha (on purpose)

- **Looks and sound:** Milestone F (graphics and sound overhaul, models, music). The placeholder look is fine for testing the loop.
- **More content:** the other three weapons and the five-tier pistol path (Milestone C), relics, curses, more modifiers, events, cosmetics and skins (B, D), rider variety and arena hazards, height and hills (K).
- **Extra systems:** Heat and per-difficulty leaderboards, jumping (L), third person (M), the run start sequence (H), the melee lock at level 5 (dropped by the owner for the alpha, see C1), daily modifiers and the share card, caches with a catch.
- **Melee weapon locked at the start** (moved here from Milestone C by C1): Melee weapon is locked at the start, and unlocks very fast: the melee weapon is **not unlocked right away**. A new player starts with only the primary weapon (the Dart Nerf Pistol, see below) and the melee slot stays empty until the melee weapon is unlocked. Decided with the owner: it can be bought on the Unlocks page from **player level 5** (the XP level of `data/xp.json`, saved as `xp` in `meta.json`; with the current numbers level 5 needs 1,800 XP, about one or two runs) for a **low amount of meta currency**: tier 1 of the price curve (60 coins) as a first guess, set as `tier: 1` in `data/unlocks.json`. Before level 5 the Unlocks page shows it as locked with the level needed (a new unlock rule next to `planned`, for example `min_level`, checked by `Meta.buy` as well so it cannot be bought early). Needs: a `weapon` entry for the melee weapon in `data/unlocks.json`, a "no melee" empty slot value like `NO_GADGET`, the Loadout page and `apply_loadout` coping with an empty melee slot, and Q / wheel / 1 / 2 switching and the HUD slot display skipping an empty slot. **Today the melee weapon is always owned and every run starts with it**, so this changes the current behaviour
- **Online and polish:** the website, accounts, cloud saves, key rebinding, localization, the tutorial (E, N).

### Roadmap audit (2026-10-27)

**The check suite.** All 44 checks were run headless with Godot 4.7-stable on Linux, each with an empty save folder (`python tools/run_checks.py`). **41 passed. 3 did not:**

| Check | Result | Cause | Item |
|---|---|---|---|
| `scores_reset_check` | FAILED | the Delete key is not handled anywhere in the game (a real bug, not the timing problem that was suspected) | A2.2 |
| `arena_style_title_check` | FAILED | the check does not opt in to the generated arena, which became the default after it was written | A2.3 |
| `arena_generated_check` | TIMED OUT at 200 arenas | about 6 s per arena, so about 20 minutes with no output; it passes for 3 arenas, so this is slowness, not a failure | A2.4 |

Without `arena_generated_check` the suite takes about 7 minutes; the slowest passing check is `arena_gen_check` (3.6 minutes). What this changes: the notes "written in a session without Godot, only gdformat and gdlint were run, so run the .bat once" (24 of them) are now satisfied for every check that passed, and the six explicit "NOT RUN YET" / "Not run yet" notes (map walk, map content, map validation, map viewer, custom seed, objectives) were replaced with the result. What those items still wait for is the in-game look. No script covers: playing, how anything looks, and Windows (the runner itself was only run on Linux, see A2.1b).

**Fixed in this commit (README and tools only, no game code):**
- The testing rule said every check needs its own `.bat`; it now describes the one-command runner `tools/run_checks.py` (A2.1).
- Milestone B "Unlock starting perks" was unticked although it works (Milestone I buying and the Loadout page); ticked with a note.
- Milestone D "Normal encounter", "Boss node" and "Double riders modifier" were unticked although they work; ticked with a note naming where they were built. "Elite encounter" is only partly there; annotated.
- Stale notes were flagged: "rounds do not follow the map yet" and "nothing reads the rules file" (Milestone G), "not used by the game yet" and "nothing in the game uses it yet" (Milestone K) are history now.
- Nine items that are finished but do nothing (or only part) in play got a **BUILT, NOT USED YET** or **PARTLY BUILT** marker at the item itself; the table above lists those and the rest.
- My own alpha plan was corrected after checking it against the code: B1.1 (an empty upgrade pool jumped to the shop), B2.2 (the shop offers are already seeded per floor, the node seed is not needed), B4.1 (a second upgrade pick needs its own shuffle part or it repeats the first), A1.2 (Claude can run the checks), A2 (rewritten around the runner), and two new items were added: **A4** (frame time of the generated arena: `tools/baseline.gd` still measures the roundabout) and **E5** (reset progress).

**Found and left for the items named, or for a decision:**
- CI never runs the 44 checks (it lints, checks the format and loads the project), so a change can turn a check red unnoticed; `gdlint` and `gdformat` also skip `tools/*.gd`. (A2.6)
- The weapons branch's wording and this README disagree about weapons in the shop pool (Milestone B "Unlock additional weapons in shop pool", Milestone I "adds them to the shop pool", `data/README.md`). Not edited now because the branch edits the lines next to them and the merge would conflict. (A1.6)
- `roadmap/level-rewards` makes XP about 7 times slower, which breaks the weapons branch's note that level 5 takes one or two runs; moot while the melee lock is dropped, but the XP numbers need an owner decision. (C4.2)
- The README is about 70,000 tokens, nearly all of it the long "how it was built" note after each ticked item. It is hard to scan and hard for any tool to read in one go. **Suggestion, not done:** move each long parenthetical to `docs/ROADMAP_HISTORY.md` and leave one line plus a link per item. Do it after A1 so the weapons branch does not conflict, and together with A2.7.
- Open items that look done but are not: Milestone A "Support separate leaderboards per difficulty" (needs Heat, so not alpha), Milestone D "Night modifier" (the NIGHT theme exists and nodes use it, but not as a modifier).

---

# Roguelite Development Roadmap

> The game is already most of the way to a roguelite. It has runs made of rounds, a shop, perks that pair into duos, and bosses. Almost everything on this list is a layer on top of that, plus the missing "between runs" progression.

## Proper version control
- [x] GitHub

## Big Design Choice

- [x] Decide on the game's long-term direction
  - [x] Full roguelite focus (recommended)

### Recommended Roguelite Structure

- [x] Create runs of ~10 rounds
- [ ] Target 20–30 minute run duration
  - [x] Add a run timer (run summary + console log per round) to measure it
  - [ ] Tune round length once real run times are known
- [x] Add final boss encounter (reuses the golden president model)
  - [ ] Give the final boss its own model, attacks and arena moment
- [ ] Implement permanent unlocks between runs (partly done: coins, buying, starting perks and the Loadout page work, see Milestone I; the rest is alpha C1 to C5)
- [ ] Balance pass for the 10-round difficulty curve (rider speed, boss health, final boss health)

---

# Milestone A: Menu, Game Flow, Saves & High Scores

## Menu & Game Flow

- [x] Create title screen
  - [x] Play button
  - [x] Loadout button (opens a "coming soon" page until loadouts exist)
  - [x] Unlocks button (opens a "coming soon" page until unlocks exist)
  - [x] High Scores button
  - [x] Settings button
  - [x] Quit button

- [x] Create proper pause menu

- [x] Create run summary screen
  - [x] Display score
  - [x] Display kills
  - [x] Display accuracy
  - [x] Display best style rank
  - [x] Display newly unlocked items (shows "nothing this run" until the unlock system exists)

- [x] Connect existing settings system to menus

### Menu follow-ups (found while checking the list)

- [x] Keyboard and gamepad navigation for the settings panel (sliders were mouse-only)
- [x] Controls / "How to play" page (the long controls text was removed from the title screen)
- [x] Pause automatically when the game window loses focus
- [x] Confirm before Restart Run / Quit to Title (a run is lost with one click)
- [x] Optional: "Continue" button to resume an interrupted run
- [x] Reset all progress button at the bottom of the settings panel (red, two warnings)

## High Scores

- [x] Implement local Top 10 leaderboard
- [x] Add player name entry
- [ ] Support separate leaderboards per difficulty (needs a difficulty system first: build it together with Heat in Milestone B, then split the boards by Heat level)
- [x] **BUG:** the DELETE key does nothing (it is printed on the page and described below, but no code handles it; `scores_reset_check` fails on it, alpha A2.2). The button click and gamepad X work. Reset leaderboard option (F8 used to reset only the old single high score and is gone now)
- [x] Show run time on the leaderboard (it is already saved with each entry)
- [x] Use the leaderboard's best entry for the HI score shown in the HUD, and retire `hi.dat`

### Daily Seed Mode

- [x] Generate a daily seed
- [x] Use same seed for all players on that day
  - [x] Separate "Daily Run" entry on the title menu; normal Play stays fully random
  - [x] Seed only the run layout (rider mix, shop and upgrade offers, starting boss and lighting theme), not moment-to-moment combat
- [ ] Make the Daily Run feel different from a normal run
  - [ ] One shared daily modifier for everybody that day (chosen from the seed, shown on the title screen and in the run bar), such as double riders, rain or fast riders
  - [ ] Shareable result card: the date, seed, score, time, rounds and caches, as an image or text the player can copy

### Deferred

- [ ] Online leaderboard (future feature; the website, the login and the API it needs are planned in Milestone N)
  - [ ] Submit scores to Django web leaderboard
    - [ ] Implement REST API on Django web service
    - [ ] Implement Seed and leaderboard display

---

# Milestone B: Meta Currency, Unlocks & Skins

## Meta Progression

- [x] Add meta currency
  - [x] Earn from score
  - [x] Earn from boss kills
  - [x] Earn from challenges
    - [x] Write the challenge list (`data/challenges.json`, described in `data/README.md`: five challenges, each with an `id`, `name`, `desc`, `condition` key, `scope` (round or run), `target`, meta coin `reward` and save `counter` name; a challenge pays at most once per run. Loaded by `scripts/challenges.gd`, see the next item) (a data table like `data/items.json`, each with a condition, a reward in meta coins and a counter in the save file, see `docs/SAVE_FILES.md`): clear a round without using the gun, take every cache before the last rider falls, perfect-dodge five riders in a row, clear a round without losing a life, finish a run in under 20 minutes
    - [x] Show them on the run summary (done, new, progress) and on a page of the title menu
    - [x] Optional: achievements for the same list, with a name and a small icon

- [x] Keep meta currency separate from run cash

## Meta Unlocks

- [x] Unlock starting perks (done under Milestone I: buy them on the Unlocks page, choose one on the Loadout page, and a run starts with it)
- [ ] Unlock additional weapons in shop pool (wording out of date: weapons are bought and then chosen on the Loadout page, never found in the shop; see alpha A1.6)
- [ ] Unlock cosmetics

## Difficulty Scaling

- [ ] Implement Heat system
- [ ] Allow multiple Heat modifiers
- [ ] Increase rewards for higher Heat levels

## Cosmetics & Skins

### Weapon Cosmetics

- [ ] Dart gun skins
- [ ] Worm skins

### UI Cosmetics

- [ ] Crosshair skins
- [ ] Hit effect skins

### World Cosmetics

- [ ] Cheerleader skins
- [ ] Rider bike skins
- [ ] Rider helmet skins

### Easy Cosmetic Variants

- [ ] Colour swaps
- [ ] Material swaps

---

# Milestone C: Weapon System Expansion

## Weapon Slots

- [x] Add primary weapon slot
- [x] Add melee weapon slot
- [x] Add gadget slot

### Choosing weapons: unlock, then pick a loadout

> Decided with the owner. New weapons are **bought first** with meta coins on the Unlocks page (the four weapons are already in `data/unlocks.json` as `planned`; the dart gun is bought too since alpha C2, `weapon_dart_gun`; **the melee weapon is not meant to stay always owned: see "Melee weapon is locked at the start" below**). Before a run the player **chooses one weapon per slot** (primary, melee, gadget) on the Loadout screen, and the run starts with those three equipped through `equip_primary`, `equip_melee` and `equip_gadget`. Weapons are not found or bought inside a run, so they leave the shop pool (the "joins the shop pool" note in `data/README.md` changes when the first weapon is built). **A Daily Run still allows choosing a loadout** of weapons (everyone shares the seed, not the weapons). Q / wheel / 1 / 2 keep switching between the primary and the melee weapon; a gadget is used on the spot with its own key and is not switched to. Assumed slots for the new weapons: Suction-Dart Crossbow, Confetti Cannon and Phone Launcher are primary weapons, the Stink Bomb is a gadget (say if the Phone Launcher should be something else). Decided: a custom-seed run uses the chosen weapons too, and the starting perk of the Loadout page now applies in a Daily Run and a custom-seed run as well (it did not before).

- [x] Loadout screen: choose primary, melee and gadget before a run
- [ ] HUD slot display: show the primary, melee and gadget slots with the weapon in each and the one in the player's hands highlighted (replaces the `DARTS / [Q] SWITCH` text in the bottom right)
- [ ] Gadget use key (keyboard and gamepad button): uses the gadget on the spot, with a cooldown or a number of uses shown in the HUD slot display; built together with the first gadget (Stink Bomb)
- [ ] Melee weapon is locked at the start, and unlocks very fast: **after the alpha** (decided with the owner in C1: for the alpha the melee weapon stays owned from the start). The full text is under "Not in the early alpha" in the Early Alpha Roadmap.

## New Weapons

### Dart Nerf Pistol

> A small, single-dart nerf pistol: one dart per trigger pull, no pump, light and quick. It is meant to **replace the dart gun as the starting primary weapon** (the starting weapon is switched last, once the pistol is built and its upgrades work, so the game stays playable meanwhile). Assumed: it is a primary weapon (`PRIMARY_WEAPONS` in `scripts/weapon_slots.gd`) with its tuning in `data/weapons.json`, the dart gun stays in the game as a primary weapon that can be unlocked later (say if it should go instead), and all numbers below are first guesses to tune by playing.

- [x] Implement weapon
- [ ] Create upgrade path (five tiers, bought in the run like the other upgrade tiers of `data/items.json`, each one stronger and dearer than the last; the pistol's tuning numbers grow with the tier):
  - [ ] Tier 1, Spare Darts: bigger clip
  - [ ] Tier 2, Quick Loader: shorter reload
  - [ ] Tier 3, Steady Grip: less spread and less bloom while shooting
  - [ ] Tier 4, Hair Trigger: faster fire rate
  - [ ] Tier 5, Hard-Tip Darts: more damage per dart (the last tier, so it pays off after the others)
- [x] Make it the starting primary weapon

### Suction-Dart Crossbow

- [ ] Implement weapon
- [ ] Add piercing mechanic
- [ ] Create upgrade path

### Confetti Cannon

- [ ] Implement weapon
- [ ] Add area damage mechanic
- [ ] Create upgrade path

### Stink Bomb

- [ ] Implement weapon
- [ ] Make riders swerve
- [ ] Create upgrade path

### Phone Launcher

- [ ] Implement weapon
- [ ] Create upgrade path

## Synergies

- [ ] Create perk interactions
- [ ] Create duo synergies with existing perk system

---

# Milestone D: Run Map, Relics & Modifiers

## Run Structure

- [x] **BUILT, NOT FULLY USED YET:** a run walks the map, but `shop`, `rest`, `elite` and `event` nodes all play an ordinary round (alpha B1 to B5). Replace linear round progression

### Map Nodes

- [x] Normal encounter (works: the node's content sets the theme, the rider count and mix and the open gates, see Milestone K "Connect the arena to the run map")
- [ ] Elite encounter (an elite node has 10 to 12 riders and 40 % armoured ones, and since alpha B4 a second upgrade pick on clearing it; built on branch `roadmap/b4-elite-extra-upgrade`, waits for the owner's run, B4.4)
- [ ] Shop (alpha B1, B2; today a shop node plays an ordinary round)
- [ ] Event (left out of the alpha, event weight set to 0 in alpha B5)
- [ ] Rest stop (alpha B3; built on branch `roadmap/b3-rest-node`, a rest node is now a screen with REFILL HEARTS or EXTRA UPGRADE; waits for the owner's run, B3.5)
- [x] Boss node (works: a boss node has its boss after every rider is down, and the last one is the final boss, see Milestone K "Connect the arena to the run map")

## Relics

- [ ] Implement relic system
- [ ] Add rule-changing relic effects

## Curses

- [ ] Add risk/reward curse system

## Round Modifiers

- [ ] Night modifier (the NIGHT theme exists and nodes use it, but not as a modifier a node can add)
- [ ] Rain modifier (nodes can carry it, but it has no effect; switched off in alpha B5)
- [x] Double riders modifier (works: `double_riders` makes every wave a pair and shows DOUBLE RIDERS at the start of the round, `has_modifier` in `scripts/main.gd` and `scripts/riders.gd`)
- [ ] Additional modifier ideas

## New Arenas

> These become arena styles of the procedural arena generator (Milestone K), chosen once per run, instead of hand-built scenes.

- [x] Bridge arena (now the `bridge` arena style, see Milestone K "Arena styles chosen by the seed")
- [x] Market arena (now the `market` arena style)
- [x] Tunnel arena (now the `tunnel` arena style)

---

# Milestone E: Polish & Accessibility

## Dynamic Presentation

- [ ] Dynamic music system
- [ ] Scale intensity with style rank

## Onboarding

- [ ] Short tutorial
- [ ] Key rebinding

## Accessibility

- [ ] Directional warning sounds for riders: a bike bell or horn from a rider that is close and approaching from behind or the side (louder and panned by its direction, louder the closer it gets and the faster it closes), so a player can hear what the threat arrows and the radar show; also helps players who miss visual cues. Builds on the 3D audio item S7 and `closing` and `dist` in `threat_list` (`scripts/main.gd`); a setting to turn it off or make it quieter
- [ ] English localization
- [x] Screen shake and screen flash intensity options (reduced-motion / photosensitivity)

## Release Readiness

- [x] Rename the game from FstreliBiciklina3D to FB3D everywhere the player can see it: the title screen and logo text, the window title, the credits screen and any other in-game text that shows the name. This is a small change. The internal name stays as it is: the GitHub repository, the folder and file names, the project files and the docs keep "FstreliBiciklina3D", so no clone URLs, CI links or save files change (the Godot project name in `project.godot` also stays, because `user://` follows it and the old settings, scores and meta currency must keep loading, see `docs/SAVE_FILES.md`)
- [x] Create app icon
- [x] Configure Windows export presets
- [x] Show the game version on the title screen
- [x] Bring `README.txt` up to date

## Code signing

> Added 2026-10-27 at the owner's request. A certificate Windows trusts costs money, so the first step is a **self-signed** one, which is possible and free. What it gives and what it does not (checked against Microsoft's [Code signing options for Windows app developers](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options)): the exe carries a signature that shows it was not changed after signing, and Windows treats it as signed on a computer where the certificate was installed as trusted (the owner's, or a tester's who chooses to). It does **not** remove the SmartScreen or "unknown publisher" warning for anybody else: Windows does not trust a self-signed certificate by default, and Microsoft describes it as meant for development, testing and internal use, not for public downloads.

- [ ] Before any certificate file exists, extend `.gitignore` with `*.pfx`, `*.p12`, `*.pem`, `*.key` and `*.crt` (this is the second item of "Keeping secrets out of the public repository" in Milestone N: do it now and tick both). This repository is public, see "Secrets and credentials".
- [ ] Create the self-signed code signing certificate on the owner's Windows machine (Godot's Windows export page links Microsoft's guide for creating one; in PowerShell `New-SelfSignedCertificate -Type CodeSigningCert` is the usual way). Export it as a `.pfx` with a password and keep the file and the password outside the repository (the owner's user folder and a password manager). Write the certificate's SHA-256 thumbprint and its expiry date in `docs/` (the thumbprint is public, the file and the password are secret) so testers can compare it.
- [ ] Decide `binary_format/embed_pck` in `export_presets.cfg`. It is `true` today, and Godot's documentation says an exported exe with an embedded PCK breaks signing (it also says embedding can trigger antivirus false positives). Signing means `false`: the export becomes `FB3D.exe` and `FB3D.pck` side by side, and the E2 smoke test (E2.2, E2.3) and the installer in Milestone N have to treat the two files as one build.
- [ ] Set up the export: `SignTool.exe` from the Windows SDK, its path in Editor Settings > Export > Windows (Sign Tool), and in the Windows preset `codesign/enable=true` with the identity type and the `.pfx` as identity. **Leave the password out of the tracked `export_presets.cfg`**: Godot reads it from the environment variable `GODOT_WINDOWS_CODESIGN_PASSWORD` (the identity type and the identity have `GODOT_WINDOWS_CODESIGN_IDENTITY_TYPE` and `GODOT_WINDOWS_CODESIGN_IDENTITY`), the same rule as the PCK encryption key under "Secrets and credentials". Decide whether to timestamp (`codesign/timestamp` is `true` and `codesign/timestamp_server_url` is empty today); a timestamp keeps the signature valid after the certificate expires.
- [ ] Export and verify: FB3D.exe > Properties > Digital Signatures shows the signature, and `signtool verify /pa build\windows\FB3D.exe` reports it as untrusted on a computer without the certificate (expected) and as valid after the certificate was imported as a trusted root and trusted publisher on the owner's test machine. Then repeat E2.2 and E2.3 with the signed build: it starts and the saves are still found in `user://`.
- [ ] Tell testers in `docs/ALPHA_NOTES.md` (E4.2): the build is self-signed, here is the thumbprint, Windows will still warn, and importing the certificate is optional and only for people who trust the owner (it makes Windows trust anything signed with it). Never ask a player to import it.
- [ ] Before a public release, decide about a certificate Windows trusts (the "decide about code signing" part of Milestone N "Installer and auto updates"). The options on Microsoft's page, with prices as of 2026-10-27: Azure Artifact Signing, about $9.99 a month (individuals only in the USA and Canada, organisations in the USA, Canada, the EU and the UK); an OV certificate, $150 to $300 a year, worldwide, with the private key on a hardware token or HSM; an EV certificate, $400 or more a year, which since 2024 no longer skips SmartScreen and so is not worth the premium for that; and [SignPath Foundation](https://signpath.org/)'s free signing for open source projects, where the signature is issued to SignPath Foundation and not to the owner (this repository is public but has no `LICENSE` file today, so read their conditions first). All of them still show SmartScreen warnings until the signed program has built up a reputation.
- [ ] Sign the installer as well once it exists (Milestone N); the update download there already says it checks "its checksum (and signature)".

---

# Milestone F: Graphics & Sound Overhaul

> Complete, hard overhaul of how the game looks and sounds. The current toon look (outlines, flat unlit colours, smooth primitive models) is removed and replaced by a chunky, rugged low-poly style with strong light and dark contrast and glowing accents, inspired by the Deep Rock franchise and built to run on low-end PCs. Direction and rules: [`docs/ART_DIRECTION.md`](docs/ART_DIRECTION.md). Free asset sources and licences: [`docs/ASSET_SOURCES.md`](docs/ASSET_SOURCES.md).
>
> **3D models: Claude is the 3D modeler.** Models are written as Python scripts for **Blender used as a Python module (`bpy`)**, kept in `tools/models/`, and exported as `.glb` into `assets/models/`. Claude cannot run Godot in its working environment, so every model step ends with an in-game check by the owner.
>
> Work top to bottom, one checkbox at a time. Each step is done when the old version of that thing is fully replaced, it passes the readability rules in the art direction, frame time is within budget, and there is a before/after screenshot.

## Graphics

### F1. Foundation (before any new asset)
- [x] Answer the first open questions (minimum spec, who makes models, references, bright look): done, see `docs/ART_DIRECTION.md`
- [x] Answer the remaining questions (UI language, ammo on the weapon, rarity colours, hazard-stripe motif, logo): done, see section 9 of `docs/ART_DIRECTION.md`
- [x] Record the "before" baseline: screenshots of every screen and theme, plus frame time
- [x] Set up the model pipeline (Claude as modeler, Blender as a Python module `bpy`): scripts in `tools/models/`, output to `assets/models/*.glb` with a preview sheet per model in `docs/model_previews/`, automatic budget and file validation, conventions (1 unit = 1 metre), and an in-game model viewer (`tools/viewer/model_viewer.tscn`). How to use it: `tools/models/README.md`
- [x] Build the shared style kit: bevelled primitive helpers, the colour palette and material set (`tools/models/kit/`), and a test model (`test_crate`)
- [x] Owner check: open `tools/viewer/model_viewer.tscn` in Godot (F6) and confirm `test_crate` looks right in the game (colours, bevels, hazard stripes, the glowing lamp, scale) (confirmed by the owner)
- [x] Create `CREDITS.md` and the rule that every third-party asset gets an entry when it is added (see `CREDITS.md`; the voice recorders' names are still to be added under S6)
- [x] **BUILT, LEAVES DEAD CODE:** `Toon.ENABLED = false` leaves the outline code in `scripts/toon.gd` unused until F12 removes it. Switch off the outline pass and flat unlit toon materials behind a flag; simple lit low-poly materials become the default
- [x] Lighting baseline for DAY: bright sun with soft readable shadows, light sky, tone mapping, glow on gameplay accents
- [x] Lighting for GOLDEN HOUR, DUSK and NIGHT (warm lamp pools and lit windows, medium-dark sky, nothing hides in the dark)
- [x] Test the Compatibility renderer against Forward+ on old hardware and decide which to ship
- [x] Anti-aliasing choice (MSAA or cheaper FXAA) and re-define the F9 quality presets for the new look

### F2. Dart gun (first person)
- [x] Viewmodel setup: separate camera and FOV so the gun never clips into walls (`scripts/viewmodel.gd`; checked in game by the owner: no clipping, same look, frame time fine; `VIEWMODEL_PASS = false` in `main.gd` switches it off)
- [x] Chunky low-poly gun model with a hand-painted texture
- [x] Idle sway and walk / sprint bob (written in `update_gun` in `scripts/player.gd`, tuning constants at the top of that file; waiting for your in-game check: breathing sway, walk and sprint bob, and a small lag when you turn; all of it fades out while aiming)
- [x] Shoot and recoil animation (springy kick-back, muzzle rise and a little roll that overshoot and settle, rapid fire stacks up to a limit; `update_kick` in `scripts/player.gd`, tuning constants at the top of that file; waiting for your in-game check)
- [x] Pump / reload animation
- [x] Aim-down-sights pose and crosshair behaviour
- [x] Dart and shell models
- [x] Muzzle flash and shell ejection
- [x] (Optional) Ammo count shown on the gun itself

### F3. Melee
- [x] Chunky model with a glossy rubber material
- [x] No alternating colors (the whole club is one glossy pink; the light and dark pink ribs of the old worm are gone; confirmed by the owner in game)
- [x] More detail (like the Dart gun)
- [x] More rubbery look (glossy jelly material with toon highlights and a pink rim glow, ridges and rings that bend with the wobble, a squash and stretch on every swing and a flash on every hit; confirmed by the owner in game)
- [x] No eyes (the new club has none; confirmed by the owner in game)
- [x] Rubbery wobble swing animation
- [x] Hit, deflect and phone-return feedback

### F4. Riders and bikes
- [ ] Base rider and bike model ("pro") with a rig
- [ ] Pedal, lean and steer animation cycle
- [ ] Sprinter variant
- [ ] Courier variant
- [ ] Armoured ("tough") variant, including the dismount and charge animation
- [ ] Variation kit: helmets, clothes and bike colours (also the base for rider skins in Milestone B)
- [ ] Hit reactions, crash and the parts that fall off
- [ ] Readability check of all riders against all four themes

### F5. Thrown phones
- [ ] Desk phone model
- [ ] Throw, flight trail and smash effect

### F6. Pedestrians and cheerleaders
- [ ] Pedestrian models (several body types and outfits) and walk cycle
- [ ] Pedestrian hit reaction
- [x] Rim glow (fresnel) that tells foes from bystanders: red-orange on riders and bosses, green-cyan on pedestrians and cheerleaders
- [ ] Pedestrian vs rider readability check, including NIGHT (the rim glow above is the first help for it; the check itself waits for the in-game look)
- [ ] Cheerleader models and animations

### F7. Bosses
- [ ] Rogue lawnmower (model, animation, attack telegraphs)
- [ ] Mesh wifi adapter (model, hover, animation, attack telegraphs)
- [ ] Minister (model, animation)
- [ ] Golden president / final boss (model, animation, intro moment)
- [ ] Angry cyclist
- [ ] Boss health bar, weak-spot marker and defeat effects

### F8. Pickups
- [ ] Pickup models or icons for rapid fire, fat darts, slow motion, shield, extra life and cash
- [ ] Glow, pickup and magnet effects

### F9. World
- [ ] Road, lane markings and curbs (stylised asphalt and concrete)
- [ ] Central fountain
- [ ] Buildings (chunky facade kit with windows that light up at dusk and night)
- [ ] Tunnel
- [ ] Props: lamps, benches, trees, bins, signs
- [ ] Ambient life: passing cars, birds and other background motion
- [ ] Weather and atmosphere touches per theme

### F10. Effects
- [ ] Dart impact and hit sparks
- [ ] Dust, debris and rider crash effects
- [ ] Boss telegraphs (lane strip, slam circle, volley warning) as bold glowing overlays or decals
- [ ] Hype, shield and slow-motion screen effects
- [ ] Damage vignette and screen response
- [ ] Confetti (perfect round, victory)

### F11. UI and menus
- [ ] UI theme: condensed bold font, dark translucent panels with amber accents, icons, key-hint chips (see section 4 of the art direction)
- [ ] HUD top bar (hearts, score, round, round progress)
- [ ] HUD bottom (ammo, dash, style rank), crosshair and hit marker
- [ ] Threat arrows, radar and floating popups
- [ ] Upgrade and shop cards (header, icon, reroll button, key hints; rarity tags are optional and can come later)
- [ ] Title screen with a live 3D background and a text-only logo
- [ ] Pause menu and settings panel (amber buttons, hazard-stripe footer)
- [ ] Run summary and leaderboard screens
- [ ] Ultrawide and resolution scaling check

### F12. Final pass
- [ ] Remove `toon.gd`, the outline option and all leftover cartoon assets and code
- [ ] Performance pass on the minimum-spec machine (instancing, shadow and light counts, particle overdraw)
- [ ] Final colour grade and consistency review of every screen and theme
- [ ] Before / after comparison for the repo

## Sound

Where to get free assets, and the licence rules: [`docs/ASSET_SOURCES.md`](docs/ASSET_SOURCES.md). Plan: use professional free libraries for effects and ambience, keep your own voice recordings, and keep the existing synthesised sounds only until each is replaced.

### S1. Foundation
- [ ] Set up the audio pipeline: folders, naming, one loudness target, and a `CREDITS.md` entry for every file
- [ ] Download the sources worth mining (the latest Sonniss GDC bundle, Freesound CC0 / CC-BY searches, Kenney) and build a shortlist per sound category
- [ ] Bus layout: Master with Music, SFX, Voice, Ambience and UI buses; voice ducking
- [ ] One volume slider per bus in Settings (only one master slider today)

### S2. Weapons and combat
- [ ] Dart gun: shot, pump / reload, empty click, shell drops
- [ ] Dart impact on rider, pedestrian, boss armour and weak spot
- [ ] Melee: swing, hit and deflect
- [ ] Phone: throw whoosh, flight, smash

### S3. Riders and world
- [ ] Bike and rider loop (with pitch and volume by speed)
- [ ] Footsteps, landing, slide and dash
- [ ] Crashes and falling parts
- [ ] Ambience loops per theme (day, golden hour, dusk, night) and the tunnel
- [ ] Passing cars, birds, sirens and crowd cheer

### S4. Bosses
- [ ] Lawnmower and wifi loops, intro and hit sounds
- [ ] Minister and golden president sounds
- [ ] Boss defeat and final boss defeat stingers

### S5. UI and flow
- [ ] Menu sounds: hover, confirm, back, error
- [ ] Pickup, hype, shield and slow-motion sounds
- [ ] Stingers: round start, round clear, game over, run complete
- [ ] Leaderboard name entry sounds

### S6. Voice lines
- [ ] Normalise all 79 lines to one loudness and remove the unused `voice_old` files
- [ ] Record new lines: run start, final boss intro, victory
- [ ] Note who recorded each line (for the credits)

### S7. 3D audio and mixing pass
- [ ] Distance attenuation, doppler for riders, tunnel reverb
- [ ] Mix pass of every theme and boss fight
- [ ] Remove `tools/bake_audio.py` and the synthesised files once nothing uses them

### S8. Music
- [ ] Music: see "Dynamic music system" in Milestone E

---

# Milestone G: Procedural Map Generation

> **Note 2026-10-27:** several items below say "rounds do not follow the map yet", "nothing reads the rules file yet" or "NOT RUN YET". Those parts are history: a run walks this map (Milestone D) and the checks were run (see "Roadmap audit" at the top). They are left as they were written.

> Works together with the run map in Milestone D: the seed decides the map, and the map decides which encounters, shops and bosses a run contains.

- [x] Generate the run map procedurally from a seed (all three parts below are done; the map is generated and printed to the console, but rounds do not follow it yet: that is Milestone D)
  - [x] Same seed always produces the same map
  - [x] Daily seed produces the same map for every player that day (builds on Daily Seed Mode in Milestone A) (a Daily Run uses the daily seed as its run seed, so it gets the same map as every other player that day; checked headless with Godot 4.7: two Daily Runs started in a row printed the same map)
  - [x] Random seed for normal runs, shown on the run summary so a run can be replayed
- [x] Define the map generation rules (number of nodes, branching, guaranteed shop / rest stop / boss placement)
- [x] **BUILT, NOT FULLY USED YET:** the `seed` that shop, rest and event nodes get is never read, and `rain` has no effect (alpha B2, B3, B5). Generate arena layouts and encounter contents from the seed (the arena layout is the run seed's layout from `scripts/arena_gen.gd` (Milestone K); every map node gets a `content` entry from `scripts/map_content.gd`: theme, rider count and mix, open gates, 0 or 1 modifier, boss kind, or a seed for shop / rest / event nodes; each node has its own generator so one node never changes another and the floors, edges and types of every seed are unchanged; numbers in the `content` section of `data/map_rules.json`, explained in `docs/MAP_GENERATION.md`; `tools/map_check.gd` checks the content of 2,000 maps. Headless check run 2026-10-27 with Godot 4.7: `map_check` PASSED (`python tools/run_checks.py map_check`). (Old note: rounds did not use the content yet, it is used now: that is Milestone D)
- [x] Validate that every generated map is completable (no dead ends, boss always reachable)
- [x] Debug tool: enter a seed and preview the generated map
- [x] Optional: let the player type in a custom seed on the title screen

---

# Milestone H: Run Start Sequence

- [ ] Design the opening sequence (storyboard: bed, house, door, nerf gun, street)
- [ ] Build the bedroom and house interior (small, low-poly, matches the art direction)
- [ ] Wake-up animation: the player stands up from the bed (first-person camera)
- [ ] Walk from the bed to the front door (scripted movement, no player control)
- [ ] Pick up the nerf gun on the way out (the starting one-dart gun appears in the viewmodel)
- [ ] Walk out the door onto the street
- [ ] Screen fades out, then fades back in on the generated map
- [ ] Allow the player to skip the sequence (button or key), and a setting to always skip it
- [ ] Keep the sequence short (target under 15 seconds) and skip it on a restart after dying
- [ ] Hook the sequence into Play and Daily Run, and make sure the seed is already chosen before it starts

---

# Milestone I: Roguelite Progression

> The player starts every run with the simplest possible loadout and earns everything else across runs.

- [x] Starting loadout: the Dart Nerf Pistol and the melee weapon
- [ ] Unlock and buy new weapons with meta currency (adds them to the shop pool)
- [x] **BUILT, NOT FULLY USED YET:** starting perks work (Loadout page); the six shop-item unlocks are sold in the shop only once bought (alpha C3, built on branch `roadmap/c3-shop-unlock-filter`, waits for the owner's check C3.5). Unlock and buy upgrades and starting perks with meta currency
- [x] Unlock screen replaces the "coming soon" Unlocks page (items, price, owned / locked state)
- [x] Loadout screen replaces the "coming soon" Loadout page (choose what you start a run with from what you own)
- [x] Save unlocks and purchases in the versioned save files (see `docs/SAVE_FILES.md`)
- [x] Show newly unlocked items on the run summary screen
- [x] Define the unlock list and price curve in a data table (like `data/items.json`)
- [ ] Balance pass: the first runs with the starting loadout must be winnable but hard, and each unlock should feel meaningful
- [ ] Reset progress option in Settings, with confirmation
- [ ] **PARTLY BUILT:** XP is earned, saved and shown, but a level does nothing yet, on purpose for the alpha (decided in alpha C4). XP and levels (the in-game side; the website shows the same numbers, see Milestone N)
  - [x] Decide what earns XP (for example score, kills, boss kills, finished rounds and runs, challenges) and write the XP table and the level curve in a data table (like `data/items.json`), so the numbers can be tuned without touching code
  - [x] Keep XP and level in the versioned save files (see `docs/SAVE_FILES.md`), separate from meta currency (XP is never spent, it only goes up)
  - [x] Show XP, level and a progress bar to the next level on the title screen, and the XP gained and any level-up on the run summary screen
  - [x] Decide whether a level unlocks anything (items, cosmetics, titles) or is only a number to show off: **for the early alpha a level is only a number to show off** (title screen and run summary); the first use of levels comes after the alpha (alpha C4)
  - [ ] Send XP and level to the website with the other progress (needs the account and API in Milestone N; without an account XP and level still work locally and are only shown in the game), and make sure the server is the one that adds up XP from the runs it is sent, so an edited number in a save file cannot raise a level

---

# Milestone J: Manual Reload

- [x] Remove the automatic reload after a few seconds
- [x] Press R to reload manually
- [x] Automatically reload when the magazine reaches 0
- [x] Cannot shoot while reloading; reloading can be interrupted by dashing or switching to melee (decide the exact rule when building it)
- [x] **BUILT, NOT USED YET:** `reload_started` and `reload_interrupted` have no listener, and the sound and jolt on `reload_finished` are placeholders (after the alpha). Reload animation and sound hooks (builds on the pump / reload animation in F2)
- [x] HUD and ammo label on the gun show the reloading state
- [ ] Add reload to the key rebinding list and the Controls page (the Controls page exists now and lists R and X for reload; key rebinding does not exist yet, so only the rebinding list is left)
- [ ] Rebalance darts per magazine and reload time now that reloading is not free
- [x] Check how perks and items that touch ammo (rapid fire, infinite ammo, fat darts) interact with the new reload

---

# Milestone K: Procedural Arenas

> **Note 2026-10-27:** the notes under Foundation, Generation, Building the world and Generated arena class that say "not used by the game yet", "nothing in the game uses it yet" or "not connected" are history: the generated arena is the default since "Make the generated arena the default" below. They are left as they were written.

> Every run gets one generated arena, about four times bigger than the roundabout, that the player walks through freely and where riders can ride on roads, sidewalks, grass and anywhere open. Design, owner decisions, current-code notes and open questions: [`docs/PROCEDURAL_ARENAS.md`](docs/PROCEDURAL_ARENAS.md). Needs the seed from Milestone G; the world kit from Milestone F9 should be reused for the dressing. This replaces how riders, bosses and pedestrians move (street coordinates become world positions), so it is large: work top to bottom, and the first steps keep the roundabout playing as it does today.

## Decisions

- [x] Size: about 4 times the walkable area (about 6,000 m² against about 1,500 m² now)
- [x] The player walks through the whole arena
- [x] Riders do not lap or follow a fixed lane: they can ride on road, sidewalk, grass, anywhere open
- [x] One arena per run (generated once from the run seed)
- [x] Riders ride toward the player, pass if they are not shot, then turn round in a smooth arc (limited turning rate, never a sharp 180 degree switch) and ride toward the player again
- [x] Map nodes: every node uses the whole arena with its own set-up (rider mix, gates in use, props, theme and modifiers), and the player starts each round in a clear start area (the owner left this choice to Claude, reasons in the design note)
- [x] A rider that passes the player does damage as it does now (same dash and perfect-dodge rules); riders keep coming back until they are killed, with no cap on passes and no time limit (the melee weapon is the fallback), and a round ends when every rider is down
- [x] Decide whether road, sidewalk and grass change rider speed
- [ ] Set the performance budget (triangles, lights, shadows, draw distance) on the minimum-spec machine (deferred by the owner: not needed yet, but needed before the world is built)

## Foundation

- [x] Put the arena behind one `Arena` interface with world-space queries (player bounds, surface at a point, obstacles, gates), with the roundabout as its first implementation (no visible change)
- [x] Move rider, boss and pedestrian movement from street coordinates to world positions with steering and obstacle avoidance (the roundabout must still play the same)
- [x] Player bounds from the arena instead of `PLAYER_R_MIN` / `PLAYER_R_MAX`

## Generation

- [x] Arena generator: seed in, terrain layout out (size, roads, plazas, grass, building blocks, gates); same seed, same arena
- [x] **BUILT, NOT USED YET:** `nav_clearance` is used (validation, cheerleader spots), but `nav_cost` is only called by a check; nothing searches the grid (after the alpha). Generate the navigation grid with the layout
- [x] Validate every generated arena (all gates connected, no sealed areas, minimum corridor widths, a clear start area, sightlines)
- [x] Debug tool: enter a seed and preview the generated arena

## Building the world

- [x] Ground surfaces, curbs and markings from the layout
- [x] Place buildings, props, lamps and gates (tunnels, alleys) from the layout (reuse the F9 kit)
- [x] Theme lighting and lit windows on generated arenas

## Generated arena class

> Puts the `Arena` interface on a generated layout (`scripts/arena_generated.gd`, checked by `tools/arena_generated_check.gd`), so the game can be played on a generated arena. One small step at a time, each pushed to its own branch commit. It is the base of the "Connect the arena to the run map" item below.

- [x] Skeleton and ground queries: `surface_at`, `rider_speed_at`, `start_position`, `gates` in world space, `rider_pursuit()` and `rider_avoidance()` true (checked against 200 layouts, and broken on purpose three ways: swapped start axes, flipped gate directions, wrong rider speeds; not used by the game yet)
- [x] Bounds and blocking: `clamp_walk` for player, boss and pickup, `obstacle_at`, `ray_blocked`, `rider_blocked` (open through the gates), `hidden_at` (inside a gate's tunnel)
- [x] Street-coordinate stubs (`tw`, `to_track`, `lim`, `clamp_road`, ...) that return safe values, so code that still thinks in street coordinates cannot crash on a generated arena
- [x] Build the world from the arena: `WorldGen` ground, `WorldDress` buildings, lamps and trees, `Lighting.apply_theme`, handed to `main.gd` in the shape `world.gd` gives for the roundabout
- [x] Switch `main.gd` to a generated arena behind a flag (off by default), with a headless load check and a short scripted run on a generated arena
- [x] Make the generated arena the default and keep the roundabout behind `--roundabout`

## Gameplay on open ground

- [x] Rider pursuit steering: ride toward the player on any open surface, pass, then turn round in a smooth arc and return; spawning at gates
- [x] Round clear rule for riders that cannot escape: the round ends when every rider is down; rework the round progress icons, the "N of 10 hit" count, `NEED`, the perfect-round rule and style and score rules in `main.gd` and `hud.gd`
- [x] Boss attacks (strips, slam circles, volleys) on open ground
- [x] Pedestrians, cheerleaders and pickups placed on generated arenas
- [x] Riders no longer creep into walls in narrow corridors
- [x] Threat arrows, radar and aim assist for attacks from every direction and distance
- [x] Thrown phones and boss volleys respect buildings on open ground (found while playtesting: `update_phones` in `scripts/phones.gd` flies a phone in a straight lob from the rider to the player and never asks the arena, so riders throw phones through buildings, and boss volleys do the same. Two parts: riders and bosses only start a throw when they can see the player, which can reuse `Threats.sight_clear`, and a phone already in flight smashes on the wall it meets (the smash effect and sound exist, `plastic_burst` and `phone_smash`). The roundabout must play as before.
  Done on branch `roadmap/phone-walls` (`tools\run_phone_wall_check.bat` PASSED on the owner's machine and the gameplay was played and looked good): where `arena.rider_pursuit()` is true a rider starts a throw (`scripts/riders.gd`) and a boss throws a phone (`boss_throws` in `scripts/bosses.gd`) only when `PhoneSys.throw_clear` says nothing solid is between them and the player (`scripts/phones.gd`, which reuses `Threats.sight_clear`); a rider whose wind-up ends behind a building holds the phone and tries again after 0.3 s, a boss waits 0.3 s; a phone in flight that meets a building smashes there (`flight_blocked` and `wall_smash`: no hit, no popup, no score). Boss volleys (`do_volley`) are not held back, their phones smash on the wall. Deflected phones flying back are not changed. `tools/phone_wall_check.gd` (`tools\run_phone_wall_check.bat`) checks all of it on a flat test arena with one wall and the roundabout, and it passed; gdlint and gdformat are clean)
- [x] **BUILT, NOT FULLY USED YET:** fight nodes use their content (theme, riders, gates, double riders), but the `rain` modifier is only carried, and shop, rest and event nodes still play a round (alpha B2, B3, B5). Connect the arena to the run map (every node uses the whole arena with its own set-up)

## Exploration and extraction

> The round no longer ends by itself when the last rider falls. Supply caches are spread over the (now bigger) arena for the curious, and once every rider and boss is down an extraction point opens at the far end and the round is cleared when the player walks into it. Built on branch `rework/caches-extraction-point-fresnel-wip-crash-on-round-end`, which is a work in progress (commit "WIP rework", then "Crash fix"): nothing here is ticked off as playtested, and the lines that say "waiting for your in-game check" are still to be played. The roundabout has none of it (`objective_sys.enabled()` is false there) and plays as before.

- [x] Pick the spots: an extraction point far from the start and supply caches spread over the arena
- [x] Supply caches
- [x] Extraction point instead of "last rider down ends the round"
- [x] Show them: a line at the top of the HUD (REACH THE EXTRACTION POINT with the distance, or the dimmed EXTRACTION POINT line saying to down every rider to open it) and CACHES n / 4 under it; a world marker for the point (a diamond with its distance, or an arrow on the screen edge when it is behind or to the side) and for each cache within 45 m; and on the radar a green square (dim until it opens) for the point and gold diamonds for the caches in range (`_draw_objective`, `_world_marker`, `_draw_radar_objectives` in `scripts/hud.gd`)
- [x] Crash fix: `clear()` in `scripts/objective.gd` stopped with "Trying to assign invalid previously freed instance" when the player reached the extraction point after taking a cache
- [x] Checks
- [ ] Playtest the objectives: do the caches pull the player across the map, is the extraction walk too long on a 144 m arena once the riders are down, do `CACHE_CASH`, `CACHE_SCORE`, `CACHE_COUNT` and the 45 m sense range feel right (first guesses in `scripts/objective.gd`)
- [ ] Riders and pickups on the bigger arena: riders spawn at the gates and ride at the player over a map about twice as wide, so check that a round is not too slow, and whether the extraction point should open earlier or the arena be smaller for the early rounds
- [x] Extraction on other nodes: shop, rest, event and elite nodes (Milestone D) have no riders to put down, so decide what, if anything, they use the extraction point for
- [x] Ambush when the extraction point opens: the walk to the point is quiet today because every rider is already down, so send a short last wave or reinforcements through the gates once it opens (a few riders, or a boss node's escort), so the walk is a moment of its own and the caches become a trade-off between the gold detour and the straight run out. Decide the size and the timing while building it, and keep the round clear rule (`finish_wave_set`, `objective_reached`) and the perfect-round rule working
- [ ] Caches with a catch (today they are pure reward): some of the 4 caches get a variant, chosen by the same seeded stream so the Daily Run gives everybody the same ones
  - [ ] Cursed cache: pays more but calls riders from the nearest gate when taken
  - [ ] Locked cache: needs a key that is found at another cache or dropped by a rider
  - [ ] Vanishing cache: a countdown starts when the player comes within range, so it has to be taken quickly
  - [ ] Mark the variants on the HUD and the radar so the player can tell them apart (colour and shape, not colour alone)
- [ ] Choose your exit: the arena has several gates and the run map branches, so the extraction point could be one per exit gate, each matching a next node on the map (the player leaves through the gate of the node they want), instead of one fixed point. Needs the node choice (`pick_node`, Milestone D) to be made on the way out instead of on the map screen, and the HUD, radar and world markers to show more than one point
- [x] Arena map (hold M; it was a pause-screen map first): a top-down view of the arena, shown while M is held, showing the layout the player has explored, the start, the gates, the caches (taken and not) and the extraction point; a cache or the point is revealed when the player first comes within sense range, so exploring is rewarded and nothing is shown that the player has not found. Reuse the drawing from `tools/viewer/arena_viewer.tscn`

## Rider variety and arena hazards

> Riders ride at the player, pass, turn and come back (`scripts/riders.gd`). On the bigger arena a few more patterns would make fights different from each other, and the buildings the arena already has could be part of the fight. Ideas to decide on before building; each must keep `rider_pursuit_check` and `round_clear_check` working (a round still ends when every rider is down, so no pattern may leave a rider that cannot be reached).

- [ ] Riders that flank in pairs: two riders that come in by different gates and reach the player from two sides, or one that peels off to the side while the other rides straight on
- [ ] Ambush rider: waits behind a building near the player's path and rides out when the player comes within range (needs `Arena.rider_blocked` and the sight rule `Threats.sight_clear` to pick the spot; show it on the radar only once it moves, and decide how it reads with the rim glow)
- [ ] Heavy rider that blocks a road: slow, tough and wide, it rides along a road and forces the player to go round or shoot it down; check that the other riders' obstacle avoidance (`avoid_obstacles`) copes with it
- [ ] Riders crash on the arena: a rider that hits a building, lamp post or tree at speed crashes (the crash and falling-parts effects of F4 and F10 are the model), and a startled pedestrian group can be ridden into, so the player can use the arena as a weapon. Decide what a crash pays (score, style, a `kill` for the round count) and make sure a rider that crashed by itself still counts as down
- [ ] Add the new rider kinds to the map content (`scripts/map_content.gd`, `rider_plan`) and the rider mix numbers in `data/map_rules.json`, so the node decides which of them appear

## Height: hills, walkways and stairs

> Every arena is flat today: the ground is made of flat meshes at y 0 (`WorldGen.build_ground`), and `Arena.surface_at` only says what the ground is made of, not how high it is. Small hills, raised walkways and stairs would turn the arena into real 3D ground to fight on. It is a big change because height touches the layout, the ground, the `Arena` interface, riders, aiming and jumping, so it is split into small steps, and the flat arenas and the roundabout must keep playing exactly as they do now until a step says otherwise. Milestone L (jumping) and this section affect each other (jump height, "Keep the player inside the arena while jumping"), so decide the numbers together.

- [ ] Raised terrain: small hills, walkways and stairs, so the arena is not just a flat map
  - [ ] Decide the height model before building anything: a height per cell beside the ground grid (steps of about 0.5 m, smooth for hills, stepped for stairs and ledges), how much height there is (small, up to about 3 to 4 m, so sightlines and the radar still work), what counts as walkable (a maximum slope and a maximum step), and whether bikes can ride slopes and stairs
  - [ ] Layout: `ArenaGen.generate` adds a height per cell from the seed (hills on grass and parks, raised walkways over roads and plazas, stairs where two heights meet), with the numbers in `data/arena_rules.json`; the same seed still gives the same arena, and a rule can switch height off so the flat arenas stay
  - [ ] Navigation and validation: the nav grid and `ArenaGen.validate` know climbable and not climbable (a slope or step too steep is a wall), and every gate, cache and the extraction point must still be reachable on foot and by riders, with no cache or start spot inside a hill
  - [ ] Build the ground from the heights in `WorldGen` (hill meshes, stair treads and risers, walkway decks with edges or railings, retaining walls), and stand buildings, props and lamps at the right height in `WorldDress`; the surface, curbs and markings must follow the slope
  - [ ] Height in the `Arena` interface: a `height_at(p)` query, the roundabout and flat arenas answering 0; `clamp_walk`, `obstacle_at`, `surface_at` and `start_position` use it, and the player walks up slopes and stairs smoothly (step-up, no jitter) and stands on the ground height
  - [ ] Riders, pedestrians, bosses and pickups follow the ground height (steering and speed on slopes, spawning at the right height, `rider_speed_at` on stairs), and decide where a rider cannot go (stairs) and how `avoid_obstacles` treats it
  - [ ] Combat and sight with height: darts, aim assist, `ray_blocked`, `Threats.sight_clear`, the radar and the threat arrows, thrown phones and the boss attacks (strips, slam circles, volleys) still work when the rider is above or below the player
  - [ ] Show height in the tools: the arena viewer (`tools/viewer/arena_viewer.tscn`) shades or draws contour lines by height, and a check over many seeds (with a `.bat` script) tests reachability, slopes and that nothing clips into a hill
  - [ ] Playtest and balance: does height make fights better or does it hide riders, are stairs and walkways fun to use, and the cost in frame time on the minimum-spec machine

## Scale, variety and polish

- [ ] Performance pass for the bigger arena (draw distance, culling, shadow and light counts) on the minimum-spec machine (the arena is now 144 m square, about 8 to 12 times the roundabout instead of 4, so the walkable ground, the buildings, the lamps and the gates all grew, and the 4 gold and 1 green light column of the objectives are new draw cost; frame time on weak hardware is not known)
- [x] Arena styles chosen by the seed: plaza, street canyon, market, bridge, tunnel, park (replaces the hand-built arenas in Milestone D)
  - [ ] Look and feel of the bridge and the tunnel: they are walled placeholder boxes with no water edge, no roof or ceiling and the same ground surfaces as the other styles; decide on water or a drop beside the deck, a roof or ceiling lights for the tunnel and a different ground (planks, tiles)
  - [ ] Playtest and balance each style: rider speed, sightlines and run length per style, how a bridge with only 2 gates plays against 3 to 6 riders, whether a tunnel's short sightlines are fair, and the weights (all 1 now; a style can be made rarer by lowering its `weight`)
  - [x] Show the style on the run map or the title screen
  - [x] Show the style on the run map screen too
- [ ] Playtest and balance: rider speed, run length and sightlines on the bigger arena

---

# Milestone L: Jumping

Jumping on Space, so the movement feels like a modern FPS. Space is the dash key today (and the gamepad A button), so the first step is to give dash a new key.

> Feel goal: fast-paced, like a Quake game. Sprints, jumps and dashes chain into each other, and the player can aim and shoot while airborne. Every decision below should be judged against that.
>
> Movement inspiration: the game S4 League (fast, acrobatic third-person shooter movement with wall-jumps, dashes and dodges that chain into each other). Take the feel of the movement, not the exact rules or numbers.

- [ ] Decide the new dash key and gamepad button (Space and A are taken by jumping), and move dash there in the input map, the key rebinding list, the Controls page and the HUD hint under the dash bar
- [ ] Jump on Space: a short hop with gravity, a fixed jump height and some air control (decide the numbers while building it; coyote time and jump buffering make it feel right)
- [ ] Jump on the gamepad (A) and add it to the key rebinding list and the Controls page
- [ ] Decide how jumping mixes with sprint, crouch, slide and dash (can you jump out of a slide, dash in the air, shoot and aim while airborne)
- [ ] Fast, Quake-like movement flow: sprint into a jump without losing speed, start a dash from the air or out of a jump, keep momentum through the landing, and aim, shoot and throw while airborne with no penalty to aim; tune it so chaining sprint, jump and dash is clearly faster than walking and every step of it can be cancelled into the next (decide the numbers while building it, and check it does not make riders, bosses or the arena size feel too small)
- [ ] Wall-jumps (S4 League style): jump off a wall or other solid surface while airborne next to it to get pushed away from it and upwards, with a short window after contact, a limit on how many wall-jumps can chain before touching the ground, and momentum kept through the jump so a run of them climbs or crosses a gap; decide which arena surfaces allow it (buildings and walls yes, the fountain and props to be decided), and check the `Arena` bounds queries (`clamp_walk`, `obstacle_at`) so a wall-jump can never lift the player over the arena edge, which is covered by the "Keep the player inside the arena" item below
- [ ] Side dash / dodge (S4 League style): a quick sideways burst to the left or right, taken from the ground or from the air, with its own short cooldown and key or double-tap input (decide with the dash key above), that can be chained out of a jump, a wall-jump or a sprint and into the next move; decide how it relates to the existing dash and its bar (a separate charge or the same one), and whether a side dash at the right moment counts as a PERFECT DODGE (see the dodge item below)
- [ ] Decide whether jumping over a passing rider counts as a dodge, and keep the PERFECT DODGE rule working as it does now
- [ ] Keep the player inside the arena while jumping: the height must not let the player clear buildings, props or the fountain, so the `Arena` bounds queries (`clamp_walk`, `obstacle_at`) still hold in the air
- [ ] Camera and gun feedback for take-off and landing (viewmodel dip, a small camera kick) and the jump and landing sounds (builds on "Footsteps, landing, slide and dash" in S2)
- [ ] Check darts, melee, hit boxes, aim assist and the radar while airborne
- [ ] Playtest and tune the feel: jump height, gravity, air control, wall-jump push and side dash distance

---

# Milestone M: First and Third Person View

Today the game is first person only (the camera is the player's eyes and the gun and club are a separate viewmodel, see F2). This milestone adds a third-person view and a way to switch between the two at any time. It pairs well with the acrobatic movement in Milestone L, because wall-jumps and side dashes read much better when the player can see their own body, but it does not depend on it.

- [ ] Toggle between first and third person with a key and a gamepad button (decide which, for example a key near the camera and mouse controls), add it to the key rebinding list and the Controls page, and remember the choice in the settings file (see `docs/SAVE_FILES.md`); the switch works mid-round, in the air and while shooting, and pauses nothing
- [ ] Build the third-person camera: behind and over the shoulder, with the camera pulled in when a wall or prop is in the way (so it never clips through the arena), smooth follow and a short blend when switching from first person, plus a FOV and distance that keep riders and bosses readable
- [ ] Player body model for the third-person view (needs a model, since the player has no visible body in first person) built with the model pipeline in `tools/models/`, with idle, walk, sprint, slide, jump, dash and hit animations (the movement ones follow Milestone L); hidden or reduced in first person so it never blocks the view
- [ ] Weapons in third person: the dart gun and the jelly club held by the player model instead of the first-person viewmodel (`scripts/viewmodel.gd` is off in this view), with the muzzle flash, shell ejection, pump animation and club swing still working; the ammo count on the gun and the HUD ammo stay readable
- [ ] Aiming in third person: the crosshair shows where the dart really lands (no mismatch between the camera and the gun), aim-down-sights works with a closer camera, and aim assist, hit boxes and melee reach behave the same as in first person; decide whether a third-person shot starts at the gun or at the camera ray
- [ ] Check every system in both views: threat arrows and the radar, the damage and hit flashes, PERFECT DODGE, the caches and the extraction point, the map and menus, and the screen shake option (`fx_scale`); riders and bosses must not be able to hide behind the camera
- [ ] Playtest and tune both views: camera distance and height, blend speed and whether third person feels fair against riders coming from behind (it must not be a clear advantage or a clear disadvantage compared to first person)

---

# Milestone N: Website, Launcher & Online Services

The game gets a home on the web: a new Django app on the existing website (Django + PostgreSQL + nginx + gunicorn, already running), a launcher where players log in, cloud saves, leaderboards, bug reports, and a proper installer with auto updates. Planning only for now: nothing below is built yet.

> Design rules: the game talks to the website only through a REST API. The website, not the game, is the authority on accounts, XP and levels, leaderboards and which version is current. Only the superuser can publish a new game version. An account is optional (decided): the whole game, with its local saves, leaderboard, unlocks and XP, works without one, and a player who never logs in only misses the web features (cloud saves, online leaderboards, the account page, bug reports through the game). A missing network or a down website never blocks a run either, it only delays syncing.

## Website: Django app and REST API

- [ ] Create a new Django app for the game on the existing website (decide the app name and URL prefix, for example `/fb3d/`), with its own models, migrations, templates and tests, so it does not touch the rest of the site
- [ ] Write down the REST API in a short doc (`docs/WEBSITE_API.md`): endpoints, request and response shapes, error codes, auth headers, the API version in the URL (so an old game build keeps working after the API changes), and rate limits
- [ ] Set up the REST API (Django REST Framework or similar) behind nginx and gunicorn, with HTTPS only, CORS closed (the game is not a browser), and request size limits (saves are small)
- [ ] Keep the game's website code in the repo or next to it (decide which), and describe the deploy steps for Django + PostgreSQL + nginx + gunicorn (migrations, static files, restart) in `docs/`

## Accounts and login

- [ ] Account login through the REST API with username and password (decided: players register on the website only, so the game has no sign-up form, only a login and a "No account? Register on the website" link that opens the registration page; use the website's existing accounts if there are any)
- [ ] Token-based session after login: the launcher gets a token (and a refresh token), keeps it on the player's PC in a protected place (Windows Credential Manager or an encrypted file, never the password), and sends it with every call; logging out deletes it
- [ ] "Remember me": when ticked, the token is kept so the next start skips the login and goes straight on (the launcher checks the token with the website, and shows the login form again if it has expired or was revoked); when not ticked, the token is only kept for this session; a LOG OUT button on the launcher screen forgets it
- [ ] Password handling: the password only travels over HTTPS and is never stored or logged by the game, the website uses Django's password hashing, and failed logins are rate-limited
- [ ] Password reset and email confirmation through the website (reuse what the site already has)
- [ ] Playing without an account (decided: the account is optional): the game starts and plays fully with the local save, nothing in the game is locked behind a login, and the web features are simply not offered until the player logs in; the same goes for a player who is logged in but offline, who syncs later

## Launcher

- [ ] The launcher is the game's first screen (decided: no separate launcher program), shown before the title menu: login form (username, password, "remember me"), a "Register on the website" link, a PLAY button that works logged in or not (a "Play without an account" button next to the login form, and with a remembered "play without an account" choice the screen can be skipped), the installed game version, "update available" status, and a link to the website and the bug report page; with a remembered login it only shows briefly and goes on to the title menu by itself
- [ ] Offline and skip: if the website cannot be reached, the launcher screen says so and lets the player continue offline with the local save (see "Playing without an account" above); the login stays one click away in the title menu or settings (LOG IN / ACCOUNT entry) for a player who skipped it, so they can log in later without restarting
- [ ] Show what is missed without an account in a small, non-nagging way (for example a grey "Online features off: log in" line on the title menu), and never block, delay or repeatedly ask the player
- [ ] Build the launcher login against the REST API, with clear messages for a wrong password, no connection and a server error
- [ ] After login the game knows the account (name, token) for the whole session, so saves, scores and XP go to the right account without asking again; a log out or an expired token drops the game back to playing without an account, it never interrupts a run, but it always tells the player: a clear "You were logged out, log in again to use online features" message (a toast or a notice on the title menu, shown right away, or as soon as the run ends if it happens mid-run) with a LOG IN button, and the login form is shown again on the next start
- [ ] Show the account name, level and XP in the launcher after login

## API key (game to website, in the background)

- [ ] Create an API key for the game build and use it for the background calls between the game and the website (version check, score submit, save sync), next to the player's login token, so calls that do not come from a real build of the game can be rejected
- [ ] Store the key encrypted: on the server only a hash (or the key in an encrypted settings value, not in the repo or in plain text in the database), and in the game build encrypted and obfuscated, not as a plain string in a script or in `project.godot`; keys are never committed to the repository (`.gitignore` and a secrets check in CI)
- [ ] Support key rotation: the server accepts a new and an old key for a while, the game build carries the current one, and a leaked key can be switched off from the Django admin
- [ ] Be honest about the limit in the docs: a key inside a game that runs on the player's PC can be extracted by someone determined, so it is one layer, not the only one. The server must still check the player's token, validate every submitted score and save, and rate-limit per account

## Cloud saves (like Steam Cloud)

- [ ] Keep the local save file exactly as it is today (see `docs/SAVE_FILES.md`): the game always reads and writes the local file, and the cloud is a copy
- [ ] Upload the save to the website for each user after a run ends, when the player quits, and on a timer, in the background and without blocking the game (one current save per account, plus a few older versions to roll back to; decide how many)
- [ ] On login on a new PC (or with no local save), offer to download the cloud save so the player can continue
- [ ] First login of a player who already played without an account: decide how the local progress joins the account (upload it as the account's first cloud save, or ask when the account already has a cloud save: use the cloud save, keep this PC's save, never merge silently), and decide whether runs played before logging in count for the website leaderboards and XP (they cannot be checked by the server, so probably they do not)
- [ ] Conflict handling when the local and the cloud save differ (for example two PCs played offline): compare the save version, the save time and the XP, and ask the player which one to keep ("Use cloud save / Use this PC's save"), never overwrite silently, and keep a `.bak` of whatever is replaced (same rule as the version safety in `docs/SAVE_FILES.md`)
- [ ] Sync status in the game and launcher (synced, syncing, offline, conflict), and a manual SYNC NOW button
- [ ] Server side: store saves per user in PostgreSQL (or on disk with the path in the database), with a size limit, a save-format version check, and the rule that a save from a newer game version is kept but never loaded by an older build

## Save file protection

- [ ] Check what the save files look like today (`settings`, `scores.json`, meta currency, unlocks): which ones hold anything worth cheating with (meta coins, unlocks, XP, level, scores) and which are only settings; protect the first group and leave plain settings readable
- [ ] Encrypt the save files so they cannot be opened in a text editor and edited (Godot's `FileAccess.open_encrypted_with_pass`, or an own format with authenticated encryption), with the key kept out of plain sight in the build (it must work without an account, so it cannot depend on the login)
- [ ] Add tamper detection on top of encryption: a signature or HMAC over the save contents, a check on load, and a clear rule for what happens when it fails (refuse to load that save, keep it as `.bad` for inspection, fall back to the last good backup or a fresh save, and tell the player)
- [ ] Keep it compatible with the versioned save files (see `docs/SAVE_FILES.md`): an old plain save from before this item is read once, upgraded and written back encrypted, and a `.bak` is made first
- [ ] Do not trust the client for anything that matters online: the server checks submitted scores, recomputes XP from the runs it is sent, and treats a cloud save that fails its signature or has impossible values as invalid
- [ ] Be honest about the limit in the docs: a determined player can always attack a game on their own PC, so the goal is to stop casual editing in a text editor, and to keep cheated saves and scores off the website's leaderboards
- [ ] Check: `tools/save_protection_check.gd` (with a `tools\run_save_protection_check.bat` next to it, as the testing rule asks) saves, loads, edits one byte, loads again and checks that the edit is caught

## Leaderboards and the player's account page

- [ ] Submit scores from the game to the website after a ranked run (builds on the local Top 10 and the Daily Run in Milestone A), with the run seed, score, time, kills, rounds and game version, and validate them on the server (sanity limits, the same seed rules as the game, and no scores from versions that are no longer allowed)
- [ ] Website leaderboards: all-time, daily (same seed for everyone that day, see Daily Seed Mode in Milestone A) and per difficulty once Heat exists (Milestone B), with the player's own rank highlighted
- [ ] Leaderboard in the game itself (an ONLINE tab next to the local High Scores page) that reads from the API and shows a clear message when offline
- [ ] Account overview page on the website: account name, level, XP and progress to the next level, runs played, best scores, total kills, bosses defeated and the unlocks the account owns
- [ ] Progression page: XP and level over time (a small chart), recent runs with their results, and challenges or achievements done (when they exist, see Milestone B)
- [ ] Show the same XP and level in the game (see "XP and levels" in Milestone I), and make the website the source when the two disagree
- [ ] Privacy basics: what the website stores about a player, a page that says so, and a way to delete the account and its saves

## Bug reports

- [ ] Bug report page on the website (logged-in players): title, what happened, what was expected, steps to repeat, game version and an optional screenshot, saved in the database and listed in the Django admin with a status (new, seen, fixed)
- [ ] "Report a bug" button in the launcher and on the pause menu that opens the report page, or sends a report through the API with the game version, the account name and the end of the game log filled in (decide which; the log must never include the password, the token or the API key)
- [ ] Limit abuse: one report form rate limit per account and a size limit on text and images
- [ ] Optional: email or message to the owner when a new report comes in

## Installer and auto updates

- [ ] Proper Windows installer (`.exe`), built from the export in `build/windows/FB3D.exe` (see "Configure Windows export presets" in Milestone E): installs into Program Files or the user's folder, adds a Start Menu entry and a desktop shortcut, and has an uninstaller that leaves the saves alone unless asked (decide the tool, for example Inno Setup or NSIS; written as a script in the repo so the build can be repeated)
- [ ] Fill in the Windows version information (`application/file_version` and `application/product_version` in `export_presets.cfg`, read from `config/version`) and decide about code signing the installer and the exe (without a signature Windows SmartScreen shows a warning; the self-signed first step and the choice of a certificate Windows trusts are under "Code signing" in Milestone E)
- [ ] Version check through the website: the launcher asks the API for the newest version (and the minimum version still allowed) when it starts, and shows "Update available" or "Update required"
- [ ] Download and install updates automatically: the launcher screen in the game downloads the new version from the website, checks its checksum (and signature) before using it, keeps the saves, and can roll back if the update fails; decide between a full installer download and a smaller patch
  - [ ] Since the launcher runs inside the game, the running game cannot replace its own files: the game downloads the update, then starts a small separate updater (or the installer in silent mode), quits, and the updater replaces the files and starts the game again; write down which of the two is used and how a failed update restores the old version
- [ ] Release publishing, superuser only: a page in the Django admin (or a small form) where only the superuser uploads a new build, enters its version and release notes, and marks it as the current one; the website stores the file's checksum, nobody else (not even logged-in staff) can publish, and old versions can be kept or withdrawn
- [ ] Show the release notes (what changed) in the launcher before or after an update
- [ ] Decide how the version number is kept in step: `config/version` in `project.godot` stays the one place the game's version is written (see "Show the game version on the title screen" in Milestone E), and the release page on the website reads or checks against it

## Keeping secrets out of the public repository

- [ ] Turn on GitHub secret scanning and push protection for the repository (Settings > Code security), so a push that contains a known key format is blocked
- [ ] Extend `.gitignore` before any secret file exists: `.env`, `.env.*`, `secrets.local.*`, `*.pem`, `*.key`, `*.pfx`, `*.p12`, `*.crt`, `export_credentials.cfg` (already there), `user://`-style save and token files if one ever ends up inside the project folder, and the Django `local_settings.py` or settings override of the website app
- [ ] Add an example file with fake values (for example `secrets.example.cfg`) that shows what the game or the build expects, and have the game, the launcher and the build scripts read the real values from an untracked file or an environment variable
- [ ] Add a pre-commit check (a small script in `tools/`, with a `.bat` next to it as the testing rule asks, plus a one-line install step in this README) that stops a commit if the staged changes contain a key-like string (long random strings, `api_key=`, `password=`, `SECRET_KEY`, `BEGIN PRIVATE KEY`)
- [ ] Add a secrets check to CI (`.github/workflows/ci.yml`, for example gitleaks or a small script over the changed files) that fails a pull request when it finds one
- [ ] Decide where the real keys live: the game-to-website API key and the Django secrets in the server's environment or a protected settings file outside the repository, the CI and release keys in GitHub Actions secrets, and write down who has them and how to rotate them (see the key rotation item above)
- [ ] Write a short "a key leaked" procedure in `docs/` (revoke and replace the key first, then clean the history with `git filter-repo` or similar, check the website logs for misuse, and note that forks and clones keep the old history)
- [ ] Do a one-time look through the existing history for anything key-like before the web integration starts (nothing was found in the current files)

## Suggested order inside this milestone

> Roughly: API doc and Django app, then accounts and login, then the launcher, then the API key, then save protection (before saves go online, so no unprotected save is ever uploaded), then cloud saves, then leaderboards, the account page and XP, then bug reports, and last the installer and auto updates (they need a stable launcher and API first).

---

# Tooling & QA

- [ ] Playtest pass of everything built in Milestone A (title, pause, settings, run, win / lose, leaderboard, name entry). It was written without running the game
- [ ] Bot playthrough balance harness: a headless script (`tools/bot_run.gd` with a `tools\\run_bot_run.bat` next to it, as the testing rule asks) where a simple bot plays whole runs on many seeds (aims at the nearest rider, dashes away from a threat that is about to hit, takes the nearest cache, walks to the extraction point) and logs, for every round, the time, lives lost, damage taken, kills, caches taken and whether it reached the extraction point; a summary per seed and across seeds gives real numbers for the playtest and balance items in Milestone K, the 10-round difficulty curve and the run length target. Reuse `tools/generated_run_check.gd` for the scripted run; the bot does not have to be good, only the same every time, so changes show as changes in the numbers
- [x] CI check on every pull request: GDScript lint / format (gdtoolkit) and a headless Godot project load
- [x] Save-file safety: version the settings and score files so later changes do not break old saves

---

# Technical Refactor (Recommended Before Milestone D)

## Code Structure

- [x] Break up `main.gd` (~3,600 lines)
- [x] Move systems into dedicated modules

## Data-Driven Content

- [x] Move items into data tables (shop items, packs and upgrade tiers are in `data/items.json`; see `data/README.md`)
- [x] Move perks into data tables (perks and duos are in `data/perks.json`; see `data/README.md`)
- [x] Move weapons into data tables (dart gun and melee tuning are in `data/weapons.json`; see `data/README.md`)

## Future-Proofing

- [ ] Make weapon additions easier
- [ ] Make relic additions easier
- [ ] Prepare architecture for potential co-op support

---

# Suggested Development Order

- [ ] Milestone A: Menu, game flow, saves, high scores
- [ ] Milestone B: Meta currency, unlocks, skins
- [ ] Milestone C: Weapon slots and new weapons
- [ ] Milestone D: Run map, relics, modifiers
- [ ] Milestone E: Polish, tutorial, music
- [ ] Milestone F: Graphics and sound overhaul (art direction first; can start any time after Milestone A)
- [ ] Milestone G: Procedural map generation (build together with the run map in Milestone D)
- [ ] Milestone H: Run start sequence (needs the map from Milestone G to fade into)
- [ ] Milestone I: Roguelite progression (builds on the meta currency and unlocks in Milestone B)
- [ ] Milestone J: Manual reload (small and independent, can be done at any time)
- [ ] Milestone K: Procedural arenas (big: replaces how riders and bosses move; start with the "Foundation" steps, which keep the roundabout playing as today)
- [ ] Milestone L: Jumping (small and independent; Space is the dash key today, so dash moves to another key first); now also holds the fast S4 League style movement: wall-jumps and the side dash / dodge
- [ ] Milestone M: First and third person view (needs a player body model; best after Milestone L, so the new movement can be seen on the character)
- [ ] Milestone N: Website, launcher and online services (Django app and API, login, cloud saves, save protection, leaderboards, bug reports, installer and auto updates; mostly independent of the gameplay milestones, but XP and levels live in Milestone I, and the online leaderboard builds on Milestone A)