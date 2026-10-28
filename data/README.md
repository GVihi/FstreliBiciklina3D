# Game data tables

Content the game reads at startup, so it can be tuned without touching code.

## `items.json`

Shop items that are not perks: the heal, the one-round packs and the upgrade tiers. Perks and duos are in `perks.json` (below).
It is loaded by `scripts/items.gd`; bad entries are skipped and logged with `push_error`, so check the Godot output panel after editing.

```
{
  "upgrade_order": ["clip", "pump", ...],   // order of the between-round upgrade offers (tier items only)
  "items": [ {entry}, ... ]                  // order of the shop pool
}
```

**Keep the order of both lists unless you mean to change it:** every run now shuffles these lists with a generator seeded by the run seed, so reordering changes what every player sees for the same seed.

Every entry has `id`, `kind` (`heal`, `pack` or `tier`), `name`, `desc`, `cost` (base price in dollars) and `min` (first round it can appear in), and may have `needs`: what it needs to matter (see "What an entry needs to matter" below).

| kind | extra fields | what it does |
|---|---|---|
| `heal` | `heal` (lives, default 1) | restores that many lives |
| `pack` | `pending` | `{"rapid": 25}` and `{"big": 25}` are seconds of the buff, `{"free": 12}` is darts that cost no ammo, `{"shield": true}` and `{"hype": true}` switch the effect on next round |
| `tier` | none | an upgrade that levels up; what each level changes is still coded by id in `scripts/shop.gd` (`upgrade_ok`, `apply_upgrade`, `upgrade_stat`) |

A new `tier` id therefore also needs code in `shop.gd`, and a new `pack` needs its `pending` key handled in `main.gd` (`start_round`).

The export preset includes `data/*.json`, because Godot leaves plain data files out of an export otherwise.

## `perks.json`

Perks (bought once per run) and the duos that two perks form together. Loaded by `scripts/perks.gd`; bad entries are skipped and logged with `push_error`.

```
{
  "perks": [ {"id", "name", "desc", "cost", "min", "needs"?}, ... ],   // shop pool order, after the items in items.json
  "duos":  [ {"a", "b", "name", "desc", "needs"?}, ... ]               // "a" and "b" are perk ids
}
```

`cost` and `min` mean the same as for items, and `needs` is optional on perks and duos too (below). A duo needs two different perks that exist in the file, and duo names must be unique (the game looks a duo up by name).
**Keep the order unless you mean to change it**, for the same seeded-run reason as above.

What a perk *does* is still coded where it applies, by id (`g.perks.has("deadeye")` and so on in `combat.gd`, `player.gd`, `pickups.gd`, `bosses.gd`, `main.gd`), and duo effects are checked by name with `has_duo(...)`. A new perk or duo therefore needs code too; the table only holds its name, text, price and pairing.

## What an entry needs to matter (`needs`, roadmap alpha B9)

Nothing should be dropped, offered or sold that cannot change the next round for what the player holds now. The game does not hard-code that for each item: an entry says what it **needs**, and one function answers for all of them, `Needs.ok` in `scripts/needs.gd`. An entry without `needs` always passes. The test reads the player's state, not only the weapon id: the pistol holds 1 dart and passes `clip_min` 3 only after three EXTENDED CLIP levels, the dart gun holds 6 from the start.

`needs` is an object whose keys are all required (every one has to hold):

| key | holds when | example |
|---|---|---|
| `"clip_min": N` | the clip the player holds is at least N darts (ammo goes through `add_shells`, which stops at the clip) | SCAVENGER `{"clip_min": 3}` |
| `"hurt": true` | hearts are below the maximum | PATCH UP, the heart drop |
| `"shop_ahead": true` | a shop node is still ahead on the run map: cash only pays there | HAGGLER, BOUNTY, the CASH drop |
| `"boss_ahead": true` | a boss node is still ahead on the run map: weak spots exist only on bosses | DEADEYE |

"Ahead" is read from the run map (`node_type_ahead` in `scripts/main.gd`): nodes on later floors that the current node leads to. Shops are guaranteed on floors 4 and 9 and bosses on floors 5 and 10, so these only fail late in a run. A run without a map has both, every round.

Where `needs` goes: on an entry of `items.json` or a perk of `perks.json`; on a duo, where it decides whether the shop advertises the pairing (the effect itself still runs when both perks are owned); and for the drops in `DROP_NEEDS` in `scripts/content.gd`. Unknown keys and values of the wrong kind are logged with `push_error` and left out, so check the Godot output panel after editing.

