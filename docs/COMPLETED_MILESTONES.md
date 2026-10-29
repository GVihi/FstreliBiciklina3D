# Completed milestones

Everything in `README.md` that is finished, moved here word for word on 2026-10-29 so the README only holds what is still open: whole milestones with every box ticked (Milestone G), whole sections with every box ticked, and the ticked items of sections that still have open boxes. The headings are one level deeper here than they were in the README (a `##` section is `###`), and the milestones are in README order. Every milestone that lost something keeps its heading in the README with a link to its block here, so "Milestone G" and similar references still resolve. A ticked item that has an open box inside it stays in the README with its open box. For the finished early alpha roadmap see [`ALPHA_ROADMAP.md`](ALPHA_ROADMAP.md); the long notes written after ticked items are in [`ROADMAP_HISTORY.md`](ROADMAP_HISTORY.md).

## Roguelite Development Roadmap

### Proper version control
- [x] GitHub

### Big Design Choice

- [x] Decide on the game's long-term direction
  - [x] Full roguelite focus (recommended)

#### Recommended Roguelite Structure

- [x] Create runs of ~10 rounds
- [x] Target 20–30 minute run duration (alpha D1)
  - [x] Add a run timer (run summary + console log per round) to measure it
  - [x] Tune round length once real run times are known (alpha D1)
- [x] Implement permanent unlocks between runs (coins, buying, starting perks, the Dart Gun and the Loadout page work, see Milestone I; alpha C1 to C5)
- [x] Balance pass for the 10-round difficulty curve (rider speed, boss health, final boss health) (alpha D2)

## Milestone A: Menu, Game Flow, Saves & High Scores

### Menu & Game Flow

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

#### Menu follow-ups (found while checking the list)

- [x] Keyboard and gamepad navigation for the settings panel (sliders were mouse-only)
- [x] Controls / "How to play" page (the long controls text was removed from the title screen)
- [x] Pause automatically when the game window loses focus
- [x] Confirm before Restart Run / Quit to Title (a run is lost with one click)
- [x] Optional: "Continue" button to resume an interrupted run
- [x] Reset all progress button at the bottom of the settings panel (red, two warnings)

### High Scores

- [x] Implement local Top 10 leaderboard
- [x] Add player name entry
- [x] **BUG:** the DELETE key does nothing (it is printed on the page and described below, but no code handles it; `scores_reset_check` fails on it, alpha A2.2). The button click and gamepad X work. Reset leaderboard option (F8 used to reset only the old single high score and is gone now)
- [x] Show run time on the leaderboard (it is already saved with each entry)
- [x] Use the leaderboard's best entry for the HI score shown in the HUD, and retire `hi.dat`

#### Daily Seed Mode

- [x] Generate a daily seed
- [x] Use same seed for all players on that day
  - [x] Separate "Daily Run" entry on the title menu; normal Play stays fully random
  - [x] Seed only the run layout (rider mix, shop and upgrade offers, starting boss and lighting theme), not moment-to-moment combat

## Milestone B: Meta Currency, Unlocks & Skins

### Meta Progression

- [x] Add meta currency
  - [x] Earn from score
  - [x] Earn from boss kills
  - [x] Earn from challenges
    - [x] Write the challenge list (`data/challenges.json`, described in `data/README.md`: five challenges, each with an `id`, `name`, `desc`, `condition` key, `scope` (round or run), `target`, meta coin `reward` and save `counter` name; a challenge pays at most once per run. Loaded by `scripts/challenges.gd`, see the next item) (a data table like `data/items.json`, each with a condition, a reward in meta coins and a counter in the save file, see `docs/SAVE_FILES.md`): clear a round without using the gun, take every cache before the last rider falls, perfect-dodge five riders in a row, clear a round without losing a life, finish a run in under 20 minutes
    - [x] Show them on the run summary (done, new, progress) and on a page of the title menu
    - [x] Optional: achievements for the same list, with a name and a small icon

- [x] Keep meta currency separate from run cash

### Meta Unlocks

