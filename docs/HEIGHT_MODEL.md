# Height model (roadmap: "Height: hills, walkways and stairs", first step)

Status: **decided with the owner on 2026-11-02** (the four answers are at the end). Nothing is built.
Every number is a first guess, tuned by playing. The point of this page is that the later steps (layout, navigation,
ground, the `Arena` interface, riders, combat, tools) all read the same rules.

## Principles

1. **One height per point.** The ground is a height field: `height_at(x, z)` returns one number. No bridges you can ride
   under, no overhangs, no caves. A raised walkway is solid raised ground. This keeps `clamp_walk`, `ray_blocked`, the
   nav grid and the radar 2D-plus-a-number instead of real 3D.
2. **Flat stays flat.** A rule in `data/arena_rules.json` switches height off (per style). With it off every
   `height_at` is 0 and the arena is built, played and checked exactly as today; the roundabout, the training room and
   every flat style answer 0 without any rule.
3. **Same seed, same arena.** Height is rolled from its own stream (`arena_height`), so the roads, plazas, buildings
   and spots of every existing seed do not move when height is added.
4. **Small.** Hills and decks are low enough that sightlines, the radar and the threat arrows still work.

## The numbers

| Thing | Value | Why |
|---|---|---|
| Grid | the ground grid, 2 m cells (`cell` 2.0, 72 x 72) | one height per cell next to the ground type |
| Unit | 0.5 m | heights are whole units, so checks compare integers |
| Most height | 3 m (6 units) | buildings start at about 6.5 m, so a 3 m hill never makes a building a toy |
| Hills | smooth: the ground between cell centres is interpolated | no stair-stepping on a lawn |
| Ledges, stairs, decks | stepped: the height changes at a cell edge | reads as a kerb, a stair or a deck edge |
| Gates, border, start plaza | always 0 | the way in and the spawn stay flat |
| Caches, extraction point, building footprints | flat inside their footprint (and 2 m round a cache or the exit) | nothing is built into a slope |

## What can be walked

| Change between neighbouring cells | Player | Riders and bosses |
|---|---|---|
| up to 0.5 m (1 unit) | walks, **automatic step-up** | rides it as a slope (see below) |
| 0.5 to 0.8 m | jump (the hop is about 1.09 m since 2026-11-03, so a ledge up to 0.8 m is a jump and not a wall) | blocked |
| more than 0.8 m | blocked (wall-jump can climb it) | blocked |
| stairs | walk up (treads of 0.5 m) | **blocked in the first version** (stairs are obstacles for bikes) |

- **Slopes for bikes:** a slope of up to 0.5 m per 2 m (about 14 degrees) can be ridden. Uphill scales the rider's speed
  down (first guess: speed x (1 - 1.5 x grade), at least 0.5), downhill gives nothing extra. Steeper is a wall.
- So a raised walkway needs a **ramp** at its ends for riders (and the player may use the ramp or the stairs). Every
  deck therefore has at least one ramp, and `ArenaGen.validate` keeps that true.
- A slope the player cannot step up is a wall for the player too: one limit, no ledge only one side can use.

## Which styles get height

| Style | Height | What |
|---|---|---|
| park | yes | rolling hills on grass, a few stairs where a path climbs one |
| plaza | yes | raised walkways over plazas and a side road, with ramps and stairs |
| market, canyon | yes (owner's choice) | their narrow streets and stalls leave little room, so they get lower hills and short ramps, and `ArenaGen.validate` rejects a seed where a ramp or a cache does not fit; tune per style in `data/arena_rules.json` |
| bridge, tunnel, roundabout, training | no | they are special shapes |

## What every later step must keep true

- A gate, every cache, the extraction point and the start spot are on flat ground and reachable on foot **and** by riders
  (ramps, not stairs). No cache or start spot inside a hill.
- Pickups, pedestrians, riders and bosses stand and spawn at `height_at`. Darts are blocked by the ground when
  `p.y < height_at(p)`; the radar stays top-down; the threat arrows ignore height.
- The player's camera follows the ground height smoothly (no jitter on stairs).
- Frame time on the minimum-spec machine is measured before and after the ground mesh is built from heights.

## Order of work

See the roadmap: decide (this page) -> `height_at` everywhere returning 0 -> height in the layout -> navigation and
validation -> the ground meshes and dress -> combat and sight -> tools and playtest.

## Decisions (the owner, 2026-11-02)

1. **One height per point**: yes. Nobody rides under a deck.
2. **Bikes and stairs**: no. Stairs block riders and bosses; every deck has a ramp.
3. **Numbers**: yes, as in the tables (top 3 m, step-up 0.5 m, hop 0.5 to 0.8 m, bike slopes up to about 14 degrees); tuned later by playing.
4. **Styles**: all the open ones: park, plaza, market and canyon. The bridge, the tunnel, the roundabout and the training room stay flat.
