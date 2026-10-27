extends SceneTree
# Checks the rest node (README alpha B3, Milestone D "Rest stop"): a map node of type `rest` is a screen with two
# choices, REFILL HEARTS and EXTRA UPGRADE, and not a round. Run from the project folder:
#   godot --headless --path . --script res://tools/rest_node_check.gd
# It checks that
#   - picking a rest node opens the rest screen and no round: the round number is the floor, no riders, no boss,
#     no round time, and the node counts as a screen in `screens_passed`
#   - REFILL HEARTS sets the hearts to MAXHEARTS and goes to the map screen, which is the checkpoint a saved run
#     continues from (the hearts in it are the refilled ones)
#   - EXTRA UPGRADE opens one upgrade pick with three offers, labelled as the rest stop's, and the pick goes to the
#     map screen
#   - a choice that would do nothing (full hearts, no upgrade left) is refused and the screen stays, unless
#     neither can do anything, when REFILL leaves the stop
#   - keys 1 and 2, Left / Right with Enter, and the cards under the mouse choose, and the keys are ignored in the
#     first moment of the screen (a held key must not pick)
#   - the screen draws at 1280x720 and 1920x1080 with its cards on screen and apart from each other
#   - the rest screen is counted in `shop_time` and not in `play_time`
# Exits with status 1 and prints the problems when a check fails.

const SEED = 0x13572468

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_check_refill()
	_check_extra_upgrade()
	_check_refused()
	_check_keys()
	await _check_drawing()
	_check_time()
	_finish()


func _fail(text: String) -> void:
	problems.append(text)


func _key(code: int) -> void:
	var e = InputEventKey.new()
	e.pressed = true
	e.keycode = code
	main.input_sys.handle_input(e)


# starts a run on SEED and turns the first node of floor 1 into a rest node, then picks it
func _enter_rest() -> void:
	main.start_game(false, SEED)
	main.run_map["floors"][0][0]["type"] = "rest"
	main.pick_node(0)


func _check_refill() -> void:
	_enter_rest()
	if main.state != "rest":
		_fail("picking a rest node gave state %s, not rest" % main.state)
		return
	if main.round_n != 1 or main.map_floor != 0:
		_fail("the rest node made round %d on floor index %d" % [main.round_n, main.map_floor])
	if not main.riders.is_empty() or not main.bosses.is_empty():
		_fail("the rest node has riders or a boss")
	if main.rest_opts.size() != 2:
		_fail("the rest screen has %d choices, not 2" % main.rest_opts.size())
		return
	if main.screens_passed() != 0:
		_fail("screens_passed is %d on the rest node itself" % main.screens_passed())
	var times = main.round_times.size()
	var buys = main.shop_buys
	main.hearts = 1
	main.shop_sys.rest_choose(0)
	if main.hearts != main.MAXHEARTS:
		_fail("REFILL HEARTS left %d of %d hearts" % [main.hearts, main.MAXHEARTS])
	if main.state != "map":
		_fail("REFILL HEARTS led to state %s, not the map" % main.state)
	if main.round_times.size() != times or main.shop_buys != buys:
		_fail("the rest node changed round_times or shop_buys")
	if main.round_n != 1:
		_fail("the round number is %d after the rest node, the floor is 1" % main.round_n)
	var saved = main.RunSave.capture(main)
	if int(saved.get("hearts", -1)) != main.MAXHEARTS:
		_fail(
			(
				"the checkpoint on the map screen has %s hearts, not the refilled ones"
				% saved.get("hearts")
			)
		)
	# one floor on: the node walked before counts as a screen, not as a cleared round
	if main.state == "map":
		main.pick_node(0)
		if main.screens_passed() != 1:
			_fail("screens_passed is %d one floor after a rest node, not 1" % main.screens_passed())


func _check_extra_upgrade() -> void:
	_enter_rest()
	main.hearts = main.MAXHEARTS
	main.state_t = 1.0
	main.shop_sys.rest_choose(1)
	if main.state != "upgrade":
		_fail("EXTRA UPGRADE led to state %s, not the upgrade pick" % main.state)
		return
	if main.offers.size() != 3:
		_fail("the extra upgrade offers %d cards, not 3" % main.offers.size())
	if not main.rest_upgrade:
		_fail("the upgrade pick does not know it is the rest stop's")
	main.shop_sys.pick_upgrade(0)
	if main.state != "map":
		_fail("the extra upgrade pick led to state %s, not the map" % main.state)
	if main.rest_upgrade:
		_fail("rest_upgrade is still set on the map screen")
	# a normal upgrade pick after a fight is not labelled as the rest stop's
	if main.state == "map":
		main.shop_sys.enter_upgrade()
		if main.rest_upgrade:
			_fail("an upgrade pick after a fight is labelled as the rest stop's")
		main.shop_sys.pick_upgrade(0)


