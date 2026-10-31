extends RefCounted
# Loads every player weapon from res://data/weapons.json: its tuning numbers (what `g.primary_stats()`,
# `g.melee_stats()` and `g.gadget_stats()` return) and its `info` (the slot it sits in, its HUD name, the name and text
# of the Loadout page, its shot sound and its first-person model). The file is the one place a weapon is listed:
# scripts/weapon_slots.gd builds its slot tables from it, so a new weapon is a new entry in the file (data/README.md,
# "Adding a weapon"), with no change here.
# JSON numbers arrive as floats; whole-number fields are cast to int. A missing or invalid value is logged with
# push_error and replaced, so a typo cannot crash a run: a missing number takes the value of the slot's base weapon
# (the dart pistol for a primary weapon, the gummy worm for a melee weapon), a weapon with a broken `info` is left out.
# The built-in values below are only the safety net for a missing file: the two weapons every run starts with.

const PATH = "res://data/weapons.json"
const SLOTS = ["primary", "melee", "gadget"]
# the weapon whose numbers fill in what another weapon of the same slot leaves out (the slot's default weapon)
const BASE = {"primary": "dart_pistol", "melee": "melee"}
# fields that must be integers
const WHOLE = ["start_clip", "max_clip", "clip_step", "damage", "semi_auto", "pellets", "uses"]
# numbers a weapon may have on top of its slot's required ones: the ones only some weapons use. A new tuning number
# that a weapon's code reads is added here (and to WHOLE when it is a whole number) and described in data/README.md;
# a key that is in neither place is logged as a typo and ignored.
const OPTIONAL = ["pellets", "sweep_arc", "place_dist", "trigger_radius", "stun_time"]
# what a gadget must have (there is no gadget to copy from): uses per round (0 = no limit) and seconds between uses
# (0 = none); a gadget that has neither limit is refused by tools/weapon_registry_check.gd
const GADGET_REQUIRED = {"uses": 0, "cooldown": 0.0}
const INFO_TEXT_KEYS = ["desc", "sound", "model"]
const FALLBACK = {
	"dart_pistol":
	{
		"start_clip": 1,
		"max_clip": 4,
		"clip_step": 1,
		"pump_start": 0.26,
		"pump_min": 0.14,
		"pump_step": 0.03,
		"rapid_pump": 0.08,
		"hype_pump_mul": 0.65,
		"reload_step": 0.45,
		"reload_cut_per_level": 0.22,
		"reload_extra": 0.1,
		"spread_hip": 2.6,
		"spread_aimed": 0.35,
		"spread_move_extra": 0.7,
		"spread_crouch_mul": 0.7,
		"spread_steady_mul": 0.7,
		"bloom_per_shot": 0.6,
		"bloom_max": 1.8,
		"range": 70.0,
		"damage": 1,
		"semi_auto": 1
	},
	"melee":
	{
		"cooldown": 0.3,
		"swing_time": 0.26,
		"zone_forward": 2.3,
		"zone_radius": 1.5,
		"reach_per_level": 0.3,
		"deflect_range": 2.7,
		"damage": 2
	}
}
const FALLBACK_INFO = {
	"dart_pistol":
	{
		"slot": "primary",
		"hud": "PISTOL",
		"name": "DART NERF PISTOL",
		"desc": "THE STARTING WEAPON: ONE DART PER PULL, SMALL CLIP, QUICK HANDS",
		"sound": "shot",
		"model": "dart_pistol"
	},
	"melee":
	{
		"slot": "melee",
		"hud": "MELEE",
		"name": "GUMMY WORM",
		"desc": "THE GIANT GUMMY WORM: SWING IT AT RIDERS AND INCOMING PHONES",
		"sound": "",
		"model": ""
	}
}


# The numbers every weapon of a slot must have, with the value used when one is missing; {} for an unknown slot.
static func required_numbers(slot: String) -> Dictionary:
	if slot == "gadget":
		return GADGET_REQUIRED
	if BASE.has(slot):
		return FALLBACK[BASE[slot]]
	return {}


