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

**Event nodes are off for the alpha (README alpha B5):** the `event` weight is 0, so the draw never picks one (a type with weight 0 stays in the table, its code and its `seed` content are kept for Milestone D "Event"). The `rain` round modifier was off the same way (weight 0 under `content.modifiers.types`), because nothing drew or did rain yet; it is on again since MD6.5 (weight 20, see "Rain turned on" below); `double_riders` stayed on. `version` in `map_rules.json` went from 2 to 3 because changing the weights changes every seed's map (the draws divide by the weight total). `tools/map_check.gd` fails if a node of a weight-0 type, or a weight-0 modifier, shows up in any of its 2,000 maps. To bring events or rain back, give them a weight again and bump `version`. The `night` modifier (Milestone D, see "Night modifier" below) is in the table the same way, at weight 0 and `min_floor` 3; adding a weight-0 entry moves no seed (the weights add up to the same total), so `version` stayed at 3 for it.

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
| normal, elite, boss | `riders` (`count` and a `mix` of pro / sprinter / courier / tough that adds up to the count), `gates` (sorted indexes of the arena gates riders may enter by, at least `min_open`), `modifiers` (0 or 1 of `rain`, `double_riders`, `night`) |
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

## Round modifiers: night (README MD5.1 design, MD5.2 the rule in the data, MD5.3 the theme in play)

Today a node carries 0 or 1 modifier from `modifiers.types` in `data/map_rules.json` (`rain` weight 20 since MD6.5, 0 before, `double_riders` weight 50, `night` weight 20 since MD5.6, 0 before), rolled in `_modifiers` of `scripts/map_content.gd` and read in play with `has_modifier(name)` (`round_modifiers` in `main.gd`). The NIGHT theme is the last row of `Content.THEMES`, and a node already draws a theme of its own (`content["theme"]`), so a node can be night today, but only by chance of the theme draw and the player cannot see it coming as a rule. Night as a modifier makes it a named, shown property of a node.

**What it is.**
- A node carries `"night"` in its `modifiers` (still 0 or 1 per node, so night never meets rain or double riders, which settles the question of MD6.6 for night). The round then plays under the NIGHT theme **whatever theme the node drew**. The node's own `theme` stays in its content untouched, so the map, the Daily Run and every saved run read the same as before; only the round's theme is replaced.
- `round_theme()` in `main.gd` is the one place that changes. It reads the modifiers from `node_setup()` itself and does not rely on `round_modifiers`, because `start_round` calls `round_theme()` and `plan_riders()` is not guaranteed to have run first. The theme comes from the `forces_theme` key of the modifier's row (MD5.2), not from a number written in the code.
- Not on boss nodes: the boss `chance` in `modifiers` is 0.0, and boss nodes keep the fixed theme of their boss (`boss_theme`). That stays.

**What it changes for the player.** The NIGHT theme's own values (dark blue sky, cool ambient light, street lamps on, windows fully lit) and one rule, a shorter radar (see "Night radar" below, merged from PR #212). Rider speed, rider count, pickups, pay and score are exactly those of the same node without the modifier. What makes it hard: foes are harder to place in the dark, and the radar warns later. What keeps it fair: riders and bosses keep their rim glow (`scripts/rim.gd`, `Rim.FOE`), which is the same glow they have in every theme, and no new light or darker value is added.

**Readability rules it must keep** (`docs/ART_DIRECTION.md`): NIGHT stays readable with a medium-dark blue sky and not black, with warm lamps, lit windows and glowing gameplay accents (rule on DUSK and NIGHT); pedestrians against riders are checked at distance in NIGHT (the pedestrian rule); the far visibility of foes and thrown phones (README F5) must still hold. The modifier uses the existing NIGHT row and never a darker one, so these rules are already the ones the theme was checked against; MD5.4 looks at it again in play.

