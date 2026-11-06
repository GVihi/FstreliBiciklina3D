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
- **Run save:** a `heat` key (0 to the top level), cast and clamped on load like the others. An old `run.json` without it loads as 0 (H1.3). A run played with a set of the player's own also has `heat_set` (H2.5); an old file without it plays as the preset of its level.
- **Settings:** the level last chosen is remembered in `settings.cfg` (H1.3), and with it the set of the player's own, if there is one (`heat_set`, H2.5).
- **Unlock:** Heat 0 is always open; Heat N+1 opens the first time a run is won at Heat N. The highest open level is kept in `meta.json`; an old file reads as only H0 open (H1.11). **Built in H1.11:** `heat_open` in `meta.json`, `Meta.unlock_heat_after_win` (called by `award_run`), `Heat.open_level` and `Heat.clamp_open`. Only a win at the highest open level opens the next one (a win at a lower level, a lost or quit run, and the training room open nothing); a Daily Run is always Heat 0, so a win there counts as a win at Heat 0. The PLAY page stops at the highest open level, says which levels are open and locked and what opens the next one, and the run summary adds "HEAT n OPENED" to its Heat line. A run starts at the highest open level at most.
- **Leaderboards:** the local Top 10 stays one board until the split item of Milestone A is done. Each entry gets a `heat` field (an old entry reads as 0) and the list shows it, so a Heat 5 score is not mistaken for a Heat 0 one. **Built in H1.10.**
- **Where the level is shown (H1.10):** the run bar (top centre, after the round name, from Heat 1; Heat 0 leaves the bar as it was), the pause menu (a line under the buttons, "HEAT 3  FEWER LIVES", also at Heat 0 as "HEAT 0"; not in the training room), the run summary (the same line under the title) and a HEAT column on the High Scores page. All of them use `Heat.label`. The score record the website will take (Milestone N, `docs/WEBSITE_API.md`) has to carry `heat` as well; that file is not changed in this chunk. From H2.5 the run bar, the pause menu and the run summary also list the modifiers of the run (see "Built in H2.5" below).

## Modifiers (the second roadmap item, design note H2.1)

**Built so far: the table and the arithmetic on sets (H2.2), playing a set with the stacking rules (H2.3), the page that chooses a set (H2.4), and saving the set and listing it (H2.5)**; the scripted runs of every modifier are H2.6. The ladder above stays and becomes five presets. All numbers are first guesses for the bot harness (H2.6, H3.5).

### The five modifiers

Each effect of H1.5 to H1.9 becomes one modifier with ranks. Rank 0 is "off" and changes nothing; rank 1 is exactly what the ladder adds, so a preset is just a set of rank 1s. The points are what the rank is worth **in total** (not per step), and the Heat of a run is the sum of the points of its ranks.

| Modifier | Id | Rank 1 | Rank 2 | Rank 3 | Points (rank 1 / 2 / 3) |
|---|---|---|---|---|---|
| SWIFT RIDERS | `swift` | riders ride x1.10 | x1.20 | x1.30 | 1 / 2 / 4 |
| CROWD | `crowd` | +20 % riders in a round | +40 % | not offered | 1 / 2 / - |
| FEWER LIVES | `lives` | 2 hearts | 1 heart | not offered | 1 / 4 / - |
| TOUGH | `tough` | tough riders +1 health, bosses x1.15 | tough riders +2, bosses x1.30 | not offered | 1 / 3 / - |
| STINGY | `stingy` | shop prices x1.2, cash x0.8 | prices x1.4, cash x0.65 | prices x1.6, cash x0.5 | 1 / 2 / 3 |

