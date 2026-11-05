# Save files

The game keeps four small files in Godot's `user://` folder (on Windows: `%APPDATA%\Godot\app_userdata\<project name>\`).

| File | Written by | Format | Version |
|---|---|---|---|
| `settings.cfg` | `scripts/settings.gd` | ConfigFile; the version is `[meta] version` | 1 |
| `scores.json` | `scripts/scores.gd` | `{"version": 1, "entries": [...]}` | 1 |
| `meta.json` | `scripts/meta.gd` | `{"version": 1, "balance": n, "total_earned": n, "owned": [unlock ids], "start_perk": unlock id, "loadout": {slot: weapon id}, "challenges": {counter: n}, "xp": n, "heat_open": n}` | 1 |
| `run.json` | `scripts/run_save.gd` | `{"version": 1, "run": {...}}`, `"run"` is `{}` when no run is saved | 1 |

`hi.dat` (a plain number, the old single high score) is no longer read or written: the HI score is the best entry of `scores.json`. An old `hi.dat` in the folder does nothing and can be deleted by hand; its score is not moved to the leaderboard, because it has no name or date.

A file written before versioning has no version number and counts as **version 0**. Loading it works as before, and the next save writes version 1.

## Tutorial (`tutorial_done` under `[game]` in `settings.cfg`)

`tutorial_done` is `true` once the short tutorial in the training room was finished or skipped; then the TRAINING ROOM entry opens a plain room. A missing key or a value that is not `true` / `false` loads as `false` (the tutorial starts on the next visit). It is a setting, not progress: RESET ALL PROGRESS keeps it. To see the tutorial start by itself again, delete the key by hand; TUTORIAL in the room's pause menu runs it any time.

## First-run hints (`[hints]` in `settings.cfg`)

`settings.cfg` has a `[hints]` section with one `true` / `false` per first-run hint: `map`, `upgrade`, `shop`, `rest`, `extract` and `cache` (`HINT_IDS` in `scripts/settings.gd`). `true` means the hint was shown once and is not shown again. It is a field with a default, so there is no version bump.

- A file without the section, a missing key, or a value that is not `true` / `false` loads as **not seen**: the worst a hand-edited file can do is show a hint again. A key that is not one of the six ids is ignored (and dropped the next time the file is saved).
- `Settings.mark_hint_seen(id)` sets the flag and saves; it returns `true` only the first time, so the caller knows when to draw the hint.
- The flags are **settings, not progress**: RESET ALL PROGRESS keeps `settings.cfg`, so a reset does not show the hints again. To see them again, delete the `[hints]` section (or set the values to `false`) by hand.
- The **FIRST-TIME HINTS** row of the settings page is `show_hints` under `[game]` (`true` = ON, the default). A missing key or a value that is not `true` / `false` loads as ON. With it OFF no hint is shown and the flags above are **not** used up, so switching it ON again shows the hints the player has not met yet; a hint that was already seen stays seen. Switching it OFF also takes a line that is on screen away at once. Like the flags it is kept by RESET ALL PROGRESS.

## Rider warning sounds (`rider_warning` under `[game]` in `settings.cfg`)

The RIDER WARNING SOUNDS row of the settings is a whole number: `0` OFF, `1` QUIET, `2` NORMAL (the default). A missing key, a value that is not a whole number, or a number outside 0 to 2 loads as the default or is clamped to that range. No version bump (a new field with a default). It is a setting, not progress: RESET ALL PROGRESS keeps it.

## Window size (`window_w` and `window_h` under `[game]` in `settings.cfg`)

The WINDOW SIZE row of the settings saves the size of the window in pixels as two whole numbers. A missing key, a value that is not a whole number, or a size under 640 x 360 or over 8192 x 8192 is ignored and the window keeps its default size; a size bigger than the free area of the screen is cut to it. While the game is fullscreen the saved size is the one it goes back to when fullscreen is switched off. Settings, not progress: RESET ALL PROGRESS keeps it.

## Heat level (`heat` under `[game]` in `settings.cfg`, and `heat` in `run.json`)

The Heat level (README Milestone B, `docs/HEAT.md`) is saved in two places, both whole numbers from 0 (no Heat) up to the top level of `data/heat.json`:

- **`settings.cfg`, `[game] heat`:** the level the title screen starts from. It is the level of the run last started or continued, and the picker of README H1.4 changes it. A missing key (a file from before Heat), or a value that is not a number, leaves the level as it is (0 on a fresh start); a number below 0 or above the top level is kept to that range. It is a setting, not progress, so RESET ALL PROGRESS keeps it.
- **`run.json`, `heat` in the saved run:** the level the run is played at, so CONTINUE plays on at the same Heat. A run saved before Heat has no key and was played at 0. A number past the sanity limit (20) is cut there when the file is read, and to the levels the table has when the run is put into the game; anything that is not a number reads as 0. **A saved Daily Run always loads as Heat 0**, whatever the file says, because the Daily Run is the same for everybody.

