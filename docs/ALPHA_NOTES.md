# Fstreli Biciklina 3D: early alpha notes (0.2.0)

This is an early alpha. It is meant to test one thing: does a run, the coins you take out of it and the next run feel like a game worth playing again? The look and the sound are placeholders on purpose.

## How to run it

- **Windows build:** start `FB3D.exe` from the build folder. It needs no install. It opens in a 1280x720 window; F11 switches to fullscreen and the choice is saved.
- **From the Godot editor (developers):** open the project with Godot 4.7 or newer and press Play. If the editor shows the game in its embedded game view, fullscreen does not work there; turn the embedded window off or use the exported build.
- **Your saves** are four small files in Godot's `user://` folder, on Windows `%APPDATA%\Godot\app_userdata\Fstreli Biciklina 3D\` (`settings.cfg`, `scores.json`, `meta.json`, `run.json`). `docs/SAVE_FILES.md` describes them. To start again from nothing, use RESET ALL PROGRESS at the bottom of the settings; it asks twice and cannot be undone.

## Controls

The full list, for keyboard and mouse and for a gamepad, is on the **CONTROLS** page of the title menu (and of the pause menu). The short version: WASD to move, mouse to aim, left click to shoot, Space to jump, V to dash (A or D with Space is a side dash), R to reload, Esc to pause, Tab for the settings, M to hold the map.

## What is in

- A run of 10 floors on a map made from a seed: you pick a node on each floor. Fight nodes (normal, elite, boss), shop nodes and rest nodes all work. There is a mid boss on floor 5 and a final boss on floor 10.
- A fight node is a round on a generated arena: riders, caches, an extraction point and an ambush. Clearing it gives an upgrade pick (an elite gives two), then the map again. Cash is spent at shop nodes. A rest node refills your hearts or gives one extra upgrade.
- The run summary with score, coins and XP, and buttons that lead on to a new run or to the Unlocks page.
- Coins you earn are kept between runs. On the **UNLOCKS** page you buy starting perks, shop items and the Dart Gun. On the **LOADOUT** page you choose a starting perk and a weapon for each slot. You start with the Dart Nerf Pistol and the melee weapon.
- CONTINUE for a run you quit, DAILY RUN, CUSTOM SEED, CHALLENGES and a local leaderboard (HIGH SCORES).
- Saved settings, including graphics quality, voices and screen shake.

## What is not in

On purpose, so the alpha stays small: the graphics and sound overhaul, the other weapons and the longer pistol path, relics, curses, event nodes and the rain modifier (both switched off), rider variety and arena hazards, jumping, Heat and per-difficulty leaderboards, key rebinding, localization and a tutorial. The full list is "Not in the early alpha" in `README.md`.

## Known issues

- **Difficulty and run length are not tuned yet.** A first run may end much earlier or later than it should, and a round may feel too long or too short. Tell us which.
- Riders and bosses steer by look-ahead and have no path search, so they can get stuck in a dead end.
- The sound and the gun jolt on reload are placeholders.
- The SHAKE AND FLASH setting only covers camera shake, the hit flash and the damage flash.
- The Windows export has been tried only as a smoke test so far.

## Where to send feedback

Open an issue at https://github.com/GVihi/FstreliBiciklina3D/issues, or tell the owner directly. Useful things to include: the version (shown on the title screen), what you were doing, the floor you reached and why the run ended, and the seed if you used a custom one. If the game printed an error, copy the last lines of the log from the `logs` folder next to your save files.
