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
| event | 0 (off for the alpha) | 2 | 3 |
| shop | 10 | 2 | no limit |
| rest | 10 | 2 | no limit |

**Event nodes are off for the alpha (README alpha B5):** the `event` weight is 0, so the draw never picks one (a type with weight 0 stays in the table, its code and its `seed` content are kept for Milestone D "Event"). The `rain` round modifier is off the same way (weight 0 under `content.modifiers.types`, see below), because nothing draws or does rain yet; `double_riders` stays on. `version` in `map_rules.json` went from 2 to 3 because changing the weights changes every seed's map (the draws divide by the weight total). `tools/map_check.gd` fails if a node of a weight-0 type, or a weight-0 modifier, shows up in any of its 2,000 maps. To bring events or rain back, give them a weight again and bump `version`. The `night` modifier (Milestone D, see "Night modifier" below) is in the table the same way, at weight 0 and `min_floor` 3; adding a weight-0 entry moves no seed (the weights add up to the same total), so `version` stayed at 3 for it.

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
| normal, elite, boss | `riders` (`count` and a `mix` of pro / sprinter / courier / tough that adds up to the count), `gates` (sorted indexes of the arena gates riders may enter by, at least `min_open`), `modifiers` (0 or 1 of `rain`, `night`, `double_riders`; `night` is in the table at weight 0 until MD5.6) |
| boss | `boss` (`mower`, `wifi` or `minister`; the final boss is always `minister` in the map, and the fight spawns the golden president (`president`) for the node with `final: true`) and `final: true` on the last one |
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

A run starts on the **map screen** (state `map`): it shows the whole map, floor 1 at the bottom, with the nodes you can pick ringed. Left / Right or the mouse choose, Enter or a click go (1 to 3 pick directly). Picking a node plays that floor's round, and after the upgrade pick (one of three, after every fight; the shop is only at shop nodes, README alpha B1) the map screen comes back with the nodes the current node connects to, until the final boss floor. The floor number is the round number, so rider speed, prices and boss strength grow exactly as before, and `MAX_ROUNDS` follows the map's floor count. A run without a map (it could not be generated) plays its rounds in a line as before. Code: `enter_map`, `pick_node`, `next_round` in `scripts/main.gd`, `_draw_map_screen` in `scripts/hud.gd`, checked by `tools/map_walk_check.gd`.

**A shop node is a screen, not a round** (README alpha B2): picking it starts no round, it opens the shop screen at once (`pick_node` calls `shop_sys.enter_shop()` for a node type listed in `SCREEN_NODES` in `scripts/main.gd`), with the same seeded offers as any shop on that floor (`offer_shuffle` uses the run seed and the floor), and leaving it (`leave_shop` -> `next_round` -> `enter_map`) goes back to the map and saves the checkpoint. The floor and round number still go up by one, but it is not a cleared round: no hearts back, no round XP (`Meta.award_run` takes the shop nodes walked through off the rounds cleared, `screens_passed` in `main.gd`), no `challenges.on_round_cleared`, no entry in `round_times`, no perfect round; its time counts as `shop_time`. Checked by `tools/map_walk_check.gd` and `tools/xp_check.gd`.

**Not done yet** (the other node items of Milestone D): what the other node types do. For now the rest, elite and normal nodes all play the ordinary round and the type is only shown, the bosses still follow the old round rule; on a generated arena the node `content` now sets up the round: the theme, the number and kinds of riders and the gates they come in by (`node_setup`, `round_theme`, `plan_riders` in `scripts/main.gd`, `pick_gate` in `scripts/riders.gd`; the roundabout ignores it). A boss node has its boss kind (`spawn_boss`) after every rider is down and only once, and a fight node without a boss has none (`need_boss`). The `double_riders` modifier is used (every wave is a pair); `rain` is only carried in `round_modifiers` until its Milestone D item.

## Seeds typed in by the player

The title screen has a CUSTOM SEED page: 8 hex digits at most, the same text the game shows as "RUN SEED". It plays exactly that seed, so the map, the arena and the riders are the ones `tools/viewer/map_viewer.tscn` and `tools/viewer/arena_viewer.tscn` show for it. Such a run is **not ranked** (no normal high score, no Top 10, like a Daily Run) and a restart replays the same seed.

## Night modifier (Milestone D, MD5.1 design, MD5.2 the entry in the data, MD5.3 the effect; the look and the labels come in MD5.4 and MD5.5)

**What is there today.** `theme_count` is 4 in `data/map_rules.json` (DAY 0, GOLDEN HOUR 1, DUSK 2, NIGHT 3 in `content.gd`). `_node_content` draws a node's theme first (`rng.randi() % theme_count`), the mid boss is DUSK and the final boss NIGHT, and `Main.round_theme()` plays the node's theme. So about a quarter of all fights already **look** like night, with no rule attached. The round modifiers are a separate draw (0 or 1 per fight, `modifiers.types`), read through `has_modifier`.

**Decisions** (assumed, change by saying so):

