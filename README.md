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

- [x] Generate a daily seed
- [x] Use same seed for all players on that day
  - [x] Separate "Daily Run" entry on the title menu; normal Play stays fully random
  - [x] Seed only the run layout (rider mix, shop and upgrade offers, starting boss and lighting theme), not moment-to-moment combat
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
  - [x] Earn from score
  - [ ] Earn from boss kills
  - [ ] Earn from challenges

- [x] Keep meta currency separate from run cash

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

> Complete, hard overhaul of how the game looks and sounds. The current toon look (outlines, flat unlit colours, smooth primitive models) is removed and replaced by a chunky, rugged low-poly style with strong light and dark contrast and glowing accents, inspired by the Deep Rock franchise and built to run on low-end PCs. Direction and rules: [`docs/ART_DIRECTION.md`](docs/ART_DIRECTION.md). Free asset sources and licences: [`docs/ASSET_SOURCES.md`](docs/ASSET_SOURCES.md).
>
> **3D models: Claude is the 3D modeler.** Models are written as Python scripts for **Blender used as a Python module (`bpy`)**, kept in `tools/models/`, and exported as `.glb` into `assets/models/`. Claude cannot run Godot in its working environment, so every model step ends with an in-game check by the owner.
>
> Work top to bottom, one checkbox at a time. Each step is done when the old version of that thing is fully replaced, it passes the readability rules in the art direction, frame time is within budget, and there is a before/after screenshot.

## Graphics

