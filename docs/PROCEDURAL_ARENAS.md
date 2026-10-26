# Procedural arenas (design note for Milestone K)

Goal: every run gets one generated arena, about four times bigger than today's roundabout, that the player walks through freely and where riders can ride on roads, sidewalks, grass and so on. This page records the owner's decisions, what the code does now, what has to change and what is still open. The checklist is in the README under Milestone K.

## Decisions so far (owner)

- **Size:** about 4 times the walkable area. Today the player walks in a ring from 2.3 m to 22.3 m from the centre, roughly 1,500 m². Four times that is about 6,000 m² (for example a 80 m by 80 m area). The world drawn around it is bigger still.
- **Player:** walks through the whole arena (no longer held to a ring around a central island).
- **Riders:** do not have to lap or follow a fixed lane. They can ride on the road, the sidewalk, the grass, anywhere that is open.
- **One arena per run:** the arena is generated once from the run seed and used for every round of that run. Different rounds still change theme and lighting.
- **Rider behaviour:** a rider rides toward the player. If the player does not shoot it, it passes, then turns around and rides toward the player again. The turn must be smooth (a limited turning rate, so it swings round in an arc), never a sharp 180 degree switch.
- **A pass costs health, as now:** a rider that reaches the player and is not shot, dashed or dodged does damage, with the same dash and perfect-dodge rules as today.
- **Rounds can run on:** a rider keeps returning until it is killed, with no cap on passes and no time limit. The melee weapon is the answer to a player who keeps missing, and damage from passes is the pressure. A round ends when every rider is down. This means a rider can no longer "escape", so the round progress icons, the "N of 10 hit" count, `NEED` and the perfect-round rule in `main.gd` must be reworked for it (see the README gameplay item).
- **Map nodes (decided by Claude, owner left it open):** every node uses the whole arena with its own set-up: rider mix, which gates are in use, props and hazards, theme and round modifiers (night, rain, double riders from Milestone D). The player starts each round in a clear start area. Reasons: walking to a different district for each of about ten rounds would eat run time and break the 20 to 30 minute target; one set of gates and navigation data serves every node; the arena stays familiar, which suits a run the player is learning; and node variety comes from set-ups, which are cheap, rather than from more geometry. Shop, rest and event nodes are not fights, so they can stay screens or sit at a fixed spot in the arena, to be decided with Milestone D.
- **Speed by surface (riders):** road and plaza 1.0, sidewalk 0.9, grass 0.75 of a rider's speed, so the surface a rider crosses matters and the player can choose where to stand. The table is `rider_speed` in `data/arena_rules.json`; the numbers are a first guess for the playtest item. The player's own speed does not change.
- **Performance budget:** deferred by the owner, not a blocker for now. It still has to be set before the world is built (step 6).

## How the arena works today

