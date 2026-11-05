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
| Rider speed | factor 1.0 | `riders.gd`, the `diff` line (`1 + (round_n - 1) * ROUND_SPEED_GROWTH + next_idx * 0.03`), as a factor on the whole `base` speed | `RIDER_SPEED_CAP` (18 m/s) stays the hard limit, so a late sprinter that is already at the cap does not get faster; the early floors feel it most, which is the point. A floor 10 rider is already 1.45 to 1.75 times its floor 1 speed. **Built in H1.5**; the speed a rider starts a round with (each rider then aims at 0.7 to 1.4 times it, bursts 1.8 to 2.3 times): a pro rider has 8.25 m/s on floor 1 and 11.96 on floor 10 at Heat 0, and 9.08 and 13.16 at Heat 1; a sprinter (x1.4) has 11.55 and 16.75 at Heat 0, and 12.71 and 18.42 at Heat 1. From about floor 4 the top of a sprinter's aim range is already over the cap, so a sprinter gains less than 10 % there and slow and normal riders gain the full 10 % |
| Riders per round | +0 % | `Main.plan_riders` after the plan is built, before the shuffle | Round up, at least +1 from H2; the extras copy the mix in its proportions. `double_riders` pairs waves, it does not change the count, so they stack without trouble. **Built in H1.6** as `Heat.with_extra_riders`, called in `plan_riders` after the seed's own shuffle (not before, so the seed's shuffle and its random draws are the same at every Heat): the seed's riders keep their order, the extras are counted with the largest remainder method and spread evenly through the round, and nothing is drawn from a random stream. A normal node of 8 to 10 riders gets 2 more at H2 and above, an elite (10 to 12) gets 3, a boss round (6 to 8) gets 2; a plan already at 16 gets none |
| Hearts | 3 | `Main.MAXHEARTS` (set where a run starts, `Main.start_game`; MAX LIVES in `shop.gd` still adds 1) | Never below 2 on the ladder, never below 1 in any set of modifiers. **Built in H1.7** as `Heat.start_hearts`: 3 less `hearts_minus`, never below the `hearts_min` cap and never above 3. It is applied in `start_game` only, after a Daily Run has set Heat 0, so `reset_run` (practice, the title screen, before CONTINUE) and a loaded run (its own `max_hearts`) are not touched. MAX LIVES works on top: it adds 1 while `MAXHEARTS < 4`, so from H3 it can be bought twice (2 to 4) instead of once (3 to 4), which H1.12 should look at |
| Tough rider health | 2, 3 from round 5 | `riders.gd`, the `hp` of type `tough` | +1 at H4. The angry cyclist mini boss (`bosses.gd`, `spawn_runner`) follows the boss factor, rounded up. **Built in H1.8**: `spawn_rider` adds `tough_hp_plus` to a tough rider only, so a tough rider has 3 health (4 from round 5) at H4 and H5 instead of 2 (3); pro, sprinter and courier riders keep 1 at every level. `spawn_runner` takes its base from the tough rider's health without the Heat bonus (so the bonus is not counted twice), then applies the boss factor rounded up: the cyclist of round 2 has 3 health at H4 instead of 2, of round 5 has 5 instead of 4, of round 8 has 7 instead of 6 |
| Boss health | factor 1.0 | `bosses.gd`, after `boss_hp()` and before `FINAL_HP_MUL` | x1.15 at H4. **Built in H1.8** as `Heat.boss_health`, called in `spawn_boss` on the health after `boss_hp()` (rounded to the nearest whole number) and before `FINAL_HP_MUL`. The weak spot is not touched: it still does double damage when it is open, so only the health it takes off grows in proportion. The golden president, if it is round 10, has 117 health at H4 instead of 101 (78 from the growth per round, 90 with Heat, x1.3 for the final boss; a shop screen is not a round, so it may come a round or two earlier); H1.12 checks that against the fire rate |
| Shop prices | factor 1.0 | `shop.gd`, `shop_price` | x1.20 before HAGGLER (x0.85); the price still rounds to 5 and stays at least 5. **Built in H1.9** as `Heat.price_factor`, a factor in `shop_price` after the round, buy count and tier growth and before HAGGLER. Only the price of an item changes: the reroll cost (20 + 15 per reroll) is not a shop price and stays as it is. At H5 a 100 coin perk on floor 1 costs 120, on floor 4 with no buys 165 (was 135, rounded to 5) |
| Cash | factor 1.0 | `shop.gd`, `add_cash` | x0.80, before BOUNTY (x1.35). Every cash source (rider and boss kills, the cash drop, cache cash, the LIFE INSURANCE payout) goes through `add_cash`, so one place covers them. **Built in H1.9** as `Heat.cash_factor` (the `cash` of the level, never below the `cash_min` cap and never above 1.0), multiplied in `add_cash` after the growth per round and before BOUNTY, and rounded once at the end. At H5 a pro rider that pays 5 pays 4 on floor 1, a tough rider (13) pays 10, a cash drop (15) pays 12 and a boss kill (55) pays 44; the 2 coin style bonus rounds to 2 |

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
- **Unlock:** Heat 0 is always open; Heat N+1 opens the first time a run is won at Heat N. The highest open level is kept in `meta.json`; an old file reads as only H0 open (H1.11). **Built in H1.11:** `heat_open` in `meta.json`, `Meta.unlock_heat_after_win` (called by `award_run`), `Heat.open_level` and `Heat.clamp_open`. Only a win at the highest open level opens the next one (a win at a lower level, a lost or quit run, and the training room open nothing); a Daily Run is always Heat 0, so a win there counts as a win at Heat 0. The PLAY page stops at the highest open level, says which levels are open and locked and what opens the next one, and the run summary adds "HEAT n OPENED" to its Heat line. A run starts at the highest open level at most.
- **Leaderboards:** the local Top 10 stays one board until the split item of Milestone A is done. Each entry gets a `heat` field (an old entry reads as 0) and the list shows it, so a Heat 5 score is not mistaken for a Heat 0 one. **Built in H1.10.**
- **Where the level is shown (H1.10):** the run bar (top centre, after the round name, from Heat 1; Heat 0 leaves the bar as it was), the pause menu (a line under the buttons, "HEAT 3  FEWER LIVES", also at Heat 0 as "HEAT 0"; not in the training room), the run summary (the same line under the title) and a HEAT column on the High Scores page. All of them use `Heat.label`. The score record the website will take (Milestone N, `docs/WEBSITE_API.md`) has to carry `heat` as well; that file is not changed in this chunk.

## What the later chunks decide

- H1.12 and H3.5 tune every number above with the bot harness; none of them is final.
- The second item replaces "level" with "a set of ranks and points" and keeps H1 to H5 as presets (H2.1 lists the modifiers, ranks, points and clashing pairs).
- The third item decides what the levels pay (H3.1); until then Heat pays nothing extra.

## Checks

`tools/heat_check.gd` (H1.2) loads `data/heat.json`, checks the level range and that level 0 is neutral. Each effect chunk (H1.5 to H1.9) adds its own case to it and runs the checks of the code it touches (`python tools/run_checks.py heat rider`, and so on), not the whole suite.
