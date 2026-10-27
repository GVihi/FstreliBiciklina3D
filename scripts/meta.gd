extends RefCounted
# Meta currency: earned when a run ends and kept between runs in user://meta.json.
# It is deliberately separate from run cash (g.cash): run cash is earned and spent inside one run and is
# gone when the run ends, while the meta balance only ever goes up from finished runs. It will be the
# currency for permanent unlocks, cosmetics and Heat rewards (roadmap, Milestone B).

# File format: {"version": 1, "balance", "total_earned", "owned": [unlock ids], "start_perk": unlock id, "challenges", "xp"}.
# Version 0 (before versioning) had no "version" field; a file without "owned" (written before unlocks could be bought)
# loads with nothing owned. "challenges" is {counter name: times done} for the challenges in data/challenges.json
# (scripts/challenges.gd). "xp" is the total XP of all finished runs (scripts/xp.gd, data/xp.json); the level is worked
# out from it and not saved. Both were added with a default (no counts, 0 XP), so they needed no version bump.
const SaveUtil = preload("res://scripts/save_util.gd")
const XpScript = preload("res://scripts/xp.gd")
const UnlocksTable = preload("res://scripts/unlocks.gd")
const WeaponSlots = preload("res://scripts/weapon_slots.gd")
const PATH = "user://meta.json"
const VERSION = 1
const MAX_XP = 100000000  # sanity limit for the saved XP (far above the top level)
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
var xp = 0  # total XP over all finished runs (never spent); the level comes from it, see `xp_info`
var xp_boss = 0  # XP this run's boss kills are worth; paid out with the run, like boss_coins
var xp_earned = 0  # XP the run that just ended paid out (shown on the run summary)
var level_before = 1  # the level when the run that just ended paid out, to tell whether it went up


func _init(game) -> void:
	g = game
	load_meta()


func load_meta() -> void:
	balance = 0
	total_earned = 0
	owned = {}
	start_perk = ""
	weapon_choice = {}
	challenge_counts = {}
	xp = 0
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
		var raw_xp = data.get("xp", 0)
		if typeof(raw_xp) == TYPE_INT or typeof(raw_xp) == TYPE_FLOAT:
			xp = clampi(int(raw_xp), 0, MAX_XP)  # a hand-edited number cannot crash it or pass the top level
		if typeof(data.get("start_perk", "")) == TYPE_STRING:
			start_perk = str(data.get("start_perk", ""))
		var wc = data.get("loadout", {})
		if wc is Dictionary:
			for slot in WeaponSlots.SLOTS:
				if typeof(wc.get(slot, "")) == TYPE_STRING:
					weapon_choice[slot] = str(wc.get(slot, ""))  # main.gd loadout_weapon_id checks it is still owned
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
					"loadout": weapon_choice,
					"challenges": challenge_counts,
					"xp": xp
				}
			)
		)
		f.close()


# Back to a new player's values in memory (RESET ALL PROGRESS): no coins, nothing owned, no chosen perk or weapons, no
# challenge counts, 0 XP. It does not touch the file; main.gd `reset_all_progress` deletes it.
func reset_all() -> void:
	balance = 0
	total_earned = 0
	owned = {}
	start_perk = ""
	weapon_choice = {}
	challenge_counts = {}
	xp = 0
	awarded = false
	boss_coins = 0
	xp_boss = 0
	xp_earned = 0
	level_before = 1


# called when a new run starts
func begin_run() -> void:
	awarded = false
	boss_coins = 0
	xp_boss = 0
	xp_earned = 0
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
	xp_boss += XpScript.boss_xp(kind, final)


# Pays out the run that just ended (once). Returns the coins earned and leaves them in g.meta_earned for the summary screen.
func award_run() -> int:
	if awarded:
		return 0
	awarded = true
	var challenge_coins = g.challenges.award()  # also counts the challenges done, saved below
	var n = reward_for_score(g.score) + boss_coins + challenge_coins
	g.meta_earned = n
	level_before = int(xp_info()["level"])
	# rounds cleared: the round reached minus the one the run ended in, plus that one when the run was won, and
	# minus the shop nodes walked through on the way (a shop node is a screen, not a round: alpha B2.4)
	var cleared = maxi(0, g.round_n - 1 - g.screens_passed()) + (1 if g.run_won else 0)
	xp_earned = XpScript.run_xp(
		g.score, g.kills, cleared, g.run_won, g.challenges.done.size(), xp_boss
	)
	xp = mini(MAX_XP, xp + xp_earned)
	var balance_before = balance
	if n > 0 or xp_earned > 0 or g.challenges.done.size() > 0:
		balance += n
		total_earned += n
		save_meta()
	# what this run's coins put within reach, for the summary screen (names only; the Unlocks page sells them)
	g.new_unlocks = []
	for u in UnlocksTable.newly_affordable(g.UNLOCKS, owned, balance_before, balance):
		g.new_unlocks.append(str(u["name"]))
	return n


# {"level", "into", "need", "max"} for the XP the player has now (see XpScript.info)
func xp_info() -> Dictionary:
	return XpScript.info(xp)


# true when the run that just ended paid out enough XP to reach a higher level
func leveled_up() -> bool:
	return int(xp_info()["level"]) > level_before


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


# the weapon chosen on the Loadout page for each slot (slot -> weapon id, "" or missing = the slot's default)
var weapon_choice = {}


func choose_weapon(slot: String, id: String) -> void:
	if not WeaponSlots.SLOTS.has(slot):
		return
	weapon_choice[slot] = id
	save_meta()
