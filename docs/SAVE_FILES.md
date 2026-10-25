# Save files

The game keeps four small files in Godot's `user://` folder (on Windows: `%APPDATA%\Godot\app_userdata\<project name>\`).

| File | Written by | Format | Version |
|---|---|---|---|
| `settings.cfg` | `scripts/settings.gd` | ConfigFile; the version is `[meta] version` | 1 |
| `scores.json` | `scripts/scores.gd` | `{"version": 1, "entries": [...]}` | 1 |
| `meta.json` | `scripts/meta.gd` | `{"version": 1, "balance": n, "total_earned": n}` | 1 |
| `hi.dat` | `scripts/settings.gd` | plain number (to be retired, see the roadmap) | none |

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