No version bump for either (a new field with a default, like the other files). `tools/heat_check.gd` checks both round trips and the bad values.

- **`meta.json`, `heat_open`:** the highest Heat level that is open to play (README H1.11), a whole number, 0 for a player who has not won a run yet. A file without the key (written before the ladder was locked) reads as 0, so only Heat 0 is open; a value that is not a number or is below 0 reads as 0, a number above the sanity limit (20) is cut there, and the game never uses more than the top level of `data/heat.json` (`Heat.open_level`). It only goes up: a run won at the highest open level opens the next one (`Meta.unlock_heat_after_win`, called by `award_run`) and the file is saved at once. RESET ALL PROGRESS closes the ladder again (it deletes `meta.json`); `settings.cfg` keeps the level last chosen, and a run starts at the highest open level if that level is not open (`Main.start_game`). No version bump.
- **`scores.json`, `heat` in each entry:** the level the run was played at (README H1.10), a whole number from 0 up to the sanity limit (20). An entry written before Heat has no key and reads as 0; a value that is not a number (text, null, a list, true) reads as 0, a negative one as 0 and one above the limit is cut there. A new entry always gets the level of the run (`Scores.heat_of`). Only ranked runs are recorded, so a Daily Run (always Heat 0) and a custom-seed run never appear. No version bump. The one board stays one board until the split-boards item of Milestone A; the High Scores page has a HEAT column so the levels are told apart.

## Key bindings (`[keys]` in `settings.cfg`)

`settings.cfg` has a `[keys]` section with one entry per rebindable control (`forward`, `left`, `back`, `right`, `sprint`, `crouch`, `jump`, `dash`, `reload`, `switch`, `gun`, `melee`, `gadget`, `map`; the list is `ACTIONS` in `scripts/keybinds.gd`). Each value is a pair of whole numbers, the key and the alternative, as Godot physical key codes (`0` = no alternative), for example `jump=[32, 0]`.

- A missing section, an entry that is not a pair of whole numbers, a menu key (Esc, Tab, Enter, the arrows, F7, F9, F10, F11, Delete, Backspace, T) or Alt, Meta or Caps Lock, a control with no key, or the same key on both spots: that control loads on its **default** keys.
- Two controls on one key: **every** control loads on its defaults, so a hand-edited file can only make the keys go back, never leave a control that cannot be pressed.
- The bindings are **settings, not progress**: RESET ALL PROGRESS keeps them. RESET TO DEFAULTS on the REBIND KEYS page puts them back.
- Not rebindable: the mouse, the gamepad, and the menu keys above. Keys 1 to 4 and Space also work on the shop, map and upgrade screens whatever the bindings say.

## Safety rules (`scripts/save_util.gd`)

- A file that cannot be read is copied to `<file>.bad.bak` before the game saves over it.
- A file with a version **higher** than the game knows (for example after going back to an older build) is copied to `<file>.v<N>.bak` before the game saves over it.
- Starting a new run while a run is saved (PLAY, DAILY RUN, CUSTOM SEED or RESTART RUN) first copies `run.json` to `run.json.replaced.bak`, so one mistaken click can be undone by copying that file back over `run.json`. An empty "no run" file is never copied over a real backup.
- RESET LEADERBOARD on the High Scores page copies `scores.json` to `scores.json.reset.bak` before it erases the list, so one mistaken reset can be undone by copying that file back.
- The game deletes a save file in one case only: RESET ALL PROGRESS (see below). Every value is clamped or cast on load, so a hand-edited file cannot crash it.

## Developer start options: a read-only session (`scripts/dev_start.gd`)

`godot --path . -- --dev-coins=500 --dev-unlocks=item_magnet,weapon_dart_gun` starts the game with 500 meta coins and those unlocks owned, for the balance pass (roadmap alpha D2). `--dev-unlocks=all` owns every unlock that is not planned. The values are set in memory only. As soon as either argument is given, `SaveUtil.read_only` is on for the whole session: `settings.cfg`, `scores.json`, `meta.json` and `run.json` are not written or deleted (including by RESET ALL PROGRESS), and no `.bak` copy is made. The real files are still read, so the session starts from the real settings, scores and saved run. Every writer checks the switch first, so **a new writer of a file in `user://` has to check `SaveUtil.read_only` too**. The options work only when the game runs from the Godot editor binary; an exported game ignores them. `tools/dev_start_check.gd` covers all of it.

## RESET ALL PROGRESS (last row of the settings panel)

The red button at the bottom of the settings panel (title screen and pause menu) wipes the player's progress after two warnings: first "all progress will be wiped and cannot be recovered", then "are you absolutely sure". Only YES on the second one does it (`scripts/progress_reset.gd`, `reset_all_progress` in `scripts/main.gd`).