func _check_refused() -> void:
	# full hearts: REFILL is refused, the screen stays and the choice is still there
	_enter_rest()
	main.hearts = main.MAXHEARTS
	main.shop_sys.rest_choose(0)
	if main.state != "rest":
		_fail("REFILL with full hearts left the rest screen (state %s)" % main.state)
	# no upgrade left: EXTRA UPGRADE is refused
	main.hearts = 1
	var all_upgrades = main.UPGRADES
	main.UPGRADES = []
	main.shop_sys.rest_choose(1)
	if main.state != "rest":
		_fail("EXTRA UPGRADE with nothing left left the rest screen (state %s)" % main.state)
	# neither works: REFILL leaves the stop, so the node is never a dead end
	main.hearts = main.MAXHEARTS
	main.shop_sys.rest_choose(0)
	main.UPGRADES = all_upgrades
	if main.state != "map":
		_fail("with nothing to do, REFILL did not leave the rest stop (state %s)" % main.state)
	# a choice outside the screen, and a call from another screen, do nothing
	_enter_rest()
	main.shop_sys.rest_choose(2)
	main.shop_sys.rest_choose(-1)
	if main.state != "rest":
		_fail("a choice number outside the screen changed the state to %s" % main.state)
	main.state = "map"
	main.shop_sys.rest_choose(0)
	if main.state != "map":
		_fail("rest_choose worked outside the rest screen")


func _check_keys() -> void:
	# keys 1 and 2
	_enter_rest()
	main.hearts = 1
	main.state_t = 1.0
	_key(KEY_1)
	if main.state != "map" or main.hearts != main.MAXHEARTS:
		_fail(
			(
				"key 1 on the rest screen did not refill (state %s, hearts %d)"
				% [main.state, main.hearts]
			)
		)
	_enter_rest()
	main.hearts = main.MAXHEARTS
	main.state_t = 1.0
	_key(KEY_2)
	if main.state != "upgrade":
		_fail("key 2 on the rest screen did not open the extra upgrade (state %s)" % main.state)
	main.shop_sys.pick_upgrade(0)
	# Left / Right move the highlight (and wrap), Enter takes it
	_enter_rest()
	main.hearts = 1
	main.state_t = 1.0
	_key(KEY_RIGHT)
	if main.menu_sel != 1:
		_fail("Right on the rest screen moved the highlight to %d, not 1" % main.menu_sel)
	_key(KEY_RIGHT)
	if main.menu_sel != 0:
		_fail("Right on the last card did not wrap to the first (%d)" % main.menu_sel)
	_key(KEY_LEFT)
	if main.menu_sel != 1:
		_fail("Left on the first card did not wrap to the last (%d)" % main.menu_sel)
	_key(KEY_LEFT)
	_key(KEY_ENTER)
	if main.state != "map" or main.hearts != main.MAXHEARTS:
		_fail("Enter on REFILL did not refill (state %s, hearts %d)" % [main.state, main.hearts])
	# keys held from the last screen are ignored in the first moment
	_enter_rest()
	main.hearts = 1
	main.state_t = 0.0
	_key(KEY_1)
	_key(KEY_ENTER)
	if main.state != "rest" or main.hearts != 1:
		_fail("a key in the first moment of the rest screen chose (state %s)" % main.state)


func _check_drawing() -> void:
	_enter_rest()
	for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]:
		main.hud.size = s
		for i in range(2):
			main.hud.queue_redraw()
			await process_frame
		var rects = []
		for i in range(2):
			var r = main.hud.card_rect(i, 2)
			rects.append(r)
			if not Rect2(Vector2.ZERO, s).encloses(r):
				_fail("at %dx%d card %d is not on screen" % [s.x, s.y, i + 1])
			if main.hud.card_at(r.get_center()) != i:
				_fail("at %dx%d the middle of card %d is not card %d" % [s.x, s.y, i + 1, i + 1])
		if rects[0].intersects(rects[1]):
			_fail("at %dx%d the two cards overlap" % [s.x, s.y])
		if main.hud.card_at(Vector2(2.0, 2.0)) != -1:
			_fail("at %dx%d a point outside the cards chose one" % [s.x, s.y])
	main.hud.size = Vector2(1280.0, 720.0)


func _check_time() -> void:
	_enter_rest()
	var shop_before = main.shop_time
	var play_before = main.play_time
	main.update_game(0.5)
	if main.shop_time <= shop_before:
		_fail("time on the rest screen is not counted in shop_time")
	if main.play_time != play_before:
		_fail("time on the rest screen is counted as play_time")


func _finish() -> void:
	if problems.is_empty():
		print("rest_node_check: the rest node is a screen with two working choices and no round")
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("rest_node_check: " + line)
		quit(1)