- All game logic (riders, bosses, pedestrians, hit zones, pickups) runs in **street coordinates**: `x` is the distance along the road, `z` is the position across it (barrier, three lanes, sidewalk, facade).
- The game talks to the arena through one object, `arena` in `main.gd` (interface in `scripts/arena.gd`, the roundabout in `scripts/arena_roundabout.gd`). It offers the street-coordinate functions below and the world-space queries `start_position`, `clamp_walk`, `ray_blocked`, `obstacle_at`, `surface_at` and `gates`. Only `arena_roundabout.gd` still reads `ring.gd`.
- `scripts/ring.gd` is where the roundabout turns street coordinates into the world: `tw(x, z)`, `tangent`, `inward`, `yaw` and `to_track`. It bends the street into a circle of radius about 13 m, with the player on a central island.
- Riders loop around the ring (`x` wraps at `ARENA_HX`, half a lap) and enter and leave through a tunnel block at the seam. Each rider has a lane with a speed multiplier (`LANE_MULT`).
- The player is held to a ring-shaped area by the arena itself: `clamp_walk(p, who)` in `arena_roundabout.gd` keeps a point between the fountain (2.3 m) and the buildings (22.3 m) and out of the tunnel wedge. `who` ("player", "boss" or "pickup") only picks the margin.
- `scripts/world.gd` builds the whole roundabout once at start-up, reading its numbers from the arena object. It is the roundabout's own builder; generated arenas get one of their own (step 6).
- Not yet generalised: boss attacks, which are still drawn in street space. Bosses move by their world position `wp` and `yaw` is the hit box turn (the street `x` and `z` are gone). Riders own `pos`, `yaw` and `hidden` and move them in `move_rider` in `riders.gd`: they steer at a point on their lane a little ahead (`arena.lane_point`) with a limited turn rate (`TURN_RATE`), so on the roundabout they still ride the ring (an arena that says `rider_pursuit()` gets the open-ground pursuit below instead), and `avoid_obstacles` steers them round `obstacle_at()` where the arena asks for it (`arena.rider_avoidance()`; the roundabout does not). Pedestrians do the same in `move_civ` in `pedestrians.gd` (own `pos`, `yaw` and `hidden`, a `lane_z` to follow, `left` street metres to walk before they are out, the riders' `avoid_obstacles`); only `street_left` and `turn_to_flee` there still think in street coordinates, until pedestrians are placed on generated arenas. Cheerleaders have a fixed `pos`.

## What the decisions mean

The earlier idea of a generated "route" with street coordinates along it no longer fits: riders that cross grass and sidewalks do not live on a road, and a player who walks everywhere is not standing next to one. The game logic has to move from street coordinates to **world positions**, and the arena becomes a **terrain map** instead of a road:

- a ground layer with a surface type at every point (road, sidewalk, grass, plaza, and so on),
- obstacles (buildings, fountains, props, walls) and a boundary,
- **gates** at the edge (tunnels, alleys) where riders appear and leave,
- a **navigation grid** so riders can steer around obstacles on any open surface.

This is a rewrite of how riders move, not only of how the world is built. It touches `riders.gd`, `bosses.gd`, `combat.gd`, `pedestrians.gd`, `pickups.gd`, `player.gd`, the HUD's threat arrows and radar, and `main.gd`.

## Plan in steps (README Milestone K)

The first step changes nothing a player sees.

1. Put the arena behind one `Arena` interface with world-space queries (player bounds, surface at a point, obstacles, gates). The roundabout is the first implementation.
2. Move rider, boss and pedestrian movement from street coordinates to world positions with steering and obstacle avoidance. The roundabout must still play the same way (riders can follow a circular path in the new system). Rider steering is then built as pursuit with a limited turning rate: ride toward the player, pass, swing round in an arc, return.
3. Player bounds from the arena instead of two radii.
4. The arena generator: seed in, terrain layout out (size, roads, plazas, grass, building blocks, gates), same seed same arena.
5. Generate the navigation grid with it and validate every arena (all gates connected, no sealed areas, minimum corridor widths, a clear start area).
6. Build the world from the layout: ground surfaces, curbs, buildings and props (reuse the Milestone F9 kit), gates, theme lighting.
7. Gameplay on open ground: riders on any surface that pursue the player and turn round smoothly after a pass, spawn at gates, boss attacks in open space, pedestrians and pickups, threat arrows, radar and aim assist for attacks from every direction and distance.
8. Scale and performance for four times the area on the minimum-spec machine.
9. Arena styles chosen by the seed (plaza, street canyon, market, bridge, tunnel, park), which also covers the "New Arenas" items in Milestone D.
10. Playtest and balance.

## The generator (step 4, first part)

`scripts/arena_gen.gd` turns a run seed into a layout, using `data/arena_rules.json` and nothing else. The layout is plain data: a grid of 72 by 72 cells of 2 m (144 m square, centred on the origin, x east and z south) written as text rows, with lists of roads, plazas, building blocks, gates and the start area (the field list is at the top of the script). Roads run straight from edge to edge and cross; the edge is a 2-cell building ring in which some road ends are opened as tunnel gates and the others are walled off; the start plaza is placed first and has a clear 5 by 5 area in the middle; building blocks fill the grass with a 1-cell gap to roads and each other. Streams are `arena_roads`, `arena_plazas` and `arena_blocks`, each seeded with the attempt number, and an attempt that fails (no room for the start plaza, ground outside the style's range, 11,500 to 17,500 m² by default) is replaced by the next one. `tools/arena_gen_check.gd` checks it. The layout also carries the navigation grid (step 5): for every cell the clearance to the nearest building (diagonals count, capped at 9; 1 means touching), and `nav_cost` turns the rider speed table into a per-cell cost for path searches. Every layout is then validated (step 5): `ArenaGen.validate` checks that the start area is clear, that no open ground is sealed off, that every gate can be reached from the start through corridors at least three cells (6 m) wide, and that at least half of the ground within 40 m of the start is in view; a layout that fails is replaced by the next attempt. The ground is built from the layout by `scripts/world_gen.gd` (next section); nothing else in the game uses the layout yet.

### Looking at an arena

Open `tools/viewer/arena_viewer.tscn` in Godot and press F6 (the same way as the model viewer). Type a seed as the game shows it (up to 8 hex digits, e.g. `7F3A91C2`, or `today`) and press Enter, or use the Random and Daily buttons or Left / Right (previous and next seed). The arena is drawn from above: ground in its surface colour, buildings as blocks, gates (tunnels) with an arrow pointing out and a number, the start area as a pink square with a START label. The text above it gives the seed, the attempt that was used (1 is the first), the ground area, the counts and the result of `ArenaGen.validate`. Press C to colour the cells by navigation clearance instead (red 1, touching a building, to green 9 and more), which is the quickest way to see narrow corridors. Mouse drag orbits, the wheel zooms, R resets the camera. The viewer only calls `ArenaGen`, so it always shows what the game would get; `tools/arena_viewer_check.gd` tests the drawing. Press W to swap the flat plan for the real ground the game would build (see "The ground" below): lit surfaces, curbs, road paint and the start frame, with the triangle and draw-call counts in the text. W keeps the view when you change seed; C goes back to the plan. The W view also shows the dressing (next section), and T changes the lighting theme in it.

## The ground (step 6, first part)

`scripts/world_gen.gd` builds the ground of a layout: `WorldGen.build_ground(layout)` returns the nodes (not in the tree), the parts by name, the triangle count and the draw-call count. Everything is in world metres with the surface at y 0, and it reads only the layout, so one seed gives one ground.

- **Surfaces:** one flat mesh per ground type, neighbouring cells of a type merged into rectangles, so a whole arena is a few hundred triangles.
- **Curbs:** 0.12 m high and 0.22 m wide, centred on every cell edge where a road meets a sidewalk, plaza or grass. No curb against a building, a tunnel mouth or another road.
- **Paint:** a white edge line just inside the road along every curb, and a dashed centre line along each road with whole dashes, kept 0.8 m clear of crossings and of the road's ends.
- **Start frame:** a hazard-yellow frame round the clear start area.
- **Cost:** 334 to 688 triangles and at most 10 draw calls over 400 seeds. The performance budget (README, "Decisions") is still open, so these are measured, not budgeted.
- **Not here yet:** collision (the layout and `surface_at` stay the truth for where things can go) and real materials (it uses the roundabout's until Milestone F).

`tools/world_gen_check.gd` reads the finished meshes back and compares them with the layout (run it like the other check tools: `godot --headless --path . --script res://tools/world_gen_check.gd`, optionally followed by `-- <seeds>`).

## The dressing (step 6, second part)

`scripts/world_dress.gd`: `WorldDress.build(layout)` returns a node (not in the tree), the parts by name, the lots, the props (`props_of`), the window and lamp-head materials, the hidden lamp lights, and the triangle and draw-call counts. Like the ground it reads only the layout.

- **Buildings:** each `b` cell is under one lot (a box at most 3 cells across, 6.5 to 11.3 m high, brick or dark by a hash of the cells) with windows on every face that looks onto open ground.
- **Gates:** each `t` cell is under a black block 6.5 m high with a hazard band on each open face. Alleys are not generated, so there are none.
- **Lamps:** on sidewalk cells that touch one road and no tunnel, every 16 m, sides staggered; a pole, an arm, a glowing head and a hidden `OmniLight3D`.
- **Trees:** on grass cells with only grass and sidewalk round them, about one in 14.
- **No collision:** props are decoration; the layout does not know about them. They become obstacles with rider pursuit.
- **Cost:** 4,500 to 6,100 triangles, 10 draw calls over 100 seeds. Not budgeted: the performance budget is still open.

`tools/world_dress_check.gd` checks the finished meshes against the layout (`godot --headless --path . --script res://tools/world_dress_check.gd`).

## Theme lighting (step 6, third part)

`Lighting.apply_theme(theme, world, focus)` (`scripts/lighting.gd`) applies a `Content.THEMES` entry to any world that has `sky_mat`, `sun`, `env`, `lamps`, `lamp_mat` and `win_mat`: the roundabout (through `main.gd`) and a dressed arena (`WorldDress.build` hands back `lamps`, `lamp_mat` and `win_mat`). Windows glow at the theme's `lit` strength, lamp heads at `LAMP_HEAD_GLOW` when it has lamps, and at most `MAX_LAMP_LIGHTS` (8) lamp lights come on, the ones nearest `focus` (the start). The viewer's W view uses it, with T to change theme. `tools/arena_theme_check.gd` checks it.

## The generated arena class (step 5, in small parts)

`scripts/arena_generated.gd` (`GeneratedArena`) puts the `Arena` interface on a layout from `ArenaGen`, so the game can later be played on a generated arena. Nothing in the game uses it yet. `tools/arena_generated_check.gd` compares it with 200 layouts (`godot --headless --path . --script res://tools/arena_generated_check.gd`, optionally followed by `-- <seeds>`), and each part below has checks that were also broken on purpose to see them fail.

- **The ground:** `surface_at`, `rider_speed_at`, `start_position` and `gates` (in world space) read the layout; `rider_pursuit()` and `rider_avoidance()` are true.
- **Bounds and blocking:** a cell is walkable unless it is a building or a tunnel block. `obstacle_at` is true on those cells and outside the arena (what a boss cannot walk on). `ray_blocked` is true on them below 6.5 m (the lowest roof), so a dart passes over. `hidden_at` is true on tunnel cells and in the opening past the outer wall in front of a gate. `rider_blocked` is true on a building unless it is `hidden_at`, so riders can ride in and out through the gates.
- **`clamp_walk(p, who)`:** a point that has room round it (`MARGINS`: player 0.45 m, boss 0.3 m, pickup 1.0 m) comes back unchanged. Any other point is first brought inside the grid, then moved to the nearest point that has room, found with rings round it: every 0.25 m out to 8 m, then every 1 m beyond that, out to 1.5 times the arena size, so even a point deep in a thick block at the edge lands on the nearest free ground and not far across the arena. The first version of this stopped at 8 m and then walked the point towards the start, which threw some points 25 to 36 m. The check fails if a result is in or against a wall, if a free point moves, or if a point goes more than 25 m.
- **Street-coordinate stubs:** code that still thinks in street coordinates (`tw`, `to_track`, `tangent`, `inward`, `yaw`, `hidden`, `scale_at`, `lane_point`, `exit_distance`, `lim`, `player_lim`, `clamp_road`, `ray_exit_circle` and the `FACADE_RHO` constant) gets safe answers: street x and z are read as world x and z, results stay inside the arena and on ground a boss can stand on, and nothing logs an error. They exist only until the remaining movement code is on world positions. The check reads the source to make sure every `Arena` function is overridden and every `arena.` name the game scripts use exists (`world.gd` is left out: it is the roundabout's own builder).
- **The world:** `WorldGenerated.build(root, arena)` (`scripts/world_generated.gd`) is the generated arena's `world.gd`: same signature, same result dictionary (`env`, `sky_mat`, `sun`, `win_mat`, `lamp_mat`, `lamps`, and the cost as `tris` and `draw_calls`), so `main.gd` can take either. It puts a `WorldEnvironment`, the sun, `WorldGen`'s ground and `WorldDress`'s buildings, tunnels, lamps and trees under the root, all from the layout, and starts dark until `Lighting.apply_theme(theme, world, start)` is called. `tools/world_generated_check.gd` checks it (`godot --headless --path . --script res://tools/world_generated_check.gd`, optionally followed by `-- <seeds>`).
- **The flag:** `main.gd` plays on a generated arena when the game is started with the user argument `--generated-arena` (`godot --path . -- --generated-arena`), or when `main.generated_arena` is set before it enters the tree. (Later made the default, see "The generated arena is the default" below: the text in this item is how the flag was first built.) It was off by default, so the game was the roundabout as always. With it on, the title screen shows the arena of today's daily seed and every `start_game` makes the arena of the run seed (`use_generated_arena`, which frees the old world). Work in progress on such an arena: cheerleaders are hidden, no pedestrians are spawned, bosses come in at a gate, and the round does not end by itself until every rider is down (the round clear item). `tools/generated_run_check.gd` plays 30 seconds per seed (`godot --headless --path . --script res://tools/generated_run_check.gd`, optionally followed by `-- <count>`); it sets `main.force_captured` because headless Godot cannot capture the mouse. Run with `tools\run_generated_run_check.bat`: passed on 5 seeds (Godot 4.7.2). It prints a harmless "Resumed function `_warm_up()` after await" error and a leaked-objects warning at exit, because the flag-off part frees its `main` while the warm-up still waits.

## The generated arena is the default

`main.gd` now starts on a generated arena without any argument: the title screen shows the arena of today's daily seed and every run plays on the arena of its run seed. The roundabout is still in the project behind the user argument `--roundabout` (`godot --path . -- --roundabout`, or `tools\play_roundabout.bat`), as a fallback and for comparing. `--generated-arena` is still accepted and means the same as the default. `wants_generated_arena(args, is_game, already)` in `main.gd` decides, in this order: `--roundabout` gives the roundabout, `--generated-arena` gives the generated arena, otherwise it is the generated arena when this `main` is the scene the engine started (`get_tree().current_scene == self`, so running the project, F5 or F6 in the editor) or when the caller already set `generated_arena` before the scene entered the tree. A `main` made by a check script is not the scene the engine started, so every check that builds its own `main` keeps the roundabout unless it sets `main.generated_arena = true` itself, and none of them had to change. `tools/generated_run_check.gd` checks the choice for the cases above (`wants_generated_arena` only: it does not start the game) next to its existing checks. Open: the performance pass for the bigger arena (Milestone K, "Scale, variety and polish"), which also decides how the CI "load" job (which now runs the main scene on a generated arena) behaves on a slower machine.

## Rider pursuit (step 7, first part)

Where an arena says `rider_pursuit()` (the roundabout does not), `move_rider` in `scripts/riders.gd` steers a rider at the player instead of along a lane. It is written and checked on a test arena (`tools/rider_pursuit_check.gd`); no arena in play uses it until the generated arena is connected.

- **Spawn:** at one of `arena.gates()`, drawn with the layout's random numbers (a seed gives the same riders), 2 m inside the tunnel and facing out of it. A rider in its tunnel does not avoid obstacles and is hidden (`arena.hidden_at`).
- **Chase, pass, return:** the rider rides at the player. Once the player is behind it and within `PASS_RANGE` (7 m) it rides straight on for `OVERSHOOT` (9 m), then turns back at the player, and so on without a cap on passes.
- **Turning:** limited by sideways acceleration, `PURSUIT_ACCEL` (20 m/s²): the most it turns per second is 20 divided by its speed, never more than `PURSUIT_MAX_TURN` (6 rad/s). A rider at 20 m/s therefore swings a circle of about 20 m, a slow one turns tight, and nothing snaps round.
- **Ground:** its speed is its own speed times `arena.rider_speed_at(p)` (road and plaza 1.0, sidewalk 0.9, grass 0.75).
- **Obstacles:** `avoid_obstacles` looks along the wanted heading over at least the rider's own turning circle (1.2 times speed squared over the acceleration, plus 3 m), sampled every metre, using `arena.rider_blocked` (by default `obstacle_at`). The rider also brakes when the free ground ahead is short: it never rides faster than 2.3 times the free metres (`OBSTACLE_BRAKE`, at least 3 m/s), because a fast rider cannot turn away from a post a few metres ahead.
- **Giving up:** after its time limit a rider rides out of the nearest gate. Its speed is capped so that its turning circle fits in the distance left (`away_speed_cap`, at least 8 m/s), and it is out when it is within 2 m of a point 3 m inside the tunnel. Where `main.riders_can_escape()` is false (every arena with rider pursuit) a rider spawns with a time limit it cannot reach (`NEVER_GIVES_UP`), so it never gives up, and its speed-up with age stops at 6 s (`AGE_SPEED_CAP`); the give-up code stays for arenas where riders can get away and for `tools/rider_pursuit_check.gd`. The round then ends when every rider is down (`hits_needed()` is all ten), and a perfect round is one with no life lost (`is_perfect_round`); see `tools/round_clear_check.gd`.
- **What an arena has to provide:** `rider_pursuit()` true, `gates()`, `hidden_at(p)`, `rider_speed_at(p)` and, if its gates are not open to a boss, `rider_blocked(p)`.

## Arena styles (step 9)

The run seed picks one of six styles, once per run, and every round of the run uses it (`ArenaGen.pick_style`, drawn from its own stream `arena_style`, attempt 0, by the `weight` of each style, which are all 1 now). A style is an entry in `data/arena_rules.json` under `styles`: `rules` are laid over the plain rules (every key a style names replaces the key, dictionaries are merged key by key, `ArenaGen.rules_for_style`), `dress` is how `world_dress.gd` dresses it, `label` is its name on the screen. A retry changes the layout, never the style, and the layout carries `style`, `style_label` and `dress`. The round banner shows the label under ROUND n, `Arena.style_name()` and `style_label()` give it to the game, and the viewer shows it on its first line. Rules without `styles` give the plain arena and an empty style.

| Style | Roads (north-south / east-west) and gates | Plazas and blocks | Dress | Plays like |
|---|---|---|---|---|
| plaza | 1 / 1, 3 to 6 gates | start plaza 12 to 16 cells, 1 to 2 big plazas, few small blocks (14 % of the ground) | roofs 6.5 to 10.1 m, a tree in 14 cells | wide open, long sightlines, riders can come from anywhere |
| canyon | 2 / 0 to 1 | 1 to 2 plazas, big blocks (27 %) | roofs 8.5 to 14.1 m | tall walls along a few long streets, fights go along the street |
| market | 1 / 1 | 2 to 3 plazas, many small blocks 3 to 4 cells across (stalls) | roofs 6.5 to 7.3 m | a maze of small obstacles, short sightlines |
| park | 1 / 1 | 0 to 1 plaza, few small blocks | roofs 6.5 to 8.9 m, a tree in 9 cells | grass (riders at 75 % speed), trees and open ground |
| bridge | one road 7 cells wide (a deck) from end to end, exactly 2 gates | start plaza and up to one pier joined to the deck; no blocks; all the rest is walled in (grass kept 1 cell from the deck) | roofs 12 to 15 m, all dark, no windows (the girders) | one long line: riders come from the two ends and the player is squeezed between them; about 3,500 to 6,500 m² |
| tunnel | 2 to 3 / 2 to 3 corridors 3 cells wide, 12 cells apart, 3 to 6 gates | start plaza and 2 to 3 chambers joined to the corridors; no blocks; everything else walled in | roofs 9 to 11 m, all dark, no windows | a network of corridors and chambers, short sightlines (validated with a quarter of the ground in view instead of a half); about 5,500 to 11,000 m² |

Two things were added to the generator for the last two. `enclose: {"verge": k}` turns every grass cell further than `k` cells from a sidewalk, road, plaza or tunnel cell into building after the blocks are placed (`_enclose`), and `touch: true` on `start` or `plazas` makes a plaza join the roads or an earlier plaza, so a walled-in style never leaves a plaza on an island. Two dress keys were added with them: `windows: false` (no window quads) and `dark_all: true` (every building dark). The bridge and the tunnel have no sky-high roof, no water and no ceiling: the girders and the tunnel walls are placeholder boxes like the other buildings, so a bridge is a long walled deck and a tunnel is a walled network without a roof. A real water edge, a roof and a different ground (planks, tiles) are not built.

The effect on the numbers elsewhere: the ground of an arena is now between about 3,500 m² (bridge) and 16,400 m² (park) instead of one range, the dressing is 5,500 to 15,500 triangles (the park's trees are the most), and a seed gets a different style and layout than before the styles were added (the daily seed too). `tools/arena_gen_check.gd` holds every layout to its own style's numbers (roads, gates, plazas, blocks, ground, the walled-in grass, the dress numbers), checks that each style turns up and that the style is the one the seed picks, and names a layout with the wrong style, a bridge with a meadow and a canyon with a road missing. `tools/world_dress_check.gd` checks that a style with no windows has none, that an all-dark style has no brick, and that all six styles were dressed.

## Extraction on the node types of the run map

Decided as the working rule (built on how the code behaves today; the owner can change it): **the extraction point belongs to rounds with riders.**

| Node | Plays in the arena? | Extraction point and caches |
|---|---|---|
| normal, elite, boss | yes | as built: the point opens when every rider (and the boss) is down, caches are spread over the arena. An elite changes the riders and the pay, not this rule (Milestone D "Elite encounter") |
| shop, rest | no, a screen | none. There is nothing to put down and nothing to explore, so a walk to a point would only be a chore. The shop is already a screen today |
| event | no, a screen with a choice | none, for the same reason. Revisit it only if an event needs the player to walk somewhere |

Why: the point is the end of a fight (README Milestone K, "Exploration and extraction"). A node without riders has no fight to end, and its own screen already is its end. This also keeps one rule for the code (`finish_wave_set` in `scripts/main.gd` opens the point after the last rider) and means the shop, rest and event items of Milestone D do not have to touch `scripts/objective.gd`.

Safeguard for later: if a node without riders is ever played in the arena (an event that needs a walk, say), its extraction point must be open from the first second, never locked behind zero riders, or the round could not end. Nothing in the game does this yet: today a shop, rest or event node has no `riders` in its content, so `plan_riders` gives it the default rider count and it plays an ordinary round, which the Milestone D node items replace. No code was changed for this decision.

## The ambush when the extraction point opens

The walk to the extraction point used to be quiet, because every rider was already down. Now `scripts/ambush.gd` lines up a few more riders the moment the way out opens (README Milestone K, "Exploration and extraction"), so the walk is a moment of its own and the caches become a choice between the gold detour and the straight run out.

| Rule | Value (first guesses, all constants in `scripts/ambush.gd` and `scripts/riders.gd`) |
|---|---|
| Riders | 2 in rounds 1 to 4, 3 in rounds 5 to 7, 4 from round 8 |
| Timing | the first rider 2 s after the way opens (with an AMBUSH note and a sound), then one every 1.6 s |
| Gates | the gates the node leaves open that are at least 35 m from the player; the farthest one if none is |
| Kinds | pro, sprinter or courier from a random stream of the ambush's own (same seed, same kinds in the same order, and the round's own riders are never shifted by it); never the armoured rider |
| Round clear | unchanged: they are not among the round's riders, the last one going down does not end the round, reaching the point does and clears the riders still on the road |
| Perfect round | a life lost to an ambush rider still counts against it |

Left for later: a boss node's escort (more or tougher riders after a boss), and moving the numbers into a data table.
## The arena map (hold M)

Holding M (or Back / View on a gamepad) during a round shows the map; letting go hides it, and the round keeps running behind it (README Milestone K, "Exploration and extraction"). It is not in the pause menu. It shows only what the player has found, so exploring is rewarded and the map never gives a spot away:

| What | Shown when |
|---|---|
| Ground (colours as in `tools/viewer/arena_viewer.gd`) | the player has been within 26 m (`REVEAL_RADIUS` in `scripts/explore_map.gd`) of the cell; the ground round the start is seen from the first second |
| Start | always (the round begins there) |
| Gates | the cell the gate stands in has been seen |
| Supply cache | the player has come within `SENSE_RANGE` (45 m, the radar's range) of it once; shown hollow grey once taken, and a taken cache is always found |
| Extraction point | the player has come within `SENSE_RANGE` of it once; red-orange while riders are up, green once it is open |

Shapes carry the meaning as well as colours (circle: start, bar: gate, diamond: cache, square: way out, triangle: you), the same rule as the cache variants in the roadmap. The state is per round (`explore_sys.setup_round()` after the objectives are built, cleared with them) and is not saved. The roundabout has no layout and no map.

## Open questions

- **Can bosses and riders see and attack from far away?** A bigger open arena changes sightlines and what a threat arrow means.

## Risks

- This is the biggest change on the roadmap: it replaces how everything moves. Step 1 and step 2 first, with the roundabout still working, keep the game playable at every point.
- Riders steering over open ground need pursuit, smooth turning and obstacle avoidance that are cheap enough for the minimum-spec machine, with up to ten riders and bosses at once. A rider that turns in an arc must not clip buildings or props while doing it.
- Boss attacks: strips and slam circles are in world space already. On open ground a boss steers round obstacles, attacks only with a clear line and a slam does not go through walls (`open_ground()` in `scripts/bosses.gd`). Still open: no path search, so a boss can get stuck in a U-shaped dead end.
- Four times the area costs frame time; step 8 exists for this, and the budget question above should come first.
