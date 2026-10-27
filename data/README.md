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

What the player can buy with meta coins (see `scripts/meta.gd`) and the price of each thing. Loaded by `scripts/unlocks.gd`; bad entries are skipped and logged with `push_error`, so check the Godot output panel after editing. Only the Unlocks page of the title menu reads it so far (`g.UNLOCKS`, from `Content.UNLOCK_TABLE`); buying happens there too (the ids bought are saved in `meta.json`, see `docs/SAVE_FILES.md`). Owning a `starting_perk` unlock lets the player choose that perk on the Loadout page, and a normal run then starts with it (a Daily Run or a typed seed does not). Owning a `shop_item` has no effect yet: the shop filter is a separate item of Milestone I in the README.

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
| `shop_item` | an item id from `items.json` (not the heal, which is always on sale) | taken from the item | the item joins the shop pool |
| `weapon` | a weapon id: a new id for a weapon that does not exist yet (`planned`), or an existing primary weapon that is held back until bought (`dart_gun`) | `name` and `desc` are written in the entry | the weapon can be chosen on the Loadout page for its slot once bought (Milestone C); it does not join the shop pool |
| `cosmetic` | a new id | `name` and `desc` are written in the entry | the skin can be equipped (Milestone B); no entries yet, each one is added with its art |

`planned: true` marks an entry whose target is not in the game yet (the four new weapons of Milestone C today; the dart gun exists and is not planned); the Unlocks page should show those as coming soon or leave them out. It is refused on a perk or an item, which exist. A thing can be unlocked once.

**Anything that is not listed is available from the first run.** So the table only holds what is held back: today all 14 perks as starting perks, six shop items (POCKET MAGNET, HYPE PACK, LUCKY CHARM, HYPE MACHINE, SHIELD PACK, THICK SKIN), the dart gun (`weapon_dart_gun`, tier 3, so 250 coins, the first weapon to buy) and the four weapons of Milestone C.

**The price curve is a first guess.** A finished run pays about 1 coin per 100 points plus 5 per boss and 20 for the final boss (`scripts/meta.gd`), so roughly 60 to 400 coins depending on how far it got. Tier 1 (60) is meant to be affordable after one short run, tier 5 (750) after several good ones, and buying everything listed takes 5,690 coins. Tune the numbers after real runs, in the balance pass of Milestone I.

Not decided here, because it changes how runs play: a shop that skips the unlocked-only items means a seed no longer offers the same items to every player, so the Daily Run (and a custom seed) will probably need the full pool and no starting perk. Decide that when the shop filter is built.
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