# Returns {"stats": {id: numbers}, "info": {id: info}}, both in the order of the file. A weapon the file leaves out
# that the game cannot start without (the dart pistol and the gummy worm) is added from the built-in values.
static func load_all(path: String = PATH) -> Dictionary:
	var data = _read(path)
	var stats = {}
	var info = {}
	for id in data:
		var raw = data[id]
		if typeof(raw) != TYPE_DICTIONARY:
			push_error('weapons: "%s" must be an object, ignored' % str(id))
			continue
		var inf = _clean_info(str(id), raw.get("info"))
		if inf.is_empty():
			continue
		info[str(id)] = inf
		stats[str(id)] = _clean_numbers(str(id), str(inf["slot"]), raw)
	for id in FALLBACK:
		if not stats.has(id):
			push_error('weapons: "%s" is missing from %s, using built-in values' % [id, path])
			stats[id] = FALLBACK[id].duplicate()
			info[id] = FALLBACK_INFO[id].duplicate()
	return {"stats": stats, "info": info}


# returns {id: numbers} of every weapon, gadget and melee weapon (what the game reads as `WEAPONS`)
static func load_table(path: String = PATH) -> Dictionary:
	return load_all(path)["stats"]


# returns {id: {"slot", "hud", "name", "desc", "sound", "model"}} of every weapon
static func load_info(path: String = PATH) -> Dictionary:
	return load_all(path)["info"]


# the weapons of one slot as {id: HUD name}, in the order of `info` (the file)
static func hud_names(info: Dictionary, slot: String) -> Dictionary:
	var out = {}
	for id in info:
		if info[id]["slot"] == slot:
			out[id] = info[id]["hud"]
	return out


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error(
			(
				"weapons: %s is missing, using built-in values. Check the export include filter (data/*.json)."
				% path
			)
		)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error(
			(
				"weapons: %s is not valid, expected an object with one entry per weapon, using built-in values"
				% path
			)
		)
		return {}
	return parsed


# the cleaned "info" of a weapon, or {} when it cannot be used (the reason is logged)
static func _clean_info(id: String, raw) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		push_error('weapons: "%s" has no "info" object (slot, hud, name), ignored' % id)
		return {}
	var slot = raw.get("slot")
	if typeof(slot) != TYPE_STRING or not SLOTS.has(slot):
		push_error(
			"weapons: %s.info.slot must be one of %s, the weapon is ignored" % [id, str(SLOTS)]
		)
		return {}
	var out = {"slot": slot}
	for key in ["hud", "name"]:
		var v = raw.get(key)
		if typeof(v) != TYPE_STRING or str(v).strip_edges() == "":
			push_error("weapons: %s.info.%s needs text, the weapon is ignored" % [id, key])
			return {}
		out[key] = str(v).strip_edges()
	for key in INFO_TEXT_KEYS:
		var v = raw.get(key, "")
		if typeof(v) != TYPE_STRING:
			push_error('weapons: %s.info.%s needs text, using ""' % [id, key])
			v = ""
		out[key] = v
	if out["sound"] == "" and slot == "primary":
		out["sound"] = "shot"  # the baked shot every weapon makes unless it names another sound
	for key in raw:
		if not out.has(key):
			push_error(
				"weapons: %s.info.%s is not a known setting (typo?), ignored" % [id, str(key)]
			)
	return out


static func _clean_numbers(id: String, slot: String, raw: Dictionary) -> Dictionary:
	var required = required_numbers(slot)
	var w = {}
	for key in required:
		var v = raw.get(key)
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			push_error("weapons: %s.%s needs a number, using %s" % [id, key, str(required[key])])
			v = required[key]
		w[key] = _cast(key, v)
	for key in raw:
		if key == "info" or required.has(key):
			continue
		var v = raw[key]
		if OPTIONAL.has(key) and (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT):
			w[key] = _cast(key, v)
		else:
			push_error("weapons: %s.%s is not a known setting (typo?), ignored" % [id, str(key)])
	return w


static func _cast(key: String, v):
	return int(v) if WHOLE.has(key) else float(v)
