extends SceneTree
# Checks that every node type of the map works inside one run and that the run still continues from the map screen
# after each of them (README alpha B7, Milestone D "Replace linear round progression"). Run from the project folder:
#   godot --headless --path . --script res://tools/node_types_run_check.gd
# It looks for a seed whose map has a path through a normal, an elite, a shop, a rest and a boss node, then walks that
# path from floor 1 to the final boss with the game's own functions: the pick on the map screen, the round set-up, the
# end of the round, the clear screen's upgrade pick(s), the shop's buy and leave, the rest stop's choice. After every
# node, once the map screen is open again, it does what the player does to quit and come back: the pause menu's quit
# to the title (`abandon_run`), then CONTINUE (`continue_run`), and checks that the map screen comes back with the
# same hearts, cash, perks, upgrades, packs, score, round, map position and choices. It also checks that
#   - a normal and an elite node are a round (state play, riders), an elite clear gives two upgrade picks and every
#     other fight node one, a shop node opens the shop and a rest node the rest screen, neither with a round
#   - a boss node has its boss only after the riders are down, and no other fight node has one
#   - quitting while on the shop or rest screen (the node not finished) continues from the map screen before that
#     node, with what the run had there (the documented checkpoint rule, README alpha B3.3)
#   - the rest stop's EXTRA UPGRADE ends on a map screen that continues the same way
#   - winning the final boss clears the saved run, so there is nothing to CONTINUE
# It uses its own file (user://node_types_run_check.json) and never touches the real user://run.json. The final boss
# is won, which pays meta coins like any won run: the check runner gives every check its own empty save folder.
# Exits with status 1 and prints the problems when a check fails.

const RunSave = preload("res://scripts/run_save.gd")
const MapGen = preload("res://scripts/map_gen.gd")
const TEST_PATH = "user://node_types_run_check.json"
const WANT_TYPES = ["normal", "elite", "shop", "rest", "boss"]
const MAX_SEEDS = 200

var problems = []
var main
var seen = {}
var bosses_seen = 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.generated_arena = true  # the node's riders and boss are made for the generated arena (node_setup in main.gd)
	root.add_child(main)
	for i in range(3):
		await process_frame
	RunSave.test_path = TEST_PATH
	_remove_test_file()
	main.run_save_enabled = true
	_check_full_run()
	_check_rest_extra_upgrade()
	_remove_test_file()
	RunSave.test_path = ""
	_finish()


func _fail(text: String) -> void:
	problems.append(text)


func _remove_test_file() -> void:
	for suffix in ["", ".bak", ".replaced.bak", ".bad.bak", ".newer.bak"]:
		if FileAccess.file_exists(TEST_PATH + suffix):
			DirAccess.remove_absolute(TEST_PATH + suffix)


# ---- finding a seed and a path


# lanes (one per floor, floor 1 to the last floor before the final boss) that pass every wanted node type, or []
func _find_path(floors: Array) -> Array:
	var found = []
	for lane in range(floors[0].size()):
		_search(floors, 0, lane, [], found)
		if not found.is_empty():
			return found
	return []


func _search(floors: Array, f: int, lane: int, path: Array, found: Array) -> void:
	if not found.is_empty():
		return
	var next_path = path.duplicate()
	next_path.append(lane)
	if f == floors.size() - 2:  # the floor before the final boss: the path is complete
		var types = {}
		for i in range(next_path.size()):
			types[str(floors[i][next_path[i]]["type"])] = true
		for want in WANT_TYPES:
			if not types.has(want):
				return
		found.append_array(next_path)
		return
	for j in floors[f][lane]["next"]:
		_search(floors, f + 1, int(j), next_path, found)


# ---- what the run holds, to compare before quitting and after CONTINUE