**Open points, with a first guess each.**
1. **Decided in MD5.2:** a node whose drawn theme is already NIGHT is not offered `night`, since it would change nothing. The row in `data/map_rules.json` is `"night": {"weight": 0, "min_floor": 3, "forces_theme": 3}`: `forces_theme` is the index in `Content.THEMES` the modifier plays the round under, and `_modifiers` in `scripts/map_content.gd` skips a row whose `forces_theme` is the node's own theme. The roll and the pick are still one draw each, so no other node moves. MD5.3 reads the same key to choose the round's theme, so the number 3 lives in one place (`tools/map_check.gd` proves it is the theme named NIGHT).
2. Whether night should also dim the arena a little more than the theme (no, first guess: not in this item; "no pitch black" stays true and a deeper night is a later modifier idea for MD7.1).
3. Frame time: the theme only swaps lights and colours, so the cost should be that of a NIGHT-themed node today; MD5.4 measures it on both renderers against `docs/PERFORMANCE_BUDGET.md`.

**MD5.4 status (2026-11-07):** the look needs no new code, because a night round runs `Lighting.apply_theme` with the NIGHT row exactly as a NIGHT-themed node does (lit windows, lamps, rim glow). It still needs an in-game look and a frame time on the generated arena: `tools/baseline.gd` already captures all four themes and times each of them (`tools/BASELINE.md`). The only NIGHT numbers on file are from the roundabout baseline of 2026-10-22 (`docs/baseline_f1/`: HIGH, Forward+ 5.09 ms average; Compatibility 6.10 ms average with 5.9% of frames over 16.7 ms), which is a different arena, so they are for orientation only.

