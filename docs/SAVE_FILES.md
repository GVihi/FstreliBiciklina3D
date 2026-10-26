# Save files

The game keeps four small files in Godot's `user://` folder (on Windows: `%APPDATA%\Godot\app_userdata\<project name>\`).

| File | Written by | Format | Version |
|---|---|---|---|
| `settings.cfg` | `scripts/settings.gd` | ConfigFile; the version is `[meta] version` | 1 |
| `scores.json` | `scripts/scores.gd` | `{"version": 1, "entries": [...]}` | 1 |
| `meta.json` | `scripts/meta.gd` | `{"version": 1, "balance": n, "total_earned": n, "owned": [unlock ids], "start_perk": unlock id, "challenges": {counter: n}, "xp": n}` | 1 |
| `run.json` | `scripts/run_save.gd` | `{"version": 1, "run": {...}}`, `"run"` is `{}` when no run is saved | 1 |

`hi.dat` (a plain number, the old single high score) is no longer read or written: the HI score is the best entry of `scores.json`. An old `hi.dat` in the folder does nothing and can be deleted by hand; its score is not moved to the leaderboard, because it has no name or date.

A file written before versioning has no version number and counts as **version 0**. Loading it works as before, and the next save writes version 1.

## Safety rules (`scripts/save_util.gd`)

- A file that cannot be read is copied to `<file>.bad.bak` before the game saves over it.
- A file with a version **higher** than the game knows (for example after going back to an older build) is copied to `<file>.v<N>.bak` before the game saves over it.
- Starting a new run while a run is saved (PLAY, DAILY RUN, CUSTOM SEED or RESTART RUN) first copies `run.json` to `run.json.replaced.bak`, so one mistaken click can be undone by copying that file back over `run.json`. An empty "no run" file is never copied over a real backup.
- RESET LEADERBOARD on the High Scores page copies `scores.json` to `scores.json.reset.bak` before it erases the list, so one mistaken reset can be undone by copying that file back.
- The game never deletes a save file. Every value is clamped or cast on load, so a hand-edited file cannot crash it.

## Changing a save format

1. Raise `VERSION` in the script that owns the file.
2. In its load function, read the old shape (`version_of(data)` gives the stored version, 0 when missing) and convert it to the new one. Keep the converter for every older version.
3. Write the new version number in its save function.
4. Update the table above.

Adding a new field with a default (`data.get("field", default)`) does not need a version bump; changing or removing a field does.

Example: `owned` in `meta.json` (the ids of the unlocks bought on the Unlocks page, see `data/unlocks.json`) was added this way. A file written before it has no `owned` and loads with nothing owned; a value that is not a list is ignored; an id the unlock table no longer has stays in the list, so a purchase is never lost. Spending coins saves `balance` and `owned` together. `start_perk` (the unlock id chosen on the Loadout page, `""` for none) works the same way: a file without it, or with a value that is not text, loads as none, and a perk that is no longer owned is simply not given.
`challenges` in `meta.json` was added this way too: a file without it loads with no counts. Its keys are the `counter` names of `data/challenges.json`, its values the number of runs each challenge was done in.

`xp` in `meta.json` is the total XP of all finished runs (`scripts/xp.gd`, `data/xp.json`). XP is never spent, it only goes up. A file without it loads with 0 XP; a value that is not a number is ignored (0), a negative one loads as 0 and one above 100,000,000 is cut to that. The **level is not saved**: it is worked out from the total XP every time, so changing the curve in `data/xp.json` re-levels every save without a conversion. A quit run pays no XP, the same as it pays no coins.

## The saved run (`run.json`, the CONTINUE button)

One run can be saved. `scripts/run_save.gd` writes it **every time the run map screen opens** (the start of a run and after every round, upgrade and shop), so a run that is quit to the title, closed or crashed comes back with CONTINUE on the title screen, on the map screen it was last on. It holds what the run has built up: the run seed and mode (normal, Daily Run or custom seed), the position on the run map, hearts, cash, perks, upgrade levels and shop levels, packs bought for the next round, score, kills, style, hype, times, shot counts and the challenges done and boss coins of the run. The run map and the arena are not saved, they are made again from the seed. A round that was being played is not saved: it is played again from the map screen, and a round cleared but not yet through its upgrade and shop screens is played again too.

- Written only by the game itself (`run_save_enabled` in `scripts/main.gd` is true when `main` is the running scene), so the check scripts in `tools/` never touch the player's `run.json`. `tools/run_save_check.gd` uses its own file through `RunSave.test_path`.
- Cleared when the run ends (lost, won or a failed round): the file is not deleted, it is rewritten as `{"version": 1, "run": {}}`.
- Only runs with a map are saved; a run without one (the map could not be made) plays in a line and cannot be continued.
- On load every value is cast and clamped, a list or dictionary of the wrong type is rebuilt empty, hearts are at least 1, and a run whose map position does not exist on the map its seed makes is ignored, so a hand-edited file cannot crash the game or give an unplayable run. A file that cannot be read goes to `run.json.bad.bak`, a file from a newer version to `run.json.v<N>.bak`; neither is loaded.
- Adding a field with a default (`clean` in `run_save.gd`) needs no version bump, like the other files.