func _snapshot() -> Dictionary:
	var perk_ids = main.perks.keys()
	perk_ids.sort()
	var up = {}
	for key in main.up:
		up[key] = snappedf(float(main.up[key]), 0.001)
	var shop_lvl = {}
	for key in main.shop_lvl:
		shop_lvl[key] = int(main.shop_lvl[key])
	var pending = {}
	for key in main.pending:
		pending[key] = (
			main.pending[key]
			if typeof(main.pending[key]) == TYPE_BOOL
			else snappedf(float(main.pending[key]), 0.001)
		)
	return {
		"state": main.state,
		"hearts": main.hearts,
		"max_hearts": main.MAXHEARTS,
		"cash": main.cash,
		"perks": perk_ids,
		"up": up,
		"shop_lvl": shop_lvl,
		"shop_buys": main.shop_buys,
		"pending": pending,
		"score": main.score,
		"kills": main.kills,
		"run_seed": main.run_seed,
		"round_n": main.round_n,
		"map_floor": main.map_floor,
		"map_lane": main.map_lane,
		"map_path": main.map_path.duplicate(),
		"map_choices": main.map_choices.duplicate(),
		"round_times": main.round_times.size(),
		"primary": main.primary,
		"melee_weapon": main.melee_weapon,
	}


# quit to the title as the pause menu does, then press CONTINUE; `label` says which node this followed
func _quit_and_continue(label: String) -> void:
	var before = _snapshot()
	if main.state != "map":
		_fail("%s: expected the map screen before quitting, the state is %s" % [label, main.state])
		return
	main.abandon_run()
	if main.state != "title":
		_fail("%s: quitting did not open the title screen (state %s)" % [label, main.state])
		return
	if main.saved_run.is_empty():
		_fail("%s: the title screen has nothing to CONTINUE" % label)
		return
	main.continue_run()
	var after = _snapshot()
	for key in before:
		if before[key] != after[key]:
			_fail(
				(
					"%s: after CONTINUE %s is %s, it was %s"
					% [label, key, str(after[key]), str(before[key])]
				)
			)


# ---- the full run


func _check_full_run() -> void:
	var seed_value = -1
	var path = []
	for n in range(MAX_SEEDS):
		var candidate = (n * 2654435761 + 4242) & 0xFFFFFFFF
		var map = MapGen.generate(candidate)
		if map.is_empty():
			continue
		path = _find_path(map["floors"])
		if not path.is_empty():
			seed_value = candidate
			break
	if seed_value < 0:
		_fail(
			(
				"no map among %d seeds has a path through a normal, elite, shop, rest and boss node"
				% MAX_SEEDS
			)
		)
		return
	main.start_game(false, seed_value)
	if main.state != "map":
		_fail(
			"seed %08X: a new run did not open the map screen (state %s)" % [seed_value, main.state]
		)
		return
	if not main.arena.rider_pursuit():
		_fail(
			(
				"seed %08X: the run is not on the generated arena, the nodes have no riders to check"
				% seed_value
			)
		)
		return
	var floors = main.run_map["floors"]
	_quit_and_continue("run start")
	for f in range(floors.size() - 1):
		var lane = int(path[f])
		var type = str(floors[f][lane]["type"])
		var label = "floor %d (%s)" % [f + 1, type]
		seen[type] = true
		if type == "shop":
			_walk_shop(lane, label)
		elif type == "rest":
			_walk_rest(lane, label)
		else:
			_walk_fight(f, lane, label)
		if main.state != "map":
			_fail("%s: the node did not end on the map screen (state %s)" % [label, main.state])
			return
		if main.round_n != f + 1 or main.map_floor != f:
			_fail(
				(
					"%s: round %d, floor index %d after the node"
					% [label, main.round_n, main.map_floor]
				)
			)
		_quit_and_continue("after " + label)
	for want in WANT_TYPES:
		if not seen.has(want):
			_fail("the walk never took a %s node" % want)
	if bosses_seen < 1:
		_fail("the walk never beat the mid boss")
	_walk_final_boss(floors.size() - 1, 0)


# the index of `lane` among the choices on the map screen, or -1
func _choice_of(lane: int) -> int:
	return main.map_choices.find(lane)


func _pick(lane: int, label: String) -> bool:
	var i = _choice_of(lane)
	if i < 0:
		_fail(
			(
				"%s: lane %d is not on the map screen (choices %s)"
				% [label, lane, str(main.map_choices)]
			)
		)
		return false
	main.pick_node(i)
	return true


