extends RefCounted
# Heat: the difficulty level the player picks before a run (README Milestone B, "Difficulty Scaling"; the design is in
# docs/HEAT.md). Level 0 is the game as it was before Heat. The table is data/heat.json (format: data/README.md): one
# entry per level with the value of EVERY effect at that level, so a lookup is a read and nothing is added up.
# This file only holds the table and the lookup. Each effect is applied where it plays out (riders.gd, bosses.gd,
# shop.gd, main.gd), one chunk each (README H1.5 to H1.9); until then nothing reads `Main.heat`.

const PATH = "res://data/heat.json"
const MAX_LEVEL = 20  # sanity limit for a hand-edited table

# effect key -> its value at level 0, where it changes nothing
const NEUTRAL = {
	"rider_speed": 1.0,  # factor on how fast riders ride
	"riders_more": 0.0,  # share of riders added to a round (0.2 = 20 % more)
	"hearts_minus": 0,  # hearts taken off the 3 a run starts with
	"tough_hp_plus": 0,  # health added to a tough rider
	"boss_hp": 1.0,  # factor on boss health
	"price": 1.0,  # factor on shop prices
	"cash": 1.0,  # factor on the cash the player earns
}
# effect key -> [lowest, highest] a table may give. Heat only makes the game harder, so no key goes the easy way
const RANGES = {
	"rider_speed": [1.0, 3.0],
	"riders_more": [0.0, 2.0],
	"hearts_minus": [0, 2],
	"tough_hp_plus": [0, 5],
	"boss_hp": [1.0, 3.0],
	"price": [1.0, 3.0],
	"cash": [0.1, 1.0],
}
const WHOLE_KEYS = ["hearts_minus", "tough_hp_plus"]  # these take whole numbers only
const CAP_DEFAULTS = {"riders_max": 16, "hearts_min": 2, "cash_min": 0.5}  # see "Caps" in docs/HEAT.md

var g = null
var levels: Array = []  # one dict per level, index = level; always has level 0
var caps: Dictionary = {}


func _init(game = null) -> void:
	g = game
	var t = load_table()
	levels = t["levels"]
	caps = t["caps"]


# the last level in the table
func top_level() -> int:
	return levels.size() - 1


# a level number made valid: 0 to the top level
func clamp_level(n: int) -> int:
	return clampi(n, 0, top_level())


# a copy of the entry of `level` (name, desc and every effect), clamped like value()
func level_info(level: int) -> Dictionary:
	return levels[clamp_level(level)].duplicate()


# the value of effect `key` at `level`; -1 (the default) is the level of the run being played (`Main.heat`)
func value(key: String, level: int = -1) -> float:
	if not NEUTRAL.has(key):
		push_error('heat: unknown effect "%s"' % key)
		return 0.0
	var lv = level
	if lv < 0:
		lv = int(g.heat) if g != null else 0
	return float(levels[clamp_level(lv)][key])


# true when `level` changes nothing (level 0 always does, the table loader makes sure)
func is_neutral(level: int) -> bool:
	var e = levels[clamp_level(level)]
	for key in NEUTRAL:
		if not is_equal_approx(float(e[key]), float(NEUTRAL[key])):
			return false
	return true


# The level 0 that is used when the file has none: nothing changes
static func neutral_level() -> Dictionary:
	var e = NEUTRAL.duplicate()
	e["level"] = 0
	e["name"] = "NO HEAT"
	e["desc"] = "THE GAME AS IT IS"
	return e


# reads the table file; always returns {"levels": Array with at least level 0, "caps": Dictionary}
static func load_table(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error(
			(
				"heat: %s is missing, the game runs without Heat. Check the export include filter (data/*.json)."
				% path
			)
		)
		return parse(null)
	return parse(JSON.parse_string(FileAccess.get_file_as_string(path)))


# turns the parsed JSON into the table. Bad entries are skipped and logged with push_error, so check the Godot output
# panel after editing. Levels have to run 0, 1, 2 ... without a gap (a level after a gap is dropped), and level 0 is
# forced to change nothing, so a broken file can never make Heat 0 harder than the game was before Heat.
static func parse(data) -> Dictionary:
	var out = {"levels": [neutral_level()], "caps": CAP_DEFAULTS.duplicate()}
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("levels")) != TYPE_ARRAY:
		push_error('heat: the table is not valid, expected an object with a "levels" array')
		return out
	var raw_caps = data.get("caps", {})
	if typeof(raw_caps) == TYPE_DICTIONARY:
		for key in CAP_DEFAULTS:
			if raw_caps.has(key):
				if _is_number(raw_caps[key]) and float(raw_caps[key]) > 0.0:
					out["caps"][key] = raw_caps[key]
				else:
					push_error('heat: cap "%s" needs a number above 0' % key)
	var by_level = {}
	for raw in data["levels"]:
		var e = _clean(raw, by_level)
		if e.size() > 0:
			by_level[e["level"]] = e
	if not by_level.has(0):
		push_error("heat: level 0 is missing, the game runs without Heat")
		return out
	var list = []
	while by_level.has(list.size()):
		list.append(by_level[list.size()])
	if by_level.size() > list.size():
		push_error(
			(
				"heat: the levels have to run 0, 1, 2 without a gap, so everything after level %d is skipped"
				% (list.size() - 1)
			)
		)
	var zero = list[0]
	for key in NEUTRAL:
		if not is_equal_approx(float(zero[key]), float(NEUTRAL[key])):
			push_error(
				'heat: level 0 must change nothing, "%s" is set back to its neutral value' % key
			)
			zero[key] = NEUTRAL[key]
	out["levels"] = list
	return out


# validates one entry; returns {} (and logs why) when it is unusable. A key that is left out keeps its neutral value
static func _clean(raw, seen: Dictionary) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("heat: entry is not an object: %s" % str(raw))
		return {}
	var id = str(raw.get("level", "?"))
	if not _is_number(raw.get("level")) or float(int(raw["level"])) != float(raw["level"]):
		push_error('heat: entry "%s" needs a whole number "level"' % id)
		return {}
	var level = int(raw["level"])
	if level < 0 or level > MAX_LEVEL:
		push_error("heat: level %d is outside 0 to %d" % [level, MAX_LEVEL])
		return {}
	if seen.has(level):
		push_error("heat: duplicate level %d" % level)
		return {}
	for key in ["name", "desc"]:
		if typeof(raw.get(key)) != TYPE_STRING or str(raw[key]) == "":
			push_error('heat: level %d needs a text "%s"' % [level, key])
			return {}
	var e = NEUTRAL.duplicate()
	e["level"] = level
	e["name"] = raw["name"]
	e["desc"] = raw["desc"]
	for key in NEUTRAL:
		if not raw.has(key):
			continue
		var v = raw[key]
		if not _is_number(v):
			push_error('heat: level %d needs a number for "%s"' % [level, key])
			return {}
		if float(v) < float(RANGES[key][0]) or float(v) > float(RANGES[key][1]):
			push_error(
				(
					'heat: level %d: "%s" is %s, it has to be %s to %s'
					% [level, key, str(v), str(RANGES[key][0]), str(RANGES[key][1])]
				)
			)
			return {}
		if WHOLE_KEYS.has(key):
			if float(int(v)) != float(v):
				push_error('heat: level %d: "%s" has to be a whole number' % [level, key])
				return {}
			e[key] = int(v)
		else:
			e[key] = float(v)
	return e


static func _is_number(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT
