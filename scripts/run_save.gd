extends RefCounted
# Saved run: the checkpoint behind the CONTINUE button of the title screen (user://run.json).
# A checkpoint is written every time the run map screen opens (the start of a run and after every round and
# shop), so a run that is quit, crashed or closed comes back at the map screen with everything the player had
# there. A round that was being played is not saved, it is played again from the map screen.
# It is cleared when the run ends (lost, won) and when a new run replaces it (the old file is first copied to
# run.json.replaced.bak, see docs/SAVE_FILES.md). Nothing is deleted: "no run" is the file {"version": 1, "run": {}}.
# File format: {"version": 1, "run": {...}}. Every value is cast and clamped on load, so a hand-edited file cannot crash.

const SaveUtil = preload("res://scripts/save_util.gd")
const WeaponSlots = preload("res://scripts/weapon_slots.gd")
const PATH = "user://run.json"
const VERSION = 1
# a check sets this to another file, so it never touches the player's own saved run (empty = the real file)
static var test_path = ""
const MAX_ROUNDS_SAVED = 100  # sanity limit for the round lists and counters
const MAX_NUMBER = 1000000000.0  # sanity limit for a saved number (score, cash, time)
# the shape of the saved run, name -> the value it falls back to. `capture` writes exactly these keys.
const NUMBER_KEYS = {
	"run_seed": 0,
	"round_n": 1,
	"map_floor": -1,
	"map_lane": 0,
	"hearts": 3,
	"max_hearts": 3,
	"max_shells": 6,
	"cash": 0,
	"shop_buys": 0,
	"free_shots": 0,
	"score": 0,
	"combo": 0,
	"best_combo": 0,
	"kills": 0,
	"best_rank": 0,
	"shots_fired": 0,
	"shots_hit": 0,
	"civs_hit": 0,
	"perfect_dodges": 0,
	"boss_coins": 0,
	"xp_boss": 0,
	"streak": 0,
	"best_streak": 0
}
const FLOAT_KEYS = {
	"pump_base": 0.0,
	"pump_dur": 0.2,
	"style": 0.0,
	"hype": 0.0,
	"hype_gain": 1.0,
	"play_time": 0.0,
	"shop_time": 0.0
}
# the packs the shop sets up for the next round (`pending` in main.gd)
const PENDING_FLAGS = ["shield", "hype"]
const PENDING_NUMBERS = ["rapid", "big", "free"]
const BOOL_KEYS = {"daily": false, "custom": false, "final_boss_dead": false, "melee": false}

# ---- the file


static func path() -> String:
	return test_path if test_path != "" else PATH


# Loads the saved run and returns it checked and cleaned, or {} when there is none or the file is no good.
# A file that cannot be read, or that a newer game wrote, is copied to a .bak first (see save_util.gd).
static func load_file() -> Dictionary:
	if not FileAccess.file_exists(path()):
		return {}
	var f = FileAccess.open(path(), FileAccess.READ)
	if f == null:
		return {}
	var json = JSON.new()  # not parse_string: a damaged file is handled here and must not print an engine error
	var parsed = json.parse(f.get_as_text())
	f.close()
	var data = json.data if parsed == OK else null
	if not (data is Dictionary):
		SaveUtil.backup(path(), "bad")
		return {}
	SaveUtil.backup_if_newer(path(), SaveUtil.version_of(data), VERSION)
	if SaveUtil.version_of(data) > VERSION:
		return {}  # a run from a newer game: kept in the .bak file, not loaded by this build
	var run = data.get("run", {})
	if not (run is Dictionary) or run.is_empty():
		return {}
	return clean(run)


static func write_file(run: Dictionary) -> bool:
	var f = FileAccess.open(path(), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"version": VERSION, "run": run}))
	f.close()
	return true


# the run on the map screen is now the saved one
static func save(g) -> bool:
	return write_file(capture(g))


# no run is saved any more (a run that ended); the file stays, empty
static func clear() -> void:
	if FileAccess.file_exists(path()):
		write_file({})


# copies the saved run next to itself before a new run replaces it, so one mistaken PLAY can be undone by hand
static func backup_before_replace() -> void:
	if not load_file().is_empty():  # an empty "no run" file is not worth a backup, and must not replace a real one
		SaveUtil.backup(path(), "replaced")


# ---- capturing and restoring a run