# a normal, elite or boss node: a round with riders, a boss only on a boss node, then the clear screen and its picks
func _walk_fight(f: int, lane: int, label: String) -> void:
	var type = str(main.run_map["floors"][f][lane]["type"])
	if main.MAXHEARTS >= 2:
		main.hearts = main.MAXHEARTS - 1  # a hurt player, so the clear screen's heart is visible
	main.cash += 40
	if not _pick(lane, label):
		return
	if main.state != "play":
		_fail("%s: picking the node gave state %s, not play" % [label, main.state])
		return
	if main.PER_ROUND <= 0:
		_fail("%s: the round has no riders planned" % label)
	var is_boss = type == "boss"
	# every rider down, nobody on the road: the boss of a boss node is next, any other round is over
	main.clear_riders()
	main.clear_bosses()
	for i in range(main.PER_ROUND):
		main.hits[i] = true
	main.next_idx = main.PER_ROUND
	if main.need_boss() != is_boss:
		_fail(
			(
				"%s: need_boss is %s with the riders down, a %s node should say %s"
				% [label, main.need_boss(), type, is_boss]
			)
		)
	if is_boss:
		main.boss_count = 1  # the boss is beaten (boss_check.gd covers the fight itself)
		bosses_seen += 1
	var times = main.round_times.size()
	var hearts_before = main.hearts
	main.end_round()
	if main.state != "clear":
		_fail("%s: ending the round gave state %s, not clear" % [label, main.state])
		return
	if main.round_times.size() != times + 1:
		_fail("%s: the cleared round was not counted in round_times" % label)
	if main.hearts != mini(main.MAXHEARTS, hearts_before + 1):
		_fail(
			(
				"%s: hearts %d after the clear, expected %d"
				% [label, main.hearts, mini(main.MAXHEARTS, hearts_before + 1)]
			)
		)
	# the clear screen goes on to the upgrade pick (input.gd), an elite node pays a second one (README alpha B4)
	main.state_t = 1.0
	main.shop_sys.enter_upgrade()
	var want = 2 if type == "elite" else 1
	var picks = 0
	while main.state == "upgrade" and picks < 4:
		main.shop_sys.pick_upgrade(0)
		picks += 1
	if picks != want and main.shop_sys.upgrades_left() > 0:
		_fail("%s: %d upgrade picks after the node, expected %d" % [label, picks, want])


func _walk_shop(lane: int, label: String) -> void:
	main.cash += 400
	main.hearts = maxi(1, main.MAXHEARTS - 1)
	main.save_checkpoint()  # the run as it is on this map screen is what CONTINUE brings back
	var cash_before_node = main.cash
	var before_node = _snapshot()
	if not _pick(lane, label):
		return
	if main.state != "shop":
		_fail("%s: picking the node gave state %s, not shop" % [label, main.state])
		return
	if not main.riders.is_empty() or not main.bosses.is_empty():
		_fail("%s: a shop node has riders or a boss" % label)
	# quit on the shop screen: the run comes back at the map screen before this node, as it was there
	_quit_on_screen_and_back(label, before_node)
	if main.state != "map":
		return
	if not _pick(lane, label):
		return
	# buy one perk if one is on sale, else anything affordable
	var bought = -1
	for i in range(main.shop_items.size()):
		var it = main.shop_items[i]
		if it["sold"] or it["cost"] > main.cash:
			continue
		if it["kind"] == "perk":
			bought = i
			break
		if bought < 0 and it["kind"] != "heal":
			bought = i
	if bought < 0:
		_fail("%s: nothing on sale can be bought with %d cash" % [label, main.cash])
	else:
		var buys = main.shop_buys
		main.shop_sys.buy(bought)
		if main.shop_buys != buys + 1 or main.cash >= cash_before_node:
			_fail("%s: buying did not count or did not cost cash" % label)
	main.shop_sys.leave_shop()