- [x] Unlock starting perks (done under Milestone I: buy them on the Unlocks page, choose one on the Loadout page, and a run starts with it)

## Milestone C: Weapon System Expansion

### Weapon Slots

- [x] Add primary weapon slot
- [x] Add melee weapon slot
- [x] Add gadget slot

#### Choosing weapons: unlock, then pick a loadout

- [x] Loadout screen: choose primary, melee and gadget before a run

### New Weapons

#### Dart Nerf Pistol

- [x] Implement weapon
- [x] Make it the starting primary weapon

## Milestone D: Run Map, Relics & Modifiers

### Run Structure

- [x] **BUILT, NOT FULLY USED YET:** a run walks the map, but `shop`, `rest`, `elite` and `event` nodes all play an ordinary round (alpha B1 to B5). Replace linear round progression

#### Map Nodes

- [x] Normal encounter (works: the node's content sets the theme, the rider count and mix and the open gates, see Milestone K "Connect the arena to the run map")
- [x] Elite encounter (an elite node has 10 to 12 riders and 40 % armoured ones, and since alpha B4 a second upgrade pick on clearing it)
- [x] Shop (alpha B1, B2: a shop node is a screen with the node's seeded offers, not a round)
- [x] Rest stop (alpha B3: a rest node is a screen with REFILL HEARTS or EXTRA UPGRADE)
- [x] Boss node (works: a boss node has its boss after every rider is down, and the last one is the final boss, see Milestone K "Connect the arena to the run map")

### Round Modifiers

- [x] Double riders modifier (works: `double_riders` makes every wave a pair and shows DOUBLE RIDERS at the start of the round, `has_modifier` in `scripts/main.gd` and `scripts/riders.gd`)

### New Arenas

> These become arena styles of the procedural arena generator (Milestone K), chosen once per run, instead of hand-built scenes.

- [x] Bridge arena (now the `bridge` arena style, see Milestone K "Arena styles chosen by the seed")
- [x] Market arena (now the `market` arena style)
- [x] Tunnel arena (now the `tunnel` arena style)

## Milestone E: Polish & Accessibility

### Accessibility

- [x] Screen shake and screen flash intensity options (reduced-motion / photosensitivity)

### Release Readiness

- [x] Rename the game from FstreliBiciklina3D to FB3D everywhere the player can see it: the title screen and logo text, the window title, the credits screen and any other in-game text that shows the name. This is a small change. The internal name stays as it is: the GitHub repository, the folder and file names, the project files and the docs keep "FstreliBiciklina3D", so no clone URLs, CI links or save files change (the Godot project name in `project.godot` also stays, because `user://` follows it and the old settings, scores and meta currency must keep loading, see `docs/SAVE_FILES.md`)
- [x] Create app icon
- [x] Configure Windows export presets
- [x] Show the game version on the title screen
- [x] Bring `README.txt` up to date

## Milestone F: Graphics & Sound Overhaul

### Graphics

#### F1. Foundation (before any new asset)
- [x] Answer the first open questions (minimum spec, who makes models, references, bright look): done, see `docs/ART_DIRECTION.md`
- [x] Answer the remaining questions (UI language, ammo on the weapon, rarity colours, hazard-stripe motif, logo): done, see section 9 of `docs/ART_DIRECTION.md`
- [x] Record the "before" baseline: screenshots of every screen and theme, plus frame time
- [x] Set up the model pipeline (Claude as modeler, Blender as a Python module `bpy`): scripts in `tools/models/`, output to `assets/models/*.glb` with a preview sheet per model in `docs/model_previews/`, automatic budget and file validation, conventions (1 unit = 1 metre), and an in-game model viewer (`tools/viewer/model_viewer.tscn`). How to use it: `tools/models/README.md`
- [x] Build the shared style kit: bevelled primitive helpers, the colour palette and material set (`tools/models/kit/`), and a test model (`test_crate`)
- [x] Owner check: open `tools/viewer/model_viewer.tscn` in Godot (F6) and confirm `test_crate` looks right in the game (colours, bevels, hazard stripes, the glowing lamp, scale) (confirmed by the owner)
- [x] Create `CREDITS.md` and the rule that every third-party asset gets an entry when it is added (see `CREDITS.md`; the voice recorders' names are still to be added under S6)
- [x] **BUILT, LEAVES DEAD CODE:** `Toon.ENABLED = false` leaves the outline code in `scripts/toon.gd` unused until F12 removes it. Switch off the outline pass and flat unlit toon materials behind a flag; simple lit low-poly materials become the default
- [x] Lighting baseline for DAY: bright sun with soft readable shadows, light sky, tone mapping, glow on gameplay accents
- [x] Lighting for GOLDEN HOUR, DUSK and NIGHT (warm lamp pools and lit windows, medium-dark sky, nothing hides in the dark)
- [x] Test the Compatibility renderer against Forward+ on old hardware and decide which to ship
- [x] Anti-aliasing choice (MSAA or cheaper FXAA) and re-define the F9 quality presets for the new look

#### F2. Dart gun (first person)
- [x] Viewmodel setup: separate camera and FOV so the gun never clips into walls (`scripts/viewmodel.gd`; checked in game by the owner: no clipping, same look, frame time fine; `VIEWMODEL_PASS = false` in `main.gd` switches it off)
- [x] Chunky low-poly gun model with a hand-painted texture
- [x] Idle sway and walk / sprint bob (written in `update_gun` in `scripts/player.gd`, tuning constants at the top of that file; waiting for your in-game check: breathing sway, walk and sprint bob, and a small lag when you turn; all of it fades out while aiming)
- [x] Shoot and recoil animation (springy kick-back, muzzle rise and a little roll that overshoot and settle, rapid fire stacks up to a limit; `update_kick` in `scripts/player.gd`, tuning constants at the top of that file; waiting for your in-game check)
- [x] Pump / reload animation
- [x] Aim-down-sights pose and crosshair behaviour
- [x] Dart and shell models
- [x] Muzzle flash and shell ejection
- [x] (Optional) Ammo count shown on the gun itself

#### F3. Melee
- [x] Chunky model with a glossy rubber material
- [x] No alternating colors (the whole club is one glossy pink; the light and dark pink ribs of the old worm are gone; confirmed by the owner in game)
- [x] More detail (like the Dart gun)
- [x] More rubbery look (glossy jelly material with toon highlights and a pink rim glow, ridges and rings that bend with the wobble, a squash and stretch on every swing and a flash on every hit; confirmed by the owner in game)
- [x] No eyes (the new club has none; confirmed by the owner in game)
- [x] Rubbery wobble swing animation
- [x] Hit, deflect and phone-return feedback

#### F6. Pedestrians and cheerleaders

- [x] Rim glow (fresnel) that tells foes from bystanders: red-orange on riders and bosses, green-cyan on pedestrians and cheerleaders

## Milestone G: Procedural Map Generation (moved 2026-10-29)

> **Note 2026-10-27:** several items below say "rounds do not follow the map yet", "nothing reads the rules file yet" or "NOT RUN YET". Those parts are history: a run walks this map (Milestone D) and the checks were run (see "Roadmap audit" at the top). They are left as they were written.

> Works together with the run map in Milestone D: the seed decides the map, and the map decides which encounters, shops and bosses a run contains.

- [x] Generate the run map procedurally from a seed (all three parts below are done; the map is generated and printed to the console, but rounds do not follow it yet: that is Milestone D)
  - [x] Same seed always produces the same map
  - [x] Daily seed produces the same map for every player that day (builds on Daily Seed Mode in Milestone A) (a Daily Run uses the daily seed as its run seed, so it gets the same map as every other player that day; checked headless with Godot 4.7: two Daily Runs started in a row printed the same map)
  - [x] Random seed for normal runs, shown on the run summary so a run can be replayed
- [x] Define the map generation rules (number of nodes, branching, guaranteed shop / rest stop / boss placement)
- [x] **BUILT, NOT FULLY USED YET:** the `seed` that shop, rest and event nodes get is never read, and `rain` has no effect (alpha B2, B3, B5). Generate arena layouts and encounter contents from the seed (the arena layout is the run seed's layout from `scripts/arena_gen.gd` (Milestone K); every map node gets a `content` entry from `scripts/map_content.gd`: theme, rider count and mix, open gates, 0 or 1 modifier, boss kind, or a seed for shop / rest / event nodes; each node has its own generator so one node never changes another and the floors, edges and types of every seed are unchanged; numbers in the `content` section of `data/map_rules.json`, explained in `docs/MAP_GENERATION.md`; `tools/map_check.gd` checks the content of 2,000 maps. Headless check run 2026-10-27 with Godot 4.7: `map_check` PASSED (`python tools/run_checks.py map_check`). (Old note: rounds did not use the content yet, it is used now: that is Milestone D)
- [x] Validate that every generated map is completable (no dead ends, boss always reachable)
- [x] Debug tool: enter a seed and preview the generated map
- [x] Optional: let the player type in a custom seed on the title screen

## Milestone I: Roguelite Progression

- [x] Starting loadout: the Dart Nerf Pistol and the melee weapon
- [x] **BUILT, NOT FULLY USED YET:** starting perks work (Loadout page); the six shop-item unlocks are sold in the shop only once bought (alpha C3, built on branch `roadmap/c3-shop-unlock-filter`, waits for the owner's check C3.5). Unlock and buy upgrades and starting perks with meta currency
- [x] Unlock screen replaces the "coming soon" Unlocks page (items, price, owned / locked state)
- [x] Loadout screen replaces the "coming soon" Loadout page (choose what you start a run with from what you own)
- [x] Save unlocks and purchases in the versioned save files (see `docs/SAVE_FILES.md`)
- [x] Show newly unlocked items on the run summary screen
- [x] Define the unlock list and price curve in a data table (like `data/items.json`)
- [x] Balance pass: the first runs with the starting loadout must be winnable but hard, and each unlock should feel meaningful (alpha D2)
- [x] Reset progress option in Settings, with confirmation (alpha E5, the RESET ALL PROGRESS row)

## Milestone J: Manual Reload

- [x] Remove the automatic reload after a few seconds
- [x] Press R to reload manually
- [x] Automatically reload when the magazine reaches 0
- [x] Cannot shoot while reloading; reloading can be interrupted by dashing or switching to melee (decide the exact rule when building it)
- [x] **BUILT, NOT USED YET:** `reload_started` and `reload_interrupted` have no listener, and the sound and jolt on `reload_finished` are placeholders (after the alpha). Reload animation and sound hooks (builds on the pump / reload animation in F2)
- [x] HUD and ammo label on the gun show the reloading state
- [x] Check how perks and items that touch ammo (rapid fire, infinite ammo, fat darts) interact with the new reload

## Milestone K: Procedural Arenas

> **Note 2026-10-27:** the notes under Foundation, Generation, Building the world and Generated arena class that say "not used by the game yet", "nothing in the game uses it yet" or "not connected" are history: the generated arena is the default since "Make the generated arena the default" below. They are left as they were written.

### Decisions

- [x] Size: about 4 times the walkable area (about 6,000 m² against about 1,500 m² now)
- [x] The player walks through the whole arena
- [x] Riders do not lap or follow a fixed lane: they can ride on road, sidewalk, grass, anywhere open
- [x] One arena per run (generated once from the run seed)
- [x] Riders ride toward the player, pass if they are not shot, then turn round in a smooth arc (limited turning rate, never a sharp 180 degree switch) and ride toward the player again
- [x] Map nodes: every node uses the whole arena with its own set-up (rider mix, gates in use, props, theme and modifiers), and the player starts each round in a clear start area (the owner left this choice to Claude, reasons in the design note)
- [x] A rider that passes the player does damage as it does now (same dash and perfect-dodge rules); riders keep coming back until they are killed, with no cap on passes and no time limit (the melee weapon is the fallback), and a round ends when every rider is down
- [x] Decide whether road, sidewalk and grass change rider speed

### Foundation

- [x] Put the arena behind one `Arena` interface with world-space queries (player bounds, surface at a point, obstacles, gates), with the roundabout as its first implementation (no visible change)
- [x] Move rider, boss and pedestrian movement from street coordinates to world positions with steering and obstacle avoidance (the roundabout must still play the same)
- [x] Player bounds from the arena instead of `PLAYER_R_MIN` / `PLAYER_R_MAX`

### Generation

- [x] Arena generator: seed in, terrain layout out (size, roads, plazas, grass, building blocks, gates); same seed, same arena
- [x] **BUILT, NOT USED YET:** `nav_clearance` is used (validation, cheerleader spots), but `nav_cost` is only called by a check; nothing searches the grid (after the alpha). Generate the navigation grid with the layout
- [x] Validate every generated arena (all gates connected, no sealed areas, minimum corridor widths, a clear start area, sightlines)
- [x] Debug tool: enter a seed and preview the generated arena

### Building the world

- [x] Ground surfaces, curbs and markings from the layout
- [x] Place buildings, props, lamps and gates (tunnels, alleys) from the layout (reuse the F9 kit)
- [x] Theme lighting and lit windows on generated arenas

### Generated arena class

> Puts the `Arena` interface on a generated layout (`scripts/arena_generated.gd`, checked by `tools/arena_generated_check.gd`), so the game can be played on a generated arena. One small step at a time, each pushed to its own branch commit. It is the base of the "Connect the arena to the run map" item below.

- [x] Skeleton and ground queries: `surface_at`, `rider_speed_at`, `start_position`, `gates` in world space, `rider_pursuit()` and `rider_avoidance()` true (checked against 200 layouts, and broken on purpose three ways: swapped start axes, flipped gate directions, wrong rider speeds; not used by the game yet)
- [x] Bounds and blocking: `clamp_walk` for player, boss and pickup, `obstacle_at`, `ray_blocked`, `rider_blocked` (open through the gates), `hidden_at` (inside a gate's tunnel)
- [x] Street-coordinate stubs (`tw`, `to_track`, `lim`, `clamp_road`, ...) that return safe values, so code that still thinks in street coordinates cannot crash on a generated arena
- [x] Build the world from the arena: `WorldGen` ground, `WorldDress` buildings, lamps and trees, `Lighting.apply_theme`, handed to `main.gd` in the shape `world.gd` gives for the roundabout
- [x] Switch `main.gd` to a generated arena behind a flag (off by default), with a headless load check and a short scripted run on a generated arena
- [x] Make the generated arena the default and keep the roundabout behind `--roundabout`

### Gameplay on open ground

- [x] Rider pursuit steering: ride toward the player on any open surface, pass, then turn round in a smooth arc and return; spawning at gates
- [x] Round clear rule for riders that cannot escape: the round ends when every rider is down; rework the round progress icons, the "N of 10 hit" count, `NEED`, the perfect-round rule and style and score rules in `main.gd` and `hud.gd`
- [x] Boss attacks (strips, slam circles, volleys) on open ground
- [x] Pedestrians, cheerleaders and pickups placed on generated arenas
- [x] Riders no longer creep into walls in narrow corridors
- [x] Threat arrows, radar and aim assist for attacks from every direction and distance
- [x] Thrown phones and boss volleys respect buildings on open ground (found while playtesting: `update_phones` in `scripts/phones.gd` flies a phone in a straight lob from the rider to the player and never asks the arena, so riders throw phones through buildings, and boss volleys do the same. Two parts: riders and bosses only start a throw when they can see the player, which can reuse `Threats.sight_clear`, and a phone already in flight smashes on the wall it meets (the smash effect and sound exist, `plastic_burst` and `phone_smash`). The roundabout must play as before.
  Done on branch `roadmap/phone-walls` (`tools\run_phone_wall_check.bat` PASSED on the owner's machine and the gameplay was played and looked good): where `arena.rider_pursuit()` is true a rider starts a throw (`scripts/riders.gd`) and a boss throws a phone (`boss_throws` in `scripts/bosses.gd`) only when `PhoneSys.throw_clear` says nothing solid is between them and the player (`scripts/phones.gd`, which reuses `Threats.sight_clear`); a rider whose wind-up ends behind a building holds the phone and tries again after 0.3 s, a boss waits 0.3 s; a phone in flight that meets a building smashes there (`flight_blocked` and `wall_smash`: no hit, no popup, no score). Boss volleys (`do_volley`) are not held back, their phones smash on the wall. Deflected phones flying back are not changed. `tools/phone_wall_check.gd` (`tools\run_phone_wall_check.bat`) checks all of it on a flat test arena with one wall and the roundabout, and it passed; gdlint and gdformat are clean)
- [x] **BUILT, NOT FULLY USED YET:** fight nodes use their content (theme, riders, gates, double riders), but the `rain` modifier is only carried, and shop, rest and event nodes still play a round (alpha B2, B3, B5). Connect the arena to the run map (every node uses the whole arena with its own set-up)

### Exploration and extraction

- [x] Pick the spots: an extraction point far from the start and supply caches spread over the arena
- [x] Supply caches
- [x] Extraction point instead of "last rider down ends the round"
- [x] Show them: a line at the top of the HUD (REACH THE EXTRACTION POINT with the distance, or the dimmed EXTRACTION POINT line saying to down every rider to open it) and CACHES n / 4 under it; a world marker for the point (a diamond with its distance, or an arrow on the screen edge when it is behind or to the side) and for each cache within 45 m; and on the radar a green square (dim until it opens) for the point and gold diamonds for the caches in range (`_draw_objective`, `_world_marker`, `_draw_radar_objectives` in `scripts/hud.gd`)
- [x] Crash fix: `clear()` in `scripts/objective.gd` stopped with "Trying to assign invalid previously freed instance" when the player reached the extraction point after taking a cache
- [x] Checks
- [x] (covered by alpha D1) Playtest the objectives: do the caches pull the player across the map, is the extraction walk too long on a 144 m arena once the riders are down, do `CACHE_CASH`, `CACHE_SCORE`, `CACHE_COUNT` and the 45 m sense range feel right (first guesses in `scripts/objective.gd`)
- [x] (covered by alpha D1) Riders and pickups on the bigger arena: riders spawn at the gates and ride at the player over a map about twice as wide, so check that a round is not too slow, and whether the extraction point should open earlier or the arena be smaller for the early rounds
- [x] Extraction on other nodes: shop, rest, event and elite nodes (Milestone D) have no riders to put down, so decide what, if anything, they use the extraction point for
- [x] Ambush when the extraction point opens: the walk to the point is quiet today because every rider is already down, so send a short last wave or reinforcements through the gates once it opens (a few riders, or a boss node's escort), so the walk is a moment of its own and the caches become a trade-off between the gold detour and the straight run out. Decide the size and the timing while building it, and keep the round clear rule (`finish_wave_set`, `objective_reached`) and the perfect-round rule working
- [x] Arena map (hold M; it was a pause-screen map first): a top-down view of the arena, shown while M is held, showing the layout the player has explored, the start, the gates, the caches (taken and not) and the extraction point; a cache or the point is revealed when the player first comes within sense range, so exploring is rewarded and nothing is shown that the player has not found. Reuse the drawing from `tools/viewer/arena_viewer.tscn`

### Scale, variety and polish

- [x] Playtest and balance: rider speed, run length and sightlines on the bigger arena (covered by alpha D1)

## Tooling & QA

- [x] CI check on every pull request: GDScript lint / format (gdtoolkit) and a headless Godot project load
- [x] Save-file safety: version the settings and score files so later changes do not break old saves

## Technical Refactor (Recommended Before Milestone D)

### Code Structure

- [x] Break up `main.gd` (~3,600 lines)
- [x] Move systems into dedicated modules

### Data-Driven Content

- [x] Move items into data tables (shop items, packs and upgrade tiers are in `data/items.json`; see `data/README.md`)
- [x] Move perks into data tables (perks and duos are in `data/perks.json`; see `data/README.md`)
- [x] Move weapons into data tables (dart gun and melee tuning are in `data/weapons.json`; see `data/README.md`)
