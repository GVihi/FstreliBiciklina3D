# Developing and testing the game

How to run the game from the editor and how to start it with test coins and unlocks. Moved word for word from `README.md` on 2026-10-29; the rules for tests, secrets and the roadmap stay in the README.

## Running from the Godot editor
- The game starts in a 1280x720 window (the base size in `project.godot`). Fullscreen is built in: F11, or the FULLSCREEN row in the settings, and the choice is saved.
- If the game runs inside the editor's embedded game view, fullscreen and other window changes do not work there, because the game is not its own window. Turn off the editor's embedded game window option (in the game view toolbar) so the game runs in a separate window, or run an exported build.

## Developer start options (roadmap alpha D2.1)
- To test the game with coins and unlocks without grinding for them, start it from the editor binary with user arguments: `godot --path . -- --dev-coins=500 --dev-unlocks=item_magnet,item_heart,weapon_dart_gun` (`--dev-unlocks=all` owns everything that is in the game; ids are `id` in `data/unlocks.json`). The coins are set to that number, not added.
- **Nothing is saved in such a session**: no settings, scores, coins, unlocks or run are written or deleted, so the real save is never touched. One `[dev start]` line in the console says what was applied and names any value that was left out. An exported game ignores these arguments.
- Details and the rule for new save writers: `docs/SAVE_FILES.md`. Check: `python tools/run_checks.py dev_start`.
- The game starts on an **intro screen** (press any key, click or a gamepad button for the title menu). A run with a developer start option applied skips it, and so does every check script, which starts on the title menu. Check: `python tools/run_checks.py menu_backdrop`.

## Talking to the website while developing (roadmap V4.1)
- All calls go through `scripts/web_api.gd`. From the editor binary it takes the API address and key from `--dev-api=URL` (address only, after `--`), then `secrets.local.cfg` or the environment variables `FB3D_API_BASE_URL` and `FB3D_API_KEY` (see "Secrets and credentials" in the README), then `api_key.bin`. With none of them set nothing is sent and the game plays offline. An exported game reads only `api_key.bin` and ignores `--dev-api`.
- The address must be https. The one exception is `--dev-api=http://127.0.0.1:PORT/fb3d/api/v1/` (or `localhost`), only in an editor run, for the pretend website `tools/fake_api_server.py` on your own PC (see the next section).
- `api_key.bin` is made by `tools/build_release.py` from `FB3D_API_KEY` and `FB3D_API_BASE_URL` for one export and deleted afterwards; never make or commit one by hand. Check: `python tools/run_checks.py web_api`.

## The pretend website for the web checks (roadmap V4.2)
- `tools/fake_api_server.py` plays the API of `docs/WEBSITE_API.md` on `127.0.0.1`, so the web checks need no key, no network and no real site. Python standard library only, so it runs on Windows too. Test the tool itself with `python tools/fake_api_server.py --self-test` (about 4 seconds, no Godot).
- By hand: `python tools/fake_api_server.py --key SOMETHING-YOU-MAKE-UP --lifetime 0`, then start the game from the editor binary with `-- --dev-api=http://127.0.0.1:PORT/fb3d/api/v1/` (the port is the one the program says it listens on) and put the same key in `secrets.local.cfg` or `FB3D_API_KEY`. A key that looks like a real game key (`fb3dk_...`) is refused; never type a real one here.
- A check starts it with `--ready-file PATH --lifetime 120` instead. The ready file holds the port, both addresses and the key, which is made up for each run and never printed. The server ends by itself after the lifetime, so a check that crashes leaves nothing running.
- What it does is chosen with `POST <root address>__fake__/scenario` (`current`, `wrong_key`, `slow`, `server_error`, `damaged_json`, `dead_connection`, plus the published and the minimum version), what it got is read with `GET <root address>__fake__/stats` (a count, and per request the headers' names, the version and build, never a key or a token), and `POST __fake__/reset` and `POST __fake__/stop` do what they say. The full list is at the top of the file.