What the game does with an entry that fails: an upgrade card or shop item is left out of the pool before the offers are drawn, so the three cards and the four shelves are still filled from what is left; a duo is not advertised; a drop is not spawned (`drop_ok` and `matter_drop` in `scripts/pickups.gd`): a single draw from the drop table (a boss's drop, a cache's reward) turns it into cash when cash matters and into nothing otherwise, and a kill's separate chances simply skip it, as they always skipped a heart at full hearts. The test never draws a random number: the offers still come from the seeded `offer_shuffle`, so the same seed and the same loadout give everybody the same offers, the Daily Run included.

**A new item, perk, duo or drop has to say what it needs.** Ask of it, for the pistol (a 1-dart clip) and for the dart gun: does it change the next round? If it does for both, leave `needs` out. If it only does while something holds, write that as `needs`. If the condition is not one of the four keys, add it in `needs.gd` (the list `KEYS`, `ok` and `clean`) and say what it reads here. A new weapon is covered without edits: `tools/offer_sense_check.gd` runs every weapon in `PRIMARY_WEAPONS` and fails when anything it offers or drops cannot matter; run it with `python tools/run_checks.py offer_sense`.

## Does it matter for what you hold? (the B9.1 audit, 2026-10-28)

Roadmap alpha B9: nothing should be dropped, offered or sold that cannot change the next round for the loadout the player holds. This table is the first step (B9.1): every drop, upgrade card, shop item, perk and duo, what it needs to matter, and what it does today with the two primary weapons. It was written by reading the code, not by playing, so the owner read it and decided (B9.2, 2026-10-28); the **Decision** column holds those decisions. A row with an empty Decision passes the test (`OK`) and needs none. Hearts are the model case: `drop_kill` only drops one when you are hurt, `maybe_drop` and the cache turn one into cash at full hearts, `shop_ok` offers PATCH UP only when hurt.

Numbers used below (from `weapons.json`, `combat.gd`): the **pistol** holds 1 dart (`start_clip` 1, `max_clip` 4, `clip_step` 1, one dart per pull), the **dart gun** holds 6 (`max_clip` 12, `clip_step` 2). Refilling the pistol's one dart takes 0.55 s (0.25 s with three SPEEDLOADER levels); refilling the dart gun from empty takes 2.4 s (0.9 s with three levels). The clip is refilled to full at the start of every round (`start_round`), so ammo only matters inside a round. `add_shells` (`combat.gd`) never goes past the clip, which is what makes ammo weak with a small clip. Style rank S also gives back one dart every 3 s, whatever you hold.

**What an entry can need** (the inputs a test would read): a clip that is not full, hearts below the maximum, cash to spend (a shop node still ahead on the map: since B1 the shop is only a node), a boss still ahead (the mid boss on floor 5 and the final boss on floor 10), an armoured rider (type `tough`), or nothing (it always matters).

**Verdicts:** `OK` matters for both weapons; `COND` matters only while its need holds, and the game can tell whether it does; `WEAK` does little with the pistol's one-dart clip (a little more with a bigger clip); `TEXT` works but its card says something else; `ODD` works, but not the way the card or the balance assumes.

### Drops (`DROPS` in `scripts/content.gd`, `drop_kill` and `maybe_drop` in `scripts/pickups.gd`, `REWARDS` in `scripts/objective.gd`)

| Entry | Comes from | Needs | Pistol today | Dart gun today | Verdict | Decision |
|---|---|---|---|---|---|---|
| EXTRA LIFE (heart) | `drop_kill` only when hurt; `maybe_drop` and cache turn it into cash at full hearts | hearts below the maximum | the rule is built | same | OK (the model case) | |
| RAPID FIRE (8 s) | power-up draw of `drop_kill`, 2 of 11 in `DROPS` (boss kills only, through `maybe_drop`), 1 of 9 cache rewards | nothing | no magazine use and a 0.08 s pump, but `semi_auto` is 1, so it is one dart per click and a held gamepad trigger does not repeat | held trigger repeats | OK, weaker on the pistol with a gamepad | |
| FAT DARTS (10 s) | same | nothing | bigger hit area | same | OK | |
| SLOW MO (6 s) | same | nothing | slows the world to 55 % | same | OK | |
| SHIELD | same | nothing | absorbs the next hit | same | OK | |
| CASH +$15 | `drop_kill` 15 %, 2 of 11 in `DROPS`, 2 of 9 cache rewards | cash to spend | +500 score always; the cash only pays at a shop node | same | COND (the cash half) | **Filter by what is ahead** (B9.2): not offered once no shop node is ahead on the map. |
| AMMO +2 (+4 with SCAVENGER) | `drop_kill` 28 % + 4 % per style rank (+15 % SCAVENGER), SALVAGE, SCRAPYARD, 1 of 11 in `DROPS`, 2 of 9 cache rewards | a clip that is not full | does nothing with the dart in the gun; with the pistol empty it only fills the one dart (saves a 0.55 s reload); with 3 EXTENDED CLIP levels up to 2 darts | up to 2 of 6 darts, about 0.8 s of reload | WEAK | **Hide until the clip is 3+** (B9.2): not dropped, not a cache reward, while the clip the player holds is below 3 darts. The AMMO family below follows the same rule. |

