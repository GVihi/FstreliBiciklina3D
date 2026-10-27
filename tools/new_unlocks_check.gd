extends SceneTree
# Checks the "now affordable" block of the run summary (README Milestone I: "Show newly unlocked items on the run
# summary screen"). Unlocks are bought with meta coins, so "newly unlocked" means the unlocks that the coins of the
# run that just ended put within reach for the first time:
#   - UnlocksTable.newly_affordable lists an unlock only when it is not owned, not planned, and the balance went from
#     below its price to the price or above it (not when it was already affordable, not when it is still too dear),
#   - Meta.award_run fills g.new_unlocks with those names, an empty list when nothing crossed a price, and a run that
#     pays nothing leaves it empty,
#   - an unlock that was bought before the run is never listed,
#   - the summary shows at most three lines, the third saying how many are left out,
#   - the summary draws at two window sizes with none, one and many names.
# It keeps the real meta.json (and its backups) first and puts them back at the end.
# Run from the project folder:
#   godot --headless --path . --script res://tools/new_unlocks_check.gd
# or with tools\run_new_unlocks_check.bat on Windows.
# Exits with status 1 and prints the problems when a check fails.

const UnlocksTable = preload("res://scripts/unlocks.gd")

var problems = []
var main
var kept = {}


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_keep_user_files()
	_check_function()
	_check_award()
	_check_lines()
	await _check_screens()
	_restore_user_files()
	_finish()


