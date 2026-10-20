# FstreliBiciklina3D
Mostly vibe coded Godot game

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
- [ ] Implement permanent unlocks between runs
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

- [ ] Keyboard and gamepad navigation for the settings panel (sliders are mouse-only today)
- [ ] Controls / "How to play" page (the long controls text was removed from the title screen)
- [ ] Pause automatically when the game window loses focus
- [ ] Confirm before Restart Run / Quit to Title (a run is lost with one click)
- [ ] Optional: "Continue" button to resume an interrupted run

## High Scores

- [x] Implement local Top 10 leaderboard
- [x] Add player name entry
- [ ] Support separate leaderboards per difficulty (needs a difficulty system first: build it together with Heat in Milestone B, then split the boards by Heat level)
- [ ] Show run time on the leaderboard (it is already saved with each entry)
- [ ] Reset leaderboard option (F8 still only resets the old single high score)
- [ ] Use the leaderboard's best entry for the HI score shown in the HUD, and retire `hi.dat`

### Daily Seed Mode

- [ ] Generate a daily seed
- [ ] Use same seed for all players on that day
- [ ] Add dedicated daily-run scoreboard

### Deferred

- [ ] Online leaderboard (future feature)
  - [ ] Submit scores to Django web leaderboard
    - [ ] Implement REST API on Django web service
    - [ ] Implement Seed and leaderboard display

---

# Milestone B: Meta Currency, Unlocks & Skins

## Meta Progression

- [ ] Add meta currency
  - [ ] Earn from score
  - [ ] Earn from boss kills
  - [ ] Earn from challenges

- [ ] Keep meta currency separate from run cash

## Meta Unlocks

- [ ] Unlock starting perks
- [ ] Unlock additional weapons in shop pool
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

- [ ] Add primary weapon slot
- [ ] Add melee weapon slot
- [ ] Add gadget slot

## New Weapons

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

- [ ] Replace linear round progression

### Map Nodes

- [ ] Normal encounter
- [ ] Elite encounter
- [ ] Shop
- [ ] Event
- [ ] Rest stop
- [ ] Boss node

## Relics

- [ ] Implement relic system
- [ ] Add rule-changing relic effects

## Curses

- [ ] Add risk/reward curse system

## Round Modifiers

- [ ] Night modifier
- [ ] Rain modifier
- [ ] Double riders modifier
- [ ] Additional modifier ideas

## New Arenas

- [ ] Bridge arena
- [ ] Market arena
- [ ] Tunnel arena

---

# Milestone E: Polish & Accessibility

## Dynamic Presentation

- [ ] Dynamic music system
- [ ] Scale intensity with style rank

## Onboarding

- [ ] Short tutorial
- [ ] Key rebinding

## Accessibility

- [ ] Subtitle support for voice lines
- [ ] Colourblind-safe telegraphs
- [ ] English localization
- [ ] Slovenian localization review
- [ ] Screen shake and screen flash intensity options (reduced-motion / photosensitivity)

## Release Readiness

- [ ] Create app icon
- [ ] Add credits screen (include audio, font and voice-recording credits)
- [ ] Configure Windows export presets (the current export path points at a personal Desktop folder: make it relative)
- [ ] Show the game version on the title screen
- [ ] Bring `README.txt` up to date (it still describes v10 controls and the old click-to-start / click-to-resume flow)

---

# Milestone F: Graphics & Sound Overhaul

> Complete, hard overhaul of how the game looks and sounds. Today everything is built in code: models are assembled from primitive shapes (`models.gd`), the sky is procedural, effects are pooled boxes and quads, and all ~50 sound effects are synthesised by `tools/bake_audio.py`. Voice lines are your own recordings (`audio/voice/`). Do the art direction first; everything else follows from it.

## Graphics

- [ ] Art direction pass: one visual style, a short style guide (palette, outline weight, shape language, UI look)
- [ ] Replace primitive-built models with authored 3D models and rigs
  - [ ] Riders and bikes (all types: pro, sprinter, courier, armoured)
  - [ ] Bosses (lawnmower, mesh wifi node, minister, golden president / final boss)
  - [ ] Pedestrians and cheerleaders
  - [ ] First-person viewmodel: dart gun, gummy worm, hands
- [ ] Animation: rider and boss cycles, hit reactions, death animations, gun reload / shoot / melee swing
- [ ] Environment art pass: roundabout, buildings, props, textures and materials for all 4 lighting themes
- [ ] Lighting and post-processing: authored sky, colour grading per theme, SSAO, fog and glow tuning
- [ ] Rebuild effects with real particle systems: muzzle flash, dart trails, hit sparks, impact decals, boss telegraphs
- [ ] HUD and menu redesign: custom font and icons, one consistent theme, animated transitions, ultrawide support
- [ ] Animated title screen background (live 3D scene)
- [ ] Performance budget (target 60 fps on a mid-range GPU), instancing / LODs, keep the F9 quality presets meaningful

## Sound

- [ ] Replace the synthesised effects (`tools/bake_audio.py`) with recorded or produced sounds: shots, hits, bikes, steps, ambience
- [ ] Variations and pitch randomisation for every frequently repeated sound
- [ ] Proper mixing: separate Music / SFX / Voice / Ambience / UI buses, voice ducking, and a volume slider per bus in Settings (only one master slider today)
- [ ] 3D audio pass: distance attenuation, doppler for riders, tunnel reverb
- [ ] Clean up and normalise the 79 voice lines to one loudness, remove the unused `voice_old` files, record new lines for the final boss, victory and run start
- [ ] Menu sounds: hover, confirm, back (menus currently reuse the click sound)
- [ ] Stingers for round clear, boss intro, final boss defeat, run complete and game over
- [ ] Music: see "Dynamic music system" in Milestone E

---

# Tooling & QA

- [ ] Playtest pass of everything built in Milestone A (title, pause, settings, run, win / lose, leaderboard, name entry). It was written without running the game
- [ ] CI check on every pull request: GDScript lint / format (gdtoolkit) and a headless Godot project load
- [ ] Save-file safety: version the settings and score files so later changes do not break old saves

---

# Technical Refactor (Recommended Before Milestone D)

## Code Structure

- [x] Break up `main.gd` (~3,600 lines)
- [x] Move systems into dedicated modules

## Data-Driven Content

- [ ] Move items into data tables
- [ ] Move perks into data tables
- [ ] Move weapons into data tables

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