- **Built in H2.2:** `data/heat.json` (version 2) holds the modifiers, the clashes (each with the reason the page will show) and the presets; the loader builds the ladder (`Heat.levels`) from the presets, so everything that reads a level works as before. `Heat` has `total_points`, `points_of`, `max_rank`, `clashes_in`, `is_legal`, `clean_set`, `effects_of`, `preset_ranks`, `preset_points`, `modifier_ids` and `top_total`; the format is in `data/README.md`. The hearts cap in the file is now 1 (the ladder still never goes below 2, which `heat_check` tests on every preset). `tools/heat_check.gd` proves the total of every preset equals its level, that the presets build exactly the ladder of H1, and counts all 432 sets (330 legal, top total 12, two sets). The game itself still plays by level; ranks above 1 are not read by anything yet.
- **Built in H2.3:** `Heat.play_set(ranks)` plays a set from then on and `Heat.clear_set()` goes back to the level (`has_set`, `set_points`, `set_ranks` and `set_effects` say what is played). While a set is played, every lookup with no level given (`value`, `start_hearts`, `price_factor`, `cash_factor`, `boss_health`, `with_extra_riders`) reads the set, so the code that plays each effect did not change and its caps apply to a set exactly as they did to a level; a level given on purpose still reads the table. A set with a clash is refused by `clean_set` (the second named goes down until it fits), so what is played is always legal and worth at most the top total. A Daily Run is Heat 0 for everybody and clears the set (`Main.start_game`). `start_hearts` is also never below 1. **Nothing in the game chooses a set yet**: the page is H2.4, saving the set H2.5, so a run plays by level exactly as before.
- **Built in H2.4:** the HEAT MODIFIERS page, opened from the PLAY page (MODIFIERS button, M, gamepad X). The page only draws and asks: the rules are `Heat.try_step` (a rank up or down by one; up is refused at the top rank, for a clash with the reason from the table, and past the open Heat; down is always allowed), `preset_step`, `settle`, `preset_matching` and `custom_set`. What Main keeps: a set that is exactly a preset is the level (`Main.heat`, `Main.heat_ranks` empty) and plays by level as before; any other set is `Main.heat_ranks` with `Main.heat` set to its total, `start_game` plays it with `Heat.play_set`, and the run is called "HEAT n  CUSTOM". A Daily Run drops the set; the level arrows of the PLAY page drop it too (a level is a preset). Saving the set is H2.5, below.
- **Built in H2.5:** the set of the player's own is saved next to the level, in `settings.cfg` (`[game] heat_set`) and in the saved run (`run.json` `heat_set`), as `{modifier id: rank}`; a preset is not written, the level says it. One rule reads both files, `Heat.load_saved(level, raw)`: nothing, or something that is not a set, is the preset of the saved level (so every old file plays as it did); anything else goes through `clean_set` (unknown ids dropped, ranks kept to the table, a clash resolved), a set that is a preset is kept as its level, a set worth more than the top level is ignored (the page cannot hold one yet), and the set wins over a level beside it that does not match, so the Heat number is always what the set is worth. A saved run is put back with `Heat.play_set`, so CONTINUE plays the modifiers and not the preset of the level; a Daily Run is Heat 0 with no set whatever the file says. **Shown:** `Heat.modifiers_line` writes the modifiers of the run being played in table order with their ranks ("SWIFT RIDERS 2, CROWD 1"), for a preset and for a set of the player's own, and nothing at Heat 0. It is a small line under the segments of the run bar (the training room and Heat 0 keep the bar as it was), a line under the Heat line of the pause menu, and a MODIFIERS line under the table of the run summary. The "HEAT n  CUSTOM" line stays, and the PLAY page still lists the set. Checked by `tools/heat_save_check.gd`. **Not done:** the score record still carries only the total (`heat`), see the note under the top total below.
- **Where each plugs in** is the table "Where each effect goes" above: the code that reads an effect (`rider_speed`, `riders_more`, `hearts_minus`, `tough_hp_plus` with `boss_hp`, `price` with `cash`) does not change. H2.2 only changes where the numbers come from (the ranks, not a level's row).
- **TOUGH and STINGY are one modifier each**, not two, because H4 and H5 are one effect each on the ladder; splitting them (riders and bosses, prices and cash) would make H4 and H5 worth 2 points and the presets would no longer be 1 to 5.
- **Why these steps:** speed climbs by 10 % a rank (the cap stays `RIDER_SPEED_CAP`, so rank 3 matters mostly on the early floors, as in H1.5), rank 3 is worth 4 (two more than rank 2) because x1.30 is the biggest speed step and the one the 16 rider rounds feel most. CROWD stops at rank 2 because the 16 rider cap (below) leaves rank 3 with nothing to add: +40 % is 12 to 14 riders in a normal round, 14 to 16 in an elite round (the 12 rider elite round is cut from 17 to 16, the only place the cap bites), 9 to 12 in a boss round. One heart (FEWER LIVES rank 2) is worth 4 because it is by far the biggest step: it turns a bad round into the end of the run. TOUGH rank 2 stays at +2 health and x1.30 on bosses (a round 10 president at 131 health against 101 at Heat 0 (78 from the growth per round, 101 with x1.30, x1.3 for the final boss); H2.6 checks that against the fire rate). STINGY rank 3 is the one that reaches the cash cap of 0.5.
- **MAX LIVES** in `shop.gd` adds 1 heart while `MAXHEARTS < 4`, so at FEWER LIVES rank 2 it can be bought up to three times (1 to 4). That is a soft spot for H2.6 to look at, not a reason to change the shop.

### The presets (H1 to H5 stay as they are)

| Preset | Set of ranks | Total |
|---|---|---|
| H0 | none | 0 |
| H1 FASTER | swift 1 | 1 |
| H2 CROWDED | swift 1, crowd 1 | 2 |
| H3 FEWER LIVES | swift 1, crowd 1, lives 1 | 3 |
| H4 TOUGH | swift 1, crowd 1, lives 1, tough 1 | 4 |
| H5 STINGY | swift 1, crowd 1, lives 1, tough 1, stingy 1 | 5 |

So **the total of every preset equals the Heat it names**, which is what the check of H2.2 proves, and every H1 check keeps passing because a preset gives the same effect values as its row of `data/heat.json` does today.

### Rules for a set of ranks

1. **Each modifier is at most at its top rank**, and the Heat of a set is the sum of the points of its ranks (0 to the top total below).
2. **Clashing pairs are refused** (the page of H2.4 greys the second one named out and says why; `Heat.clean_set`, used when a saved set is loaded, takes the second one named back one rank at a time until the set is legal; a clash is "this rank or higher" of both):
   - FEWER LIVES rank 2 with SWIFT RIDERS rank 3, or with CROWD rank 2: one heart against faster or more riders is a run that ends on the first mistake in round 1.
   - TOUGH rank 2 with STINGY rank 3: bosses with 30 % more health while cash is halved and every upgrade costs 60 % more means the damage upgrades cannot be bought in time.
   No preset has a clash. Every other pair is allowed.
3. **Caps on the sum of each effect** stay the ones of "Caps that keep a late floor playable": riders in a round at most 16, rider speed at `RIDER_SPEED_CAP`, cash factor at least 0.5, prices rounded to 5 and at least 5, and now **hearts at least 1** (the ladder never goes below 2, which FEWER LIVES rank 1 respects). One-hit kills stay: pro, sprinter and courier riders keep 1 health at every set.
   - **What the rider speed cap promises (checked in H2.3):** `RIDER_SPEED_CAP` limits the speed a rider *aims* for, and a rider that is faster than that only slows down to it, never speeds up past it. It does not limit the speed a rider spawns with, at any Heat including 0: a sprinter on floor 10 comes out of the tunnel at about 22 m/s at Heat 0 and takes about 1.5 s to slow to the cap of 18, and with SWIFT RIDERS rank 3 it comes out at about 28 m/s and takes about 1.8 s. Clamping the spawn speed would change Heat 0 slightly, so it is left as it is until the owner says (see "Rider speed at spawn" below).
4. **Top total: 12.** There are 432 combinations of ranks, 330 of them have no clash, and the highest total among those is 12, reached by two sets only: swift 2, crowd 1, lives 2, tough 2, stingy 2, and swift 3, crowd 2, lives 1, tough 2, stingy 2 (checked by counting them all, not by hand). The totals in between are 1 (5 sets), 2 (13), 3 (24), 4 (36), 5 (47), 6 (52), 7 (50), 8 (42), 9 (31), 10 (19), 11 (8). The same total from two different sets is not the same run, so the leaderboard should show the total and the set, and the split boards stay a Milestone A item. (H2.5 saves and lists the set of a run being played; it does not put the set into the score record, so the High Scores page shows the total only until the split-boards item or a chunk of its own does that.)
5. The rules that hold at every level still hold for every set: a seed gives the same map, arena and rider mix; Heat 0 (no ranks) is the game as it is today; score is not multiplied by Heat.

### How the ladder's unlock meets modifiers (to confirm)

H1.11 opens Heat N+1 when a run is won at the highest open level. Assumed for the modifier page (H2.4): **a set can be played when its total is at most the highest open level**, and the open level keeps rising by one per win at the highest open level, now up to the top total 12 instead of 5. So a player who has opened Heat 5 can pick any set worth 5 points or less (the preset or one of their own), and a win at Heat 5 opens Heat 6, where the presets end and only sets of their own can be picked. The alternative is to keep custom sets locked behind the top preset; that is one condition in H2.4 and does not change the data. Say if it should be that.

**Built in H2.4 as assumed:** `Heat.try_step` refuses a rank when the set would be worth more than `open_level()`. Because the open level still ends at the top level of the ladder (5), the page cannot hold a set worth more than 5 yet; letting the open level rise to the top total 12 changes `top_level`, `open_level` and `Meta.unlock_heat_after_win` (H1.11) and the run record's Heat range, so it is not done here. It is one decision for the owner: raise the open level past the presets (then sets above 5 become choosable), or keep custom sets within the presets' range.

### Rider speed at spawn (to confirm, found in H2.3)

The cap of 18 m/s is a limit on what riders aim for (`riders.gd`, the line that eases a rider's speed towards its target), while `spawn_rider` starts every rider at its full base speed. On late floors that base is over the cap for sprinters even at Heat 0, so a rider comes out of the tunnel faster than the cap for under two seconds, and the higher the SWIFT RIDERS rank the faster and the longer. If the cap should be a hard limit, start riders at `minf(base, RIDER_SPEED_CAP)`: one line, but it changes late sprinters at Heat 0 too, so it is not done without a yes. `tools/heat_check.gd` checks what holds today (after 3 s no rider rides over the cap, and none speeds up past its spawn speed).

## Rewards (the third roadmap item, design note H3.1)

**Decided in H3.1 and built in H3.2 (the pay, see "Built in H3.2" below); showing it is H3.3 and the unlocks and challenges that need Heat are H3.4.** Until H3.3 the player sees the bonus only in the coins and XP the run pays. All numbers are first guesses for H3.5 to tune with the bot harness.

"Coins" here are the **meta coins** that `Meta.award_run` pays when a run ends and the Unlocks page spends, and XP is the XP of `XpScript.run_xp`. The cash of a round (shop money, `add_cash`) is a different thing: it stays as H1.9 made it (STINGY lowers it) and the formula below never touches it.

### The formula

Let `H` be the Heat of the run: the level, or the total points of a set of the player's own (the same number `Main.heat` holds, so a set pays by what it is worth, not by its name).

1. **The bonus is 10 % of the base pay per Heat point**: `bonus = max(1, (base * H * 10 + 50) / 100)` in whole-number arithmetic, which is `base * 0.10 * H` rounded to the nearest whole number (a half goes up). The 10 is `rewards.pct_per_point` in `data/heat.json`, so H3.5 changes one number and no code.
2. **It is worked out once per run, on the sum**, never per kill or per round. A bonus of 10 % on 2 coins rounds to nothing, and a bonus per source would pay 0 at every low Heat.
3. **At least +1.** From Heat 1 up a run that earned any base pay gets at least one extra coin (and at least one extra XP), so Heat 1 is never a level that pays exactly like Heat 0. A run with no base pay gets no bonus (`base` of 0 gives 0).
4. **Heat 0 pays exactly as before.** `H` of 0 gives a bonus of 0 and nothing else in `award_run` or `run_xp` changes.
5. **Linear in points, the same for every modifier.** The points of a modifier rank were already chosen to say how much harder it is (FEWER LIVES rank 2 is 4 points because it is the biggest step), so a point pays the same whichever modifier it came from. At the top of the ladder (H5) the bonus is +50 %; the top total of 12 would give +120 %, which only matters once the open Heat rises past the presets (see "How the ladder's unlock meets modifiers").

### What the bonus is paid on

| Part of the pay | Heat bonus? | Why |
|---|---|---|
| Coins for rounds cleared (`reward_for_rounds`) | yes | the base of the bonus |
| Coins for bosses (`boss_coins`, including the cyclist and the final boss) | yes | |
| Coins from caches (`cache_coins`) | yes | |
| Coins the score pays (`reward_for_score`, capped by `SCORE_COINS_MAX`) | **no** | **score is not multiplied by Heat** (rule 5 above), and the cap keeps meaning what it says |
| Coins from challenges (`challenges.award()`) | **no** | a challenge shows a fixed reward in its list; a bonus would make that number wrong, and H3.4 gives Heat its own challenges instead |
| XP for rounds cleared, kills, a won run and the boss XP | yes | the base of the XP bonus |
| XP from the score (`score_per_xp`) | **no** | the same reason as the score coins |
| XP from challenges (`per_challenge`) | **no** | the same reason as the challenge coins |

So `base` for coins is rounds + bosses + caches, and `base` for XP is rounds + kills + the win + boss XP. The two bonuses are two separate sums with the same rule, each paid on top of the plain pay.

### Which runs it applies to

- **A run that ended through `award_run`** (won, or lost to the riders or another reason), the same runs that pay at all today. A quit run does not reach `award_run`, so it still pays nothing, and the bonus is not a reason to change that.
- **A lost run is paid in proportion**: the bonus follows what the run earned, so dying in round 3 at Heat 5 pays a little more than at Heat 0 and not the bonus of a won run. Heat is not a reason to play a run to lose.
- **The Daily Run** is Heat 0, so it pays no bonus. **A custom-seed run** may use Heat and pays the bonus like any run (it already pays coins and XP; it stays unranked, as before).

### Worked examples (to check H3.2 against)

A won run with 10 rounds cleared, the mid boss and the final boss, and 2 cache coins has a coin `base` of 20 + 3 + 8 + 2 = 33 (the score coins, up to 5, and any challenge coins come on top and are not bonused):

| Heat | 0 | 1 | 2 | 3 | 4 | 5 | 12 |
|---|---|---|---|---|---|---|---|
| Bonus coins on a base of 33 | 0 | 3 | 7 | 10 | 13 | 17 | 40 |

A run lost after 2 rounds has a coin `base` of 4: the bonus is 0 at H0, then 1 at H1 to H3, 2 at H4 and H5 (it is the minimum of 1 that decides H1 to H3), and 5 at the top total of 12. A run that cleared one round (base 2) gets 1 at every Heat from 1 to 7 (the minimum of 1 is what pays at H1 and H2) and 2 at the top total of 12.

XP, for a won run with 120 kills, 10 rounds, the win, and the mid and final boss: 100 + 120 + 150 + 15 + 100 = 485 bonusable XP. The bonus is 0, 49, 146, 243 and 582 at Heat 0, 1, 3, 5 and 12 (the XP of the score and of challenges is not in that sum). The kills and the boss are only guesses for a typical run; the rule, not these two numbers, is what H3.2 must match.

### Built in H3.2

- **`data/heat.json`** has a `rewards` entry, `{"pct_per_point": 10, "min": 1}`. The loader keeps a missing or bad value at that default (a whole number, 0 to 100) and says so in the log.
- **`Heat.reward_bonus(base, points = -1)`** does the arithmetic above and is the only place that does it. `points` of -1 is the run being played: the points of the set of ranks played, or else `Main.heat`. Points past what the table can ask for (`Heat.total_cap()`, the top total or the top level) are kept to it, so a bad number from a save cannot pay more than the table allows. The sum is whole numbers until one division, because `base * 0.10 * points` as a float may land a half on either side.
- **`Meta.award_run`** works out `heat_base` (the coins of rounds cleared, bosses and caches), pays `heat_coins = reward_bonus(heat_base)` on top, and leaves the coins of the score and of challenges as they were. For XP it calls `XpScript.bonusable_xp` (kills, rounds, the win, boss XP), takes `heat_xp = reward_bonus(...)` of that and passes it to `XpScript.run_xp` as its new last argument, `heat_bonus` (default 0, so every old caller pays what it did). `Meta.heat_coins` and `Meta.heat_xp` keep the two bonuses for the run summary of H3.3; both are part of `meta_earned` and `xp_earned`, not extra, and both start at 0 with every new run.
- **`tools/heat_check.gd`** (`_check_rewards`) checks: the table entry and a bad one, every worked example above, the rules (0 at Heat 0 and for a base of 0, at least 1 from Heat 1, never less for more points), a set of ranks paying by its total, runs paid through the real `award_run` at every level (the won run of the note, Heat 0 exactly as before Heat, more coins and XP at every level up, the score cap and the score XP left out of the bonus, a lost run paid in proportion, a run that earned nothing paid nothing at every level, a second `award_run` paying nothing) and that a new run starts with no Heat pay. The check keeps the real `meta.json` and puts it back.
- **Not covered:** the bonus is not shown anywhere yet (H3.3), and `award_run` is still the only reader of `Heat.reward_bonus`. A custom-seed run pays the bonus and no check plays one through `award_run` yet.

### Why these first guesses

+10 % a point is small enough that Heat 1 and 2 are a nudge and large enough that the top preset pays about half as much again: on a won run that is 17 extra coins at H5 on top of about 38, so the dart gun (250 coins) needs about four and a half full runs at H5 against about six and a half at H0. It does not pay in proportion to how hard the level is, on purpose: H5 has 2 hearts, a crowd, faster and tougher riders and a stingier shop, so a player who clears it has earned more than 50 %, and H3.5 should look at that first. The score is left out so the boards of different Heat stay comparable. The minimum of 1 is there because at low Heat the rounding would otherwise make a harder level pay exactly the same as an easy one.

## What the later chunks decide

- H1.12 and H3.5 tune every number above with the bot harness; none of them is final.
- The second item replaces "level" with "a set of ranks and points" and keeps H1 to H5 as presets (H2.1 lists the modifiers, ranks, points and clashing pairs, in "Modifiers" above; H2.2 to H2.6 build it).
- The third item decides what the levels pay (H3.1, "Rewards" above) and builds it in H3.2 to H3.4; H3.2 pays it, H3.3 shows it and H3.4 adds the unlocks and challenges that need Heat.

## Checks

`tools/heat_check.gd` (H1.2) loads `data/heat.json`, checks the level range and that level 0 is neutral. Each effect chunk (H1.5 to H1.9) adds its own case to it and runs the checks of the code it touches (`python tools/run_checks.py heat rider`, and so on), not the whole suite.
