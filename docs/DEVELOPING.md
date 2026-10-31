# Developing and testing the game

How to run the game from the editor and how to start it with test coins and unlocks. Moved word for word from `README.md` on 2026-10-29; the rules for tests, secrets and the roadmap stay in the README.

## Running from the Godot editor
- The game starts in a 1280x720 window (the base size in `project.godot`). Fullscreen is built in: F11, or the FULLSCREEN row in the settings, and the choice is saved.
- If the game runs inside the editor's embedded game view, fullscreen and other window changes do not work there, because the game is not its own window. Turn off the editor's embedded game window option (in the game view toolbar) so the game runs in a separate window, or run an exported build.

## Developer start options (roadmap alpha D2.1)
- To test the game with coins and unlocks without grinding for them, start it from the editor binary with user arguments: `godot --path . -- --dev-coins=500 --dev-unlocks=item_magnet,item_heart,weapon_dart_gun` (`--dev-unlocks=all` owns everything that is in the game; ids are `id` in `data/unlocks.json`). The coins are set to that number, not added.
- **Nothing is saved in such a session**: no settings, scores, coins, unlocks or run are written or deleted, so the real save is never touched. One `[dev start]` line in the console says what was applied and names any value that was left out. An exported game ignores these arguments.
- Details and the rule for new save writers: `docs/SAVE_FILES.md`. Check: `python tools/run_checks.py dev_start`.

## Talking to the website while developing (roadmap V4.1)
- All calls go through `scripts/web_api.gd`. From the editor binary it takes the API address and key from `--dev-api=URL` (address only, after `--`), then `secrets.local.cfg` or the environment variables `FB3D_API_BASE_URL` and `FB3D_API_KEY` (see "Secrets and credentials" in the README), then `api_key.bin`. With none of them set nothing is sent and the game plays offline. An exported game reads only `api_key.bin` and ignores `--dev-api`.
- The address must be https. The one exception is `--dev-api=http://127.0.0.1:PORT/fb3d/api/v1/` (or `localhost`), only in an editor run, for a fake server on your own PC (V4.2).
- `api_key.bin` is made by `tools/build_release.py` from `FB3D_API_KEY` and `FB3D_API_BASE_URL` for one export and deleted afterwards; never make or commit one by hand. Check: `python tools/run_checks.py web_api`.
