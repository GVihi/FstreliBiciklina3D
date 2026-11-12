# Round modifiers: ideas

Design note for README Milestone D, "Additional modifier ideas", chunk MD7.1. **Ideas only, nothing here is built.** It lists ten round modifiers, says what each one does, which rule it touches, how the player can counter it and what it would cost to build, and picks the first three. The numbers are first guesses; MD7.6 tunes them with the bot harness. How a modifier is added is MD7.2, and `docs/MAP_GENERATION.md` has the notes of the three that exist (night, rain, and `double_riders`).

A *round modifier* is the property of a map node that changes how one round plays (`modifiers` in a node's content, `data/map_rules.json`, `scripts/map_content.gd`). It is not a Heat modifier: those are chosen by the player before a run and are in `docs/HEAT.md`.

## What exists today

| Modifier | What it does | Where it plugs in |
|---|---|---|
| `double_riders` | every wave of riders is a pair | `spawn_wave` in `scripts/riders.gd` |
| `night` | the round plays under the NIGHT theme, and the radar reaches 0.6 of its range | `forces_theme` in the rules, `threats.gd` (`radar_factor`) |
| `rain` | streaks, a greyer sky and a wet ground, a rain sound, and riders with 0.8 of their sideways grip | `scripts/rain.gd`, `sfx.gd`, `pursuit_accel` in `riders.gd` (the look and the rule are on `main`; the sound and the weight of 20 that turns it on are on the MD6 branch, not yet merged) |

All three make the round harder or, for rain, a little easier. None pays more.

## Rules every idea has to follow

These come from the notes of the three above, `docs/HEAT.md`, `docs/ART_DIRECTION.md` and the README's accessibility items.

- A node carries 0 or 1 modifiers, only fight nodes can have one (a boss node never), and only in a round of a run, never the training room or a practice round.
- The same seed gives the same map for everybody (the Daily Run too). What a modifier does in play must not draw from a random stream that moves anything else; use no random numbers, or a stream of its own like the ambush does.
- Heat is not touched, and a modifier is not a copy of a Heat effect (see "Left out").
- Readability stays: riders keep their rim glow, thrown phones and pickups stay readable at distance (README F5), pedestrians stay tellable from riders.
- No information is removed without another way to get it. The edge arrows, the radar and the rider bell read the same list (`threat_list`), and a player who cannot see or cannot hear must still be told. Nothing flashes beyond what the SHAKE AND FLASH setting (`fx_scale`) allows.
- No pitch black, and no volumetric fog, SSR or SSAO (`docs/ART_DIRECTION.md`).
- A modifier is built the way night and rain were: one read through `has_modifier` where it plays out, a name in `MODIFIER_NAMES` in `main.gd` (the round note, the map screen and the pause menu then need no work), a headless check, and a weight of 0 in `data/map_rules.json` until MD7.6.
- No modifier plays on the roundabout, in a practice round or in the training room: `node_setup()` is `{}` on an arena without rider pursuit and there is no node in the other two, so `has_modifier` is false there. An idea that needs open ground (2, 9 and 10: gates, caches, the ambush) therefore needs no line about the roundabout.

**Cost.** S is a constant or a factor read in one place, plus a check. M is one system plus a look (lighting, the HUD) or a check that has to play. L is a new state or a new screen element.

## The ten ideas

| # | Name | What it does | Rule it touches | How the player counters it | Cost |
|---|---|---|---|---|---|
| 1 | HAZE | A plain depth haze, tinted to the theme, fades far riders and phones | the environment in `lighting.gd` (`apply_theme`); far visibility of riders and phones | the radar, the edge arrows and the bell still say where they are; keep moving and fight what is near | M: one fog setting, set and put back the way rain's look is, but it has to be measured in the baseline and must keep the rim glow readable far away |
| 2 | ONE GATE | Every rider of the round comes out of a single gate | the choice of gate in `_spawn_rider`, `riders.gd` (it already takes a `gate_override`) | learn the gate, stand where its lane is covered, shoot into the tunnel mouth | S to M: the gate is picked from the node's seed; how the player is told which one is decided in the build step |
| 3 | NO DROPS | Kills drop nothing (first guess: the heart drop stays, so a bad round is no death sentence, as in the Heat note) | `drop_kill` in `pickups.gd` | cash and a pick-up still come from the supply caches and the shop; save ammo (`ammo` is in the drop table) | S: one early return, but the open question is how hard a long round is without ammo |
| 4 | SLICK | Ground speed eases to the target slowly, so turns and stops slide | the ground branch of `player.gd` (`pvel.lerp(target, dt * 10.0)`); the dash, the slide and the sidestep set the velocity directly and are not affected | plan turns early, use the dash and the slide, which keep full control | M: one number, but it is the player's own movement, which the jump and wall jump work also changes, so `jump_check` and `wall_jump_check` have to be run, and it is the one idea that changes how the player feels instead of what the round throws |
| 5 | TIMER | A countdown for the round; at zero every rider left comes at once (first guess, no life is lost) | a new round clock in `main.gd`, a HUD element, the pause menu | kill fast, skip the caches | L: nothing like it exists (`round_times` only records finished rounds); it needs a rule for zero, a HUD element and the pause handling |
| 6 | FEWER ARROWS | The edge arrows show the 3 strongest threats instead of 8 | `MAX_ARROWS` in `threats.gd`, through one function like `radar_factor` | the bell reads the same list and is unchanged (`rider_warning.gd`), the radar shows every rider; look around | S: it must never go to zero arrows |
| 7 | RUSH HOUR | Many more pedestrians on the arena | the pedestrian spawn in `pedestrians.gd` (`spawn_civ`) | hitting a pedestrian costs a heart and 1500 score (`hit_civ`), so wait for a clear line and read the rim glow | S: pedestrians against riders would be checked here as it is for NIGHT |
| 8 | PHONE STORM | Riders throw phones more often, and up to 5 are in the air instead of 3 | the cap and cool-down in the rider update, `riders.gd` (`g.phones.size() < 3`, `throw_cool`) | phones are readable at distance; dodge, or break the line of sight | S: the risk is readability when many phones fly at once |
| 9 | CURSED STREET | Caches carry a catch much more often (first guess: every one that can) | `pick_variants` in `objective.gd` (`VARIANT_CHANCE` 0.4, `VARIANT_MAX` 2) | pick which caches are worth the catch and skip the rest | S: a locked cache still needs a plain one to hold its key (`assign_keys` turns an unpairable locked cache plain), so a cap of all but one is safe |
| 10 | BIG AMBUSH | The walk to the extraction point brings twice the riders | `count_for_round` in `ambush.gd` (`MIN_RIDERS`, `MAX_RIDERS`) | take the caches first while it is quiet, plan the route to the point | S: one factor; the ambush has its own random stream, so no other stream moves |

## The first three to build

**ONE GATE (idea 2, for MD7.3), FEWER ARROWS (idea 6, MD7.4) and CURSED STREET (idea 9, MD7.5).**

- They are cheap (S, one of them S to M) and none of them touches `player.gd`, the shop or a new HUD element.
- Each one plugs in at a different place (the rider spawn, the threat arrows, the caches), so MD7.2 can write "how a modifier is added" from three different hooks and not from three copies of one.
- Each has an obvious headless check: all riders of the round come out of one gate, an arrow list is never longer than 3 and the bell list is unchanged, and no cache is plain except the ones that hold a key.
- They ask different things of the player: where to stand, where to look, and what to risk.

If one of them falls out in the build, BIG AMBUSH (idea 10) and RUSH HOUR (idea 7) are the next cheapest.

HAZE (idea 1) waits because of its art direction and baseline cost, SLICK (4) because of the jump work, TIMER (5) because it needs a new state, NO DROPS (3) and PHONE STORM (8) because their difficulty is the one the bot harness (MD7.6) has to measure first.

## Left out, and why

- **Faster riders, more riders, fewer hearts, dearer shop:** these are the Heat modifiers SWIFT, CROWD, FEWER LIVES and STINGY. A node doing the same would stack with them past the caps of `docs/HEAT.md`. The README item "One shared daily modifier" lists "fast riders" as an example; that item can decide it, since the Daily Run is always Heat 0.
- **Lightning, a screen flash, pitch black, volumetric fog:** against the flash setting and `docs/ART_DIRECTION.md`.
- **A longer dash slide, slower riders at corners:** left out in MD6.1 as a pure buff to the player; rain has the corner rule.
- **A modifier that pays more:** none of the ten is a reward. If one is wanted, MD7.6's balance pass is the place to ask, since cash and score are tuned there.
