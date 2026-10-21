# Procedural arenas (design note for Milestone K)

Goal: every map node gets its own generated arena, much bigger and more varied than today's single roundabout. This page records what the code does now, what has to change, and the questions that need an owner decision before the big steps. The checklist is in the README under Milestone K.

## How the arena works today

- All game logic (riders, bosses, pedestrians, hit zones, pickups) runs in **street coordinates**: `x` is the distance along the road, `z` is the position across it (barrier, three lanes, sidewalk, facade).
- `scripts/ring.gd` is the only place that turns street coordinates into the world: `tw(x, z)` gives a world position, `tangent`, `inward` and `yaw` give directions, `to_track` goes back. It bends the street into a circle of radius about 13 m, with the player on a central island.
- Riders loop around the ring (`x` wraps at `ARENA_HX`, half a lap) and enter and leave through a tunnel block at the seam.
- The player walks inside a ring-shaped area (`PLAYER_R_MIN` 2.3 m to `PLAYER_R_MAX` 22.3 m, plus `Ring.player_lim()` near the tunnel).
- `scripts/world.gd` builds the whole arena once at start-up. About 55 call sites use `Ring.` today (`main.gd` 21, `world.gd` 15, `combat.gd` 7, `bosses.gd` 6, `riders.gd` 4, `pedestrians.gd` 2, `player.gd` 2).

The good news: because the logic already thinks in street coordinates, a different arena shape mostly means replacing what `ring.gd` does, not rewriting the game rules. The hard parts are the places that assume a circle: the player's bounds, the lap wrap, the tunnel seam, boss attack shapes (lane strips and slam circles) and the threat arrows and radar.

## Direction (option 1: procedural arenas)

Each node on the run map (Milestone G and D) points at a generated **arena**: a bounded space, much larger than today's, with its own shape. An arena is made of:

1. A **route**: a path through the space that riders follow, with the street coordinates running along it. It is either a closed loop (laps, like today) or an open street with an entrance and an exit.
2. A **player zone**: the area the player can walk in, next to the route.
3. **Dressing** placed along the route and around the zone: facades, props, tunnel gates, lighting per theme.
4. **Parameters** chosen from the seed: size, shape, how many entrances, which preset (plaza, street canyon, bridge, market, tunnel).

## Plan in steps (README Milestone K)

The first step changes nothing a player sees. It is what makes every later step safe.

1. Put the arena behind one interface (`Arena`), with the roundabout as its first implementation, and move every `Ring.` call to it.
2. A route model: a path with an arc-length coordinate, so `tw`, `tangent`, `inward` and `yaw` work for any shape. A circle route must reproduce today's roundabout exactly (check it by comparing results).
3. Player zone and bounds as a shape instead of two radii.
4. The arena generator and its validation (seed in, arena out, same seed same arena).
5. Build the world from a route: road and lanes along the path, facades and props placed along both sides. Reuse the Milestone F9 kit (chunky facade kit, props, tunnel) instead of building it twice.
6. Adapt gameplay: spawn and despawn at entrances, wrap or end of route, boss attack shapes, pedestrians, pickups, threat arrows and radar.
7. Scale and performance: draw distance, culling, shadow and light budget on the minimum-spec machine.
8. Presets and variety (plaza, canyon, bridge, market, tunnel), which also covers the "New Arenas" items in Milestone D.
9. Playtest and balance: rider speed against longer routes, sightlines, run length.

## Decisions needed from the owner

- **How much bigger?** For example 3 to 4 times the walkable area? This drives performance work more than anything else.
- **Does the player still stay in a zone, or walk through the whole arena?** Today the player is held to a ring about 20 m wide. A free-roaming player changes aiming, riders' targets and the camera.
- **Do riders still lap, or pass through?** Laps keep the current rider logic; open streets make riders appear and leave, which changes round pacing.
- **One arena shape per run, per round, or per map node?** Per node is the most varied and the most work.
- **Low-end PCs:** the art direction targets them, so a hard budget (triangles, lights, draw distance) should be agreed before step 5.

## Risks

- The tunnel seam and the lap wrap are built into rider movement (`riders.gd`) and pedestrians; open routes need their own spawn and despawn rules.
- Boss attacks are drawn in street space as lane strips and slam circles; they need to work on curved and bent routes.
- A much larger world costs frame time. Step 7 exists for this, but the size decision above should come first.
- This is a large rewrite spread over several milestones. Doing step 1 first keeps the game playable at every point.
