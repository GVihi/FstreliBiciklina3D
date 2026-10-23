extends SceneTree
# Checks the CUSTOM SEED page of the title screen (README Milestone G, optional item): typing, the limits, starting
# a run on the typed seed, the restart, and that such a run is not ranked.
# Run from the project folder:
#   godot --headless --path . --script res://tools/seed_page_check.gd
# Exits with status 1 and prints the problems when a check fails.

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	main.go_to_title()
	var seed_item = -1
	for i in range(main.hud.TITLE_ITEMS.size()):
		if main.hud.TITLE_ITEMS[i]["id"] == "seed":
			seed_item = i
	if seed_item < 0:
		_fail("the title menu has no CUSTOM SEED entry")
		_finish()
		return
	# the buttons of the menu must stay on the screen, clear of the high score line
	main.hud.size = Vector2(1280.0, 720.0)
	var last = main.hud.title_rect(main.hud.TITLE_ITEMS.size() - 1)
	if last.end.y > 720.0 * 0.885 - 20.0:
		_fail("the last title button ends at %.0f, too close to the high score text" % last.end.y)
	main.input_sys.title_activate(seed_item)
	if main.title_page != "seed" or main.seed_buf != "":
		_fail("choosing CUSTOM SEED did not open an empty seed page")
	var muted_before = main.sfx.muted
	# letters that are hotkeys elsewhere must not fire, digits and A-F are typed, others are dropped
	for ch in "7f3Mxa91c2Z9":
		_type(ch)
	if main.seed_buf != "7F3A91C2":
		_fail(
			(
				"typing 7f3Mxa91c2Z9 gave '%s', expected 7F3A91C2 (8 hex digits at most)"
				% main.seed_buf
			)
		)
	if main.sfx.muted != muted_before or main.state != "title":
		_fail("a typed letter fired a hotkey")
	_press(KEY_BACKSPACE)
	if main.seed_buf != "7F3A91C":
		_fail("Backspace left '%s'" % main.seed_buf)
	_type("2")
	# Escape goes back without starting a run
	_press(KEY_ESCAPE)
	if main.title_page != "" or main.state != "title":
		_fail("Escape did not go back to the title menu")
	# an empty seed does not start a run
	main.input_sys.title_activate(seed_item)
	_press(KEY_ENTER)
	if main.state != "title":
		_fail("Enter on an empty seed started a run")
	# Enter on a typed seed plays exactly that seed
	for ch in "7F3A91C2":
		_type(ch)
	_press(KEY_ENTER)
	if main.state == "title" or main.run_seed != 0x7F3A91C2 or not main.custom_seed_run:
		_fail(
			(
				"Enter did not start a run on seed 7F3A91C2 (state %s, seed %08X)"
				% [main.state, main.run_seed]
			)
		)
	if main.ranked_run():
		_fail("a custom-seed run counts as ranked")
	var map_text = JSON.stringify(main.run_map)
	# the same seed makes the same map as the generator
	if map_text != JSON.stringify(main.MapGenScript.generate(0x7F3A91C2)):
		_fail("the run map is not the map MapGen makes for the typed seed")
	# a finished custom-seed run is kept out of the Top 10
	main.score = 5000
	if main.scores.submit_run() != -1:
		_fail("a custom-seed run got into the Top 10")
	# a restart from the pause menu replays the same seed
	main.start_game(main.daily_mode, main.run_seed if main.custom_seed_run else -1)
	if main.run_seed != 0x7F3A91C2 or JSON.stringify(main.run_map) != map_text:
		_fail("a restart did not replay the typed seed")
	# a normal run afterwards is random and ranked again
	main.start_game()
	if main.custom_seed_run or not main.ranked_run():
		_fail("a normal run after a custom-seed run is still unranked")
	# a daily run stays unranked, and is not a custom seed
	main.start_game(true)
	if main.custom_seed_run or main.ranked_run() or main.run_seed != main.daily_seed:
		_fail(
			"a Daily Run changed: custom %s ranked %s" % [main.custom_seed_run, main.ranked_run()]
		)
	_finish()


func _finish() -> void:
	if problems.is_empty():
		print(
			"seed_page_check: the CUSTOM SEED page types, limits, starts, restarts and stays unranked as it should"
		)
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("seed_page_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


func _type(ch: String) -> void:
	var e = InputEventKey.new()
	e.pressed = true
	e.unicode = ch.unicode_at(0)
	e.keycode = OS.find_keycode_from_string(ch.to_upper())
	main.input_sys.handle_input(e)


func _press(code: int) -> void:
	var e = InputEventKey.new()
	e.pressed = true
	e.keycode = code
	main.input_sys.handle_input(e)