1. **The modifier is a dark round that also plays by one rule; the NIGHT theme alone stays a look.** Making the theme itself carry the rule would make a quarter of all nodes and the final boss harder without a label on the map; and taking NIGHT out of the theme draw (`theme_count` 4 to 3) would change the theme of every node of every seed. Neither moves anything here. The cost: a node whose theme is NIGHT and that also carries the modifier looks the same as one without it, and only the rule and the map label tell them apart.
2. **The rule: a shorter radar.** At night the radar reaches 60 % of its usual range (`RADAR_RANGE_STREET` and `RADAR_RANGE_OPEN` in `threats.gd`, through one factor so the old numbers are the factor 1.0). A rider farther out is not drawn on the radar, and it is not squeezed onto the rim either. **The threat arrows at the screen edge are not touched**, so nothing in the arena can hide from the player (rule 6 in `docs/ART_DIRECTION.md`, "no area may hide a rider or a telegraph in the dark"); the modifier takes away the early warning, not the warning. The objectives' sense range (`explore_map.gd`, kept equal to the radar range so far) is left as it is, and MD5.4 looks at whether the radar then misses a cache the player already senses.
3. **The theme is forced for the round.** A round with the modifier plays under NIGHT whatever theme the node drew; the next round goes back to its own. The node's stored `theme` is not changed, so the map of a seed is the same. **Order matters:** `start_round` calls `round_theme()` *before* `plan_riders()` fills `round_modifiers`, so `has_modifier` is still the previous round's answer at that point. `round_theme()` has to read the modifiers from `node_setup()["modifiers"]` itself (MD5.3), not from `has_modifier`.
4. **Where it can appear.** Normal and elite fights through the existing chance (`modifiers.chance`: normal 0.2, elite 0.5, boss 0.0), `min_floor` 3 like rain, never on a boss (the final boss is already a NIGHT theme).

**Seeds.** Adding `night` to `modifiers.types` with weight 0 changes no map: `_pick` adds the weights up and a weight of 0 adds nothing (`tools/map_check.gd` proves a seed gives the same map, MD5.2). **Turning the weight on changes which modifier some nodes of a seed get**, so a seed typed in before the update plays a different map after it; there is no stored Daily Run board to break yet (Milestone A, "daily scoreboard"), so this is only noted, and it is done once, in MD5.6.

**MD5.2, done.** `data/map_rules.json` has `"night": {"weight": 0, "min_floor": 3}` under `content.modifiers.types`, after `rain`; no map holds it until MD5.6. `_check_night_modifier` in `tools/map_check.gd` checks, on 200 seeds, that the maps are byte for byte the same (a) without the entry, (b) with it at weight 0 and (c) with it at weight 0 first in the table, and that switching the weight on (a copy of the rules at 20) changes only the `modifiers` of nodes (riders, gates, boss kind, theme and the map itself are the same, because the modifier roll is always drawn) and puts `night` only on normal and elite fights from floor 3 on, never on a boss. It runs on copies of the rules, so turning the shipped weight on in MD5.6 does not need a change in the check; the shipped weight is held to the rules by `_check_modifiers`, as for every modifier. Checked on 2026-11-07 with Godot 4.7-stable headless: `map_check` passes on 2,000 seeds, and with the draw deliberately broken so that a weight of 0 counts, the new check fails.

**MD5.3, done.** The effect is built, and the data keeps it off: no node holds `night` while the weight is 0, so the check puts the modifier into a node by hand. `Main.round_theme()` returns NIGHT (`Content.theme_index("NIGHT")`) when the node's own `modifiers` hold `night`, read from `node_setup()` and not through `has_modifier` (decision 3); the node's stored `theme` is not touched, and the next round plays its own theme again. The radar goes through one factor in `scripts/threats.gd`: `Threats.radar_factor(night)` is `NIGHT_RADAR_FACTOR` (0.6) or 1.0, and `radar_range`, `radar_fraction` and `radar_hides` take it (default 1.0, which gives every number of a day round to the last digit). In `hud.gd` the radar's dots (riders, bosses and phones alike) and the caches beyond the night range are left off, not pinned on the rim. Two things the design above did not spell out, decided here: **the extraction square is always drawn** (on the rim when it is farther than the night range), so the way out is never lost, and **a cache between the night range (36 m) and the objectives' sense range (45 m)** is sensed but not on the radar, which is what MD5.4 is to look at. The edge arrows (`_draw_threats`) do not know the factor. `tools/night_modifier_check.gd` checks the radar numbers (exactly the old ones at factor 1.0), rounds on generated arenas in the order no modifier, night, no modifier (a `round_theme` that read `has_modifier` fails it, because that still holds the round before), a NIGHT-themed node without the modifier (the look, not the radar), that a far threat is still ranked for an arrow and `_draw_threats` stays free of the rule, that the themes of a map's nodes are the same with `night` in the rules, and draws the HUD once in a night round. Checked on 2026-11-07 with Godot 4.7-stable headless, only the checks that touch this code: `night_modifier_check`, `threat_check`, `node_setup_check`, `objective_check`, `cache_markers_check`, `fps_counter_check`, `hud_modern_check`, `hud_slots_check`, `arena_theme_check`, and the `map` group, all pass. Not looked at in the game (no display here): how NIGHT with the short radar feels, MD5.4 and MD5.5.

**Readability.** No rule of `docs/ART_DIRECTION.md` section 6 changes. Riders, phones and pedestrians are checked at distance under NIGHT in a screenshot (MD5.4), and the frame time stays inside `docs/PERFORMANCE_BUDGET.md`.

**Questions for the owner.** (a) Is a shorter radar the rule you want, or something else (for example riders that carry headlights and no rule at all)? (b) Should a node whose theme is NIGHT also get the rule, so every dark round is a "night" round? That is the harder game and moves no seed, but it makes a quarter of all fights harder at once.

## Open points for Milestone D and balance

- A fight now gives an upgrade pick and no shop (alpha B1); the shop is a node, so it appears on only some paths and the cash from a round waits for it (the map screen shows the cash). The economy and the upgrade pacing need a balance pass (alpha D2, D3; compare the Milestone I balance item). A run without a map has no shop nodes, so it keeps the old order: upgrade pick, then shop.
- What an `elite`, an `event` and a `rest` actually do is decided in Milestone D; this page only decides where they can appear.
- The existing boss rule in `main.gd` (`boss_count` and round 3 onwards) will be replaced by the two boss nodes.
