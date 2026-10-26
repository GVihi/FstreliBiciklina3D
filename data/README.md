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

Every entry has `id`, `kind` (`heal`, `pack` or `tier`), `name`, `desc`, `cost` (base price in dollars) and `min` (first round it can appear in).

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
  "perks": [ {"id", "name", "desc", "cost", "min"}, ... ],   // shop pool order, after the items in items.json
  "duos":  [ {"a", "b", "name", "desc"}, ... ]               // "a" and "b" are perk ids
}
```

`cost` and `min` mean the same as for items. A duo needs two different perks that exist in the file, and duo names must be unique (the game looks a duo up by name).
**Keep the order unless you mean to change it**, for the same seeded-run reason as above.

What a perk *does* is still coded where it applies, by id (`g.perks.has("deadeye")` and so on in `combat.gd`, `player.gd`, `pickups.gd`, `bosses.gd`, `main.gd`), and duo effects are checked by name with `has_duo(...)`. A new perk or duo therefore needs code too; the table only holds its name, text, price and pairing.

## `weapons.json`

Tuning numbers for the two player weapons, `dart_gun` and `melee` (the gummy worm). Loaded by `scripts/weapons.gd`. A missing or non-numeric value is logged with `push_error` and replaced by a built-in fallback (listed in `weapons.gd`, same values as shipped), and unknown keys are logged and ignored, so check the Godot output panel after editing. There is no new weapon type here yet: adding one still needs code.

**`dart_gun`**

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