# every run-long value of the game `g` (main.gd) as plain data
static func capture(g) -> Dictionary:
	var perk_ids = g.perks.keys()
	perk_ids.sort()
	var done_ids = g.challenges.done.keys()
	done_ids.sort()
	return {
		"run_seed": g.run_seed,
		"daily": g.daily_mode,
		"custom": g.custom_seed_run,
		"daily_date": g.daily_date,
		"round_n": g.round_n,
		"map_floor": g.map_floor,
		"map_lane": g.map_lane,
		"map_path": g.map_path.duplicate(),
		"hearts": g.hearts,
		"max_hearts": g.MAXHEARTS,
		"max_shells": g.MAXSHELLS,
		"pump_base": g.pump_base,
		"pump_dur": g.pump_dur,
		"cash": g.cash,
		"style": g.style,
		"perks": perk_ids,
		"up": g.up.duplicate(),
		"shop_lvl": g.shop_lvl.duplicate(),
		"shop_buys": g.shop_buys,
		"pending": g.pending.duplicate(),
		"buffs": g.buffs.duplicate(),
		"free_shots": g.free_shots,
		"hype": g.hype,
		"hype_gain": g.hype_gain,
		"melee": g.melee,
		"primary": g.primary,
		"melee_weapon": g.melee_weapon,
		"gadget": g.gadget,
		"score": g.score,
		"combo": g.combo,
		"best_combo": g.best_combo,
		"kills": g.kills,
		"best_rank": g.best_rank,
		"play_time": g.play_time,
		"shop_time": g.shop_time,
		"round_times": g.round_times.duplicate(),
		"shots_fired": g.shots_fired,
		"shots_hit": g.shots_hit,
		"civs_hit": g.civs_hit,
		"perfect_dodges": g.perfect_dodges,
		"final_boss_dead": g.final_boss_dead,
		"boss_coins": g.meta.boss_coins,
		"xp_boss": g.meta.xp_boss,
		"challenges_done": done_ids,
		"streak": g.challenges.streak,
		"best_streak": g.challenges.best_streak
	}


# Checks and cleans a loaded run: every number is cast and clamped, lists and dictionaries are rebuilt, and a run
# that cannot be played (no seed, a map position outside the map, a round past the end) gives {}.
# `perk_ids` and `challenge_ids` are not checked against the tables here: an id the game no longer has is harmless.
static func clean(raw: Dictionary) -> Dictionary:
	if not raw.has("run_seed"):
		return {}
	var out = {}
	for key in NUMBER_KEYS:
		out[key] = _int(raw.get(key, NUMBER_KEYS[key]), int(NUMBER_KEYS[key]))
	for key in FLOAT_KEYS:
		out[key] = _num(raw.get(key, FLOAT_KEYS[key]), float(FLOAT_KEYS[key]))
	for key in BOOL_KEYS:
		out[key] = _flag(raw.get(key, BOOL_KEYS[key]))
	out["daily_date"] = str(raw.get("daily_date", ""))
	out["primary"] = WeaponSlots.primary_or_default(raw.get("primary", WeaponSlots.PRIMARY_DEFAULT))
	out["melee_weapon"] = WeaponSlots.melee_or_default(
		raw.get("melee_weapon", WeaponSlots.MELEE_DEFAULT)
	)
	out["gadget"] = WeaponSlots.gadget_or_none(raw.get("gadget", WeaponSlots.NO_GADGET))
	out["run_seed"] = clampi(out["run_seed"], 0, 0xFFFFFFFF)
	out["round_n"] = clampi(out["round_n"], 1, MAX_ROUNDS_SAVED)
	out["map_floor"] = clampi(out["map_floor"], -1, MAX_ROUNDS_SAVED)
	out["map_lane"] = clampi(out["map_lane"], 0, MAX_ROUNDS_SAVED)
	out["max_hearts"] = clampi(out["max_hearts"], 1, 20)
	out["hearts"] = clampi(out["hearts"], 1, out["max_hearts"])  # a run on the map screen is alive
	out["max_shells"] = clampi(out["max_shells"], 1, 99)
	out["pump_base"] = clampf(out["pump_base"], 0.0, 10.0)
	out["pump_dur"] = clampf(out["pump_dur"], 0.01, 10.0)
	out["style"] = clampf(out["style"], 0.0, 1000.0)
	out["hype"] = clampf(out["hype"], 0.0, 100.0)
	out["hype_gain"] = clampf(out["hype_gain"], 0.0, 100.0)
	for key in [
		"cash", "score", "kills", "best_combo", "combo", "shots_fired", "shots_hit", "civs_hit"
	]:
		out[key] = clampi(out[key], 0, int(MAX_NUMBER))
	out["best_rank"] = clampi(out["best_rank"], 0, 4)
	out["map_path"] = _int_list(raw.get("map_path", []))
	out["round_times"] = _float_list(raw.get("round_times", []))
	out["perks"] = _text_list(raw.get("perks", []))
	out["challenges_done"] = _text_list(raw.get("challenges_done", []))
	out["up"] = _number_dict(raw.get("up", {}))
	out["shop_lvl"] = _number_dict(raw.get("shop_lvl", {}))
	out["buffs"] = _number_dict(raw.get("buffs", {}))
	var pend = raw.get("pending", {})
	if not (pend is Dictionary):
		pend = {}
	var pending = {}
	for key in PENDING_FLAGS:
		pending[key] = _flag(pend.get(key, false))
	for key in PENDING_NUMBERS:
		pending[key] = clampf(_num(pend.get(key, 0.0), 0.0), 0.0, MAX_NUMBER)
	out["pending"] = pending
	return out


