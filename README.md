# FstreliBiciklina3D
Mostly vibe coded Godot game

## Testing rule
- Every test or check that has to be run from the command line with Godot (`godot --headless ... --script res://tools/...`) gets a Windows `.bat` script next to it in `tools/`, written like `tools/run_baseline.bat`: an optional path to the Godot exe as the first argument, the default Steam folder searched if none is given, the Godot version printed, and the result shown at the end. A check is not finished until its `.bat` exists. The first one is `tools/run_generated_run_check.bat`.

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
- [x] Confirm before Restart Run / Quit to Title (a run is lost with one click) (both pause menu entries now open a "RESTART RUN?" / "QUIT TO TITLE?" page with NO, GO BACK selected first and a YES button; works with mouse, keyboard (arrows / W S / Enter) and gamepad (D-pad / A), Esc or B goes back, and YES ignores clicks for 0.3 s after the page opens so a double click cannot lose the run; `confirm_*` functions in `scripts/input.gd`, `_draw_confirm` in `scripts/hud.gd`. Written without running Godot, only parse-checked and linted; waiting for your in-game check: pause, pick Restart Run and Quit to Title with each input method, and try a fast double click)
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
  - [x] Earn from boss kills (5 coins for a lawnmower, wifi adapter or minister, 1 for the angry cyclist, 20 for the final boss; counted when the boss dies and paid out with the score coins when the run ends, so a run you quit pays nothing, same as the score coins; the run summary says how many came from bosses; `COINS_*` tuning constants and `add_boss_kill` in `scripts/meta.gd`, hook in `kill_boss` in `scripts/bosses.gd`. Written without running Godot, only parse-checked and linted; waiting for your in-game check: kill a boss and look at the META COINS row on the run summary. Built on the save-file versioning branch because both change `meta.gd`)
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

- [x] Replace linear round progression (a run starts on a map screen and walks the generated map one node per round: pick the next node (Left / Right or mouse, Enter or click, 1-3), play it, upgrade and shop, back to the map, until the final boss floor; the floor number is the round number so difficulty scaling is unchanged, and `MAX_ROUNDS` follows the map; a run without a map still goes in a line; `enter_map` / `pick_node` / `next_round` in `scripts/main.gd`, `_draw_map_screen` in `scripts/hud.gd`, see `docs/MAP_GENERATION.md`. What each node type DOES is the list below and still open: for now every node plays the ordinary round and the type is only shown. NOT RUN YET: written in a session without Godot, only gdformat and gdlint were run, so play a run and run `godot --headless --path . --script res://tools/map_walk_check.gd`)

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

