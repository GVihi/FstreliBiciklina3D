# Completed milestones

Milestones of `README.md` whose boxes are all ticked, moved here word for word so the README only holds what is still open. Each one keeps its heading in the README with a link to this file, so "Milestone G" and similar references still resolve. For the finished early alpha roadmap see [`ALPHA_ROADMAP.md`](ALPHA_ROADMAP.md).

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