- **Deleted:** `meta.json` (coins, unlocks, start perk, loadout, challenge counts, XP), `scores.json`, `run.json`, the old `hi.dat`, and every backup copy of them (`<file>.bad.bak`, `<file>.v<N>.bak`, `scores.json.reset.bak`, `run.json.replaced.bak`). The backups go too, because the player was told the wipe cannot be undone and a copy left behind would undo it. The wipe makes no backup of its own.
- **Kept:** `settings.cfg` (the options and the leaderboard name), which is not progress.
- **In memory** the coins, unlocks, loadout, challenge counts, XP, leaderboard, HI score and the CONTINUE button are reset at once; a run in progress (when the wipe is started from the pause menu) is dropped without score or coins. The files are made again the next time the game saves, like on a first start.
- A file that cannot be deleted is written over with the empty state, and the settings page says how many files could not be deleted.
- A new save file that holds progress must be added to `FILES` in `scripts/progress_reset.gd`, and anything that keeps progress somewhere else (the website, cloud saves, Milestone N) has to be wiped by the same button or the player asked separately.

## Changing a save format

1. Raise `VERSION` in the script that owns the file.
2. In its load function, read the old shape (`version_of(data)` gives the stored version, 0 when missing) and convert it to the new one. Keep the converter for every older version.
3. Write the new version number in its save function.
4. Update the table above.

Adding a new field with a default (`data.get("field", default)`) does not need a version bump; changing or removing a field does.

Example: `owned` in `meta.json` (the ids of the unlocks bought on the Unlocks page, see `data/unlocks.json`) was added this way. A file written before it has no `owned` and loads with nothing owned; a value that is not a list is ignored; an id the unlock table no longer has stays in the list, so a purchase is never lost. Spending coins saves `balance` and `owned` together. `start_perk` (the unlock id chosen on the Loadout page, `""` for none) works the same way: a file without it, or with a value that is not text, loads as none, and a perk that is no longer owned is simply not given.
`loadout` in `meta.json` holds the weapon chosen on the Loadout page for each slot (`primary`, `melee`, `gadget`; an empty text or a missing slot means the default: the dart pistol, an empty melee slot and an empty gadget slot). Buying a melee weapon while the melee choice is empty chooses it. A file without it loads with the defaults; a value that is not text, a slot that does not exist or a weapon that is not owned any more is ignored when the run starts (the slot's default is used).
`challenges` in `meta.json` was added this way too: a file without it loads with no counts. Its keys are the `counter` names of `data/challenges.json`, its values the number of runs each challenge was done in.

`xp` in `meta.json` is the total XP of all finished runs (`scripts/xp.gd`, `data/xp.json`). XP is never spent, it only goes up. A file without it loads with 0 XP; a value that is not a number is ignored (0), a negative one loads as 0 and one above 100,000,000 is cut to that. The **level is not saved**: it is worked out from the total XP every time, so changing the curve in `data/xp.json` re-levels every save without a conversion. A quit run pays no XP, the same as it pays no coins.

## The saved run (`run.json`, the CONTINUE button)

One run can be saved. `scripts/run_save.gd` writes it **every time the run map screen opens** (the start of a run and after every round, upgrade and shop), so a run that is quit to the title, closed or crashed comes back with CONTINUE on the title screen, on the map screen it was last on. It holds what the run has built up: the run seed and mode (normal, Daily Run or custom seed), the position on the run map, hearts, cash, the weapon in the primary slot (`primary`, `melee_weapon` for the melee slot and `gadget` for the gadget slot, ids from `data/weapons.json`; a file without `primary` loads as `dart_gun`, because such a run is older than the weapon slots and was playing with the dart gun; an unknown id or a value that is not text loads as `dart_pistol`, the slot's default; a `melee_weapon` or `gadget` that is empty, unknown or not text loads as an empty slot, because a new player's melee slot is empty until the gummy worm is bought; a file with no `melee_weapon` at all is older than the melee lock and loads with the gummy worm, which that run was played with; `melee` (the melee weapon in hand) is never on with an empty melee slot), perks, upgrade levels and shop levels, packs bought for the next round, score, kills, style, hype, times, shot counts and the challenges done and boss coins of the run. The run map and the arena are not saved, they are made again from the seed. A round that was being played is not saved: it is played again from the map screen, and a round cleared but not yet through its upgrade and shop screens is played again too.

- Written only by the game itself (`run_save_enabled` in `scripts/main.gd` is true when `main` is the running scene), so the check scripts in `tools/` never touch the player's `run.json`. `tools/run_save_check.gd` uses its own file through `RunSave.test_path`.
- Cleared when the run ends (lost, won or a failed round): the file is not deleted, it is rewritten as `{"version": 1, "run": {}}`.
- Only runs with a map are saved; a run without one (the map could not be made) plays in a line and cannot be continued.
- On load every value is cast and clamped, a list or dictionary of the wrong type is rebuilt empty, hearts are at least 1, and a run whose map position does not exist on the map its seed makes is ignored, so a hand-edited file cannot crash the game or give an unplayable run. A file that cannot be read goes to `run.json.bad.bak`, a file from a newer version to `run.json.v<N>.bak`; neither is loaded.
- Adding a field with a default (`clean` in `run_save.gd`) needs no version bump, like the other files.

