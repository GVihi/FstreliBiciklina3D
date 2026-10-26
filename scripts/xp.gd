extends RefCounted
# XP and levels (roadmap, Milestone I). XP is earned when a run ends (Meta.award_run) and only ever goes up: unlike
# meta coins it is never spent. The total is kept in user://meta.json as "xp"; the level is worked out from it
# every time, so changing the curve in res://data/xp.json re-levels every save without a conversion step.
# Every number is in data/xp.json (described in data/README.md). A missing or bad value is logged with push_error
# and replaced by the fallback in DEFAULTS, so a typo cannot stop the game.
# This script only does the arithmetic; the XP and level on screen are drawn by hud.gd.

const PATH = "res://data/xp.json"
const DEFAULTS = {
	"score_per_xp": 20,
	"per_kill": 2,
	"per_round": 15,
	"run_won": 200,
	"per_challenge": 25,
	"level_base": 300,
	"level_step": 100,
	"max_level": 50
}
const BOSS_DEFAULTS = {"boss": 25, "runner": 10, "final": 150}
# values that must be at least 1 (they divide, or are a count of levels)
const MIN_ONE = ["score_per_xp", "level_base", "max_level"]

static var table: Dictionary = load_table()


# returns the numbers of res://data/xp.json with every missing or bad value replaced by its fallback
static func load_table() -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	out["boss"] = BOSS_DEFAULTS.duplicate()
	if not FileAccess.file_exists(PATH):
		push_error(
			(
				"xp: %s is missing, using the built-in numbers. Check the export include filter (data/*.json)."
				% PATH
			)
		)
		return out
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("xp: %s is not valid, expected an object; using the built-in numbers" % PATH)
		return out
	for key in DEFAULTS:
		out[key] = _number(data.get(key), key, DEFAULTS[key], 1 if MIN_ONE.has(key) else 0)
	var boss = data.get("boss")
	if typeof(boss) != TYPE_DICTIONARY:
		push_error('xp: "boss" is missing or not an object; using the built-in numbers')
		boss = {}
	for key in BOSS_DEFAULTS:
		out["boss"][key] = _number(boss.get(key), "boss." + key, BOSS_DEFAULTS[key], 0)
	return out


# a whole number of at least `low`, or the fallback (and a logged error)
static func _number(raw, key: String, fallback: int, low: int) -> int:
	if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
		push_error('xp: "%s" needs a number, using %d' % [key, fallback])
		return fallback
	var n = int(raw)
	if n < low:
		push_error('xp: "%s" must be at least %d, using %d' % [key, low, fallback])
		return fallback
	return n


# XP a defeated boss is worth: "runner" is the angry cyclist mini boss, `final` the golden president
static func boss_xp(kind: String, final: bool) -> int:
	if final:
		return int(table["boss"]["final"])
	if kind == "runner":
		return int(table["boss"]["runner"])
	return int(table["boss"]["boss"])


# XP a finished run is worth: score, kills, cleared rounds, a won run, challenges done in it and the boss XP
# collected while it ran (Meta.xp_boss)
static func run_xp(
	score: int, kills: int, rounds_cleared: int, won: bool, challenges_done: int, boss: int
) -> int:
	var n = floori(float(maxi(0, score)) / float(table["score_per_xp"]))
	n += maxi(0, kills) * int(table["per_kill"])
	n += maxi(0, rounds_cleared) * int(table["per_round"])
	if won:
		n += int(table["run_won"])
	n += maxi(0, challenges_done) * int(table["per_challenge"])
	n += maxi(0, boss)
	return n


# XP needed to go from `level` to the next one (level 1 is the start)
static func need_for(level: int) -> int:
	return int(table["level_base"]) + int(table["level_step"]) * (maxi(1, level) - 1)


# total XP at which `level` is reached (level 1 = 0 XP)
static func total_for_level(level: int) -> int:
	var l = maxi(1, level) - 1
	return l * int(table["level_base"]) + int(table["level_step"]) * floori(l * (l - 1) * 0.5)


# {"level", "into" (XP gathered towards the next level), "need" (XP the next level takes, 0 at the top level),
# "max" (true at the top level)} for a total XP
static func info(total: int) -> Dictionary:
	var level = 1
	var left = maxi(0, total)
	var top = int(table["max_level"])
	while level < top and left >= need_for(level):
		left -= need_for(level)
		level += 1
	if level >= top:
		return {"level": top, "into": 0, "need": 0, "max": true}
	return {"level": level, "into": left, "need": need_for(level), "max": false}
