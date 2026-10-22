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
- Not yet generalised: boss attacks, which are still drawn in street space. Bosses move by their world position `wp` and `yaw` is the hit box turn (the street `x` and `z` are gone). Riders own `pos`, `yaw` and `hidden` and move them in `move_rider` in `riders.gd`: they steer at a point on their lane a little ahead (`arena.lane_point`) with a limited turn rate (`TURN_RATE`), so on the roundabout they still ride the ring, and `avoid_obstacles` steers them round `obstacle_at()` where the arena asks for it (`arena.rider_avoidance()`; the roundabout does not). Pedestrians do the same in `move_civ` in `pedestrians.gd` (own `pos`, `yaw` and `hidden`, a `lane_z` to follow, `left` street metres to walk before they are out, the riders' `avoid_obstacles`); only `street_left` and `turn_to_flee` there still think in street coordinates, until pedestrians are placed on generated arenas. Cheerleaders have a fixed `pos`.

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

`scripts/arena_gen.gd` turns a run seed into a layout, using `data/arena_rules.json` and nothing else. The layout is plain data: a grid of 48 by 48 cells of 2 m (96 m square, centred on the origin, x east and z south) written as text rows, with lists of roads, plazas, building blocks, gates and the start area (the field list is at the top of the script). Roads run straight from edge to edge and cross; the edge is a 2-cell building ring in which some road ends are opened as tunnel gates and the others are walled off; the start plaza is placed first and has a clear 5 by 5 area in the middle; building blocks fill the grass with a 1-cell gap to roads and each other. Streams are `arena_roads`, `arena_plazas` and `arena_blocks`, each seeded with the attempt number, and an attempt that fails (no room for the start plaza, ground outside 6,000 to 7,000 m²) is replaced by the next one. `tools/arena_gen_check.gd` checks it. The layout also carries the navigation grid (step 5): for every cell the clearance to the nearest building (diagonals count, capped at 9; 1 means touching), and `nav_cost` turns the rider speed table into a per-cell cost for path searches. Every layout is then validated (step 5): `ArenaGen.validate` checks that the start area is clear, that no open ground is sealed off, that every gate can be reached from the start through corridors at least three cells (6 m) wide, and that at least half of the ground within 40 m of the start is in view; a layout that fails is replaced by the next attempt. The ground is built from the layout by `scripts/world_gen.gd` (next section); nothing else in the game uses the layout yet.

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

## Open questions

- **Can bosses and riders see and attack from far away?** A bigger open arena changes sightlines and what a threat arrow means.

## Risks

- This is the biggest change on the roadmap: it replaces how everything moves. Step 1 and step 2 first, with the roundabout still working, keep the game playable at every point.
- Riders steering over open ground need pursuit, smooth turning and obstacle avoidance that are cheap enough for the minimum-spec machine, with up to ten riders and bosses at once. A rider that turns in an arc must not clip buildings or props while doing it.
- Boss attacks are drawn in street space as lane strips and slam circles; they need to be redone for open ground.
- Four times the area costs frame time; step 8 exists for this, and the budget question above should come first.