### Upgrade cards (`UPGRADES`, offered by `upgrade_ok`; the same ids are the `tier` items of the shop, which `shop_ok` filters through `upgrade_ok`)

| Entry | Needs | Pistol today | Dart gun today | Verdict | Decision |
|---|---|---|---|---|---|
| EXTENDED CLIP | clip below `max_clip` (`upgrade_ok` reads the weapon) | +1 dart a level, 1 to 4, 3 levels; the card text says "+2 darts per clip"; the stat line (`upgrade_stat`) shows the real step | +2 a level, 6 to 12, 3 levels | TEXT on the pistol | **Text follows the weapon** (B9.2): the card shows the real step of the weapon in the slot (+1 with the pistol, +2 with the dart gun), not a fixed "+2 darts per clip". |
| GREASED SLIDE | pump above `pump_min` | 0.26 s to 0.14 s, 4 levels | 0.20 s to 0.10 s, 3 levels | OK | |
| SPEEDLOADER | fewer than 3 levels | refilling one dart goes from 0.55 s to 0.25 s: small, and bigger once the clip is | 2.4 s to 0.9 s | OK | |
| FAT DARTS | fewer than 4 levels | bigger hit area | same | OK | |
| THICK SKIN | max lives below 4 | one level only (3 to 4 lives) | same | OK | |
| MELEE REACH | fewer than 4 levels | every loadout holds the melee weapon (the melee slot is never empty) and it deflects phones | same | OK | |
| HYPE MACHINE | `hype_gain` below 2.6 | hype fills faster | same | OK | |
| LUCKY CHARM | fewer than 4 levels | +10 % a level to the power-up drop of `drop_kill` and to `maybe_drop` (boss drops) | same | OK | |
| RUNNING SHOES | fewer than 4 levels | dash cooldown -0.15 s a level | same | OK | |
| POCKET MAGNET | fewer than 2 levels | pulls landed drops from 3.5 + 3 m a level (B8: drops now lie where the rider fell) | same | OK | |

### Shop items that are not tiers (`data/items.json`)

| Entry | Needs | Pistol today | Dart gun today | Verdict | Decision |
|---|---|---|---|---|---|
| PATCH UP | hearts below the maximum | the rule is built in `shop_ok` | same | OK (the model case) | |
| RAPID PACK (25 s) | nothing | rapid fire from the first second; one dart per click | held trigger repeats | OK | |
| FAT DART PACK (25 s) | nothing | bigger hit area | same | OK | |
| SHIELD PACK | nothing | starts the round with a shield | same | OK | |
| HYPE PACK | nothing | starts with the hype bar full | same | OK | |
| FREE DARTS (first 12 darts cost no ammo) | nothing | 12 darts without a reload: about 6.6 s of reloading saved, and the pistol would otherwise reload after every dart | 12 darts is two full clips: about 4.8 s saved | OK, but nobody has decided what it should be worth (the pack is counted in darts, not clips) | **Keep 12 darts** (B9.2): worth the same reload time saved on either weapon, so it stays counted in darts. |

### Perks (`data/perks.json`) and duos

