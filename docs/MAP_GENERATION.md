# Map generation rules

Rules for the procedural run map (README Milestone G). The numbers live in [`data/map_rules.json`](../data/map_rules.json); this page says what they mean. The generator is `scripts/map_gen.gd`; the game builds a map from the run seed at the start of every run and prints it to the console, but **rounds do not follow the map yet** (the map screen and the node types arrive with Milestone D). The numbers are a first guess, to be tuned once real runs can be timed.

## Shape of the map

A map is a stack of **floors**, drawn bottom to top. A run walks one node on each floor, so the path length is the number of rounds: `floors = 10` keeps a run at the README target of about 10 rounds (20-30 minutes).

- Floor 1 is the start: exactly 3 nodes, all `normal`.
- Floor 10 is the final boss: exactly 1 node, `boss` (final).
- Floor 5 is the mid boss: exactly 1 node, `boss` (mid), so every path crosses it.
- Floors 4 and 9 are **prep floors** (the floor before each boss): every node is `shop` or `rest`, and if the floor has 2 or more nodes it contains at least one of each (`need_each`). Every path therefore gets a heal / spend chance right before each boss.
- Every other floor (2, 3, 6, 7, 8) is a **free floor** with 2 to 4 nodes whose types are rolled (below).

Node types are the Milestone D list: `normal`, `elite`, `shop`, `event`, `rest`, `boss`.

## Connections

Each node sits in a lane (its position left to right on the floor). Edges only go from one floor to the next.

1. A node has 1 or 2 outgoing edges (`max_edges_out`), to nodes on the next floor whose lane is close to its own. The one exception is a lone boss node, which connects to every node on the next floor.
2. Edges never cross. They are built as a staircase from the left-most nodes of both floors to the right-most ones, which also guarantees rule 3.
3. Every node except those on floor 1 has at least one incoming edge, and every node except the final boss has at least one outgoing edge.
4. A boss floor has one node, so every node on the floor before it connects to it.

## Node types on free floors

Each node on a free floor takes a type from `types` by weighted draw, skipping any type that is not allowed there:

| type | weight | first floor | most per map |
|---|---|---|---|
| normal | 50 | 1 | no limit |
| elite | 15 | 3 | 3 |
| event | 15 | 2 | 3 |
| shop | 10 | 2 | no limit |
| rest | 10 | 2 | no limit |

`no_repeat_along_edge`: two nodes joined by an edge never have the same type if that type is `elite`, `shop`, `rest` or `event` (no shop straight into a shop, no elite straight into an elite). A draw that would break this is redrawn; if it keeps failing, the node becomes `normal`.

## Same seed, same map

The map is generated from the run seed (`run_seed`, see `scripts/daily.gd`) and nothing else, so a normal run, a Daily Run and a typed-in seed all work the same way.

- Use separate streams, the way the rest of the run already does: `DailyScript.stream_seed(run_seed, 0, <stream name>)` with the names in `streams` (`map_layout` for widths and edges, `map_types` for node types, `map_content` for arena layouts and encounter contents). A change to one part then never changes what another part draws.
- Draw in a fixed order: floor 1 to floor 10, nodes left to right. Never use the global random functions or `Array.shuffle()` in map code; use `DailyScript.shuffle_with`.
- Do not reorder or rename the keys of `map_rules.json` casually: like `items.json` and `perks.json`, changing numbers or order changes every seed's map (bump `version` and say so in the commit).

## Arena layouts and encounter contents

One run has **one arena layout** (`scripts/arena_gen.gd`, from the same run seed, see [`PROCEDURAL_ARENAS.md`](PROCEDURAL_ARENAS.md)), and every node uses that whole arena with its own set-up. So what a node holds is data about the set-up, never geometry. `scripts/map_content.gd` fills `node["content"]` for every node when `MapGen.generate` builds the map, and the map records `"gates"` (how many gates the arena has). The numbers are in the `content` section of `data/map_rules.json`.

| node | content |
|---|---|
| all | `theme`: index into `Content.THEMES` (a boss node uses the fixed theme of its boss, `boss_theme`) |
| normal, elite, boss | `riders` (`count` and a `mix` of pro / sprinter / courier / tough that adds up to the count), `gates` (sorted indexes of the arena gates riders may enter by, at least `min_open`), `modifiers` (0 or 1 of `rain`, `double_riders`) |
| boss | `boss` (`mower`, `wifi` or `minister`; the final boss is always `minister`) and `final: true` on the last one |
| shop, rest, event | `seed`: a 32-bit number for what Milestone D draws later (offers, event choice) |

