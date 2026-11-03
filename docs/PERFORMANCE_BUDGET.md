# Performance budget (Milestone K, Decisions)

Set on 2026-11-03. The numbers live in `data/performance_budget.json` and `python tools/run_checks.py arena_budget` fails when the game goes over them.

**Machine:** Intel i5-7500, GTX 1060 3 GB, 8 GB RAM, 1080p at 60 fps, so 16.6 ms a frame (`docs/ART_DIRECTION.md`, section 5). **The owner has no such machine, so nothing here was timed on it.** The limits come from what the arenas measure now (headless, no GPU) and from the targets in `ART_DIRECTION.md`. The performance passes in the README (the one for the bigger arena and the one on the minimum-spec machine) are where a frame time on real hardware is checked against them.

| Item | Budget | Measured now (60 seeds, all six styles) |
|---|---|---|
| World triangles (ground, dressing, modelled buildings, benches, crates) | 300,000 | at most about 262,000 (canyon); park, market and plaza 200,000 to 240,000; tunnel and bridge under 80,000 |
| World draw calls | 40 | 18 to 26 |
| Entity triangles on screen (riders, bosses, viewmodel; not measured) | 100,000 | ten riders at 6,000 + a boss at 15,000 + the gun at 10,000 = 85,000 from the `ART_DIRECTION.md` targets |
| Lamp lights on at once | 8 (`Lighting.MAX_LAMP_LIGHTS`, the nearest ones) | an arena has 17 to 84 lamps, all hidden until a theme turns the nearest 8 on |
| Other lights on at once (pickups, effects) | 4 | not measured |
| Lights that cast shadows | 1, the sun | the sun only |
| Sun shadow | one split (`SHADOW_ORTHOGONAL`), 36 m reach; map 2048 high, 1024 medium, none low | as budgeted |
| Draw distance (`cam.far`) | 250 m | 250 m; the arena is 144 m square, 204 m corner to corner, so all of it stays in range |

**Why these numbers:** on a GTX 1060 triangles are not the first limit, so the triangle number is generous (about 15% over the worst arena) and exists to stop an asset swap from quietly doubling the world. Draw calls, the CPU (4 cores) and shadows are the real limits: the world is 26 calls at most today, and every extra light or shadow caster costs a full extra pass over the geometry. That is why only the sun casts shadows, from one map with a short reach, and why at most 8 lamps are lit.

**Changing a number:** raise it only after a frame time on the minimum-spec machine says there is room (`tools/baseline.gd` plays the generated arena; see `tools/BASELINE.md`), then edit `data/performance_budget.json` and this table together.

**Not covered:** frame time, video memory, particles and overdraw, entity triangles, and the lights the F9 kit will add when it replaces the stand-in buildings; each of those belongs to the performance passes in the README.
