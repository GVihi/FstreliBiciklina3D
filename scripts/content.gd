extends RefCounted
const Items = preload("res://scripts/items.gd")
const Perks = preload("res://scripts/perks.gd")
const Weapons = preload("res://scripts/weapons.gd")
# Game content tables: round messages, rider types, themes, boss stats, drops, perks, duos and upgrades.
# Shop items, packs and upgrade tiers live in data/items.json (items.gd); perks and duos in data/perks.json (perks.gd);
# weapon tuning (dart gun, melee) in data/weapons.json (weapons.gd).
# Pure data, no behaviour. main.gd re-exports each table under the same name, so other scripts (hud.gd) keep reading g.NAME.
# These are static vars, not consts, because the colour tables call Color.html().

static var OVER_MSG = {
	"run": "RUN OVER ON THE ROAD",
	"civ": "TOO MANY PEDESTRIANS HIT",
	"riders": "TOO MANY RIDERS GOT AWAY",
	"boss": "THE BOSSES GOT YOU",
	"phone": "TOO MANY MISSED CALLS"
}
static var TYPES = {
	"pro": {"sp": 1.0, "pts": 1.0},
	"sprinter": {"sp": 1.4, "pts": 1.6},
	"courier": {"sp": 0.72, "pts": 0.8},
	"tough": {"sp": 0.85, "pts": 2.2}
}
static var THEMES = [
	{
		"name": "DAY",
		"top": Color.html("#4f98d8"),
		"hor": Color.html("#dbe9ee"),
		"sun": Color.html("#fff4e0"),
		"sun_e": 1.1,
		"sun_x": -55.0,
		"sun_y": -30.0,
		"amb": Color(0.62, 0.68, 0.76),
		"amb_e": 0.75,
		"lamps": false,
		"lit": 0.0
	},
	{
		"name": "GOLDEN HOUR",
		"top": Color.html("#6d9bd0"),
		"hor": Color.html("#f7d9a8"),
		"sun": Color.html("#ffb865"),
		"sun_e": 1.2,
		"sun_x": -16.0,
		"sun_y": -60.0,
		"amb": Color(0.78, 0.66, 0.55),
		"amb_e": 0.7,
		"lamps": false,
		"lit": 0.4
	},
	{
		"name": "DUSK",
		"top": Color.html("#2c3770"),
		"hor": Color.html("#f09a68"),
		"sun": Color.html("#ff8a5a"),
		"sun_e": 0.55,
		"sun_x": -7.0,
		"sun_y": -70.0,
		"amb": Color(0.42, 0.38, 0.55),
		"amb_e": 0.7,
		"lamps": true,
		"lit": 1.2
	},
	{
		"name": "NIGHT",
		"top": Color.html("#050a1e"),
		"hor": Color.html("#26345c"),
		"sun": Color.html("#8fa8ff"),
		"sun_e": 0.3,
		"sun_x": -45.0,
		"sun_y": 35.0,
		"amb": Color(0.22, 0.27, 0.45),
		"amb_e": 0.8,
		"lamps": true,
		"lit": 2.0
	}
]
static var BOSS_KINDS = ["mower", "wifi", "minister"]
static var BOSS_INFO = {
	"mower":
	{
		"name": "ROGUE LUBA",
		"hp": 16,
		"dur": 6.0,
		"lat": 150.0,
		"cy": 0.5,
		"r": Vector3(1.0, 0.6, 0.85),
		"voice": "boss_mower",
		"weak_y": 0.62,
		"wk": 0.85,
		"speed": 4.4
	},
	"wifi":
	{
		"name": "MESH WIFI ADAPTER",
		"hp": 16,
		"dur": 6.5,
		"lat": 95.0,
		"cy": 1.0,
		"r": Vector3(0.6, 1.2, 0.6),
		"voice": "boss_wifi",
		"weak_y": 1.3,
		"wk": 1.5,
		"speed": 3.6
	},
	"minister":
	{
		"name": "MINISTER MIKROFON",
		"hp": 22,
		"dur": 8.0,
		"lat": 125.0,
		"cy": 1.0,
		"r": Vector3(0.7, 1.15, 0.6),
		"voice": "boss_minister",
		"weak_y": 1.55,
		"wk": 1.8,
		"speed": 3.8
	},
	"runner":
	{
		"name": "ANGRY CYCLIST",
		"hp": 3,
		"dur": 3.2,
		"lat": 150.0,
		"cy": 0.95,
		"r": Vector3(0.62, 1.05, 0.5),
		"voice": "boss_runner",
		"weak_y": 1.55,
		"wk": 1.8,
		"speed": 5.6
	}
}
static var CHEER_PX = [108.0, 146.0, 184.0, 612.0, 650.0, 688.0]
static var DROPS = [
	"heart", "rapid", "rapid", "big", "big", "slow", "shield", "shield", "cash", "cash", "ammo"
]
static var DROP_INFO = {
	"heart": {"col": Color.html("#e5533d"), "ch": "+", "name": "EXTRA LIFE"},
	"rapid": {"col": Color.html("#ff7a1a"), "ch": "R", "name": "RAPID FIRE"},
	"big": {"col": Color.html("#58b36a"), "ch": "B", "name": "FAT DARTS"},
	"slow": {"col": Color.html("#4a90d6"), "ch": "S", "name": "SLOW MO"},
	"shield": {"col": Color.html("#9a62c8"), "ch": "O", "name": "SHIELD"},
	"cash": {"col": Color.html("#f2b630"), "ch": "$", "name": "CASH +$15"},
	"ammo": {"col": Color.html("#ffb13a"), "ch": "A", "name": "AMMO +2"}
}
# things you can buy between rounds.
#   kind "heal" / "pack" (one-round consumable, can be bought again every shop) / "tier" (an upgrade that goes up in levels,
#   each level costs more) come from data/items.json (see items.gd and data/README.md).
#   kind "perk" (bought once, combines with other perks into a duo, see DUOS) comes from data/perks.json.
#   "min" = first round it can show up in.
static var ITEM_TABLE = Items.load_table()
static var PERK_TABLE = Perks.load_table()
static var PERKS = PERK_TABLE["perks"]
# the order matters: it feeds the Daily Run shuffles, so items stay first and perks last, as before
static var SHOP_POOL = ITEM_TABLE["items"] + PERKS
static var DUOS = PERK_TABLE["duos"]
static var UPGRADES = ITEM_TABLE["upgrades"]
static var WEAPONS = Weapons.load_table()
