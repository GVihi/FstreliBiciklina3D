# Procedural arenas (design note for Milestone K)

Goal: every run gets one generated arena, about four times bigger than today's roundabout, that the player walks through freely and where riders can ride on roads, sidewalks, grass and so on. This page records the owner's decisions, what the code does now, what has to change and what is still open. The checklist is in the README under Milestone K.

## Decisions so far (owner)

- **Size:** about 4 times the walkable area. Today the player walks in a ring from 2.3 m to 22.3 m from the centre, roughly 1,500 m². Four times that is about 6,000 m² (for example a 80 m by 80 m area). The world drawn around it is bigger still.
- **Player:** walks through the whole arena (no longer held to a ring around a central island).
- **Riders:** do not have to lap or follow a fixed lane. They can ride on the road, the sidewalk, the grass, anywhere that is open.
- **One arena per run:** the arena is generated once from the run seed and used for every round of that run. Different rounds still change theme and lighting.
- **Rider behaviour:** a rider rides toward the player. If the player does not shoot it, it passes, then turns around and rides toward the player again. The turn must be smooth (a limited turning rate, so it swings round in an arc), never a sharp 180 degree switch.
- **Map nodes (decided by Claude, owner left it open):** every node uses the whole arena with its own set-up: rider mix, which gates are in use, props and hazards, theme and round modifiers (night, rain, double riders from Milestone D). The player starts each round in a clear start area. Reasons: walking to a different district for each of about ten rounds would eat run time and break the 20 to 30 minute target; one set of gates and navigation data serves every node; the arena stays familiar, which suits a run the player is learning; and node variety comes from set-ups, which are cheap, rather than from more geometry. Shop, rest and event nodes are not fights, so they can stay screens or sit at a fixed spot in the arena, to be decided with Milestone D.
- **Performance budget:** deferred by the owner, not a blocker for now. It still has to be set before the world is built (step 6).

## How the arena works today

- All game logic (riders, bosses, pedestrians, hit zones, pickups) runs in **street coordinates**: `x` is the distance along the road, `z` is the position across it (barrier, three lanes, sidewalk, facade).
- `scripts/ring.gd` is the only place that turns street coordinates into the world: `tw(x, z)`, `tangent`, `inward`, `yaw` and `to_track`. It bends the street into a circle of radius about 13 m, with the player on a central island.
- Riders loop around the ring (`x` wraps at `ARENA_HX`, half a lap) and enter and leave through a tunnel block at the seam. Each rider has a lane with a speed multiplier (`LANE_MULT`).
- The player is held to a ring-shaped area (`PLAYER_R_MIN`, `PLAYER_R_MAX`, `Ring.player_lim()`).
- `scripts/world.gd` builds the whole arena once at start-up. About 55 call sites use `Ring.` (`main.gd` 21, `world.gd` 15, `combat.gd` 7, `bosses.gd` 6, `riders.gd` 4, `pedestrians.gd` 2, `player.gd` 2).

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

## Open questions

- **What happens when a rider passes the player?** Today a rider that reaches the player's lane is resolved as a hit or an escape, with dash and perfect-dodge rules. In the new behaviour the rider keeps coming back, so a pass needs a rule (damage unless the player dashes or dodges?).
- **How does a round end?** If riders keep returning until they are shot, a round can run on forever for a player who misses. Options: a time limit, a cap on passes per rider, or riders that leave through a gate after a number of passes. Today each round has a fixed number of riders, each of which counts as hit or missed.
- **Speed by surface:** road fastest, sidewalk slower, grass slowest? It makes surfaces matter and lets the player choose where to stand. Not decided.
- **Can bosses and riders see and attack from far away?** A bigger open arena changes sightlines and what a threat arrow means.

## Risks

- This is the biggest change on the roadmap: it replaces how everything moves. Step 1 and step 2 first, with the roundabout still working, keep the game playable at every point.
- Riders steering over open ground need pursuit, smooth turning and obstacle avoidance that are cheap enough for the minimum-spec machine, with up to ten riders and bosses at once. A rider that turns in an arc must not clip buildings or props while doing it.
- Boss attacks are drawn in street space as lane strips and slam circles; they need to be redone for open ground.
- Four times the area costs frame time; step 8 exists for this, and the budget question above should come first.
