extends RefCounted
# Meta challenges (roadmap, Milestone B, "Earn from challenges"): small goals that pay meta coins.
# The list (names, targets, rewards, save counter names) is in res://data/challenges.json, described in
# data/README.md. This script loads that table, watches the run for each condition, pays the coins with the
# run (through Meta.award_run, so a quit run pays nothing, like the score coins) and keeps how many times each
# challenge was done in user://meta.json (Meta.challenge_counts, keyed by the entry's "counter").
# A challenge pays at most once per run, however many times its condition is met.

const PATH = "res://data/challenges.json"
const CONDITIONS = [
	"round_no_gun",
	"all_caches_before_last_rider",
	"perfect_dodge_streak",
	"round_no_life_lost",
	"run_time_under"
]
const SCOPES = ["round", "run"]

var g = null
var table: Array = []  # the cleaned entries, in file order
var done: Dictionary = {}  # id -> true: challenges whose condition was met in this run
var new_ids: Array = []  # ids done for the first time ever, filled by award() when the run ends
var coins = 0  # meta coins this run's challenges are worth; paid out with the run
var paid = false
var gun_used = false  # a dart was fired in this round (melee does not count)
var early_caches = false  # every cache of this round was taken while riders were still up
var streak = 0  # perfect dodges in a row (a lost life ends the streak)
var best_streak = 0  # the longest streak of this run, for the progress shown on the run summary


func _init(game) -> void:
	g = game
	table = load_table()


# returns the entries of res://data/challenges.json that are usable, in file order; bad ones are logged and skipped
static func load_table() -> Array:
	var out: Array = []
	if not FileAccess.file_exists(PATH):
		push_error(
			(
				"challenges: %s is missing, there will be no challenges. Check the export include filter (data/*.json)."
				% PATH
			)
		)
		return out
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("challenges")) != TYPE_ARRAY:
		push_error(
			'challenges: %s is not valid, expected an object with a "challenges" array' % PATH
		)
		return out
	var ids = {}
	var counters = {}
	for raw in data["challenges"]:
		var c = _clean(raw, ids, counters)
		if c.size() > 0:
			ids[c["id"]] = true
			counters[c["counter"]] = true
			out.append(c)
	return out


# validates one entry and fixes number types; returns {} (and logs why) when the entry is unusable
static func _clean(raw, ids: Dictionary, counters: Dictionary) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("challenges: entry is not an object: %s" % str(raw))
		return {}
	for key in ["id", "name", "desc", "condition", "scope", "counter"]:
		if typeof(raw.get(key)) != TYPE_STRING or String(raw[key]) == "":
			push_error('challenges: entry %s needs a text "%s"' % [str(raw.get("id", "?")), key])
			return {}
	for key in ["target", "reward"]:
		if typeof(raw.get(key)) != TYPE_FLOAT and typeof(raw.get(key)) != TYPE_INT:
			push_error('challenges: %s needs a number "%s"' % [raw["id"], key])
			return {}
	if not CONDITIONS.has(raw["condition"]):
		push_error('challenges: %s has unknown condition "%s"' % [raw["id"], raw["condition"]])
		return {}
	if not SCOPES.has(raw["scope"]):
		push_error('challenges: %s has unknown scope "%s"' % [raw["id"], raw["scope"]])
		return {}
	if ids.has(raw["id"]):
		push_error('challenges: duplicate id "%s"' % raw["id"])
		return {}
	if counters.has(raw["counter"]):
		push_error('challenges: duplicate counter "%s"' % raw["counter"])
		return {}
	if float(raw["target"]) <= 0.0 or float(raw["reward"]) < 0.0:
		push_error("challenges: %s needs a target above 0 and a reward of 0 or more" % raw["id"])
		return {}
	return {
		"id": raw["id"],
		"name": raw["name"],
		"desc": raw["desc"],
		"condition": raw["condition"],
		"scope": raw["scope"],
		"target": int(raw["target"]),
		"reward": int(raw["reward"]),
		"counter": raw["counter"]
	}


# ---- the run


# a new run starts
func begin_run() -> void:
	done.clear()
	new_ids.clear()
	coins = 0
	paid = false
	streak = 0
	best_streak = 0
	begin_round()


# a new round starts
func begin_round() -> void:
	gun_used = false
	early_caches = false


func on_dart_fired() -> void:
	gun_used = true


# every cache of the round is taken; `riders_up` is true while the way out is still locked (riders or a boss up)
func on_all_caches(riders_up: bool) -> void:
	early_caches = riders_up


func on_perfect_dodge() -> void:
	streak += 1
	best_streak = maxi(best_streak, streak)
	for c in table:
		if c["condition"] == "perfect_dodge_streak" and streak >= c["target"]:
			_complete(c)


func on_life_lost() -> void:
	streak = 0


# the round was cleared: the round challenges are judged on how it went
func on_round_cleared() -> void:
	for c in table:
		if c["scope"] != "round":
			continue
		if c["condition"] == "round_no_gun" and not gun_used:
			_complete(c)
		elif c["condition"] == "all_caches_before_last_rider" and early_caches:
			_complete(c)
		elif c["condition"] == "round_no_life_lost" and g.round_lives_lost == 0:
			_complete(c)


# the whole run was won, in `seconds` of fighting and shopping
func on_run_won(seconds: float) -> void:
	for c in table:
		if c["condition"] == "run_time_under" and seconds < float(c["target"]):
			_complete(c)


func _complete(c: Dictionary) -> void:
	if done.has(c["id"]):
		return
	done[c["id"]] = true
	g.add_note("CHALLENGE DONE: %s" % c["name"], g.GOLD)


# Pays out the run that just ended (once): counts every challenge done, remembers which were done for the
# first time ever and returns the meta coins. Meta.award_run() calls it and saves the file.
func award() -> int:
	if paid:
		return coins
	paid = true
	coins = 0
	for c in table:
		if not done.has(c["id"]):
			continue
		coins += c["reward"]
		var n = count_of(c)
		if n == 0:
			new_ids.append(c["id"])
		g.meta.challenge_counts[c["counter"]] = n + 1
	return coins


# ---- what the screens show


# how many times the challenge was done over all runs
func count_of(c: Dictionary) -> int:
	return int(g.meta.challenge_counts.get(c["counter"], 0))


# progress of a challenge that was not done in this run, "3 / 5", or "" when there is nothing to show
func progress_text(c: Dictionary) -> String:
	if c["condition"] == "perfect_dodge_streak" and best_streak > 0:
		return "%d / %d" % [mini(best_streak, c["target"]), c["target"]]
	return ""
