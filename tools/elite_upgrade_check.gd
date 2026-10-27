extends SceneTree
# Checks the elite node's reward (README alpha B4, Milestone D "Elite encounter"): clearing an elite node gives two
# upgrade picks in a row, the second from fresh offers, and every other cleared node still gives one. Run from the
# project folder:
#   godot --headless --path . --script res://tools/elite_upgrade_check.gd
# It checks that
#   - after a normal node the upgrade screen has three offers, one pick leads to the map, and no extra pick is owed
#   - after an elite node the first pick leads to a second upgrade screen (its own shuffle part, "upgrade2") with
#     three offers that are not the first three, and the second pick leads to the map
#   - the second screen's offers are the same for the same seed and the same picks (the Daily Run stays fair)
#   - the rest node's EXTRA UPGRADE is one pick, even when the node under it says elite, and nothing is owed after it
#   - with every upgrade bought out an elite clear goes straight on to the map, with no second screen
#   - starting a new run clears a pick that was still owed
# Exits with status 1 and prints the problems when a check fails.

const SEED = 0x2468ACE1

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_check_normal()
	_check_elite()
	_check_same_seed()
	_check_rest_and_empty_pool()
	_check_new_run()
	_finish()


func _fail(text: String) -> void:
	problems.append(text)


# starts a run on SEED and makes the node of floor 1 (lane 0) a node of this type, as if its round had just been
# cleared (the clear screen goes on to `enter_upgrade`)
func _clear_node(type: String) -> void:
	main.start_game(false, SEED)
	main.run_map["floors"][0][0]["type"] = type
	main.map_floor = 0
	main.map_lane = 0
	main.round_n = 1
	main.shop_sys.enter_upgrade()


func _ids(offers: Array) -> Array:
	var out = []
	for o in offers:
		out.append(str(o["id"]))
	return out


func _check_normal() -> void:
	_clear_node("normal")
	if main.state != "upgrade" or main.offers.size() != 3:
		_fail(
			(
				"normal clear: state %s with %d offers, expected 3 offers"
				% [main.state, main.offers.size()]
			)
		)
		return
	if main.upgrade_extra != 0 or main.upgrade_part != "upgrade":
		_fail(
			(
				"normal clear: an extra pick is owed (%d, part %s)"
				% [main.upgrade_extra, main.upgrade_part]
			)
		)
	main.shop_sys.pick_upgrade(0)
	if main.state != "map":
		_fail("normal clear: one pick led to state %s, not the map" % main.state)


func _check_elite() -> void:
	_clear_node("elite")
	if main.state != "upgrade" or main.offers.size() != 3:
		_fail(
			(
				"elite clear: state %s with %d offers, expected 3 offers"
				% [main.state, main.offers.size()]
			)
		)
		return
	if main.upgrade_extra != 1 or main.upgrade_part != "upgrade":
		_fail(
			(
				"elite clear: first screen owes %d extra picks (part %s), expected 1"
				% [main.upgrade_extra, main.upgrade_part]
			)
		)
	var first = _ids(main.offers)
	main.shop_sys.pick_upgrade(0)
	if main.state != "upgrade":
		_fail(
			"elite clear: the first pick led to state %s, not a second upgrade screen" % main.state
		)
		return
	if main.upgrade_part != "upgrade2" or main.upgrade_extra != 0:
		_fail(
			(
				"elite clear: second screen has part %s and owes %d"
				% [main.upgrade_part, main.upgrade_extra]
			)
		)
	if main.offers.size() != 3:
		_fail("elite clear: the second screen has %d offers, not 3" % main.offers.size())
	if _ids(main.offers) == first:
		_fail("elite clear: the second pick repeats the first offers %s" % str(first))
	if main.state_t != 0.0:
		_fail(
			(
				"elite clear: the second screen did not restart its input guard (state_t %f)"
				% main.state_t
			)
		)
	main.shop_sys.pick_upgrade(0)
	if main.state != "map":
		_fail("elite clear: the second pick led to state %s, not the map" % main.state)
	if main.upgrade_extra != 0 or main.rest_upgrade:
		_fail("elite clear: a pick is still owed on the map screen")


# the whole elite sequence twice from the same seed: the same offers both times
func _check_same_seed() -> void:
	var runs = []
	for i in range(2):
		_clear_node("elite")
		var first = _ids(main.offers)
		main.shop_sys.pick_upgrade(0)
		runs.append([first, _ids(main.offers)])
		main.shop_sys.pick_upgrade(0)
	if runs[0] != runs[1]:
		_fail("elite clear: the same seed gave offers %s, then %s" % [str(runs[0]), str(runs[1])])


func _check_rest_and_empty_pool() -> void:
	# the rest node's EXTRA UPGRADE is one pick, whatever the node says
	_clear_node("elite")
	main.state = "map"
	main.rest_upgrade = true
	main.shop_sys.enter_upgrade()
	if main.upgrade_extra != 0:
		_fail("rest stop: EXTRA UPGRADE owes %d more picks" % main.upgrade_extra)
	main.shop_sys.pick_upgrade(0)
	if main.state != "map":
		_fail("rest stop: the extra upgrade led to state %s, not the map" % main.state)
	# every upgrade bought out: an elite clear goes on to the map and owes nothing
	_clear_node("elite")
	main.state = "map"
	var all_upgrades = main.UPGRADES
	main.UPGRADES = []
	main.shop_sys.enter_upgrade()
	main.UPGRADES = all_upgrades
	if main.state != "map" or main.upgrade_extra != 0:
		_fail(
			(
				"empty pool: state %s owing %d, expected the map and 0"
				% [main.state, main.upgrade_extra]
			)
		)


func _check_new_run() -> void:
	_clear_node("elite")  # leaves a second pick owed
	main.start_game(false, SEED)
	if main.upgrade_extra != 0 or main.upgrade_part != "upgrade":
		_fail("a new run kept an owed pick (%d, part %s)" % [main.upgrade_extra, main.upgrade_part])


func _finish() -> void:
	if problems.is_empty():
		print("elite_upgrade_check: an elite clear gives two upgrade picks, every other node one")
		quit(0)
	else:
		print("elite_upgrade_check: %d problem(s)" % problems.size())
		for p in problems.slice(0, 12):
			print("  " + p)
		quit(1)