> These become arena styles of the procedural arena generator (Milestone K), chosen once per run, instead of hand-built scenes.

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
- [x] Record the "before" baseline: screenshots of every screen and theme, plus frame time (owner decision: the development laptop run counts as the baseline, since no minimum-spec machine is available; `tools/baseline.gd`, `tools/run_baseline.bat`, `tools/BASELINE.md`. Run on a Core Ultra 7 155U laptop with integrated graphics at 1280x720 with Godot 4.7.2: all 20 screens per renderer and frame times for every preset and theme are in `docs/baseline_f1/`. Not measured: a GTX 1060 class machine or 1080p, so the 16.6 ms budget at 1080p is only checked on this laptop)
- [x] Set up the model pipeline (Claude as modeler, Blender as a Python module `bpy`): scripts in `tools/models/`, output to `assets/models/*.glb` with a preview sheet per model in `docs/model_previews/`, automatic budget and file validation, conventions (1 unit = 1 metre), and an in-game model viewer (`tools/viewer/model_viewer.tscn`). How to use it: `tools/models/README.md`
- [x] Build the shared style kit: bevelled primitive helpers, the colour palette and material set (`tools/models/kit/`), and a test model (`test_crate`)
- [x] Owner check: open `tools/viewer/model_viewer.tscn` in Godot (F6) and confirm `test_crate` looks right in the game (colours, bevels, hazard stripes, the glowing lamp, scale) (confirmed by the owner)
- [x] Create `CREDITS.md` and the rule that every third-party asset gets an entry when it is added (see `CREDITS.md`; the voice recorders' names are still to be added under S6)
- [x] Switch off the outline pass and flat unlit toon materials behind a flag; simple lit low-poly materials become the default (`Toon.ENABLED = false` in `scripts/toon.gd`: no outline quad, `Util.mat()` and the jelly club shader use ordinary lit shading, and the OUTLINES row in settings and the F10 key are gone while it is off; `true` brings the old look back. Effects, strips and rings stay unshaded on purpose. Checked by rendering the game here with a software renderer, before and after: `docs/screenshots/f1-toon-off-before.png` and `f1-toon-off-after.png`. With flat toon lighting gone the NIGHT theme is clearly darker, which the next lighting items are there to fix; waiting for your in-game check on real hardware, including the jelly club and the settings panel)
- [x] Lighting baseline for DAY: bright sun with soft readable shadows, light sky, tone mapping, glow on gameplay accents (new `scripts/lighting.gd` sets up the environment and the sun once for all themes: Filmic tone mapping kept, because ACES washed the yellow kerb stripe out to white; additive glow that only picks up things brighter than 1.0; sun shadow blur 2.0 with adjusted biases. DAY itself got a lighter sky, a warmer and stronger sun at 48 degrees and more blue fill light in `Content.THEMES`. `Toon.setup_glow` is gone, so `toon.gd` now holds only the outline code that F12 removes. Checked by rendering the game here with a software renderer in the Compatibility renderer, before and after: `docs/screenshots/f1-day-lighting-before.png` and `f1-day-lighting-after.png`; NIGHT renders the same as before. Not checked: Forward+, shadow softness on real hardware (the software render still shows jagged shadow edges), frame time, glow on pickups in motion; waiting for your in-game check)
- [x] Lighting for GOLDEN HOUR, DUSK and NIGHT (warm lamp pools and lit windows, medium-dark sky, nothing hides in the dark) (`Content.THEMES`: GOLDEN HOUR got a higher sun for shorter shadows and more warm fill light; DUSK and NIGHT got a lighter blue sky (NIGHT is no longer near black), stronger fill light so the road and sidewalk stay readable, and a dimmer window glow; lit windows are warm orange so they no longer burn out to white, and the street lamps reach 16 m with more energy. Checked by rendering the game here with a software renderer, before and after, for each theme: `docs/screenshots/f1-golden-hour-*.png`, `f1-dusk-*.png`, `f1-night-*.png`. Not checked: real hardware, Forward+, frame time, how far the lamp pools reach on the road in motion (the software render shows them only faintly); waiting for your in-game check)
- [x] Test the Compatibility renderer against Forward+ on old hardware and decide which to ship (decided: ship Forward+, which is the project default, and keep Compatibility only as Godot's fallback when Vulkan fails. On the dev laptop with integrated graphics Forward+ stayed under 16.7 ms in every preset and theme (HIGH 1% low 142 fps or better), while Compatibility stuttered on HIGH (1% low 37 to 53 fps, up to 5.9% of frames over budget) and has no FXAA on MEDIUM; numbers in `docs/baseline_f1/README.md`. Not tested on old hardware, which the owner does not have; no code change, `project.godot` already uses Forward+)
- [x] Anti-aliasing choice (MSAA or cheaper FXAA) and re-define the F9 quality presets for the new look (decided: HIGH = 2x MSAA and a 2048 shadow map, MEDIUM = FXAA and a 1024 shadow map, LOW = no anti-aliasing, no shadows, no glow; in `scripts/settings.gd`, the viewmodel follows, decision recorded in `docs/ART_DIRECTION.md`. In zoomed test renders MSAA 2x clearly smooths the chunky edges and 4x showed no visible gain over it. FXAA only exists in Forward+: in the Compatibility renderer, which is also Godot\'s fallback when Vulkan fails, MEDIUM has no anti-aliasing, so the code only asks for it when Forward+ is running. Checked here: each preset sets the right MSAA, FXAA, shadow and glow state on both viewports, no warnings, all CI checks pass. Not checked: Forward+ (no Vulkan here, so FXAA was never seen working), frame time on any machine; to settle with the Compatibility vs Forward+ test)

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
- [x] No alternating colors (the whole club is one glossy pink; the light and dark pink ribs of the old worm are gone; confirmed by the owner in game)
- [x] More detail (like the Dart gun) (flanged end with a groove, ribbed grip collar, two kinds of ridges on the shaft: rings low down and spiral ridges below the head, a moulded seam down one side, glitter in two sizes; 16-sided rings, 4,884 tris of the 10,000 budget; `geo.tube` now takes a `radius_fn` for ridges and seams; built on the jelly club branch; waiting for your in-game check, including whether the ridges read at swing distance)
- [x] More rubbery look (glossy jelly material with toon highlights and a pink rim glow, ridges and rings that bend with the wobble, a squash and stretch on every swing and a flash on every hit; confirmed by the owner in game)
- [x] No eyes (the new club has none; confirmed by the owner in game)
- [x] Rubbery wobble swing animation (the club bends against the swing, overshoots when the swing stops and rings down, with a small ripple and a little stretch while it whips: a vertex shader on the club driven by a spring, `update_jelly` and the `JELLY_*` tuning constants in `scripts/player.gd`, `RUBBER_SHADER` in `models.gd`; `RUBBER_WOBBLE = false` in `models.gd` keeps the club rigid. Written without running Godot, only parse-checked with gdtoolkit; waiting for your in-game check: the bend, how strong the bend and ring-down feel (it now rings for about two seconds, tune the `JELLY_*` constants), and that the colours and gloss match the plain model)
- [x] Hit, deflect and phone-return feedback (a hit splashes pink jelly and the club shudders, squashes and flashes; a deflect throws a white, pink and gold flash and a harder shudder; a returned phone leaves a pink and gold trail and ends in a bigger smash and shake; `jelly_burst`, `deflect_burst` and `return_trail` in `effects.gd`, `jelly_kick` in `player.gd`, hooks in `swing`, `deflect_phone`, `update_returning_phone` and `strike_with_phone` in `combat.gd`; existing sounds, hit-stop, popups and score are unchanged. Written without running Godot, only parse-checked; waiting for your in-game check, including particle counts on the minimum-spec machine)

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

# Milestone G: Procedural Map Generation

> Works together with the run map in Milestone D: the seed decides the map, and the map decides which encounters, shops and bosses a run contains.

- [x] Generate the run map procedurally from a seed (all three parts below are done; the map is generated and printed to the console, but rounds do not follow it yet: that is Milestone D)
  - [x] Same seed always produces the same map (`scripts/map_gen.gd` builds the map from the run seed and `data/map_rules.json` only, using seeded streams and a fixed draw order, no global random calls; `start_game` in `main.gd` builds it for every run and prints it to the console, rounds do not follow it yet; `tools/map_check.gd` generates 2,000 seeds twice, compares the results and checks the rules, run it with `godot --headless --path . --script res://tools/map_check.gd`. Run here with Godot 4.7: all 2,000 maps repeat exactly and follow the rules, and the check fails when the no-repeat rule is broken on purpose. Not checked: the map as seen in game, since nothing draws it yet. Built on the map rules branch, which is built on the random run seed branch)
  - [x] Daily seed produces the same map for every player that day (builds on Daily Seed Mode in Milestone A) (a Daily Run uses the daily seed as its run seed, so it gets the same map as every other player that day; checked headless with Godot 4.7: two Daily Runs started in a row printed the same map)
  - [x] Random seed for normal runs, shown on the run summary so a run can be replayed (every normal run now gets a random 32-bit seed at the start, `random_seed` in `scripts/daily.gd`, `start_game` in `scripts/main.gd`; the run seed drives the same seeded generators the Daily Run already used (rider mix, shop and upgrade offers, starting boss and lighting theme), so `layout_*`, `offer_shuffle` and `seed_shift` (was `daily_shift`) no longer check for daily mode; the summary shows "RUN SEED xxxxxxxx" (or "DAILY RUN SEED") in small grey text at the bottom, `_draw_run_summary` in `scripts/hud.gd`; Restart Run gives a normal run a new seed and a Daily Run the same one. Behaviour change: a normal run no longer always starts on the first theme and boss, they rotate with the seed. Entering a seed to replay it needs the custom seed item below. Checked headless with Godot 4.7 (the project loads, two normal runs get different seeds, a Daily Run keeps the daily seed) but not seen on screen; waiting for your in-game check: finish or lose a run and read the seed on the summary, and confirm two normal runs start on different themes sometimes while a Daily Run is unchanged)
- [x] Define the map generation rules (number of nodes, branching, guaranteed shop / rest stop / boss placement) (10 floors so a path is 10 rounds; floor 1 is 3 normal nodes, floor 5 is the mid boss, floor 10 the final boss, floors 4 and 9 hold only shop and rest nodes with at least one of each so every path can heal or spend before each boss; other floors have 2 to 4 nodes with weighted types, caps on elites and events and no repeated elite / shop / rest / event along an edge; 1 or 2 non-crossing edges per node; fixed streams and draw order so one seed gives one map; the list of what a valid map must satisfy is in `docs/MAP_GENERATION.md`, numbers in `data/map_rules.json`. Rules only: nothing reads the file yet, the numbers are first guesses to tune once the generator exists, and the shop becoming a node changes the economy, which needs a balance pass. Built on the random run seed branch)
- [x] Generate arena layouts and encounter contents from the seed (the arena layout is the run seed's layout from `scripts/arena_gen.gd` (Milestone K); every map node gets a `content` entry from `scripts/map_content.gd`: theme, rider count and mix, open gates, 0 or 1 modifier, boss kind, or a seed for shop / rest / event nodes; each node has its own generator so one node never changes another and the floors, edges and types of every seed are unchanged; numbers in the `content` section of `data/map_rules.json`, explained in `docs/MAP_GENERATION.md`; `tools/map_check.gd` checks the content of 2,000 maps. NOT RUN YET: written in a session without Godot, only gdformat and gdlint were run, so run `godot --headless --path . --script res://tools/map_check.gd` once before merging; rounds do not use the content yet: that is Milestone D)
- [x] Validate that every generated map is completable (no dead ends, boss always reachable) (`MapGen.validate` checks floors, edges, reachability from floor 1 and to the final boss, fixed floors, caps and, now, the node content: every fight has riders and an open gate that exists, every boss a kind; a failing map is regenerated from a derived seed, up to `max_attempts`, see `docs/MAP_GENERATION.md`; `tools/map_check.gd` damages a good map 20 ways and checks each is named. NOT RUN YET: written in a session without Godot, only gdformat and gdlint were run, so run `godot --headless --path . --script res://tools/map_check.gd` before merging)
- [x] Debug tool: enter a seed and preview the generated map (a viewer scene, `tools/viewer/map_viewer.tscn`: open it in Godot and press F6, like the arena viewer. Type a seed in the box and press Enter (up to 8 hex digits such as `7F3A91C2`, or `today`; the same text works in the arena viewer, which draws the arena of that seed), or use Random / Daily / Left / Right. The run map is drawn with floor 1 at the bottom and the final boss at the top, a circle per node (letter and colour = type) and a line per edge; click a node to see its theme, riders, open gates, modifier, boss kind or seed and to highlight the nodes it joins. `tools/map_viewer_check.gd` checks the positions, the texts and the scene headless. NOT RUN YET: written in a session without Godot, only gdformat and gdlint were run, so open the scene once and run `godot --headless --path . --script res://tools/map_viewer_check.gd`)
- [x] Optional: let the player type in a custom seed on the title screen (new CUSTOM SEED entry on the title menu (the buttons are a little smaller so eight fit): type up to 8 hex digits (0-9, A-F) or paste with Ctrl+V, press Enter or click START to play that seed; Esc or a click elsewhere goes back; while the page is open the letter hotkeys do nothing so A-F can be typed; `start_game(daily, custom_seed)` in `scripts/main.gd`, `seed_key` in `scripts/input.gd`, `_draw_seed_page` in `scripts/hud.gd`. Decisions: a custom-seed run is not ranked (no normal high score and no Top 10, like a Daily Run, so one known easy seed cannot be farmed; `Main.ranked_run()`), a restart from the pause menu replays the same seed, the run bar says SEED and the summary says CUSTOM SEED (NOT RANKED); gamepad cannot type, so the page is keyboard only. NOT RUN YET: written in a session without Godot, only gdformat and gdlint were run, so try it once and run `godot --headless --path . --script res://tools/seed_page_check.gd`)

---

# Milestone H: Run Start Sequence

- [ ] Design the opening sequence (storyboard: bed, house, door, nerf gun, street)
- [ ] Build the bedroom and house interior (small, low-poly, matches the art direction)
- [ ] Wake-up animation: the player stands up from the bed (first-person camera)
- [ ] Walk from the bed to the front door (scripted movement, no player control)
- [ ] Pick up the nerf gun on the way out (the starting one-dart gun appears in the viewmodel)
- [ ] Walk out the door onto the street
- [ ] Screen fades out, then fades back in on the generated map
- [ ] Allow the player to skip the sequence (button or key), and a setting to always skip it
- [ ] Keep the sequence short (target under 15 seconds) and skip it on a restart after dying
- [ ] Hook the sequence into Play and Daily Run, and make sure the seed is already chosen before it starts

---

# Milestone I: Roguelite Progression

> The player starts every run with the simplest possible loadout and earns everything else across runs.

- [ ] Starting loadout: a simple one-dart gun and the melee weapon, nothing else
- [ ] Unlock and buy new weapons with meta currency (adds them to the shop pool)
- [ ] Unlock and buy upgrades and starting perks with meta currency
- [ ] Unlock screen replaces the "coming soon" Unlocks page (items, price, owned / locked state)
- [ ] Loadout screen replaces the "coming soon" Loadout page (choose what you start a run with from what you own)
- [ ] Save unlocks and purchases in the versioned save files (see `docs/SAVE_FILES.md`)
- [ ] Show newly unlocked items on the run summary screen
- [ ] Define the unlock list and price curve in a data table (like `data/items.json`)
- [ ] Balance pass: the first runs with the starting loadout must be winnable but hard, and each unlock should feel meaningful
- [ ] Reset progress option in Settings, with confirmation

---

# Milestone J: Manual Reload

- [ ] Remove the automatic reload after a few seconds
- [ ] Press R to reload manually
- [ ] Automatically reload when the magazine reaches 0
- [ ] Cannot shoot while reloading; reloading can be interrupted by dashing or switching to melee (decide the exact rule when building it)
- [ ] Reload animation and sound hooks (builds on the pump / reload animation in F2)
- [ ] HUD and ammo label on the gun show the reloading state
- [ ] Add reload to the key rebinding list and the Controls page
- [ ] Rebalance darts per magazine and reload time now that reloading is not free
- [ ] Check how perks and items that touch ammo (rapid fire, infinite ammo, fat darts) interact with the new reload

---

# Milestone K: Procedural Arenas

> Every run gets one generated arena, about four times bigger than the roundabout, that the player walks through freely and where riders can ride on roads, sidewalks, grass and anywhere open. Design, owner decisions, current-code notes and open questions: [`docs/PROCEDURAL_ARENAS.md`](docs/PROCEDURAL_ARENAS.md). Needs the seed from Milestone G; the world kit from Milestone F9 should be reused for the dressing. This replaces how riders, bosses and pedestrians move (street coordinates become world positions), so it is large: work top to bottom, and the first steps keep the roundabout playing as it does today.

## Decisions

- [x] Size: about 4 times the walkable area (about 6,000 m² against about 1,500 m² now)
- [x] The player walks through the whole arena
- [x] Riders do not lap or follow a fixed lane: they can ride on road, sidewalk, grass, anywhere open
- [x] One arena per run (generated once from the run seed)
- [x] Riders ride toward the player, pass if they are not shot, then turn round in a smooth arc (limited turning rate, never a sharp 180 degree switch) and ride toward the player again
- [x] Map nodes: every node uses the whole arena with its own set-up (rider mix, gates in use, props, theme and modifiers), and the player starts each round in a clear start area (the owner left this choice to Claude, reasons in the design note)
- [x] A rider that passes the player does damage as it does now (same dash and perfect-dodge rules); riders keep coming back until they are killed, with no cap on passes and no time limit (the melee weapon is the fallback), and a round ends when every rider is down
- [x] Decide whether road, sidewalk and grass change rider speed (yes, for riders: road and plaza 1.0, sidewalk 0.9, grass 0.75 of a rider's speed, in `rider_speed` in `data/arena_rules.json`; buildings are not ridden on. The owner accepted this suggestion; the player's own speed does not change. The numbers are a first guess to be tuned in the playtest item. Nothing reads the table yet: riders use it once they move over open ground)
- [ ] Set the performance budget (triangles, lights, shadows, draw distance) on the minimum-spec machine (deferred by the owner: not needed yet, but needed before the world is built)

## Foundation

- [x] Put the arena behind one `Arena` interface with world-space queries (player bounds, surface at a point, obstacles, gates), with the roundabout as its first implementation (no visible change) (`scripts/arena.gd` is the interface and `scripts/arena_roundabout.gd` the roundabout; `main.gd` owns one `arena` object and no game script outside `arena_roundabout.gd` preloads `ring.gd` any more (only the check tool keeps it, as a fallback from before the interface existed). The queries are `start_position`, `clamp_walk` (player bounds), `ray_blocked` (darts), `obstacle_at` (boss movement), `surface_at` and `gates`, next to the street-coordinate functions that riders, bosses and pedestrians still use until the next item moves them to world positions. `clamp_walk`, `ray_blocked` and `obstacle_at` moved out of `main.gd` and `bosses.gd` unchanged, `surface_at` and `gates` are new and nothing calls them yet. `world.gd` takes the arena object and is still the roundabout's own builder. Checked headless with Godot 4.7: `tools/arena_check.gd` matches its golden file (now 901 lines: the 601 from the original code plus 300 dense dart samples taken from the original code, since random points rarely land in the fountain) and fails when `clamp_walk` or `ray_blocked` is broken on purpose, plus new checks that `surface_at`, `gates` and `start_position` agree with the ground `world.gd` lays down; `world.gd` builds the same 261 nodes with the same fingerprint (class, position, rotation, mesh size, colour) before and after; gdlint, gdformat and the CI project load run are clean. Not checked: playing it on screen, and the golden file is not a complete test of player movement, so a short walk around the island, the planter and the tunnel in game is the check I would still like from you)
- [x] Move rider, boss and pedestrian movement from street coordinates to world positions with steering and obstacle avoidance (the roundabout must still play the same) (done: bosses, riders and pedestrians now move on world positions. Boss attacks are still drawn in street space; they are the "Boss attacks on open ground" item under Gameplay, so they are not part of this one. Bosses (branch `roadmap/boss-world-positions`): a boss already moved by its world position `wp`, so its street `x` and `z` are gone and `combat.gd`, `hud.gd`, `player.gd` and `bosses.gd` read `wp` (through `boss_world`) and a stored `yaw` for the hit box; `tools/boss_check.gd` runs every boss kind and fails if `wp` leaves the ground a boss may walk on, `yaw` or the model drift from `wp`, or the street keys come back. Pedestrians and cheerleaders (branch `roadmap/pedestrian-world-positions`): they publish `pos`, `yaw` and `hidden` and `combat.gd` reads those; a cheerleader has a fixed `pos`. Riders (branch `roadmap/rider-steering`, on top of the other two): a rider owns `pos`, `yaw` and `hidden` in world space and moves them itself in `move_rider` in `riders.gd`; there is no street `x` on a rider any more. It steers at a point on its lane a little ahead (`arena.lane_point`, `LOOKAHEAD_*`), turning no faster than `TURN_RATE` (9 rad/s, the ring asks for about 3), and rides at `spd * arena.scale_at(lane_z)` metres per second over the ground. A rider that gives up turns at once towards the nearer seam and rides out through `arena.exit_distance`. `arena.rider_avoidance()` says whether riders must steer round `obstacle_at()` themselves: the roundabout says no (its lanes are clear), generated arenas will say yes, and `avoid_obstacles` and `way_clear` in `riders.gd` do it (nearest clear heading to the wanted one, remembering which side it swung to so it does not dither, up to 120 degrees off). Phones leave from `phone_origin` and parts fly off along the rider's heading (`part_vel`). Riders still follow their lane: ride-at-the-player pursuit is the first item under Gameplay on open ground. `tools/rider_check.gd` replays the old street-coordinate movement next to the new one and fails if a rider is ever more than 0.15 m or 0.12 rad from where the old code puts it, is hidden when it should not be, leaves the arena more than a step away from when the old code did, has its model off `pos` or `yaw`, or if parts fly off the wrong way; it also checks that `avoid_obstacles` steers a rider round the fountain and leaves a clear heading alone. Largest gap on the roundabout: 0.05 m at 20 fps, 0.07 m at 60, 0.11 m at 144. It fails when `TURN_RATE` is cut to 1, when `exit_distance` is zeroed and when the avoidance swing is removed. `tools/arena_check.gd` still matches its golden file, `tools/boss_check.gd` and `tools/pedestrian_check.gd` pass, gdlint and gdformat are clean and the project loads headless with Godot 4.7 for 120 frames without errors. Pedestrians (branch `roadmap/pedestrian-steering`, on top of main): a pedestrian owns `pos`, `yaw` and `hidden` in world space and moves them itself in `move_civ` in `pedestrians.gd`; it has no street `x` or `z` any more (it keeps its lane as `lane_z`, and `left` counts the street metres still to walk before it is out of the arena). It steers at a point on its lane a little ahead (`arena.lane_point`, `LOOKAHEAD_*`), turning no faster than `TURN_RATE` (6 rad/s), and walks at `spd * arena.scale_at(lane_z)` metres per second over the ground; where the arena asks for it (`arena.rider_avoidance()`) it steers round `obstacle_at()` with the riders' `avoid_obstacles`. A startled pedestrian still turns round at once and runs for the nearer end (`turn_to_flee`). `street_left` and `turn_to_flee` are the only places in `pedestrians.gd` that still use street coordinates; the placement item under Gameplay replaces them with gates. `tools/pedestrian_check.gd` replays the old street-coordinate walking (walk speed, standing still while a tourist takes a photo, the flee speed after a hit) next to the new one and fails if a pedestrian is ever more than 0.15 m or 0.12 rad from where the old code puts it, is hidden when it should not be, leaves the arena more than one step away from when the old code did, has its model off `pos` or `yaw`, or has a street key; it also puts in a test arena with a post on the sidewalk and checks that a pedestrian steers round it and goes on past. Largest gap on the roundabout: 0.04 m and 0.02 rad (at 20, 60 and 144 fps). It fails when `TURN_RATE` is cut to 0.05, when the leave distance is 10 m too long and when the avoidance is switched off. `tools/arena_check.gd`, `rider_check.gd`, `boss_check.gd`, `arena_gen_check.gd`, `map_check.gd` and `arena_viewer_check.gd` still pass, gdlint and gdformat are clean and the project loads headless with Godot 4.7 for 120 frames without errors. Not checked: playing it on screen, so a few rounds with riders in all three lanes, a phone throw, a melee hit on a rider, a rider that gives up and rides out, and pedestrians walking, jogging, stopping for a photo, fleeing after a hit and leaving through the tunnel is the check I would still like from you)
- [x] Player bounds from the arena instead of `PLAYER_R_MIN` / `PLAYER_R_MAX` (`clamp_walk(p, who)` takes "player", "boss" or "pickup" instead of two radii, and the radii (2.3 m and 22.3 m, with the boss and pickup margins) now live in `arena_roundabout.gd`; the two constants are gone from `main.gd`, and `player.gd`, `bosses.gd` and `pickups.gd` just name who is asking. No change in play: `tools/arena_check.gd` still matches its golden file (901 lines identical) and has new checks for the limits each kind gets; gdlint and gdformat are clean and the project loads headless with Godot 4.7 for 120 frames without errors. Not checked: playing it on screen, so a short walk to the fountain and the buildings, and picking up a dropped item, is the check I would still like from you)

## Generation

- [x] Arena generator: seed in, terrain layout out (size, roads, plazas, grass, building blocks, gates); same seed, same arena (`scripts/arena_gen.gd` and `data/arena_rules.json`. `ArenaGen.generate(run_seed)` returns a plain-data layout: a 48 by 48 grid of 2 m cells (96 m square, about 6,400 m² of walkable ground on average, 6,000 to 7,000 allowed) as text rows of `g` grass, `p` plaza, `s` sidewalk, `r` road, `b` building and `t` tunnel, plus lists of roads, plazas, building blocks, gates and the start area. It has a 2-cell building ring round the edge, one or two roads each way (3 cells wide with a sidewalk each side) that run edge to edge, between two and five of the road ends opened as tunnel gates (the rest walled off), a clear start plaza of at least 9 by 9 cells with a 5 by 5 clear area in the middle, up to two more plazas and building blocks on the grass. It draws only from streams seeded by `DailyScript.stream_seed` (roads, plazas, blocks) and never from the global random functions. An attempt that cannot place the start plaza or lands outside the ground range is thrown away and the next one uses streams seeded with the attempt number, so a seed still gives one layout (about one seed in ten needs a second attempt). `surface_at` and `rider_speed_at` read a layout and `to_text` prints it. `tools/arena_gen_check.gd` generates 2,000 seeds twice, checks the layouts repeat exactly and all differ (2,000 different), and checks the grid shape, border ring, gates (tunnel cells, a road behind each, position and outward direction), start area, building blocks, ground area and the speed table; it fails when the seed stream is replaced by `randomize()`, when the start plaza is not painted, when the tunnels are not opened and when grass is made faster than road. `tools/arena_check.gd` and `tools/map_check.gd` still pass, gdlint and gdformat are clean and the project loads headless with Godot 4.7 without errors. Not done: the generator is not connected to the game (the roundabout is still the only arena), props, curves and varied shapes are not generated yet (roads are straight and every layout is a grid of blocks, which the arena styles item will vary), and it has not been looked at on screen: `godot --headless --path . --script res://tools/arena_gen_check.gd -- <seed>` prints a layout as text. Reachability, minimum corridor widths and sightlines are the validation item below)
- [x] Generate the navigation grid with the layout (`ArenaGen.generate` now adds `nav` to every layout: rows of text the same size as the ground rows, `#` where nothing can go (a building) and otherwise a digit 1 to 9, the clearance, meaning how many cells away the nearest building is, counting diagonals and capped at `nav.max_clearance` in `data/arena_rules.json`. A 1 means the cell touches a building, so a rider there has no room to swing; the start area is at least 3. Tunnel cells are open so riders can enter at the gates. `nav_clearance(layout, cx, cz)` reads the grid and `nav_cost(layout, rules, cx, cz)` gives what a rider pays to cross a cell, 1 divided by its speed share on that ground (1.0 on road, 1.33 on grass) and infinity on a building, so a path search that adds the costs finds the quickest way. `tools/arena_gen_check.gd` checks for all 2,000 seeds that a cell is blocked exactly where there is a building, that no gate or the start cell is blocked or cramped, and that costs follow the speed table, and on every 40th seed compares each clearance with a slow search for the nearest building; it fails when tunnels are blocked, when diagonals are left out of the clearance and when the cost ignores the speed table. Not done: nothing searches the grid yet (path finding comes with rider pursuit, and checking that every gate can reach every other is the validation item below), and it has not been looked at on screen)
- [x] Validate every generated arena (all gates connected, no sealed areas, minimum corridor widths, a clear start area, sightlines) (`ArenaGen.validate(layout, rules)` returns the problems in words, none when the layout is fine, and `generate` throws a failing layout away and uses the next attempt, so a seed still gives one layout. The rules, numbers in `validate` in `data/arena_rules.json`: the start area is a clear square of plaza with room round it; every open cell can be reached from the start on foot (no sealed areas); every gate can be reached from the start through corridors with a clearance of at least 2 (three cells, 6 m, wide); and at least half (`min_view` 0.5) of the open ground within 20 cells (40 m) of the start is in plain view, a straight line between cell centres crossing no building, so the player sees what is coming. On 1,500 seeds before the rules were switched on, 2 layouts failed (a gate not reachable through wide corridors) and none had sealed areas; the view share had a median of 0.91 and a lowest of 0.37, so the sightline rule throws away only the rare blind start. About one seed in ten still needs a second attempt, mostly for the ground area. `tools/arena_gen_check.gd` now also damages a good layout five ways (a gate walled off, a one-cell corridor to a gate, a walled-off pocket, a dirty start area, a start walled in) and fails if `validate` does not name the matching problem; it fails when the sealed-area rule, the corridor rule or the sightline rule is switched off. Not done: the sightline rule only looks from the start (what a rider sees from a gate, and long open lines that favour a sniping boss, are for the playtest and balance item), and it has not been looked at on screen)
- [x] Debug tool: enter a seed and preview the generated arena (a viewer scene, `tools/viewer/arena_viewer.tscn`: open it in Godot and press F6, like the model viewer. Type a seed in the box and press Enter (a seed as the game shows it, up to 8 hex digits such as `7F3A91C2`, or `today`), or use the Random and Daily buttons or Left / Right for the previous and next seed. The arena is drawn from above as one coloured mesh: every 2 m cell in the colour of its ground (grass, plaza, sidewalk, road, tunnel), buildings as blocks 4 m high, each gate with an arrow pointing out of the arena and a number, and the start area as a pink square with a pole and a START label; a legend sits under the text, which gives the seed, the attempt, the ground area, how many roads, plazas, buildings and gates there are, where the start is, and what `ArenaGen.validate` says. C switches the colours to the navigation clearance (red 1, touching a building, to green 9 and more), which shows narrow corridors at a glance; mouse drag orbits, the wheel zooms, R resets the camera. It calls `ArenaGen.generate` and `validate` and reads nothing else, so it shows exactly what the game would get for that seed. `tools/arena_viewer_check.gd` checks the picture for 200 seeds: every cell is drawn once, where `surface_at` says it is and in its ground colour (so a mirrored or swapped axis fails), buildings are the right height with walls only where they face open ground, the start frame is the size of the clear start area and centred on the start, each gate arrow sits on its gate and points the way `outward` says, and the same seed gives exactly the same picture; it also runs the scene (a typed seed draws that layout, a bad seed is refused, Left / Right and C work, a label for every gate and the start). It fails when the x axis is mirrored, x and z are swapped, the gate arrows point inward, the start marker is left out or walls are drawn on every side, and while writing it found two faults in the viewer, both fixed: `-5` was accepted as a seed, and the gate arrow tips stuck out of the outer wall. Rendered here with Godot 4.7 under a virtual display (software OpenGL, no GPU) at the project's window size and looked at: the whole arena fits on screen for the seeds tried. Not checked: opening it in the Godot editor and on a real GPU, so a quick look at a few seeds there is the check I would still like from you. gdlint and gdformat are clean, `tools/arena_check.gd`, `arena_gen_check.gd` and `map_check.gd` still pass and the project loads headless for 120 frames without errors)

## Building the world

- [x] Ground surfaces, curbs and markings from the layout (`scripts/world_gen.gd`: `WorldGen.build_ground(layout)` turns a layout into the ground you walk and ride on, in world metres with the surface at y 0. One flat mesh per ground type (grass, plaza, sidewalk, road, building lot, tunnel floor) with neighbouring cells merged into rectangles; a raised curb (0.12 m high, 0.22 m wide) on every cell edge where a road meets a sidewalk, plaza or grass, and none against a building, a tunnel mouth or another road; a white edge line inside the road along each curb and a dashed centre line along each road, stopping 0.8 m short of crossings and road ends; and a hazard-yellow frame round the clear start area. It returns the nodes, the triangle count and the draw-call count, reads nothing but the layout (the same layout builds the same meshes) and uses the roundabout's materials until Milestone F replaces them. Over 400 seeds an arena is 334 to 688 triangles and at most 10 draw calls. In the viewer (`tools/viewer/arena_viewer.tscn`) W swaps the flat plan for this lit ground with its own legend and the counts; the next seed keeps the view and C goes back to the plan. `tools/world_gen_check.gd` reads the finished meshes back and checks them against the layout for 100 seeds (400 run clean): every cell is covered by exactly one rectangle of the right ground type, flat at y 0 and on the cell grid; a curb stands on exactly the road edges listed above, centred on the edge, with its sides reaching the ground; the paint lies only on road, there is an edge line next to every curb and every road has whole dashes on its middle that keep clear of crossings and ends; the start frame is four strips of the right size centred on the start with a bare middle, on plaza; every triangle faces up and is wound the way Godot draws it, so nothing is culled; normals are unit vectors, nothing leaves the arena, colours tell the ground types apart and the counts WorldGen reports match the meshes; the same layout builds the same meshes. It also damages the ground nine ways (mirrored, sidewalks built as grass, the start frame moved, paint, curbs or the start frame left out, a hole in the grass, a road wound the wrong way, a road in grass colour) and fails if a check does not name each one, and it fails on size constants outside a sensible range (curb height, dash margin and so on). I also broke `world_gen.gd` on purpose (curbs against buildings, dashes through crossings, a mirrored x axis, the edge line on the wrong side, the start frame one cell off, cells dropped from the merge) and each was caught. `tools/arena_viewer_check.gd` now also runs W: it shows the ground WorldGen builds for that layout with one light and a label for every gate and the start, keeps it when the seed changes, shows the right legend and counts in the text, and goes back to the plan on W twice or C; it fails when W does nothing, when a seed change drops the view, when the light is missing, when C stays in the real ground and when the legend is not switched. gdlint and gdformat are clean, `arena_gen_check`, `arena_check`, `rider_check`, `boss_check`, `pedestrian_check` and `map_check` still pass and the project loads headless with Godot 4.7 for 120 frames without errors. Not done: nothing in the game uses it yet (the roundabout is still the only arena in play), buildings, props, lamps and gates are the next item, the ground is flat with no collision of its own (the layout and `surface_at` stay the truth for where things can go), and the materials are placeholders. Not checked: how it looks. The ground was looked at on screen under a virtual display when it was written (surfaces, curbs, paint and the start frame sat where the layout says), but I did not look again after adding the checks, and nobody has seen it in the Godot editor or on a real GPU, so a look at a few seeds with W is the check I would still like from you. Build time and frame cost are not measured either; the performance budget above is still open)
- [x] Place buildings, props, lamps and gates (tunnels, alleys) from the layout (reuse the F9 kit) (`scripts/world_dress.gd`: `WorldDress.build(layout)` stands things on the ground `WorldGen` lays, in world metres, from the layout alone (no scene, no random functions), so one layout gives one arena. Buildings: every `b` cell is under exactly one lot, a box at most 3 cells across, 6.5 to 11.3 m high and brick or dark by a hash of its cells, with rows of windows on every face that looks onto open ground. Gates: every `t` cell is under a black tunnel block 6.5 m high with a hazard-yellow band round the top of each face that looks onto open ground. Lamps: on sidewalk cells that touch exactly one road and no tunnel, every 8 cells (16 m) along a road with the two sides half a spacing apart, each a pole, an arm over the kerb, a glowing head and a hidden warm `OmniLight3D` (the same range, energy and colour as the roundabout's after F1). Trees: on grass cells with only grass and sidewalk round them, about one in 14, a trunk and two blocks of leaves. It is all boxes merged per material: over 100 seeds an arena is 87 to 134 lots, 18 to 36 lamps, 21 to 58 trees and 4,500 to 6,100 triangles in 10 draw calls. The windows and lamp heads are dark until the theme lights them (the next item). The F9 kit is not built, so these are the roundabout's chunky stand-ins in its colours. The viewer's W view shows it all, with the counts and legend. `tools/world_dress_check.gd` reads the finished meshes back for 100 seeds (400 run clean) and checks them against the layout: every building cell under one lot, windows on exactly the open faces, tunnel blocks and bands, and for lamps and trees which cells qualify (worked out again in the check, not taken from `WorldDress`), the size and place of every pole, arm, head, trunk and block of leaves, that poles and trunks stand on the ground, that lights are hidden, over their heads and have the right range and energy, winding, normals, counts, colours and that the same layout builds the same meshes; it also damages the result fourteen ways (mirrored, a building, a lamp pole or a tree trunk missing, walls inside out, no windows, a window missing, no tunnel blocks, a band missing, windows or lamp heads lit by day, a lamp light left on, a lamp or a tree in a cell where none may stand) and fails if each is not named. `arena_viewer_check.gd` now checks the dressing in the W view too; `world_gen_check`, `arena_check`, `arena_gen_check`, `rider_check`, `boss_check`, `pedestrian_check` and `map_check` still pass, gdlint and gdformat are clean and the project loads headless with Godot 4.7 for 120 frames without errors. Main (the F1 lighting) is merged in. Not done: alleys, because the generator makes none (a layout only has tunnel gates, so alleys wait for the arena styles item); props are decoration with no collision, so riders and the player pass through trunks and poles until the rider pursuit item makes them obstacles; nothing in the game uses the arena yet. Not checked: how it looks (I did not render it, and nobody has seen it in the Godot editor or on a real GPU, so a look at a few seeds with W is the check I would still like from you), and frame cost, which the open performance budget does not cover yet. 18 to 36 hidden lamp lights is a lot if the theme turns them all on, so the theme and performance items decide how many are lit)
- [x] Theme lighting and lit windows on generated arenas (`Lighting.apply_theme(theme, world, focus)` in `scripts/lighting.gd` is now the one place a `Content.THEMES` entry (DAY, GOLDEN HOUR, DUSK, NIGHT) is applied: sky, sun, ambient light, windows glowing at the theme's `lit` strength, lamp heads glowing (`LAMP_HEAD_GLOW`, 3.0) and the lamp lights on or off. `main.gd`'s `apply_theme` now calls it, so the roundabout and a generated arena light the same way (nothing changes on the roundabout: six lamps, all lit at DUSK and NIGHT as before), and `Lighting.make_environment()` is the sky and environment `world.gd` used to build inline. A generated arena has 18 to 36 lamps, so at most `MAX_LAMP_LIGHTS` (8) lamp lights come on, the ones nearest `focus` (the start) when the world has more; every lamp head still glows, and the F1 baseline (`docs/baseline_f1`) says Compatibility with HIGH already stutters (1% lows of 37 to 53 fps) while Forward+ has plenty of room, so 8 is a cautious first number for the performance item to raise or lower. In the viewer (`tools/viewer/arena_viewer.tscn`) the W view now has its own sky, sun with shadows and the theme, and T steps through the four themes (shown in the text). `tools/arena_theme_check.gd` dresses 30 seeds, applies every theme and checks the sky, sun colour, strength and angle, ambient light, window and lamp-head glow and the number and choice of lamp lights (the nearest ones, worked out again in the check), that NIGHT then DAY puts everything out, and that a six-lamp world lights them all in order; it also damages the result six ways (no limit on lights, the farthest lamps lit, dark windows at night, lamp heads glowing by day, a light left on by day, the sun at the wrong angle) and fails if each is not named, and I broke `Lighting` on purpose (limit removed, nearest-first reversed) and the check failed both times. `tools/arena_viewer_check.gd` now runs T (every theme in turn, wrapping round, the text, the glow and lights, the plan having no theme, a new seed keeping the theme). `world_dress_check`, `world_gen_check`, `arena_check` (still 901 lines identical), `arena_gen_check`, `rider_check`, `boss_check`, `pedestrian_check` and `map_check` still pass, gdlint and gdformat are clean and the project loads headless with Godot 4.7 for 120 frames without errors. Rendered under a virtual display (software OpenGL) for DAY, GOLDEN HOUR, DUSK and NIGHT on one seed and looked at: windows light up and lamp pools sit on the road at NIGHT. Not done: every window glows the same (no dark and lit mix), the choice of theme for an arena is not connected (the run seed already picks `theme_idx` in the game, nothing builds a generated arena in play yet) and the lamp light count is not tuned. Not checked: the look on a real GPU or in the Godot editor, and in play; a look at a few seeds with W and T is the check I would still like from you)

## Generated arena class

> Puts the `Arena` interface on a generated layout (`scripts/arena_generated.gd`, checked by `tools/arena_generated_check.gd`), so the game can be played on a generated arena. One small step at a time, each pushed to its own branch commit. It is the base of the "Connect the arena to the run map" item below.

- [x] Skeleton and ground queries: `surface_at`, `rider_speed_at`, `start_position`, `gates` in world space, `rider_pursuit()` and `rider_avoidance()` true (checked against 200 layouts, and broken on purpose three ways: swapped start axes, flipped gate directions, wrong rider speeds; not used by the game yet)
- [x] Bounds and blocking: `clamp_walk` for player, boss and pickup, `obstacle_at`, `ray_blocked`, `rider_blocked` (open through the gates), `hidden_at` (inside a gate's tunnel) (`GeneratedArena` in `scripts/arena_generated.gd`; a cell is walkable unless it is a building or a tunnel block. `obstacle_at` and `ray_blocked` are true on those cells (a dart passes over them above 6.5 m), `hidden_at` is true on tunnel cells and in a gate's opening past the outer wall, and `rider_blocked` is true on a building unless it is `hidden_at`, so riders can use the gates. `clamp_walk` leaves a point with room round it alone (player 0.45 m, boss 0.3 m, pickup 1.0 m) and sends any other point to the nearest free ground with rings round it, fine out to 8 m and coarser beyond, so a point deep in a thick edge block no longer goes 25 to 80 m away. `tools/arena_generated_check.gd` agrees with 200 layouts cell by cell and at every gate; it fails when `obstacle_at` never blocks, `ray_blocked` ignores roof height, tunnels are not hidden, riders are blocked in gate openings, or `clamp_walk` has no wall margin. Checked headless with Godot 4.7; gdlint and gdformat are clean. Not used by the game yet, and not looked at on screen)
- [x] Street-coordinate stubs (`tw`, `to_track`, `lim`, `clamp_road`, ...) that return safe values, so code that still thinks in street coordinates cannot crash on a generated arena (`GeneratedArena` now answers every street-coordinate function of `Arena` as if street x and z were world x and z, which is what the roundabout has at its middle: `tw` (kept inside the arena) and `to_track`, `tangent` (+x) and `inward` (+z), `yaw` 0, `hidden` false, `scale_at` 1, `lane_point` and `clamp_road` (kept on ground a boss can stand on), `exit_distance` (metres to the nearest gate), `lim` and `player_lim` (5 and 6 m in from the edge) and `ray_exit_circle` (-1, no facade circle), plus the `FACADE_RHO` constant that `combat.gd` reads. `tools/arena_generated_check.gd` checks once that the class overrides every `Arena` function and has every name the game scripts read from `arena` (apart from `world.gd`, the roundabout's own builder), and for every layout that the stubs give safe values; it fails when a stub is missing, `tw` leaves the arena, the tangent is not a unit vector, `yaw` disagrees with the tangent, `lane_point` ends in a wall or `exit_distance` is wrong. Checked headless with Godot 4.7 on 200 layouts; gdlint and gdformat are clean and the project loads with no errors. Not used by the game yet)
- [x] Build the world from the arena: `WorldGen` ground, `WorldDress` buildings, lamps and trees, `Lighting.apply_theme`, handed to `main.gd` in the shape `world.gd` gives for the roundabout (`WorldGenerated.build(root, arena)` in `scripts/world_generated.gd` has the same signature as `world.gd`'s `build` and returns the same dictionary: `env`, `sky_mat`, `sun`, `win_mat`, `lamp_mat` and `lamps`, plus `tris` and `draw_calls`. It adds a `WorldEnvironment` and the sun, the `WorldGen` ground (which already lays the big plane under it) and the `WorldDress` buildings, tunnels, lamps and trees to the root, from the arena's layout alone. The world starts dark; `Lighting.apply_theme(theme, world, start)` lights it exactly as on the roundabout. `tools/world_generated_check.gd` builds 40 arenas and checks the keys and kinds, that the environment, sun and lamp lights are in the tree (lamps hidden, one per lamp, windows and lamp heads dark), that `draw_calls` and `tris` are the true mesh count and triangle count, that the ground plane is wider than the arena and below it and nothing else leaves the arena or passes 12 m, that building twice gives the same world, and that every theme applies through `Lighting.apply_theme`; it fails when the `WorldEnvironment`, the sun, the ground or the buildings are not added, when there are no lamp lights or when the cost is wrong. Checked headless with Godot 4.7; gdlint, gdformat and the project load are clean. Not used by the game yet (the next item switches `main.gd` over) and not looked at on screen)
- [x] Switch `main.gd` to a generated arena behind a flag (off by default), with a headless load check and a short scripted run on a generated arena (the flag is the user argument `--generated-arena` (`godot --path . -- --generated-arena`), or `main.generated_arena` set before `main` enters the tree; with it on, the title screen shows the arena of today's daily seed and every run plays on the arena of its run seed (`use_generated_arena` in `main.gd`); off, the game is the roundabout as before. On a generated arena the cheerleaders are hidden, no pedestrians are spawned and bosses come in at a gate: those are the "Pedestrians, cheerleaders and pickups" and "Round clear rule" items below. `tools/generated_run_check.gd`, run with `tools\run_generated_run_check.bat`, checks the flag is off by default, the title screen's arena, the swap to the run seed's arena (one world, one sun) and 30 s of scripted play per seed; PASSED on 5 seeds with Godot 4.7.2 on the owner's machine. Known leftovers from the check itself: Godot prints "Resumed function '_warm_up()' after await, but class instance is gone" and a leaked-objects warning at exit, because the check frees a `main` while its warm-up is still waiting. Not checked: playing it in a real window, and `tools/arena_check.gd` (the roundabout golden file) since this change)

## Gameplay on open ground

- [x] Rider pursuit steering: ride toward the player on any open surface, pass, then turn round in a smooth arc and return; spawning at gates (`Arena.rider_pursuit()` switches it on, so an arena that says yes gets it and the roundabout, which says no, keeps its lanes; the code is in `scripts/riders.gd`. A rider comes out of one of the arena's gates (drawn with the seed) facing in, rides at the player, and once the player is behind it and within 7 m it rides straight on for 9 m, then swings round and comes back, pass after pass. The turn is limited by sideways acceleration (`PURSUIT_ACCEL` 20 m/s², at most 6 rad/s), so a fast rider swings wide (a turning circle of speed squared over 20 m) and a slow one turns tight, never a snap. It rides at its speed times the share for the ground under it (`Arena.rider_speed_at`, the `rider_speed` table in `data/arena_rules.json`: road and plaza 1.0, sidewalk 0.9, grass 0.75). It steers round obstacles with a look that reaches over its own turning circle, sampled every metre so a post cannot slip between two samples (`Arena.rider_blocked`), and brakes when something is close ahead (`clear_distance`, `OBSTACLE_BRAKE`), because a fast rider cannot turn away from a post 3 m in front of it. A rider that gives up still rides out of the nearest gate, slowing so that its turning circle fits in the distance left (`away_speed_cap`): without that it circled the gate at full speed and swung 147 m out. This branch (`roadmap/rider-pursuit`) had the first draft; the check found that draft rode into a post and could not get out of a gate, both fixed here, and main is merged in. `tools/rider_pursuit_check.gd` plays riders on a flat test arena with two gates and a post and fails if a rider does not start hidden in a gate facing in (both gates used), does not come out within 3 s, does not ride at the player (first approach within 2 m), passes fewer than 3 times in 60 s, turns faster than its arc limit or more than 6 rad/s in a step, does not ride straight on after a pass or turns back early or drifts off its line, rides into the post, swings more than 8 m wide round it or never swerves, keeps the wrong share of its speed on road or grass, takes more than 7 s or swings more than 45 m out when it gives up close to a gate, or if the roundabout starts pursuing; I broke the code four ways (no straight ride after a pass, no braking for obstacles, no speed cap on the way out, turning limit removed) and each was caught. `rider_check`, `pedestrian_check`, `arena_check` (901 lines identical), `boss_check` still pass, gdlint and gdformat are clean and the project loads headless with Godot 4.7 for 120 frames without errors. Not done: no arena in play says `rider_pursuit()` yet (the generated arena is not connected until the last item of this list), so none of this has been seen in the game; riders still give up after their time limit and ride out, which the round clear item below replaces with "keep coming until they are shot"; a generated arena has to say `rider_pursuit()`, `rider_blocked`, `hidden_at` (inside a gate's tunnel) and `rider_speed_at`, and let riders through its gates, when it is connected; the obstacle look costs up to a few dozen `obstacle_at` calls per rider per frame, not measured on the minimum-spec machine. Not checked: playing it on screen, and the feel of the arcs (`PURSUIT_ACCEL`, `OVERSHOOT`, `PASS_RANGE` are first guesses for the playtest item))
- [ ] Round clear rule for riders that cannot escape: the round ends when every rider is down; rework the round progress icons, the "N of 10 hit" count, `NEED`, the perfect-round rule and style and score rules in `main.gd` and `hud.gd`
- [ ] Boss attacks (strips, slam circles, volleys) on open ground
- [ ] Pedestrians, cheerleaders and pickups placed on generated arenas
- [ ] Threat arrows, radar and aim assist for attacks from every direction and distance
- [ ] Connect the arena to the run map (every node uses the whole arena with its own set-up)

## Scale, variety and polish

- [ ] Performance pass for four times the area (draw distance, culling, shadow and light counts) on the minimum-spec machine
- [ ] Arena styles chosen by the seed: plaza, street canyon, market, bridge, tunnel, park (replaces the hand-built arenas in Milestone D)
- [ ] Playtest and balance: rider speed, run length and sightlines on the bigger arena

---

# Milestone L: Jumping

Jumping on Space, so the movement feels like a modern FPS. Space is the dash key today (and the gamepad A button), so the first step is to give dash a new key.

- [ ] Decide the new dash key and gamepad button (Space and A are taken by jumping), and move dash there in the input map, the key rebinding list, the Controls page, `README.txt` and the HUD hint under the dash bar
- [ ] Jump on Space: a short hop with gravity, a fixed jump height and some air control (decide the numbers while building it; coyote time and jump buffering make it feel right)
- [ ] Jump on the gamepad (A) and add it to the key rebinding list and the Controls page
- [ ] Decide how jumping mixes with sprint, crouch, slide and dash (can you jump out of a slide, dash in the air, shoot and aim while airborne)
- [ ] Decide whether jumping over a passing rider counts as a dodge, and keep the PERFECT DODGE rule working as it does now
- [ ] Keep the player inside the arena while jumping: the height must not let the player clear buildings, props or the fountain, so the `Arena` bounds queries (`clamp_walk`, `obstacle_at`) still hold in the air
- [ ] Camera and gun feedback for take-off and landing (viewmodel dip, a small camera kick) and the jump and landing sounds (builds on "Footsteps, landing, slide and dash" in S2)
- [ ] Check darts, melee, hit boxes, aim assist and the radar while airborne
- [ ] Playtest and tune the feel: jump height, gravity and air control

---

# Tooling & QA

- [ ] Playtest pass of everything built in Milestone A (title, pause, settings, run, win / lose, leaderboard, name entry). It was written without running the game
- [x] CI check on every pull request: GDScript lint / format (gdtoolkit) and a headless Godot project load (`.github/workflows/ci.yml`, three jobs: `gdlint` uses the rules in `.gdlintrc`; `gdformat --check` fails if a script is not formatted (fix with `gdformat scripts/ tools/viewer/`); the Godot job imports the project and runs it headless for 120 frames, and fails on any script or load error, since Godot exits with 0 even when a script does not parse. Tested here with Godot 4.7 against a clean copy and a copy with a syntax error; the workflow itself has not run on GitHub yet)
- [x] Save-file safety: version the settings and score files so later changes do not break old saves (settings, scores and meta currency files now carry a version, old files load as version 0 and are upgraded on the next save; unreadable files and files from a newer game version are copied to a `.bak` file before they are overwritten; helpers in `scripts/save_util.gd`, rules in `docs/SAVE_FILES.md`. Written without running Godot, only parse-checked and linted; waiting for your in-game check: start the game with your existing saves, finish a run and look at `user://` for the new version fields)

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
- [ ] Milestone G: Procedural map generation (build together with the run map in Milestone D)
- [ ] Milestone H: Run start sequence (needs the map from Milestone G to fade into)
- [ ] Milestone I: Roguelite progression (builds on the meta currency and unlocks in Milestone B)
- [ ] Milestone J: Manual reload (small and independent, can be done at any time)
- [ ] Milestone K: Procedural arenas (big: replaces how riders and bosses move; start with the "Foundation" steps, which keep the roundabout playing as today)
- [ ] Milestone L: Jumping (small and independent; Space is the dash key today, so dash moves to another key first)