Rider types and modifiers have a first floor (`min_floor`), so floor 1 only has plain pros and `tough` riders appear from floor 3. Elites hold more riders and more `tough` ones; bosses fewer.

Every node has **its own generator**, `DailyScript.stream_seed(run_seed, floor * 100 + lane, "map_content")` (attempt 0; a retried map uses `"map_retry:<attempt>:map_content"`), and a fixed draw order inside the node: theme, riders, gates, modifiers, boss kind. Changing what one node draws never changes another node, and the content never touches the layout or type streams: the floors, edges and types of every seed are exactly what they were before the content existed (`tools/map_check.gd` compares them). Content is drawn only for a map that passed validation, from the attempt that produced it.

## What a valid map must satisfy

This is the checklist for the "validate that every generated map is completable" item. A map that fails is regenerated from a derived seed (`stream_seed(run_seed, attempt, "map_retry")`, attempt 1, 2, ...), never patched by hand, so the seed still gives one map.

- Exactly `floors` floors, with the fixed floors as above.
- Every node can be reached from a floor 1 node, and every node can reach the final boss (no dead ends).
- Every start-to-final-boss path crosses the mid boss and both prep floors.
- Caps (`max_per_map`) and `no_repeat_along_edge` hold.
- Every fight can be played: at least one rider, a rider mix that adds up, and at least one open gate that exists in the arena; every boss node has a boss kind and every shop, rest or event has its seed. The content is drawn before validation, so a map with unplayable content is regenerated like any other.

## Checking the generator

`tools/map_check.gd` generates 2,000 maps, generates each twice to prove the same seed gives the same map, checks the list above, the retry, and the content of every node (rider counts and mixes, gates, modifiers, boss kinds, themes) against the rules. Run it from the project folder, optionally with a seed to print as text and a count:

```
godot --headless --path . --script res://tools/map_check.gd -- 3735928559 500
```

`MapGen.to_text` prints a map as one line per floor, final boss first: the letter is the node type (N normal, E elite, S shop, ? event, R rest, B boss) and the numbers are the lanes it connects to on the next floor.

## Walking the map in a run

A run starts on the **map screen** (state `map`): it shows the whole map, floor 1 at the bottom, with the nodes you can pick ringed. Left / Right or the mouse choose, Enter or a click go (1 to 3 pick directly). Picking a node plays that floor's round, and after the upgrade and the shop the map screen comes back with the nodes the current node connects to, until the final boss floor. The floor number is the round number, so rider speed, prices and boss strength grow exactly as before, and `MAX_ROUNDS` follows the map's floor count. A run without a map (it could not be generated) plays its rounds in a line as before. Code: `enter_map`, `pick_node`, `next_round` in `scripts/main.gd`, `_draw_map_screen` in `scripts/hud.gd`, checked by `tools/map_walk_check.gd`.

**Not done yet** (the node items of Milestone D): what each node type does. For now every node plays the ordinary round and the type is only shown, the shop still comes after every round and the bosses still follow the old round rule; the node `content` (riders, gates, modifiers, theme) is not used by the round yet either (Milestone K, "Connect the arena to the run map").

## Seeds typed in by the player

The title screen has a CUSTOM SEED page: 8 hex digits at most, the same text the game shows as "RUN SEED". It plays exactly that seed, so the map, the arena and the riders are the ones `tools/viewer/map_viewer.tscn` and `tools/viewer/arena_viewer.tscn` show for it. Such a run is **not ranked** (no normal high score, no Top 10, like a Daily Run) and a restart replays the same seed.

## Open points for Milestone D and balance

- Today the game offers upgrades and a shop after every round. On a map the shop is a node, so the shop now appears on only some paths: the economy and the upgrade pacing need a balance pass once the map exists (compare the Milestone I balance item).
- What an `elite`, an `event` and a `rest` actually do is decided in Milestone D; this page only decides where they can appear.
- The existing boss rule in `main.gd` (`boss_count` and round 3 onwards) will be replaced by the two boss nodes.
