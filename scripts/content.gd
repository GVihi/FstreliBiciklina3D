extends RefCounted
# Game content tables: round messages, rider types, themes, boss stats, drops, shop items, duos and upgrades.
# Pure data, no behaviour. main.gd re-exports each table under the same name, so other scripts (hud.gd) keep reading g.NAME.
# These are static vars, not consts, because the colour tables call Color.html().

static var OVER_MSG = {"run": "RUN OVER ON THE ROAD", "civ": "TOO MANY PEDESTRIANS HIT", "riders": "TOO MANY RIDERS GOT AWAY",
	"boss": "THE BOSSES GOT YOU", "phone": "TOO MANY MISSED CALLS"}
static var TYPES = {
	"pro": {"sp": 1.0, "pts": 1.0},
	"sprinter": {"sp": 1.4, "pts": 1.6},
	"courier": {"sp": 0.72, "pts": 0.8},
	"tough": {"sp": 0.85, "pts": 2.2}
}
static var THEMES = [
	{"name": "DAY", "top": Color.html("#4f98d8"), "hor": Color.html("#dbe9ee"), "sun": Color.html("#fff4e0"),
		"sun_e": 1.1, "sun_x": -55.0, "sun_y": -30.0, "amb": Color(0.62, 0.68, 0.76), "amb_e": 0.75, "lamps": false, "lit": 0.0},
	{"name": "GOLDEN HOUR", "top": Color.html("#6d9bd0"), "hor": Color.html("#f7d9a8"), "sun": Color.html("#ffb865"),
		"sun_e": 1.2, "sun_x": -16.0, "sun_y": -60.0, "amb": Color(0.78, 0.66, 0.55), "amb_e": 0.7, "lamps": false, "lit": 0.4},
	{"name": "DUSK", "top": Color.html("#2c3770"), "hor": Color.html("#f09a68"), "sun": Color.html("#ff8a5a"),
		"sun_e": 0.55, "sun_x": -7.0, "sun_y": -70.0, "amb": Color(0.42, 0.38, 0.55), "amb_e": 0.7, "lamps": true, "lit": 1.2},
	{"name": "NIGHT", "top": Color.html("#050a1e"), "hor": Color.html("#26345c"), "sun": Color.html("#8fa8ff"),
		"sun_e": 0.3, "sun_x": -45.0, "sun_y": 35.0, "amb": Color(0.22, 0.27, 0.45), "amb_e": 0.8, "lamps": true, "lit": 2.0}
]
static var BOSS_KINDS = ["mower", "wifi", "minister"]
static var BOSS_INFO = {
	"mower": {"name": "ROGUE LUBA", "hp": 16, "dur": 6.0, "lat": 150.0, "cy": 0.5, "r": Vector3(1.0, 0.6, 0.85),
		"voice": "boss_mower", "weak_y": 0.62, "wk": 0.85, "speed": 4.4},
	"wifi": {"name": "MESH WIFI ADAPTER", "hp": 16, "dur": 6.5, "lat": 95.0, "cy": 1.0, "r": Vector3(0.6, 1.2, 0.6),
		"voice": "boss_wifi", "weak_y": 1.3, "wk": 1.5, "speed": 3.6},
	"minister": {"name": "MINISTER MIKROFON", "hp": 22, "dur": 8.0, "lat": 125.0, "cy": 1.0, "r": Vector3(0.7, 1.15, 0.6),
		"voice": "boss_minister", "weak_y": 1.55, "wk": 1.8, "speed": 3.8},
	"runner": {"name": "ANGRY CYCLIST", "hp": 3, "dur": 3.2, "lat": 150.0, "cy": 0.95, "r": Vector3(0.62, 1.05, 0.5),
		"voice": "boss_runner", "weak_y": 1.55, "wk": 1.8, "speed": 5.6}
}
static var CHEER_PX = [108.0, 146.0, 184.0, 612.0, 650.0, 688.0]
static var DROPS = ["heart", "rapid", "rapid", "big", "big", "slow", "shield", "shield", "cash", "cash", "ammo"]
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
#   each level costs more) / "perk" (bought once, combines with other perks into a duo, see DUOS).
#   "min" = first round it can show up in.
static var SHOP_POOL = [
	{"id": "heal", "kind": "heal", "name": "PATCH UP", "desc": "+1 life", "cost": 70, "min": 1},
	{"id": "pack_rapid", "kind": "pack", "name": "RAPID PACK", "desc": "Next round starts with 25 s of rapid fire", "cost": 60, "min": 1},
	{"id": "pack_fat", "kind": "pack", "name": "FAT DART PACK", "desc": "Next round starts with 25 s of fat darts", "cost": 55, "min": 1},
	{"id": "pack_shield", "kind": "pack", "name": "SHIELD PACK", "desc": "Next round starts with a shield", "cost": 70, "min": 1},
	{"id": "pack_hype", "kind": "pack", "name": "HYPE PACK", "desc": "Next round starts with the hype bar full", "cost": 65, "min": 1},
	{"id": "pack_free", "kind": "pack", "name": "FREE DARTS", "desc": "Your first 12 darts next round cost no ammo", "cost": 75, "min": 1},
	{"id": "clip", "kind": "tier", "name": "EXTENDED CLIP", "desc": "+2 darts per clip", "cost": 100, "min": 1},
	{"id": "pump", "kind": "tier", "name": "GREASED SLIDE", "desc": "Faster pump action", "cost": 90, "min": 1},
	{"id": "speedload", "kind": "tier", "name": "SPEEDLOADER", "desc": "Reload 22% faster", "cost": 85, "min": 1},
	{"id": "wide", "kind": "tier", "name": "FAT DARTS", "desc": "Bigger dart hit area", "cost": 95, "min": 1},
	{"id": "dashcd", "kind": "tier", "name": "RUNNING SHOES", "desc": "Dash cooldown -0.15 s", "cost": 90, "min": 1},
	{"id": "magnet", "kind": "tier", "name": "POCKET MAGNET", "desc": "Drops are pulled towards you", "cost": 80, "min": 1},
	{"id": "rubber", "kind": "tier", "name": "MELEE REACH", "desc": "Melee reaches further", "cost": 85, "min": 1},
	{"id": "hype", "kind": "tier", "name": "HYPE MACHINE", "desc": "Hype fills 50% faster", "cost": 90, "min": 2},
	{"id": "luck", "kind": "tier", "name": "LUCKY CHARM", "desc": "More bonus drops", "cost": 95, "min": 2},
	{"id": "heart", "kind": "tier", "name": "THICK SKIN", "desc": "+1 max life and heal 1", "cost": 170, "min": 2},
	{"id": "haggler", "kind": "perk", "name": "HAGGLER", "desc": "Everything in the shop costs 15% less", "cost": 110, "min": 1},
	{"id": "steady", "kind": "perk", "name": "STEADY HANDS", "desc": "30% less dart spread", "cost": 105, "min": 1},
	{"id": "salvage", "kind": "perk", "name": "SALVAGE", "desc": "Armoured riders always drop ammo", "cost": 100, "min": 1},
	{"id": "sprinter", "kind": "perk", "name": "SPRINTER", "desc": "Sprint 12% faster", "cost": 110, "min": 2},
	{"id": "slideshot", "kind": "perk", "name": "SLIDE SHOT", "desc": "Dash or slide: your next 3 darts are free", "cost": 130, "min": 2},
	{"id": "bounty", "kind": "perk", "name": "BOUNTY", "desc": "All cash you earn x1.35", "cost": 120, "min": 2},
	{"id": "adrenaline", "kind": "perk", "name": "ADRENALINE", "desc": "Dash cooldown -40%", "cost": 125, "min": 2},
	{"id": "scavenger", "kind": "perk", "name": "SCAVENGER", "desc": "Ammo drops are twice as big and more common", "cost": 105, "min": 2},
	{"id": "counter", "kind": "perk", "name": "COUNTER", "desc": "Deflecting a phone refunds 1 dart", "cost": 115, "min": 2},
	{"id": "closeshave", "kind": "perk", "name": "CLOSE SHAVE", "desc": "Every 2nd perfect dodge heals 1 life", "cost": 150, "min": 3},
	{"id": "lastshell", "kind": "perk", "name": "LAST SHELL", "desc": "The last dart in your clip hits twice as hard", "cost": 135, "min": 3},
	{"id": "deadeye", "kind": "perk", "name": "DEADEYE", "desc": "Weak spot hits deal +1 extra damage", "cost": 140, "min": 3},
	{"id": "boomerang", "kind": "perk", "name": "BOOMERANG", "desc": "A deflected phone chains on to 2 more targets", "cost": 155, "min": 3},
	{"id": "secondwind", "kind": "perk", "name": "SECOND WIND", "desc": "Once per round a deadly hit leaves you on 1 life", "cost": 170, "min": 3}
]
static var DUOS = [
	{"a": "slideshot", "b": "closeshave", "name": "MATADOR", "desc": "Perfect dodges refill 3 darts"},
	{"a": "boomerang", "b": "bounty", "name": "BOUNTY HUNTER", "desc": "Deflect kills pay x3 cash"},
	{"a": "slideshot", "b": "bounty", "name": "QUICK DRAW", "desc": "Dash / slide gives 5 free darts"},
	{"a": "adrenaline", "b": "closeshave", "name": "GHOST", "desc": "Dash invulnerability lasts 0.15 s longer"},
	{"a": "deadeye", "b": "scavenger", "name": "HEADHUNTER", "desc": "Weak spot hits refund 2 darts"},
	{"a": "secondwind", "b": "bounty", "name": "LIFE INSURANCE", "desc": "Second wind pays $80"},
	{"a": "lastshell", "b": "deadeye", "name": "SNIPER", "desc": "Weak spot hit with the last dart: +2 damage"},
	{"a": "salvage", "b": "scavenger", "name": "SCRAPYARD", "desc": "Armoured riders drop two ammo and cash"},
	{"a": "counter", "b": "boomerang", "name": "RICOCHET", "desc": "Deflected phones chain on to 4 targets"},
	{"a": "sprinter", "b": "adrenaline", "name": "SPEEDSTER", "desc": "Dash cooldown a further -20%"}
]
static var UPGRADES = [
	{"id": "clip", "name": "EXTENDED CLIP", "desc": "+2 darts per clip"},
	{"id": "pump", "name": "GREASED SLIDE", "desc": "Faster pump action"},
	{"id": "wide", "name": "FAT DARTS", "desc": "Bigger dart hit area"},
	{"id": "heart", "name": "THICK SKIN", "desc": "+1 max life and heal 1"},
	{"id": "rubber", "name": "MELEE REACH", "desc": "Melee reaches further"},
	{"id": "hype", "name": "HYPE MACHINE", "desc": "Hype fills 50% faster"},
	{"id": "luck", "name": "LUCKY CHARM", "desc": "More bonus drops"},
	{"id": "speedload", "name": "SPEEDLOADER", "desc": "Reload 22% faster"},
	{"id": "dashcd", "name": "RUNNING SHOES", "desc": "Dash cooldown -0.15 s"},
	{"id": "magnet", "name": "POCKET MAGNET", "desc": "Drops are pulled towards you"}
]
