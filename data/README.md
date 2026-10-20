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

**Keep the order of both lists unless you mean to change it:** a Daily Run shuffles these lists with a seeded generator, so reordering changes what every player sees for the same seed.

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
**Keep the order unless you mean to change it**, for the same Daily Run reason as above.

What a perk *does* is still coded where it applies, by id (`g.perks.has("deadeye")` and so on in `combat.gd`, `player.gd`, `pickups.gd`, `bosses.gd`, `main.gd`), and duo effects are checked by name with `has_duo(...)`. A new perk or duo therefore needs code too; the table only holds its name, text, price and pairing.
