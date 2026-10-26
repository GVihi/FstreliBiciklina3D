extends RefCounted
# Meta currency: earned when a run ends and kept between runs in user://meta.json.
# It is deliberately separate from run cash (g.cash): run cash is earned and spent inside one run and is
# gone when the run ends, while the meta balance only ever goes up from finished runs. It will be the
# currency for permanent unlocks, cosmetics and Heat rewards (roadmap, Milestone B).

# File format: {"version": 1, "balance", "total_earned", "owned": [unlock ids], "start_perk": unlock id}. Version 0 (before versioning) had no
# "version" field; a file without "owned" (written before unlocks could be bought) loads with nothing owned.
# File format: {"version": 1, "balance", "total_earned", "challenges"}. Version 0 (before versioning) had no "version" field.
# "challenges" is {counter name: times done} for the challenges in data/challenges.json (scripts/challenges.gd). It was
# added with a default (no counts), so it needed no version bump.
const SaveUtil = preload("res://scripts/save_util.gd")
const UnlocksTable = preload("res://scripts/unlocks.gd")
const PATH = "user://meta.json"
const VERSION = 1
const SCORE_PER_COIN = 100  # tuning knob: 100 points of score = 1 meta coin
# tuning knobs: coins for each defeated boss, added on top of the score coins when the run ends
const COINS_PER_BOSS = 5  # lawnmower, wifi adapter, minister
const COINS_PER_CYCLIST = 1  # the angry cyclist mini boss
const COINS_FINAL_BOSS = 20  # the golden president

var g = null
var balance = 0  # coins available to spend
var total_earned = 0  # coins earned over all runs, for stats
var challenge_counts = {}  # challenge counter name -> how many runs it was done in
var awarded = false  # a run pays out once, however many end paths it passes through
var boss_coins = 0  # coins this run's boss kills are worth; paid out with the run (a quit run pays nothing)


func _init(game) -> void:
	g = game
	load_meta()


func load_meta() -> void:
	balance = 0
	total_earned = 0
	owned = {}
	start_perk = ""
	challenge_counts = {}
	if not FileAccess.file_exists(PATH):
		return
	var f = FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		SaveUtil.backup_if_newer(PATH, SaveUtil.version_of(data), VERSION)
		balance = maxi(0, int(data.get("balance", 0)))
		total_earned = maxi(balance, int(data.get("total_earned", 0)))
		if typeof(data.get("start_perk", "")) == TYPE_STRING:
			start_perk = str(data.get("start_perk", ""))
		var ids = data.get("owned", [])
		if ids is Array:
			for id in ids:
				if typeof(id) == TYPE_STRING and str(id) != "":
					owned[str(id)] = true  # an id the table no longer has stays owned, so a purchase is never lost
		var counts = data.get("challenges", {})
		if counts is Dictionary:
			for key in counts:
				challenge_counts[str(key)] = maxi(0, int(counts[key]))
	else:
		SaveUtil.backup(PATH, "bad")  # unreadable: keep a copy before the next save replaces it


func save_meta() -> void:
	var f = FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		var ids = owned.keys()
		ids.sort()
		f.store_string(
			JSON.stringify(
				{
					"version": VERSION,
					"balance": balance,
					"total_earned": total_earned,
					"owned": ids,
					"start_perk": start_perk,
					"challenges": challenge_counts
				}
			)
		)
		f.close()


# called when a new run starts
func begin_run() -> void:
	awarded = false
	boss_coins = 0
	g.meta_earned = 0


func reward_for_score(score: int) -> int:
	return floori(float(maxi(0, score)) / float(SCORE_PER_COIN))


func reward_for_boss(kind: String, final: bool) -> int:
	if final:
		return COINS_FINAL_BOSS
	if kind == "runner":
		return COINS_PER_CYCLIST
	return COINS_PER_BOSS


# called by bosses.gd when a boss is defeated; the coins are paid out in award_run()
func add_boss_kill(kind: String, final: bool) -> void:
	if awarded:
		return
	boss_coins += reward_for_boss(kind, final)


# Pays out the run that just ended (once). Returns the coins earned and leaves them in g.meta_earned for the summary screen.
func award_run() -> int:
	if awarded:
		return 0
	awarded = true
	var challenge_coins = g.challenges.award()  # also counts the challenges done, saved below
	var n = reward_for_score(g.score) + boss_coins + challenge_coins
	g.meta_earned = n
	if n > 0 or g.challenges.done.size() > 0:
		balance += n
		total_earned += n
		save_meta()
	return n


# ids of the unlocks the player owns (data/unlocks.json), saved in meta.json
var owned = {}


func owns(id: String) -> bool:
	return owned.has(id)


# Buys an unlock with meta coins and saves at once. Returns "bought", or why not: "owned", "soon" (its target is not in
# the game yet) or "locked" (not enough coins). Nothing is spent unless it returns "bought".
func buy(u: Dictionary) -> String:
	var state = UnlocksTable.state_of(u, owns(u["id"]), balance)
	if state != "afford":
		return state
	balance -= int(u["cost"])
	owned[str(u["id"])] = true
	save_meta()
	return "bought"


# the unlock id of the starting perk chosen on the Loadout page ("" = none); main.gd start_perk_id checks it is still owned
var start_perk = ""


func choose_start_perk(id: String) -> void:
	start_perk = id
	save_meta()