### F1. Foundation (before any new asset)
- [x] Answer the first open questions (minimum spec, who makes models, references, bright look): done, see `docs/ART_DIRECTION.md`
- [x] Answer the remaining questions (UI language, ammo on the weapon, rarity colours, hazard-stripe motif, logo): done, see section 9 of `docs/ART_DIRECTION.md`
- [ ] Record the "before" baseline: screenshots of every screen and theme, plus frame time on the minimum-spec machine (needs you: Godot cannot run in my working environment)
- [x] Set up the model pipeline (Claude as modeler, Blender as a Python module `bpy`): scripts in `tools/models/`, output to `assets/models/*.glb` with a preview sheet per model in `docs/model_previews/`, automatic budget and file validation, conventions (1 unit = 1 metre), and an in-game model viewer (`tools/viewer/model_viewer.tscn`). How to use it: `tools/models/README.md`
- [x] Build the shared style kit: bevelled primitive helpers, the colour palette and material set (`tools/models/kit/`), and a test model (`test_crate`)
- [x] Owner check: open `tools/viewer/model_viewer.tscn` in Godot (F6) and confirm `test_crate` looks right in the game (colours, bevels, hazard stripes, the glowing lamp, scale) (confirmed by the owner)
- [x] Create `CREDITS.md` and the rule that every third-party asset gets an entry when it is added (see `CREDITS.md`; the voice recorders' names are still to be added under S6)
- [ ] Switch off the outline pass and flat unlit toon materials behind a flag; simple lit low-poly materials become the default
- [ ] Lighting baseline for DAY: bright sun with soft readable shadows, light sky, tone mapping, glow on gameplay accents
- [ ] Lighting for GOLDEN HOUR, DUSK and NIGHT (warm lamp pools and lit windows, medium-dark sky, nothing hides in the dark)
- [ ] Test the Compatibility renderer against Forward+ on old hardware and decide which to ship
- [ ] Anti-aliasing choice (MSAA or cheaper FXAA) and re-define the F9 quality presets for the new look

### F2. Dart gun (first person)
- [x] Viewmodel setup: separate camera and FOV so the gun never clips into walls (`scripts/viewmodel.gd`; checked in game by the owner: no clipping, same look, frame time fine; `VIEWMODEL_PASS = false` in `main.gd` switches it off)
- [x] Chunky low-poly gun model with a hand-painted texture (model done and wired in: `tools/models/models/dart_gun.py` -> `assets/models/dart_gun.glb`, 1,848 tris, pump slide as its own mesh so the pump animation keeps working, `GUN_MODEL_GLB = false` in `models.gd` brings the old gun back. Waiting for: your in-game check (open the project once so Godot imports the `.glb`), and the hand-painted texture, which the model pipeline does not support yet: the gun uses the shared palette materials for now)
- [x] Idle sway and walk / sprint bob (written in `update_gun` in `scripts/player.gd`, tuning constants at the top of that file; waiting for your in-game check: breathing sway, walk and sprint bob, and a small lag when you turn; all of it fades out while aiming)
- [x] Shoot and recoil animation (springy kick-back, muzzle rise and a little roll that overshoot and settle, rapid fire stacks up to a limit; `update_kick` in `scripts/player.gd`, tuning constants at the top of that file; waiting for your in-game check)
- [x] Pump / reload animation (slide pulls back fast and pushes forward slower, the gun jolts a little with each pump; while loading it tilts towards you, the slide rests part way open and each shell nudges the gun down; `pump_curve` and `update_gun` in `scripts/player.gd`, tuning constants at the top; waiting for your in-game check)
- [x] Aim-down-sights pose and crosshair behaviour (the gun's own height puts the tops of the modelled sights on the middle of the screen, `ads_y` in `models.gd`; the crosshair shrinks and fades to nearly a dot while aiming, turns red when out of darts and dims while loading, `_draw_crosshair` in `scripts/hud.gd`; waiting for your in-game check)
- [x] Dart and shell models (`tools/models/models/dart.py` and `shell.py` -> `assets/models/dart.glb` and `shell.glb`, 312 and 268 tris; darts in flight now use the dart model, `DART_MODEL_GLB = false` in `combat.gd` brings back the old box and ball; the shell model is used by the shell ejection item; waiting for your in-game check)
- [x] Muzzle flash and shell ejection (a glowing flash on the muzzle for each shot, smaller while aiming, `_build_muzzle_flash` in `models.gd`; each pump throws a shell out of the right side that tumbles, lands and shrinks away, `eject_shell` in `player.gd` and `spawn_shell` in `effects.gd`; uses the shell model; waiting for your in-game check)
- [x] (Optional) Ammo count shown on the gun itself (a glowing number on the left side of the receiver: cyan, amber at 2 or fewer, red at 0, INF with rapid fire; `_build_ammo_label` in `models.gd`, updated in `update_gun`; the HUD ammo stays; waiting for your in-game check, including whether it is readable)

### F3. Melee
- [x] Chunky model with a glossy rubber material (new jelly club replaces the gummy worm: ribbed grip collar, fat knob, curved ringed shaft and a ridged head, one glossy pink material plus glitter flecks, shaped after the owner's reference photo; `tools/models/models/jelly_club.py` -> `assets/models/jelly_club.glb`, 2,600 tris, same reach and hand position as the worm, `RUBBER_MODEL_GLB = false` in `models.gd` brings the old worm back. It is one colour with no eyes, so the next checkboxes only need confirming in game. Waiting for your in-game check: open the project once so Godot imports the `.glb`, then look at the club in a run and in `tools/viewer/model_viewer.tscn`)
- [ ] No alternating colors
- [x] More detail (like the Dart gun) (flanged end with a groove, ribbed grip collar, two kinds of ridges on the shaft: rings low down and spiral ridges below the head, a moulded seam down one side, glitter in two sizes; 16-sided rings, 4,720 tris of the 10,000 budget; `geo.tube` now takes a `radius_fn` for ridges and seams; built on the jelly club branch; waiting for your in-game check, including whether the ridges read at swing distance)
- [ ] More rubbery look
- [ ] No eyes
- [x] Rubbery wobble swing animation (the club bends against the swing, overshoots when the swing stops and rings down, with a small ripple and a little stretch while it whips: a vertex shader on the club driven by a spring, `update_jelly` and the `JELLY_*` tuning constants in `scripts/player.gd`, `RUBBER_SHADER` in `models.gd`; `RUBBER_WOBBLE = false` in `models.gd` keeps the club rigid. Written without running Godot, only parse-checked with gdtoolkit; waiting for your in-game check: the bend, whether it settles in about half a second, and that the colours and gloss match the plain model)
- [ ] Hit, deflect and phone-return feedback

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
- [ ] Pedestrian vs rider readability check, including NIGHT
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