**Order of the next steps.** MD5.2 (done) added the data entry with weight 0, and `tools/map_check.gd` checks that a weight of 0 moves no map of any seed (the same maps come out as with no night row), that `forces_theme` is the NIGHT theme, and that no node holds `night` on its own theme once the weight is on; MD5.3 (done) applies the theme: `round_theme()` in `main.gd` asks `MapContent.forced_theme` (the `forces_theme` of the node's modifier) and falls back to the node's own theme, and `tools/node_setup_check.gd` checks both, that the node's content is never changed and that the next node is back on its own theme; MD5.4 is the look and the screenshot, MD5.6 turned the weight on (see "Night turned on" below); MD5.5 (done) shows the modifier on the map screen (the ROUND line of the info panel), in the round start note and in the pause menu, for every modifier and not only night, MD5.6 turns the weight on (first guess 20, `min_floor` 3).

**Night radar (rule, from PR #212; first guess for the owner to confirm).** A night round shortens the radar to 60 % of its usual range (`RADAR_RANGE_STREET` and `RADAR_RANGE_OPEN` in `scripts/threats.gd`), through one factor: `Threats.radar_factor(night)` is `NIGHT_RADAR_FACTOR` (0.6) or 1.0, and `radar_range`, `radar_fraction` and `radar_hides` take it (default 1.0, which gives every number of a day round unchanged). The HUD reads it through `has_modifier("night")`: a rider, boss or phone beyond the night range is left off the radar, not pinned on the rim, and a cache beyond it is left off too. **The extraction square is always drawn** (on the rim when it is farther), so the way out is never lost, and **the threat arrows at the screen edge do not know the factor**, so nothing can hide from the player in the dark (`docs/ART_DIRECTION.md`, rule 6): the modifier takes away the early warning, not the warning. The factor follows `has_modifier("night")` and not the theme, so a node that only has the NIGHT theme keeps the full radar. A cache between the night range (36 m) and the objectives' sense range (45 m, `explore_map.gd`) is sensed but not on the radar, which MD5.4 is to look at. `tools/night_modifier_check.gd` checks the radar numbers (exactly the old ones at factor 1.0), rounds in the order no modifier, night, no modifier, that a far threat still gets an arrow, and that the themes of a map's nodes do not move with `night` in the rules; it was written on PR #212 against the weight-0 design and has not been run on this combined branch (no Godot in the session that merged them). Open question for the owner: is a shorter radar the rule you want for night?

**Night turned on (README MD5.6, first guess).** `night` has `weight` 20 and `min_floor` 3. A normal node still has a modifier with chance 0.2, an elite node 0.5, a boss never. Among the modifiers a node can get: on floor 3 night is the only one (`double_riders` starts on floor 4 and `rain` is 0), so 20% of normal and 50% of elite fights there are night, except a node that already has the NIGHT theme (one in four), which gets none; from floor 4 a modifier is `double_riders` 50 : `night` 20 (about 71% / 29%), and a node on the NIGHT theme can only get `double_riders`. So `double_riders` is now about 71% of the modifiers from floor 4, where it used to be all of them. Every map of every seed that has such a node changes with this step: the Daily Run's map of a day, a typed custom seed's map, and the map a saved run is rebuilt from when it continues (types, shape and gates are untouched, only the modifiers and which round is night differ). `tools/map_check.gd` checks that night turns up and that every other rule of a node still holds.

## Round modifiers: rain (README MD6.1 design, built in MD6.2 to MD6.5)

This note was written as a design (MD6.1), when a node could carry `rain` (`modifiers.types` in `data/map_rules.json`, then weight 0, `min_floor` 3, switched off in alpha B5) and `has_modifier("rain")` answered for it but nothing drew, played or did rain. It decides what rain is, in the same shape as night above; the status paragraphs below say what has been built since (the look MD6.2, the sound MD6.3, the rule MD6.4, the weight MD6.5), and the present tense of the sections on what the player sees, hears and meets is the design.

**What it is.** One of a node's 0 or 1 modifiers, so rain never meets night or double riders (this is also the answer to MD6.6: no second modifier on a node, and `tools/map_check.gd` already fails a node with two). Unlike night it forces no theme: the round keeps the theme the node drew and rain is laid over it. It only exists in a round of a run (never the training room, which has no node). The Daily Run gets the same rain nights for everybody, because the map comes from the seed; Heat does not touch it.

**What the player sees (MD6.2).**
- Rain streaks near the camera only: one particle system that follows the camera, thin and low in opacity (first guess at most 0.25), never drawn over the HUD. First guess for the cap is 400 streaks and one draw call; the performance budget has no particle line yet (`docs/PERFORMANCE_BUDGET.md` says particles and overdraw are not covered), so MD6.2 measures it on both renderers and writes the cap there. It uses no SSR, SSAO or volumetric fog (`docs/ART_DIRECTION.md`, "Not used").
- A darker, greyer sky and a wet ground: a small shift of the theme's colours toward grey and a darker ground colour, held in one scene part that is hidden without rain and puts every shared material back after the round. It never goes darker than the NIGHT theme, because the art direction asks for no pitch black anywhere in the arena and a medium-dark sky at DUSK and NIGHT.
- It must keep the readability rules: riders keep their rim glow, thrown phones and pickups stay readable at distance (the far visibility of foes and phones, README F5), and pedestrians against riders is checked in rain as it is in NIGHT. No lightning and no screen flash. The number of streaks follows the SHAKE AND FLASH setting (`fx_scale`): at 0 only the darker look and the sound remain.

**What the player hears (MD6.3).** A seamless rain loop `loop_rain`, made in `tools/bake_audio.py` like `loop_ambient` and added to `LOOPS` in `scripts/sfx.gd`, started with the round and stopped on every way out of a round: round clear, death, quit to title, restart, and the training room. It is kept clearly quieter than the directional warning sounds for riders (README Accessibility), so it never masks them; the margin is judged by ear and written in the history note. No bird chirps in a rain round.

**What it does to the round (MD6.4): one small rule, wet tyres.** The sideways grip of riders is multiplied by 0.8 (first guess). In `scripts/riders.gd` the sideways acceleration `PURSUIT_ACCEL` is read in three places (the turn rate, the speed of a rider that gave up, and the reach used for avoiding obstacles); they move to one function that returns `PURSUIT_ACCEL` times the rain factor, read through `has_modifier("rain")`, so a rain round differs from a dry one in that function only. Riders swing wider in turns and take longer to come back after a pass, which the player can see (a wide arc) and use. Nothing else changes: rider speed, count, health, pay, score, pickups, the player's movement, weapons and thrown phones are as in a dry round.
- Why this and not the alternatives: a longer dash slide would be a pure buff to the player and touches `player.gd`, jumping and wall jumps (Milestone L); slower riders at corners is the same idea, which this describes in one number. It is a mild help to the player and no penalty, so rain is the easy modifier; if the bot harness shows rounds in rain are clearly easier or longer, the factor is tuned (MD6.4 and the balance pass of MD7.6).
- It must keep `rider_pursuit_check` and `round_clear_check` working (a round still ends when every rider is down, so no rider may become unreachable), at Heat 0 and at the top Heat set, where riders are fastest and a turn is widest. The lower grip also raises the avoidance reach by a quarter, so `avoid_obstacles` has to be checked against it.
- A round without rain is exactly as before: the factor is 1.0.

**Open points, with a first guess each.**
1. How the wet ground is done (a colour change of the shared ground material and its restore, or an overlay) is decided in MD6.2 once the material set-up is read; first guess a colour change with a restore on every way out of a round.
2. Rain on a node that already has the NIGHT theme is allowed (rain does not force a theme); MD6.2 checks that it is not darker than NIGHT.
3. Splashes where the rain hits the ground, and wet reflections of lamps, are left out of this item.
4. Weight and first floor: MD6.5 turns it on at a first guess of 20 with `min_floor` 3 (as night), next to `double_riders` 50 and `night` 20, so a rain node is about 22% of the modifiers from floor 4 and 50% of them on floor 3 beside night (before `forces_theme` skips, which only concern night). Done, see "Rain turned on" below.

**MD6.4 status:** built as designed. `pursuit_accel()` in `scripts/riders.gd` returns `PURSUIT_ACCEL` times `RAIN_GRIP` (0.8) when `has_modifier("rain")`, and the three places that read the sideways acceleration use it; `tools/rider_pursuit_check.gd` (`_check_rain`) checks that nothing else changes, that the turn rate and the give-up speed follow it, and runs the chase, post and give-up checks again in rain.

**MD6.3 status (2026-11-11):** built as designed, with these answers to what the note left open. The loop is `loop_rain` (4 s, a hiss from 1.5 kHz up with about 110 drops a second on it), baked last in `tools/bake_audio.py` so no other sound changed. It follows the state of the game and not a call at the end of a round: `Rain.raining()` (a rain round and the state `play`) is read every frame by `main.gd`, which tells `sfx.set_rain` (fades in and out in about 0.3 s, and the player is stopped, not only turned down, once it has faded out), and by `birds_may_sing()`, so a clear, a death, a quit, a restart, the training room and every other state need no call of their own. It is silent while the game is paused (the pause menu) and when the game is muted, and it stays at SHAKE AND FLASH 0. `RAIN_LEVEL` is 0.06, which puts the loop about 17 dB under the rider warning bell at its QUIET setting; `tools/rain_sound_check.gd` fails under 15 dB. The margin is a number so far, not yet judged by ear. The same step fixed the loop points of every loop in `sfx.gd` (the frame count was taken from the size of the compressed import and cut each loop to a fifth of its length). Checked with Godot 4.7.2: `python tools/run_checks.py rain_sound`.

**MD6.2 status (2026-11-11):** built as designed, `rain_look` passed once with Godot 4.7.2 (run in the MD6.3 session) and not looked at, so the box stays open. `scripts/rain.gd` holds the three parts: `Rain.rainy_theme` (sky, horizon and ambient greyer and dimmer, the sun weaker, nothing darker than the NIGHT theme), `set_wet` (the ground parts of `world["ground_parts"]` drawn with a darker, glossier copy of their material, the original put back) and `update` (400 streaks in one `MultiMesh` around the camera, `fx_scale` times 400, hidden outside a rain round that is being played). `apply_theme(i, rainy)` in `main.gd` is the one place that puts the look on and takes it off again; `start_round` reads the node's own modifiers through `node_has_modifier`. `tools/rain_look_check.gd` checks it; the screenshot and the frame times on both renderers are still to do (the cap of 400 is a first guess, `docs/PERFORMANCE_BUDGET.md`).

**Rain turned on (README MD6.5, first guess).** `rain` has `weight` 20 and `min_floor` 3, the same as night. Chance of a modifier is unchanged (normal 0.2, elite 0.5, boss never). The names needed no UI work: `MODIFIER_NAMES` in `main.gd` already writes RAIN, and the round start note, the map screen's ROUND line (`MODIFIER  RAIN`) and the pause menu read it for every modifier (MD5.5). What the odds are now, among the modifiers a node gets: on floor 3 there is `rain` 20 and `night` 20, so half of them are rain and half night, except on a node that already has the NIGHT theme (one in four), which cannot get night and so gets rain every time it has a modifier (`double_riders` starts on floor 4); from floor 4 a modifier is `double_riders` 50 : `night` 20 : `rain` 20, about 56% / 22% / 22%, and a node on the NIGHT theme draws from `double_riders` 50 : `rain` 20, about 71% / 29%. So `double_riders` falls from about 71% of the modifiers from floor 4 to about 56%. Rain forces no theme, so it is offered on every theme, the NIGHT one included. Every map of every seed that has a node with a modifier changes with this step (the Daily Run's map of a day, a typed custom seed's map, and the map a saved run is rebuilt from when it continues; types, shape and gates stay, only which modifier a node has differs). `version` in `data/map_rules.json` stays at 3, as it did for night in MD5.6; nothing in the code reads it. `tools/map_check.gd` (`_check_rain_rule`) checks that rain forces no theme and, at weight above 0, that it turns up in 400 maps on its first floor and on the NIGHT theme, and at weight 0 that the maps are those of the rules without a rain row.

**Night and rain together (README MD6.6, decided).** A node carries 0 or 1 modifiers, so the `night` modifier and `rain` never meet on one node, and neither does either with `double_riders`. This is how the code already works and nothing changed for it: `_modifiers` in `scripts/map_content.gd` returns an empty Array or a one-element Array (one pick from one weighted draw), and `tools/map_check.gd` fails a node with more than one modifier in any of its maps. What can still happen is rain on a node that has the NIGHT *theme* by its own theme draw (not the night modifier): that is allowed and looks like a rainy night, never darker than NIGHT (open point 2 above, `Rain.rainy_theme`, and the rainy NIGHT sky check in `tools/rain_look_check.gd`). Why not two modifiers: the rain look is laid over the night colours and a night round already has a shorter radar, so both together would stack a darker look, a shorter radar and wider rider turns on one round, which the balance pass (MD7.6) would have to tune as a pair instead of one factor each. If a later milestone wants two, `_modifiers` has to return more than one, `map_check` and the map screen's ROUND line (`map_modifier_text` already takes a list and `tools/map_node_lines_check.gd` already fits two names) are the places that follow, and every map of every seed changes again.

**Order of the next steps.** MD6.2 the look (built, its check passed, waits for a look and the frame times), MD6.3 the sound (done, waits for a listen), MD6.4 the rule (done), MD6.5 the names and the weight (done, see above), MD6.6 the answer (done, see above). MD6 is closed except for the owner's look, listen and harness run.

## Open points for Milestone D and balance

- A fight now gives an upgrade pick and no shop (alpha B1); the shop is a node, so it appears on only some paths and the cash from a round waits for it (the map screen shows the cash). The economy and the upgrade pacing need a balance pass (alpha D2, D3; compare the Milestone I balance item). A run without a map has no shop nodes, so it keeps the old order: upgrade pick, then shop.
- What an `elite`, an `event` and a `rest` actually do is decided in Milestone D; this page only decides where they can appear.
- The existing boss rule in `main.gd` (`boss_count` and round 3 onwards) will be replaced by the two boss nodes.
