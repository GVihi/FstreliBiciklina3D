# Developing and testing the game

How to run the game from the editor and how to start it with test coins and unlocks. Moved word for word from `README.md` on 2026-10-29; the rules for tests, secrets and the roadmap stay in the README.

## Running from the Godot editor
- The game starts in a 1280x720 window (the base size in `project.godot`). Fullscreen is built in: F11, or the FULLSCREEN row in the settings, and the choice is saved.
- If the game runs inside the editor's embedded game view, fullscreen and other window changes do not work there, because the game is not its own window. Turn off the editor's embedded game window option (in the game view toolbar) so the game runs in a separate window, or run an exported build.

## Developer start options (roadmap alpha D2.1)
- To test the game with coins and unlocks without grinding for them, start it from the editor binary with user arguments: `godot --path . -- --dev-coins=500 --dev-unlocks=item_magnet,item_heart,weapon_dart_gun` (`--dev-unlocks=all` owns everything that is in the game; ids are `id` in `data/unlocks.json`). The coins are set to that number, not added.
- **Nothing is saved in such a session**: no settings, scores, coins, unlocks or run are written or deleted, so the real save is never touched. One `[dev start]` line in the console says what was applied and names any value that was left out. An exported game ignores these arguments.
- Details and the rule for new save writers: `docs/SAVE_FILES.md`. Check: `python tools/run_checks.py dev_start`.
