# Heat

Design note for the Heat system (README, Milestone B, "Difficulty Scaling", chunk H1.1). **No Heat code exists yet**; this note fixes what the next chunks build. All numbers are first guesses to tune by playing (chunk H1.12 does that with the bot balance harness, which is not built yet).

## What Heat is

A number the player picks before a run. **Heat 0 is the game as it is today.** Every level above it makes the run harder and, in the third roadmap item, pays more. This note covers the first item, the fixed ladder H1 to H5. The second item turns the ladder into switchable modifiers (the ladder stays as presets) and the third decides the rewards, so nothing here may make those two harder than they have to be.

## Rules that hold at every level

1. **A seed gives the same map, arena and rider mix at every Heat.** Heat is applied when a round is played (`plan_riders`, `riders.gd`, `bosses.gd`, `shop.gd`), never in `map_gen.gd` or `map_content.gd`. The extra riders of H2 are drawn after the seed's own plan, from the rider-plan stream only, so no other random stream moves.
2. **A Heat 0 run gives the same numbers as before Heat.** `tools/heat_check.gd` proves it (every effect at level 0 is the neutral value), and it is the safety net for the whole section.
3. **Every level keeps everything below it.** H3 has H1's speed and H2's crowd as well.
4. **One-hit kills stay.** Pro, sprinter and courier riders keep 1 health at every level; the dart gun feel depends on it.
5. **Score is not multiplied by Heat**, so the scores of different Heat stay comparable once the boards are split.

## The ladder

| Level | Name | Adds (on top of the level below) |
|---|---|---|
| H0 | none | nothing |
| H1 | FASTER | riders ride 10 % faster |
| H2 | CROWDED | 20 % more riders in a round |
| H3 | FEWER LIVES | 2 hearts instead of 3 |
| H4 | TOUGH | tough riders have 1 more health, bosses 15 % more |
| H5 | STINGY | shop prices 20 % higher, cash 20 % lower |

## Where each effect goes

| Effect | Neutral at H0 | Where it plugs in | Notes |
|---|---|---|---|
| Rider speed | factor 1.0 | `riders.gd`, the `diff` line (`1 + (round_n - 1) * ROUND_SPEED_GROWTH + next_idx * 0.03`), as a factor on the whole `base` speed | `RIDER_SPEED_CAP` (18 m/s) stays the hard limit, so a late sprinter that is already at the cap does not get faster; the early floors feel it most, which is the point. A floor 10 rider is already 1.45 to 1.75 times its floor 1 speed. H1.5 measures the real speeds and writes them here |
| Riders per round | +0 % | `Main.plan_riders` after the plan is built, before the shuffle | Round up, at least +1 from H2; the extras copy the mix in its proportions. `double_riders` pairs waves, it does not change the count, so they stack without trouble |
| Hearts | 3 | `Main.MAXHEARTS` (reset where a run starts, `main.gd`; MAX LIVES in `shop.gd` still adds 1) | Never below 2 on the ladder, never below 1 in any set of modifiers |
| Tough rider health | 2, 3 from round 5 | `riders.gd`, the `hp` of type `tough` | +1 at H4. The angry cyclist mini boss (`bosses.gd`, `spawn_runner`) follows the boss factor, rounded up |
| Boss health | factor 1.0 | `bosses.gd`, after `boss_hp()` and before `FINAL_HP_MUL` | x1.15 at H4. The golden president, if it is round 10, is about 117 health at H4 instead of about 102 (a shop screen is not a round, so it may come a round or two earlier); H1.12 checks that against the fire rate |
| Shop prices | factor 1.0 | `shop.gd`, `shop_price` | x1.20 before HAGGLER (x0.85); the price still rounds to 5 and stays at least 5 |
| Cash | factor 1.0 | `shop.gd`, `add_cash` | x0.80, before BOUNTY (x1.35). Every cash source (rider and boss kills, the cash drop, cache cash, the LIFE INSURANCE payout) goes through `add_cash`, so one place covers them |

Heart drops, PATCH UP and the heal of one heart on a round clear **do not change at any level** in this first version. With 2 hearts each heart is already worth more, and a bad round must not be a death sentence on its own. They are the first lever to pull if H3 and above turn out too soft or too hard in the playtest (H1.12).

## Caps that keep a late floor playable

- Rider speed: `RIDER_SPEED_CAP` (18 m/s), already in the code.
- Riders in one round: at most 16, whatever the level (a normal node has 8 to 10, an elite 10 to 12, a boss round 6 to 8).
- Hearts: see the table. Prices: rounded to 5, at least 5. Cash factor: never below 0.5 once there are modifiers.
- The second item adds a cap on the sum of each effect and refuses clashing modifiers (H2.3).

## How Heat meets the rest

- **Daily Run:** always Heat 0, so everybody plays the same day. The HEAT entry is not offered for it, and a run save with `daily` set and a Heat above 0 loads as Heat 0.
- **Custom seed:** may use Heat and stays unranked, as today (`Main.ranked_run`).
- **Restart run** keeps the level; **Continue** gives it back.
- **Run save:** a `heat` key (0 to the top level), cast and clamped on load like the others. An old `run.json` without it loads as 0 (H1.3).
- **Settings:** the level last chosen is remembered in `settings.cfg` (H1.3).
- **Unlock:** Heat 0 is always open; Heat N+1 opens the first time a run is won at Heat N. The highest open level is kept in `meta.json`; an old file reads as only H0 open (H1.11).
- **Leaderboards:** the local Top 10 stays one board until the split item of Milestone A is done. Each entry gets a `heat` field (an old entry reads as 0) and the list shows it, so a Heat 5 score is not mistaken for a Heat 0 one. The score record the website will take (Milestone N, `docs/WEBSITE_API.md`) has to carry `heat` as well; that file is not changed in this chunk.

## What the later chunks decide

- H1.12 and H3.5 tune every number above with the bot harness; none of them is final.
- The second item replaces "level" with "a set of ranks and points" and keeps H1 to H5 as presets (H2.1 lists the modifiers, ranks, points and clashing pairs).
- The third item decides what the levels pay (H3.1); until then Heat pays nothing extra.

## Checks

`tools/heat_check.gd` (H1.2) loads `data/heat.json`, checks the level range and that level 0 is neutral. Each effect chunk (H1.5 to H1.9) adds its own case to it and runs the checks of the code it touches (`python tools/run_checks.py heat rider`, and so on), not the whole suite.