func _walk_rest(lane: int, label: String) -> void:
	main.hearts = 1
	main.save_checkpoint()
	var before_node = _snapshot()
	if not _pick(lane, label):
		return
	if main.state != "rest":
		_fail("%s: picking the node gave state %s, not rest" % [label, main.state])
		return
	if not main.riders.is_empty() or not main.bosses.is_empty():
		_fail("%s: a rest node has riders or a boss" % label)
	_quit_on_screen_and_back(label, before_node)
	if main.state != "map":
		return
	if not _pick(lane, label):
		return
	main.shop_sys.rest_choose(0)  # REFILL HEARTS
	if main.hearts != main.MAXHEARTS:
		_fail("%s: REFILL left %d of %d hearts" % [label, main.hearts, main.MAXHEARTS])


# the node is on its screen and not finished: quit to the title and CONTINUE comes back at the map screen before it
func _quit_on_screen_and_back(label: String, before_node: Dictionary) -> void:
	main.abandon_run()
	if main.state != "title" or main.saved_run.is_empty():
		_fail(
			(
				"%s: quitting on the node's screen left no run to CONTINUE (state %s)"
				% [label, main.state]
			)
		)
		return
	main.continue_run()
	var after = _snapshot()
	if main.state != "map":
		_fail(
			"%s: CONTINUE from the node's screen gave state %s, not the map" % [label, main.state]
		)
		return
	for key in before_node:
		if before_node[key] != after[key]:
			_fail(
				(
					"%s: quitting on the screen, CONTINUE has %s %s, expected %s"
					% [label, key, str(after[key]), str(before_node[key])]
				)
			)


# the last floor: the final boss, a minister after the riders. Winning ends the run and leaves nothing to CONTINUE
func _walk_final_boss(f: int, lane: int) -> void:
	var label = "floor %d (final boss)" % (f + 1)
	if str(main.run_map["floors"][f][lane]["type"]) != "boss":
		_fail("%s: the last floor is not a boss node" % label)
		return
	main.cash += 10
	if not _pick(lane, label):
		return
	if main.state != "play" or not main.is_final_round():
		_fail("%s: state %s, final round %s" % [label, main.state, main.is_final_round()])
		return
	main.clear_riders()
	main.clear_bosses()
	for i in range(main.PER_ROUND):
		main.hits[i] = true
	main.next_idx = main.PER_ROUND
	if not main.need_boss():
		_fail("%s: the final boss does not come after the riders" % label)
	main.boss_count = 1
	main.final_boss_dead = true
	main.end_round()
	if main.state != "over" or main.over_reason != "victory":
		_fail(
			(
				"%s: winning gave state %s (%s), not the victory screen"
				% [label, main.state, main.over_reason]
			)
		)
	if not RunSave.load_file().is_empty():
		_fail("%s: the won run is still saved" % label)
	main.go_to_title()
	if not main.saved_run.is_empty():
		_fail("%s: the title screen offers CONTINUE after the run was won" % label)


# ---- the rest stop's EXTRA UPGRADE


func _check_rest_extra_upgrade() -> void:
	main.start_game(false, 0x13579BDF)
	if main.state != "map" or main.run_map.is_empty():
		_fail("rest extra upgrade: a new run did not open the map screen")
		return
	main.run_map["floors"][0][0]["type"] = "rest"  # floor 1 does not make a rest node, so this one is made to
	main.hearts = 1
	main.pick_node(0)
	if main.state != "rest":
		_fail("rest extra upgrade: the node gave state %s, not rest" % main.state)
		return
	main.shop_sys.rest_choose(1)  # EXTRA UPGRADE
	if main.state != "upgrade":
		_fail("rest extra upgrade: the choice gave state %s, not the upgrade screen" % main.state)
		return
	main.shop_sys.pick_upgrade(0)
	if main.state != "map":
		_fail("rest extra upgrade: the pick gave state %s, not the map" % main.state)
		return
	_quit_and_continue("rest node with EXTRA UPGRADE")


func _finish() -> void:
	if problems.is_empty():
		print(
			"node_types_run_check: every node type was walked and the run continued from the map screen after each"
		)
		quit(0)
	else:
		print("node_types_run_check: %d problem(s)" % problems.size())
		for p in problems.slice(0, 15):
			print("  " + p)
		quit(1)
