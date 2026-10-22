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
- [ ] Record the "before" baseline: screenshots of every screen and theme, plus frame time on the minimum-spec machine (needs you: Godot cannot run in my working environment)
- [x] Set up the model pipeline (Claude as modeler, Blender as a Python module `bpy`): scripts in `tools/models/`, output to `assets/models/*.glb` with a preview sheet per model in `docs/model_previews/`, automatic budget and file validation, conventions (1 unit = 1 metre), and an in-game model viewer (`tools/viewer/model_viewer.tscn`). How to use it: `tools/models/README.md`
- [x] Build the shared style kit: bevelled primitive helpers, the colour palette and material set (`tools/models/kit/`), and a test model (`test_crate`)
- [x] Owner check: open `tools/viewer/model_viewer.tscn` in Godot (F6) and confirm `test_crate` looks right in the game (colours, bevels, hazard stripes, the glowing lamp, scale) (confirmed by the owner)
- [x] Create `CREDITS.md` and the rule that every third-party asset gets an entry when it is added (see `CREDITS.md`; the voice recorders' names are still to be added under S6)
- [x] Switch off the outline pass and flat unlit toon materials behind a flag; simple lit low-poly materials become the default (`Toon.ENABLED = false` in `scripts/toon.gd`: no outline quad, `Util.mat()` and the jelly club shader use ordinary lit shading, and the OUTLINES row in settings and the F10 key are gone while it is off; `true` brings the old look back. Effects, strips and rings stay unshaded on purpose. Checked by rendering the game here with a software renderer, before and after: `docs/screenshots/f1-toon-off-before.png` and `f1-toon-off-after.png`. With flat toon lighting gone the NIGHT theme is clearly darker, which the next lighting items are there to fix; waiting for your in-game check on real hardware, including the jelly club and the settings panel)
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
- [ ] Generate arena layouts and encounter contents from the seed
- [ ] Validate that every generated map is completable (no dead ends, boss always reachable)
- [ ] Debug tool: enter a seed and preview the generated map
- [ ] Optional: let the player type in a custom seed on the title screen

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

- [ ] Ground surfaces, curbs and markings from the layout
- [ ] Place buildings, props, lamps and gates (tunnels, alleys) from the layout (reuse the F9 kit)
- [ ] Theme lighting and lit windows on generated arenas

## Gameplay on open ground

- [ ] Rider pursuit steering: ride toward the player on any open surface, pass, then turn round in a smooth arc and return; spawning at gates
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