| Entry | Needs | Pistol today | Dart gun today | Verdict | Decision |
|---|---|---|---|---|---|
| HAGGLER | a shop node ahead | 15 % off, only at shop nodes | same | COND | **Filter by what is ahead** (B9.2): not offered once no shop node is ahead. |
| STEADY HANDS | nothing | 30 % less spread (the pistol's spread is wider, so it helps more) | same | OK | |
| SALVAGE | an armoured rider, and an ammo drop that matters | armoured riders always drop ammo, which is WEAK here | same, but 2 of 6 darts is worth something | WEAK on the pistol | **Hide until the clip is 3+** (B9.2), as the AMMO drop. |
| SPRINTER | nothing | sprint 12 % faster | same | OK | |
| SLIDE SHOT | nothing | 3 free darts on a dash or slide, at most once every 15 s (`FREE_SHOTS_COOLDOWN`, added 2026-10-28 because a fast dash cooldown made it nearly constant): each one is a whole clip with the pistol | 3 of 6 | OK | **Keep as it is** (B9.2); the 15 s limit was added later. |
| BOUNTY | cash to spend | cash x1.35, only useful at a shop node | same | COND | **Filter by what is ahead** (B9.2): not offered once no shop node is ahead. |
| ADRENALINE | nothing | dash cooldown -40 % | same | OK | |
| SCAVENGER | an ammo drop that matters | +15 % ammo drops and +4 darts, capped at the clip | +4 of 6 | WEAK on the pistol | **Hide until the clip is 3+** (B9.2), as the AMMO drop. |
| COUNTER | a clip that is not full | refunds 1 dart on a deflect: with the pistol only after you fired its one dart | +1 of 6 | WEAK on the pistol | **Hide until the clip is 3+** (B9.2), as the AMMO drop. |
| CLOSE SHAVE | hearts below the maximum | heals on every 2nd perfect dodge, but only when hurt | same | COND | |
| LAST SHELL | nothing | every magazine dart is the last one, so every dart does double damage: not what the card or the balance assumes | one dart in six | ODD on the pistol | **Keep it as a pistol perk** (B9.2): no change to the effect or the offer. |
| DEADEYE | a boss ahead | weak spots exist only on bosses (`hit_boss`; riders have none), so it does nothing against riders | same | COND | **Filter by what is ahead** (B9.2): not offered once no boss is ahead (bosses are on floors 5 and 10). |
| BOOMERANG | nothing | a deflected phone chains on | same | OK | |
| SECOND WIND | nothing | once a round a deadly hit leaves 1 life | same | OK | |
| MATADOR (SLIDE SHOT + CLOSE SHAVE) | a clip that is not full | perfect dodges refill 3 darts, capped at 1 | 3 of 6 | WEAK on the pistol | **Hide until the clip is 3+** (B9.2), as the AMMO drop. |
| BOUNTY HUNTER (BOOMERANG + BOUNTY) | cash to spend | deflect kills pay x3 cash | same | COND | **Filter by what is ahead** (B9.2): not offered once no shop node is ahead. |
| QUICK DRAW (SLIDE SHOT + BOUNTY) | nothing | 5 free darts on a dash or slide, at most once every 15 s (same limit as SLIDE SHOT) | 5 of 6 | OK | **Keep as it is** (B9.2); the 15 s limit was added later. |
| GHOST (ADRENALINE + CLOSE SHAVE) | nothing | dash invulnerability 0.15 s longer | same | OK | |
| HEADHUNTER (DEADEYE + SCAVENGER) | a boss ahead, and a clip that is not full | refunds 2 darts on a boss weak spot hit, capped at 1 | 2 of 6 | COND and WEAK | **Both rules** (B9.2): hide until the clip is 3+, and not offered once no boss is ahead. |
| LIFE INSURANCE (SECOND WIND + BOUNTY) | cash to spend | second wind pays $80 | same | COND | **Filter by what is ahead** (B9.2): not offered once no shop node is ahead. |
| SNIPER (LAST SHELL + DEADEYE) | a boss ahead | +2 damage on a weak spot hit with the last dart: with the pistol that is every boss weak spot hit after the first dart | only the last of 6 | COND and ODD on the pistol | **Keep it as a pistol perk** (B9.2) for the effect, and **filter by what is ahead**: not offered once no boss is ahead. |
| SCRAPYARD (SALVAGE + SCAVENGER) | an armoured rider, and an ammo drop that matters | two ammo and cash from armoured riders; the ammo is WEAK, the cash is COND | same | WEAK and COND | **Both rules** (B9.2): hide until the clip is 3+ (the ammo), and filter the cash by what is ahead (not offered once no shop node is ahead). |
| RICOCHET (COUNTER + BOOMERANG) | nothing | a deflected phone chains on to 4 targets | same | OK | |
| SPEEDSTER (SPRINTER + ADRENALINE) | nothing | dash cooldown a further -20 % | same | OK | |

**Reading the result.** Of the 47 rows, 30 are `OK`. The ones that fail the test with the pistol are the ammo family (the AMMO drop and the cache ammo reward, SCAVENGER, SALVAGE, COUNTER, MATADOR, the ammo half of HEADHUNTER and SCRAPYARD): they all go through `add_shells`, which stops at the clip. EXTENDED CLIP says the wrong step on the pistol. LAST SHELL and SNIPER do something the card does not say. The cash entries (CASH, HAGGLER, BOUNTY, BOUNTY HUNTER, LIFE INSURANCE) and the boss-only ones (DEADEYE, HEADHUNTER, SNIPER) pass the test only while a shop node or a boss is still ahead, which the run map can answer (`g.run_map`). A weapon with a bigger clip lifts most of the `WEAK` rows to `OK`, which is why the test has to read the player's clip and not only the weapon id.

**The owner's decisions (B9.2, 2026-10-28).** Five, and B9.3 to B9.5 build on them:

1. **The ammo family is hidden until the clip is 3+** (recommended option taken). The AMMO drop, the cache ammo reward, SCAVENGER, SALVAGE, COUNTER, MATADOR, HEADHUNTER and SCRAPYARD are left out of the pool while the clip the player holds is below 3 darts. The test reads the player's clip, so three levels of EXTENDED CLIP on the pistol (1 to 4) bring them back, and the dart gun (6) always has them.
2. **EXTENDED CLIP's text follows the weapon** (recommended option taken): the card shows the step of the weapon in the slot, +1 with the pistol and +2 with the dart gun.
3. **LAST SHELL and SNIPER stay as they are**, a pistol perk: with a one-dart clip every dart is the last one. (SNIPER still needs a boss ahead, see 4.)
4. **Entries are filtered by what is ahead on the map** (recommended option taken). The cash entries (CASH drop, HAGGLER, BOUNTY, BOUNTY HUNTER, LIFE INSURANCE) need a shop node ahead, and DEADEYE, HEADHUNTER and SNIPER need a boss ahead. Shops are guaranteed on floors 4 and 9 and bosses on floors 5 and 10, so these entries only drop out late in a run.
5. **FREE DARTS, SLIDE SHOT and QUICK DRAW stay as they are.** FREE DARTS stays at the first 12 darts of the next round (not counted in clips); SLIDE SHOT (3 free darts) and QUICK DRAW (5) keep their numbers. They skip the magazine, so they are worth something with either weapon and need no filter.

## Balance knobs (roadmap alpha D2.2)

Every number the balance pass (D2) can turn, in one place. Most of them are written in code, not in a data file, so the second column says where. `round_n` is the floor (1 to 10). Values were read from the code on 2026-10-28; if you change one, change it here too. Change **one number at a time** and play again (D2.4).

| Knob | Where | Now | What it does |
|---|---|---|---|
| Rider speed | `spawn_rider` in `scripts/riders.gd` | `165 * RIDER_SCALE (0.05) * diff * type speed`, with `diff = 1 + 0.13 * (round_n - 1) + 0.03 * riders already sent in the round` | The speed a rider aims for in metres per second. A `pro` rider that is the first of its round rides at 8.2 m/s on floor 1, 10.4 on floor 3, 12.5 on floor 5, 14.7 on floor 7 and 17.9 on floor 10. The type speeds (`sp`) are in `TYPES` in `scripts/content.gd`: pro 1.0, sprinter 1.4, courier 0.72, tough 0.85 |
| Rider speed, while it rides | `scripts/riders.gd` (the update of `spd`) | the target is 0.7 to 1.4 times the base speed, times `1 + 0.08 * age in seconds`. For a rider that never gives up the age counts for at most `AGE_SPEED_CAP` (6 s), so the extra speed stops at 1.48 times; any other rider keeps speeding up until it gives up | Makes a rider surge and brake. A rider that gives up speeds up towards 39 m/s |
| Riders per node, their kinds, the armoured share | `content.riders` in `data/map_rules.json` | normal 8 to 10, elite 10 to 12, boss 6 to 8; kinds by weight and `min_floor` | How many riders a round has and how many are fast or armoured. This is the main knob of D1 |
| Armoured rider health | `spawn_rider` in `scripts/riders.gd` | 2 darts, 3 from floor 5 | Health of the `tough` rider |
| Boss base health | `BOSS_INFO` in `scripts/content.gd` | ROGUE LUBA 16, MESH WIFI ADAPTER 16, MINISTER MIKROFON 22 (the angry cyclist is 3 and has its own rule in `scripts/bosses.gd`) | Health on floor 2 and below |
| Boss health by floor | `boss_hp` in `scripts/bosses.gd` | `base * (1 + 0.32 * (round_n - 2))` | The mid boss on floor 5 has 31 (mower, wifi) or 43 (minister) darts of health. Floor 3 has 21 or 29, floor 7 has 42 or 57 |
| Final boss | `FINAL_HP_MUL` in `scripts/bosses.gd` | 1.3 on top of the floor growth, on the minister | The final boss on floor 10 has 101 health (78 from the floor growth, times 1.3) |
| Boss speed | `boss_speed` in `scripts/bosses.gd`, `speed` in `BOSS_INFO` | `speed * (1 + 0.10 * (phase - 1)) * (1 + 0.03 * (round_n - 1))` and more | How fast a boss walks; `dur` and `lat` in `BOSS_INFO` shape its attacks |
| Shop prices | `cost` in `data/items.json`, `shop_price` in `scripts/shop.gd` | `cost * (1 + 0.12 * (round_n - 1)) * (1 + 0.06 * buys so far this run)`, times `1 + 0.45 * level` for a tier item already bought, times 0.85 with HAGGLER, rounded to 5, at least 5 | The base costs are heal 70, packs 55 to 75, tiers 80 to 100 and 170 for the extra heart. On floor 10 the floor factor alone is 2.08 times the base, and every purchase of the run adds 6 % on top |
| Upgrade picks (the cards after a cleared round) | `upgrade_order` in `data/items.json`, `upgrade_ok` in `scripts/shop.gd` | free | Which tier items are offered; the pick itself costs nothing. The same ids are the tier items of the shop, where they cost cash |
| Cash earned | `add_cash` in `scripts/shop.gd` | `n * (1 + 0.08 * (round_n - 1))`, times 1.35 with BOUNTY | Every cash source below goes through this, so cash is worth more on later floors, and prices rise faster (0.12 a floor) than pay (0.08 a floor) |
| Cash sources | in code, see the next rows | rider 5 (armoured 13), CASH drop 15, perfect dodge 2, return to sender 12 (36 with BOUNTY HUNTER), a boss crashing 12 (angry cyclist 5), a boss beaten 55 (angry cyclist 18) | `riders.gd`, `pickups.gd`, `player.gd`, `combat.gd`, `bosses.gd` |
| Cache | `CACHE_CASH`, `CACHE_SCORE` in `scripts/objective.gd` | 25 cash and 750 score each | The reward of one cache |
| All caches | `ALL_CACHES_CASH`, `ALL_CACHES_SCORE` in `scripts/objective.gd` | 50 cash and 2500 score | The bonus for taking every cache of a round |
| Hearts | `MAXHEARTS` in `scripts/main.gd` (reset at the start of a run), the `heart` tier in `scripts/shop.gd` | 3 at the start of a run, 4 at most (one extra-heart upgrade) | PATCH UP gives 1 back, a heart drop gives 1, a rest node refills to the maximum |

Not in this table, but part of the feel of a round: the number of caches and the extraction rules (`scripts/objective.gd`), the arena size and style (`data/arena_rules.json`), the coin rates and unlock prices of the meta game (`data/unlocks.json`, tuned in D3) and the XP numbers (`data/xp.json`).

## `xp.json`

What earns XP and how fast the levels come (roadmap, Milestone I). Loaded by `scripts/xp.gd`; a missing or bad value is logged with `push_error` and replaced by the built-in number listed in `DEFAULTS` there. A finished run pays its XP once, when it ends (`Meta.award_run`); a run that is quit pays nothing. XP is never spent. The total is saved as `xp` in `meta.json` (see `docs/SAVE_FILES.md`) and the level is worked out from it.

| key | meaning |
|---|---|
| `score_per_xp` | points of score per XP, rounded down (at least 1) |
| `per_kill` | XP per rider or boss taken down |
| `per_round` | XP per round cleared (a won run counts every round) |
| `run_won` | extra XP for winning the run |
| `per_challenge` | XP per challenge done in the run (see `challenges.json`) |
| `boss` | `{"boss", "runner", "final"}`: XP for a boss, for the angry cyclist mini boss and for the final boss, on top of the kill XP |
| `level_base`, `level_step` | going from level 1 to level 2 takes `level_base` XP and every level after it takes `level_step` more than the one before |
| `max_level` | the top level, where the XP bar is full (at least 1) |

The numbers are still guesses, retuned once after the owner's first run went from level 1 to level 8 (about 4,200 XP in one run, because score at 1 XP per 20 points was most of it: scores run to tens of thousands). Now a score point is worth much less (1 XP per 150), and the fixed amounts (kills, rounds, win, challenges, bosses) are smaller too. The aim: a won run is worth roughly 1,000 to 1,300 XP and an early loss a few hundred, so one good run reaches level 3 or 4, level 10 (6,300 XP) takes about six won runs, level 20 (22,800 XP) about twenty, and the top level 50 (132,300 XP) over a hundred. The score of a typical run was estimated, not measured, so check it against a real run with `tools\run_xp_check.bat` and the XP row of the run summary, then tune `score_per_xp` first. Tune them with the balance pass in Milestone I.

## `weapons.json`

Tuning numbers for the player weapons: `dart_gun`, `dart_pistol` (the Dart Nerf Pistol) and `melee` (the gummy worm). Loaded by `scripts/weapons.gd`. A missing or non-numeric value is logged with `push_error` and replaced by a built-in fallback (listed in `weapons.gd`, same values as shipped), and unknown keys are logged and ignored, so check the Godot output panel after editing. There is no new weapon type here yet: adding one still needs code. The player carries one weapon in the **primary slot** (`scripts/weapon_slots.gd`): a weapon id from this file: `dart_pistol` (the starting weapon, owned from the first run) or `dart_gun` (bought on the Unlocks page for 250 coins, then chosen on the Loadout page, see `unlocks.json`). A weapon can only be put in the slot if it is listed in `PRIMARY_WEAPONS` there, and the scripts that fire, reload and upgrade the gun read the numbers of the weapon in the slot, so a new primary weapon needs an entry here and an entry there. `melee` is not a primary weapon: the gummy worm sits in the **melee slot**, which works the same way (`MELEE_WEAPONS` in `weapon_slots.gd`, read through `melee_stats()`). The third slot, the **gadget slot** (`GADGET_WEAPONS`, read through `gadget_stats()`), is empty because no gadget exists yet.

**`dart_gun` and `dart_pistol`** (same keys; the pistol is a one-dart-per-pull weapon with a smaller clip, a slower first pump and wider spread, so its upgrades matter)

| key | meaning |
|---|---|
| `start_clip`, `max_clip`, `clip_step` | darts per clip at the start of a run, the most the Extended Clip upgrade can reach, and how many it adds per level (whole numbers) |
| `pump_start`, `pump_min`, `pump_step` | seconds between shots at the start of a run, the fastest the Greased Slide upgrade can reach, and how much each level removes |
| `rapid_pump` | seconds between shots during the rapid-fire buff |
| `hype_pump_mul` | multiplier on the pump time while hype is active |
| `reload_step`, `reload_cut_per_level`, `reload_extra` | seconds per dart reloaded, the fraction each Speedloader level cuts, and the extra delay before reloading starts |
| `spread_hip`, `spread_aimed` | dart spread in degrees without and with aim-down-sights |
| `spread_move_extra` | extra spread fraction at full run speed (0.9 = up to 90% wider) |
| `spread_crouch_mul`, `spread_steady_mul` | spread multipliers while crouching and with the Steady Hands perk |
| `bloom_per_shot`, `bloom_max` | spread added by each shot and the cap (it decays on its own, see `main.gd`) |
| `range` | how far a dart flies before it stops, in metres |
| `damage` | damage per dart (whole number; Last Shell doubles it) |
| `semi_auto` | 1 = one dart per pull: a held gamepad trigger does not fire again until it is let go (the mouse always fires once per click); 0 = a held trigger keeps firing (whole number, 0 or 1) |

**`melee`**

| key | meaning |
|---|---|
| `cooldown`, `swing_time` | seconds between swings and the length of the swing animation |
| `zone_forward`, `zone_radius` | how far in front of the player the hit zone is centred, and its radius in metres |
| `reach_per_level` | metres added to the hit zone and the deflect range by each Melee Reach level |
| `deflect_range` | metres within which a swing sends a thrown phone back |
| `damage` | damage per swing to riders and bosses (whole number) |

Still in code, because they are not weapon tuning or are shared with other systems: dart hit-box sizes, boss and rider hit reactions, the upgrade level caps in `shop.gd`, and everything about thrown phones.

## `map_rules.json`

Numbers for the procedural run map (floors, widths, boss and prep floors, node type weights). Read by `scripts/map_gen.gd` (the run map generator; rounds do not follow the map yet). What each key means is in [`docs/MAP_GENERATION.md`](../docs/MAP_GENERATION.md).

## `unlocks.json`

What the player can buy with meta coins (see `scripts/meta.gd`) and the price of each thing. Loaded by `scripts/unlocks.gd`; bad entries are skipped and logged with `push_error`, so check the Godot output panel after editing. Only the Unlocks page of the title menu reads it so far (`g.UNLOCKS`, from `Content.UNLOCK_TABLE`); buying happens there too (the ids bought are saved in `meta.json`, see `docs/SAVE_FILES.md`). Owning a `starting_perk` unlock lets the player choose that perk on the Loadout page, and a normal run then starts with it (a Daily Run or a typed seed does not). Owning a `shop_item` puts that item in the shop: until it is bought `shop_ok` (`scripts/shop.gd`) leaves it out of every shop, through `g.shop_item_owned` in `scripts/main.gd` (alpha C3); every item that is not a `shop_item` unlock, and the heal, is always sold.

```
{
  "price_curve": [60, 120, 250, 450, 750],   // coins for tier 1, 2, 3, ...; whole numbers above 0 that get bigger
  "unlocks": [ {entry}, ... ]                // the order is the order of the Unlocks page
}
```

Every entry has `id` (unique), `kind`, `target` and `tier` (1 to the length of the price curve). The price is `price_curve[tier - 1]`, so the whole curve is tuned in one place; an entry can set its own `cost` (a whole number from 0) when one price needs to differ.

| kind | `target` | name and text | what buying it will do |
|---|---|---|---|
| `starting_perk` | a perk id from `perks.json` | taken from the perk | the perk can be chosen to start a run with |
| `shop_item` | an item id from `items.json` (not the heal, which is always on sale) | taken from the item | the item joins the shop pool once bought; until then no shop sells it (a normal run, the Daily Run and a custom seed alike) |
| `weapon` | a weapon id: a new id for a weapon that does not exist yet (`planned`), or an existing primary weapon that is held back until bought (`dart_gun`) | `name` and `desc` are written in the entry | the weapon can be chosen on the Loadout page for its slot once bought (Milestone C); it does not join the shop pool |
| `cosmetic` | a new id | `name` and `desc` are written in the entry | the skin can be equipped (Milestone B); no entries yet, each one is added with its art |

`planned: true` marks an entry whose target is not in the game yet (the four new weapons of Milestone C today; the dart gun exists and is not planned); the Unlocks page should show those as coming soon or leave them out. It is refused on a perk or an item, which exist. A thing can be unlocked once.

**Anything that is not listed is available from the first run.** So the table only holds what is held back: today all 14 perks as starting perks, six shop items (POCKET MAGNET, HYPE PACK, LUCKY CHARM, HYPE MACHINE, SHIELD PACK, THICK SKIN), the dart gun (`weapon_dart_gun`, tier 3, so 250 coins, the first weapon to buy) and the four weapons of Milestone C.

**The price curve is a first guess.** A run pays 2 coins per round cleared, 3 for the mid boss (1 for the angry cyclist), 8 for the final boss, 1 coin per 100,000 points of score (at most 5) and the coins of its challenges (`scripts/meta.gd`, `challenges.json`). That is about 40 coins for a complete run and a few coins for a run lost in the first rounds. Tier 1 (60) is meant to be reachable in one or two good runs, the dart gun (250, tier 3) takes 6 to 7 complete runs, and buying everything listed takes 4,290 coins (about 107 complete runs: the price curve is still the first guess, see D3). Tune the numbers after real runs, in the balance pass of Milestone I.

Decided with the owner when the shop filter was built (alpha C3): the Daily Run and a custom seed use the same shop filter as a normal run. The filter only changes which items are in the pool, never the seeded draws (`offer_shuffle`), so two players with the same seed and the same unlocks get the same shops, but a player who owns a `shop_item` unlock sees a different shop from one who does not. A Daily Run still starts without a starting perk.
## `challenges.json`

The meta challenges: small goals that pay meta coins (Milestone B, "Earn from challenges"). Loaded by `scripts/challenges.gd`, which also watches the run for each condition and pays the coins with the run; bad entries are skipped and logged with `push_error`, so check the Godot output panel after editing. They show on the run summary and on the CHALLENGES page of the title menu.

```
{
  "challenges": [ {entry}, ... ]     // the order is the order a page will list them in
}
```

| key | meaning |
|---|---|
| `id` | unique text id, never changed once shipped (a save counter and later achievements point at it) |
| `name` | short shouted title, like the shop items; it is also the name of the achievement |
| `icon` | optional, the small badge drawn next to the name on the CHALLENGES page: `no_gun`, `crate`, `chevrons`, `heart`, `clock` or `star` (the default; an unknown name is logged and becomes `star`). A new icon needs a drawing in `_draw_badge` in `scripts/hud.gd` |
| `desc` | the goal in plain words, shown on the page and the run summary |
| `condition` | what the game watches, one of the keys below; a new key needs code in `challenges.gd` |
| `scope` | `round` (checked at the end of each round) or `run` (checked across the run, or at its end) |
| `target` | the number to reach: 1 for yes or no goals, 5 riders in a row for `perfect_dodge_streak`, and a maximum of seconds for `run_time_under` (1200 is 20 minutes) |
| `reward` | meta coins paid when the challenge is done |
| `counter` | name of the field in the save file (`meta.json`) that counts how many times the challenge was done; a new field with a default needs no version bump, see [`docs/SAVE_FILES.md`](../docs/SAVE_FILES.md) |

| condition | met when |
|---|---|
| `round_no_gun` | a round is cleared and no dart was fired in it (the melee does not count) |
| `all_caches_before_last_rider` | every cache of a round was taken while riders (or a boss) were still up, so before the extraction point opened; the round must then be cleared |
| `perfect_dodge_streak` | `target` perfect dodges happen with no life lost in between (a lost life ends the streak) |
| `round_no_life_lost` | a round is cleared with no life lost in it |
| `run_time_under` | the run is won in fewer than `target` seconds (fighting and shopping, the RUN TIME of the summary) |

Achievements are the same list: a challenge done at least once, ever, is an unlocked achievement (the badge turns gold and the page counts them), so they need no save field of their own.

The coins are paid when the run ends, together with the score and boss coins (a run that is quit pays nothing). Challenges done in a run are counted in `meta.json` under `challenges`, by `counter`; the run summary marks a challenge NEW the first time it is ever done.

How the numbers were chosen, so they are easy to change: a boss pays 5 coins and the final boss 20, so the easy goals pay 3 to 5 and the 20 minute run pays 10. A challenge pays at most once per run (the counter still counts every run it was done in), so it cannot be farmed inside one run. Both are first guesses to tune once the challenges can be played.

The export preset includes `data/*.json`, so the file ships with the game. `tools\run_challenges_check.bat` checks the loader, every condition, the payout and the save file.