func _finish() -> void:
	if problems.is_empty():
		print(
			"new_unlocks_check: the summary lists what the run's coins put within reach, and nothing else"
		)
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("new_unlocks_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


func _entry(id: String, cost: int, planned: bool = false) -> Dictionary:
	return {"id": id, "name": id.to_upper(), "cost": cost, "planned": planned}


func _ids(list: Array) -> Array:
	var out = []
	for u in list:
		out.append(u["id"])
	return out


# the pure rule, on a small table
func _check_function() -> void:
	var table = [
		_entry("a", 60),
		_entry("b", 120),
		_entry("c", 120),
		_entry("d", 250),
		_entry("e", 60, true),
		_entry("f", 0)
	]
	var got = _ids(UnlocksTable.newly_affordable(table, {}, 50, 130))
	if got != ["a", "b", "c"]:
		_fail("50 -> 130 coins listed %s, expected a, b, c in table order" % str(got))
	got = _ids(UnlocksTable.newly_affordable(table, {}, 60, 130))
	if got != ["b", "c"]:
		_fail(
			(
				"60 -> 130 coins listed %s: a was already affordable, so only b and c are new"
				% str(got)
			)
		)
	got = _ids(UnlocksTable.newly_affordable(table, {}, 59, 60))
	if got != ["a"]:
		_fail(
			(
				"59 -> 60 coins listed %s, expected a (the price itself counts as affordable)"
				% str(got)
			)
		)
	got = _ids(UnlocksTable.newly_affordable(table, {}, 130, 130))
	if not got.is_empty():
		_fail("a run that paid nothing listed %s" % str(got))
	got = _ids(UnlocksTable.newly_affordable(table, {}, 0, 100))
	if got != ["a"]:
		_fail(
			(
				"0 -> 100 coins listed %s: a planned unlock and a free one must not be listed"
				% str(got)
			)
		)
	got = _ids(UnlocksTable.newly_affordable(table, {"b": true}, 50, 130))
	if got != ["a", "c"]:
		_fail("an owned unlock was listed: %s" % str(got))
	if not UnlocksTable.newly_affordable([], {}, 0, 999).is_empty():
		_fail("an empty table listed something")


func _new_run(balance: int) -> void:
	main.meta.balance = balance
	main.meta.owned = {}
	main.meta.begin_run()
	main.challenges.begin_run()
	main.new_unlocks = []
	main.score = 0
	main.kills = 0
	main.round_n = 1
	main.run_won = false
	main.round_lives_lost = 0


# the real table: the cheapest buyable unlock is the first one the coins of a run reach
func _check_award() -> void:
	var cheapest = null
	for u in main.UNLOCKS:
		if not u["planned"] and (cheapest == null or int(u["cost"]) < int(cheapest["cost"])):
			cheapest = u
	if cheapest == null:
		_fail("the unlock table has nothing buyable, nothing to check")
		return
	var cost = int(cheapest["cost"])
	var per_coin = int(main.meta.SCORE_PER_COIN)
	# a run that pays enough coins to cross the cheapest price from just below it
	_new_run(cost - 1)
	main.score = per_coin * 2  # 2 coins
	main.meta.award_run()
	if not main.new_unlocks.has(str(cheapest["name"])):
		_fail(
			"crossing the price of %s did not list it: %s" % [cheapest["id"], str(main.new_unlocks)]
		)
	# paying the same run again changes nothing (a run pays once)
	var first = main.new_unlocks.duplicate()
	main.meta.award_run()
	if main.new_unlocks != first:
		_fail("paying the run a second time changed the list to %s" % str(main.new_unlocks))
	# already affordable before the run: not new
	_new_run(cost + 10)
	main.score = per_coin * 2
	main.meta.award_run()
	if main.new_unlocks.has(str(cheapest["name"])):
		_fail("%s was listed although the player could already afford it" % cheapest["id"])
	# owned before the run: never listed
	_new_run(cost - 1)
	main.meta.owned[str(cheapest["id"])] = true
	main.score = per_coin * 2
	main.meta.award_run()
	if main.new_unlocks.has(str(cheapest["name"])):
		_fail("%s was listed although the player owns it" % cheapest["id"])
	# a run that pays nothing leaves the list empty
	_new_run(cost - 1)
	main.meta.award_run()
	if not main.new_unlocks.is_empty():
		_fail("a run that paid nothing listed %s" % str(main.new_unlocks))
	# a big payout lists several, none of them planned
	_new_run(0)
	# score coins are capped (SCORE_COINS_MAX), so the big payout comes from uncapped boss coins
	main.meta.boss_coins = 100000
	main.meta.award_run()
	var buyable = 0
	for u in main.UNLOCKS:
		if not u["planned"] and int(u["cost"]) > 0:
			buyable += 1
	if main.new_unlocks.size() != buyable:
		_fail(
			(
				"a huge payout listed %d unlocks, expected all %d buyable ones"
				% [main.new_unlocks.size(), buyable]
			)
		)
	# a new run clears the list
	main.new_unlocks = ["LEFTOVER"]
	main.start_game(false)
	if not main.new_unlocks.is_empty():
		_fail("starting a run did not clear the list: %s" % str(main.new_unlocks))
	main.go_to_title()


# at most three lines, the third counting what is left out
func _check_lines() -> void:
	var hud = main.hud
	if hud.unlock_summary_lines([]) != []:
		_fail("no names gave lines")
	if hud.unlock_summary_lines(["one", "two", "three"]) != ["ONE", "TWO", "THREE"]:
		_fail(
			(
				"three names were not shown in full: %s"
				% str(hud.unlock_summary_lines(["one", "two", "three"]))
			)
		)
	var many = hud.unlock_summary_lines(["a", "b", "c", "d", "e"])
	if many != ["A", "B", "+ 3 MORE"]:
		_fail("five names gave %s, expected A, B, + 3 MORE" % str(many))
	if hud.unlock_summary_lines(["a", "b", "c", "d"]) != ["A", "B", "+ 2 MORE"]:
		_fail("four names gave %s" % str(hud.unlock_summary_lines(["a", "b", "c", "d"])))


# the summary draws with none, one and many names, at two window sizes (a script error shows up here)
func _check_screens() -> void:
	for names in [[], ["POCKET MAGNET"], ["A", "B", "C", "D", "E", "F"]]:
		_new_run(0)
		main.score = 5000
		main.kills = 12
		main.round_n = 5
		main.meta.award_run()
		main.new_unlocks = names
		main.state = "over"
		main.over_reason = "riders"
		main.run_won = false
		for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]:
			main.hud.size = s
			for f in range(2):
				main.hud.queue_redraw()
				await process_frame
		main.hud.size = Vector2(1280.0, 720.0)
	main.go_to_title()


func _paths() -> Array:
	var meta_path = main.meta.PATH
	return [meta_path, meta_path + ".bad.bak", meta_path + ".v2.bak"]


func _keep_user_files() -> void:
	for path in _paths():
		if FileAccess.file_exists(path):
			kept[path] = FileAccess.get_file_as_bytes(path)


func _restore_user_files() -> void:
	for path in _paths():
		if kept.has(path):
			var f = FileAccess.open(path, FileAccess.WRITE)
			if f:
				f.store_buffer(kept[path])
				f.close()
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.meta.load_meta()
