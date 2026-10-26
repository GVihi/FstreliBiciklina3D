# Save files

The game keeps three small files in Godot's `user://` folder (on Windows: `%APPDATA%\Godot\app_userdata\<project name>\`).

| File | Written by | Format | Version |
|---|---|---|---|
| `settings.cfg` | `scripts/settings.gd` | ConfigFile; the version is `[meta] version` | 1 |
| `scores.json` | `scripts/scores.gd` | `{"version": 1, "entries": [...]}` | 1 |
| `meta.json` | `scripts/meta.gd` | `{"version": 1, "balance": n, "total_earned": n, "owned": [unlock ids], "start_perk": unlock id}` | 1 |
| `meta.json` | `scripts/meta.gd` | `{"version": 1, "balance": n, "total_earned": n, "owned": [unlock ids]}` | 1 |
| `meta.json` | `scripts/meta.gd` | `{"version": 1, "balance": n, "total_earned": n, "challenges": {counter: n}}` | 1 |

`hi.dat` (a plain number, the old single high score) is no longer read or written: the HI score is the best entry of `scores.json`. An old `hi.dat` in the folder does nothing and can be deleted by hand; its score is not moved to the leaderboard, because it has no name or date.

A file written before versioning has no version number and counts as **version 0**. Loading it works as before, and the next save writes version 1.

## Safety rules (`scripts/save_util.gd`)

- A file that cannot be read is copied to `<file>.bad.bak` before the game saves over it.
- A file with a version **higher** than the game knows (for example after going back to an older build) is copied to `<file>.v<N>.bak` before the game saves over it.
- RESET LEADERBOARD on the High Scores page copies `scores.json` to `scores.json.reset.bak` before it erases the list, so one mistaken reset can be undone by copying that file back.
- The game never deletes a save file. Every value is clamped or cast on load, so a hand-edited file cannot crash it.

## Changing a save format

1. Raise `VERSION` in the script that owns the file.
2. In its load function, read the old shape (`version_of(data)` gives the stored version, 0 when missing) and convert it to the new one. Keep the converter for every older version.
3. Write the new version number in its save function.
4. Update the table above.

Adding a new field with a default (`data.get("field", default)`) does not need a version bump; changing or removing a field does.

Example: `owned` in `meta.json` (the ids of the unlocks bought on the Unlocks page, see `data/unlocks.json`) was added this way. A file written before it has no `owned` and loads with nothing owned; a value that is not a list is ignored; an id the unlock table no longer has stays in the list, so a purchase is never lost. Spending coins saves `balance` and `owned` together. `start_perk` (the unlock id chosen on the Loadout page, `""` for none) works the same way: a file without it, or with a value that is not text, loads as none, and a perk that is no longer owned is simply not given.
Example: `owned` in `meta.json` (the ids of the unlocks bought on the Unlocks page, see `data/unlocks.json`) was added this way. A file written before it has no `owned` and loads with nothing owned; a value that is not a list is ignored; an id the unlock table no longer has stays in the list, so a purchase is never lost. Spending coins saves `balance` and `owned` together.
Adding a new field with a default (`data.get("field", default)`) does not need a version bump; changing or removing a field does. `challenges` in `meta.json` was added this way: a file without it loads with no counts. Its keys are the `counter` names of `data/challenges.json`, its values the number of runs each challenge was done in.
