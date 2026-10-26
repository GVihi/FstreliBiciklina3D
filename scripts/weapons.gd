extends RefCounted
# Loads the player weapon tuning (dart gun, dart pistol and melee worm) from res://data/weapons.json.
# What each number does is documented in data/README.md. JSON numbers arrive as floats; whole-number fields are cast to int.
# A missing or invalid value is logged with push_error and replaced by the fallback below, so a typo cannot crash a run.
# The fallback values mirror data/weapons.json as shipped; the JSON file is the one to edit.

const PATH = "res://data/weapons.json"
const WHOLE = ["start_clip", "max_clip", "clip_step", "damage", "semi_auto"]  # fields that must be integers
const FALLBACK = {
	"dart_gun":
	{
		"start_clip": 6,
		"max_clip": 12,
		"clip_step": 2,
		"pump_start": 0.2,
		"pump_min": 0.1,
		"pump_step": 0.035,
		"rapid_pump": 0.08,
		"hype_pump_mul": 0.65,
		"reload_step": 0.38,
		"reload_cut_per_level": 0.22,
		"reload_extra": 0.12,
		"spread_hip": 2.2,
		"spread_aimed": 0.25,
		"spread_move_extra": 0.9,
		"spread_crouch_mul": 0.7,
		"spread_steady_mul": 0.7,
		"bloom_per_shot": 0.5,
		"bloom_max": 1.6,
		"range": 80.0,
		"damage": 1,
		"semi_auto": 0
	},
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


# returns {"dart_gun": {...}, "dart_pistol": {...}, "melee": {...}}, every key of FALLBACK present with the right type
static func load_table() -> Dictionary:
	var data = {}
	if not FileAccess.file_exists(PATH):
		push_error(
			(
				"weapons: %s is missing, using built-in values. Check the export include filter (data/*.json)."
				% PATH
			)
		)
	else:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			data = parsed
		else:
			push_error(
				(
					'weapons: %s is not valid, expected an object with "dart_gun", "dart_pistol" and "melee", using built-in values'
					% PATH
				)
			)
	var out = {}
	for weapon in FALLBACK:
		var src = data.get(weapon, {})
		if typeof(src) != TYPE_DICTIONARY:
			push_error('weapons: "%s" must be an object, using built-in values' % weapon)
			src = {}
		var w = {}
		for key in FALLBACK[weapon]:
			var v = src.get(key)
			if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
				push_error(
					(
						"weapons: %s.%s needs a number, using %s"
						% [weapon, key, str(FALLBACK[weapon][key])]
					)
				)
				v = FALLBACK[weapon][key]
			w[key] = int(v) if WHOLE.has(key) else float(v)
		for key in src:
			if not FALLBACK[weapon].has(key):
				push_error(
					"weapons: %s.%s is not a known setting (typo?), ignored" % [weapon, str(key)]
				)
		out[weapon] = w
	for weapon in data:
		if not FALLBACK.has(weapon):
			push_error(
				(
					'weapons: "%s" is not a known weapon (only dart_gun, dart_pistol and melee exist so far), ignored'
					% str(weapon)
				)
			)
	return out