# `data` is a cleaned run from `clean`: puts it into the game `g` (main.gd) as if the player had just reached
# that map screen. Needs reset_run() and meta / challenges begin_run() to have run first, so everything that
# the saved run does not hold starts from its usual value.
static func apply(g, data: Dictionary) -> void:
	g.run_seed = data["run_seed"]
	g.daily_mode = data["daily"]
	g.custom_seed_run = data["custom"]
	g.daily_date = data["daily_date"] if data["daily_date"] != "" else g.daily_date
	g.round_n = data["round_n"]
	g.map_floor = data["map_floor"]
	g.map_lane = data["map_lane"]
	g.map_path = data["map_path"].duplicate()
	g.MAXHEARTS = data["max_hearts"]
	g.hearts = data["hearts"]
	g.MAXSHELLS = data["max_shells"]
	g.shells = g.MAXSHELLS
	g.pump_base = data["pump_base"]
	g.pump_dur = data["pump_dur"]
	g.cash = data["cash"]
	g.style = data["style"]
	g.perks = {}
	for id in data["perks"]:
		g.perks[id] = true
	_merge_numbers(g.up, data["up"])
	g.shop_lvl = {}
	for id in data["shop_lvl"]:
		g.shop_lvl[id] = int(data["shop_lvl"][id])
	g.shop_buys = data["shop_buys"]
	for key in data["pending"]:
		if g.pending.has(key):
			g.pending[key] = data["pending"][key]
	g.pending["free"] = int(g.pending["free"])
	_merge_numbers(g.buffs, data["buffs"])
	g.free_shots = data["free_shots"]
	g.hype = data["hype"]
	g.hype_gain = data["hype_gain"]
	g.melee = data["melee"]
	g.primary = data["primary"]
	g.melee_weapon = data["melee_weapon"]
	g.gadget = data["gadget"]
	g.score = data["score"]
	g.combo = data["combo"]
	g.best_combo = data["best_combo"]
	g.kills = data["kills"]
	g.best_rank = data["best_rank"]
	g.play_time = data["play_time"]
	g.shop_time = data["shop_time"]
	g.round_times = data["round_times"].duplicate()
	g.shots_fired = data["shots_fired"]
	g.shots_hit = data["shots_hit"]
	g.civs_hit = data["civs_hit"]
	g.perfect_dodges = data["perfect_dodges"]
	g.final_boss_dead = data["final_boss_dead"]
	g.meta.boss_coins = data["boss_coins"]
	g.meta.xp_boss = data["xp_boss"]
	for id in data["challenges_done"]:
		g.challenges.done[id] = true
	g.challenges.streak = data["streak"]
	g.challenges.best_streak = data["best_streak"]


# true when a map position of the saved run is on the run map (the map is generated again from the seed)
static func fits_map(data: Dictionary, run_map: Dictionary) -> bool:
	if run_map.is_empty():
		return false
	var floors: Array = run_map["floors"]
	var f = int(data["map_floor"])
	if f >= floors.size():
		return false
	if f >= 0 and int(data["map_lane"]) >= floors[f].size():
		return false
	var path: Array = data["map_path"]
	if path.size() != f + 1:
		return false
	for i in range(path.size()):
		if int(path[i]) < 0 or int(path[i]) >= floors[i].size():
			return false
	return true


# ---- small cleaners


# true only for the JSON value true (a number or text in its place is false)
static func _flag(v) -> bool:
	return typeof(v) == TYPE_BOOL and v


static func _num(v, fallback: float) -> float:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		var x = float(v)
		if is_nan(x) or is_inf(x):
			return fallback
		return clampf(x, -MAX_NUMBER, MAX_NUMBER)
	return fallback


static func _int(v, fallback: int) -> int:
	return int(_num(v, float(fallback)))


static func _int_list(v) -> Array:
	var out = []
	if v is Array:
		for x in v:
			if out.size() < MAX_ROUNDS_SAVED:
				out.append(_int(x, 0))
	return out


static func _float_list(v) -> Array:
	var out = []
	if v is Array:
		for x in v:
			if out.size() < MAX_ROUNDS_SAVED:
				out.append(clampf(_num(x, 0.0), 0.0, MAX_NUMBER))
	return out


static func _text_list(v) -> Array:
	var out = []
	if v is Array:
		for x in v:
			if typeof(x) == TYPE_STRING and str(x) != "" and out.size() < 200:
				out.append(str(x))
	return out


static func _number_dict(v) -> Dictionary:
	var out = {}
	if v is Dictionary:
		for key in v:
			if typeof(v[key]) == TYPE_INT or typeof(v[key]) == TYPE_FLOAT:
				out[str(key)] = clampf(_num(v[key], 0.0), 0.0, MAX_NUMBER)
	return out


# copies the saved numbers over the game's own dictionary, keeping each value's own type (int levels stay int)
static func _merge_numbers(target: Dictionary, saved: Dictionary) -> void:
	for key in saved:
		if not target.has(key):
			continue
		if typeof(target[key]) == TYPE_INT:
			target[key] = int(saved[key])
		else:
			target[key] = float(saved[key])
