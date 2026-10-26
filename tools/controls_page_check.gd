extends SceneTree
# Checks the CONTROLS page (README Milestone A, menu follow-ups): the entry on the title menu and on the pause menu,
# that the menus still fit on the screen with the extra button, that the page opens, draws and closes, and that
# the lists name the reload key.
# Run from the project folder:
#   godot --headless --path . --script res://tools/controls_page_check.gd
# or with tools\run_controls_page_check.bat on Windows.
# Exits with status 1 and prints the problems when a check fails.

const SEED = 0x1234ABCD

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_check_lists()
	await _check_title()
	await _check_pause()
	_finish()


# every row has a key and an action, and both lists name the reload control
func _check_lists() -> void:
	var hud = main.hud
	for list in [hud.CONTROLS_KEYBOARD, hud.CONTROLS_GAMEPAD, hud.CONTROLS_SCREENS]:
		for row in list:
			if row.size() != 2 or str(row[0]) == "" or str(row[1]) == "":
				_fail("a controls row is not a key and an action: %s" % str(row))
	var keyboard_reload = false
	for row in hud.CONTROLS_KEYBOARD:
		if row[0] == "R" and str(row[1]).begins_with("RELOAD"):
			keyboard_reload = true
	if not keyboard_reload:
		_fail("the keyboard list does not say that R reloads")
	var pad_reload = false
	for row in hud.CONTROLS_GAMEPAD:
		if row[0] == "X" and str(row[1]).begins_with("RELOAD"):
			pad_reload = true
	if not pad_reload:
		_fail("the gamepad list does not say that X reloads")
	# the map is held with M, or with Back / View on a gamepad (it is no longer in the pause menu)
	var keyboard_map = false
	for row in hud.CONTROLS_KEYBOARD:
		if row[0] == "M" and str(row[1]).contains("MAP"):
			keyboard_map = true
	if not keyboard_map:
		_fail("the keyboard list does not say that M shows the map")
	var pad_map = false
	for row in hud.CONTROLS_GAMEPAD:
		if str(row[0]).begins_with("BACK") and str(row[1]).contains("MAP"):
			pad_map = true
	if not pad_map:
		_fail("the gamepad list does not say that Back shows the map")


func _check_title() -> void:
	main.go_to_title()
	main.hud.size = Vector2(1280.0, 720.0)
	var hud = main.hud
	var item = -1
	for i in range(hud.TITLE_ITEMS.size()):
		if hud.TITLE_ITEMS[i]["id"] == "controls":
			item = i
	if item < 0:
		_fail("the title menu has no CONTROLS entry")
		return
	# the buttons stay in order, inside the screen and clear of the high score line
	for i in range(hud.TITLE_ITEMS.size() - 1):
		if hud.title_rect(i).end.y > hud.title_rect(i + 1).position.y:
			_fail("title buttons %d and %d overlap" % [i, i + 1])
	var last = hud.title_rect(hud.TITLE_ITEMS.size() - 1)
	if last.end.y > 720.0 * 0.885 - 20.0:
		_fail("the last title button ends at %.0f, too close to the high score text" % last.end.y)
	main.input_sys.title_activate(item)
	if main.title_page != "controls":
		_fail("choosing CONTROLS opened '%s'" % main.title_page)
	# draw the page a few times, at two window shapes (a script error in the drawing code shows up here)
	for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]:
		main.hud.size = s
		for f in range(2):
			main.hud.queue_redraw()
			await process_frame
	main.hud.size = Vector2(1280.0, 720.0)
	_press(KEY_ESCAPE)
	if main.title_page != "":
		_fail("Escape did not close the CONTROLS page (page '%s')" % main.title_page)
	main.input_sys.title_activate(item)
	main.input_sys.on_click()
	if main.title_page != "":
		_fail("a click did not close the CONTROLS page (page '%s')" % main.title_page)


func _check_pause() -> void:
	main.start_game(false, SEED)
	if main.state == "map":
		main.pick_node(0)
	# headless Godot cannot capture the mouse, so the test hook plays the round
	main.force_captured = true
	await process_frame
	await process_frame
	if main.state != "play":
		_fail("could not start a round (state %s)" % main.state)
		return
	main.pause_on_focus_loss()
	await process_frame
	await process_frame
	if not main.paused:
		_fail("could not pause the round")
		return
	var hud = main.hud
	var item = -1
	for i in range(hud.PAUSE_ITEMS.size()):
		if hud.PAUSE_ITEMS[i]["id"] == "controls":
			item = i
	if item < 0:
		_fail("the pause menu has no CONTROLS entry")
		return
	for i in range(hud.PAUSE_ITEMS.size() - 1):
		if hud.pause_rect(i).end.y > hud.pause_rect(i + 1).position.y:
			_fail("pause buttons %d and %d overlap" % [i, i + 1])
	var last = hud.pause_rect(hud.PAUSE_ITEMS.size() - 1)
	if last.end.y > main.hud.size.y * 0.80 - 10.0:
		_fail("the last pause button ends at %.0f, on the ESC TO RESUME text" % last.end.y)
	main.input_sys.pause_activate(item)
	if main.pause_page != "controls":
		_fail("choosing CONTROLS in the pause menu opened '%s'" % main.pause_page)
	for f in range(2):
		main.hud.queue_redraw()
		await process_frame
	if not main.paused:
		_fail("opening the CONTROLS page resumed the game")
	main.input_sys.pause_back()
	if main.pause_page != "" or not main.paused:
		_fail("Escape on the CONTROLS page did not go back to the pause menu")
	# Tab must not jump from the page to the settings
	main.input_sys.pause_activate(item)
	_press(KEY_TAB)
	if main.pause_page != "controls":
		_fail("Tab on the CONTROLS page changed the page to '%s'" % main.pause_page)
	# the other entries still do what they did
	main.input_sys.pause_back()
	var settings_item = -1
	for i in range(hud.PAUSE_ITEMS.size()):
		if hud.PAUSE_ITEMS[i]["id"] == "settings":
			settings_item = i
	main.input_sys.pause_activate(settings_item)
	if main.pause_page != "settings":
		_fail("the SETTINGS entry opened '%s'" % main.pause_page)
	main.input_sys.pause_back()


func _finish() -> void:
	if problems.is_empty():
		print(
			"controls_page_check: the CONTROLS page opens, draws and closes from the title and the pause menu"
		)
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("controls_page_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


func _press(code: int) -> void:
	var e = InputEventKey.new()
	e.pressed = true
	e.keycode = code
	main.input_sys.handle_input(e)
