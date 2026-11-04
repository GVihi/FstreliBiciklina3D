extends SceneTree
# Checks the PLAY page where the Heat level is chosen (README Milestone B, "Difficulty Scaling", chunk H1.4; design in
# docs/HEAT.md):
#   - PLAY on the title menu opens the page and does not start a run; Esc and the gamepad's B go back,
#   - Left / Right (and the D-pad) change the level by one and stop at both ends of the ladder, every change is saved
#     in settings.cfg (a round trip through the real file), and Up / Down do nothing to it,
#   - the page draws for every level at two window shapes, and its buttons stay on the screen without overlapping,
#   - Enter and the gamepad's A start a run (loading screen, then the map) that keeps the chosen level,
#   - a click on an arrow or on START does what the keyboard does, a click beside the page goes back,
#   - a RESTART RUN keeps the level, a Daily Run (it has no Heat choice) is always Heat 0.
# Run from the project folder:
#   godot --headless --path . --script res://tools/heat_picker_check.gd
# or: python tools/run_checks.py heat
# Exits with status 1 and prints the problems when a check fails.

const SETTINGS_PATH = "user://settings.cfg"

var problems = []
var main
var kept_settings = PackedByteArray()
var had_settings = false


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_keep_settings()
	main.go_to_title()
	main.heat = 0
	_check_opens_and_goes_back()
	_check_levels()
	await _check_drawing()
	_check_start()
	_check_clicks()
	_check_restart_and_daily()
	_restore_settings()
	_finish()


# the index of the title entry with this id, or -1
func _entry(id: String) -> int:
	for i in range(main.hud.TITLE_ITEMS.size()):
		if main.hud.TITLE_ITEMS[i]["id"] == id:
			return i
	return -1


func _open_page() -> void:
	main.go_to_title()
	main.input_sys.title_activate(_entry("play"))


func _check_opens_and_goes_back() -> void:
	if _entry("play") < 0:
		_fail("the title menu has no PLAY entry")
		return
	_open_page()
	if main.state != "title" or main.title_page != "play":
		_fail(
			(
				"PLAY did not open the Heat page (state '%s', page '%s')"
				% [main.state, main.title_page]
			)
		)
	_press(KEY_ESCAPE)
	if main.title_page != "" or main.state != "title":
		_fail(
			"Escape did not go back from the PLAY page without a run (page '%s')" % main.title_page
		)
	_open_page()
	main.input_sys.on_pad_button(JOY_BUTTON_B)
	if main.title_page != "" or main.state != "title":
		_fail("the gamepad's B did not go back from the PLAY page")


# Left / Right change the level one at a time and stop at the ends, and it is saved
func _check_levels() -> void:
	var top = main.heat_sys.top_level()
	if top < 1:
		_fail("the Heat table has only level 0, so there is nothing to choose")
		return
	main.heat = 0
	_open_page()
	_press(KEY_LEFT)
	if main.heat != 0:
		_fail("Left at Heat 0 went to %d" % main.heat)
	for want in range(1, top + 1):
		_press(KEY_RIGHT)
		if main.heat != want:
			_fail("Right did not go to Heat %d (it is %d)" % [want, main.heat])
		if _saved_heat() != want:
			_fail("Heat %d was not saved in settings.cfg (it says %s)" % [want, str(_saved_heat())])
	_press(KEY_RIGHT)
	if main.heat != top:
		_fail("Right at the top level went to %d, not %d" % [main.heat, top])
	main.input_sys.on_pad_button(JOY_BUTTON_DPAD_LEFT)
	if main.heat != top - 1:
		_fail("the D-pad's left did not go down one level (it is %d)" % main.heat)
	main.input_sys.on_pad_button(JOY_BUTTON_DPAD_RIGHT)
	if main.heat != top:
		_fail("the D-pad's right did not go up one level (it is %d)" % main.heat)
	_press(KEY_UP)
	_press(KEY_DOWN)
	if main.heat != top or main.title_page != "play":
		_fail(
			"Up and Down changed the Heat page (level %d, page '%s')" % [main.heat, main.title_page]
		)
	# Left and Right on the plain menu must not touch the level
	main.go_to_title()
	_press(KEY_LEFT)
	_press(KEY_RIGHT)
	if main.heat != top:
		_fail("Left / Right on the title menu changed the level to %d" % main.heat)


# every level draws, at two window shapes, and the buttons are on the screen and apart
func _check_drawing() -> void:
	for level in range(main.heat_sys.top_level() + 1):
		main.heat = level
		_open_page()
		for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]:
			main.hud.size = s
			for f in range(2):
				main.hud.queue_redraw()
				await process_frame
			var screen = Rect2(Vector2.ZERO, s)
			var rects = {
				"the Heat row": main.hud.heat_row_rect(),
				"the left arrow": main.hud.heat_arrow_rect(-1),
				"the right arrow": main.hud.heat_arrow_rect(1),
				"START": main.hud.play_start_rect(),
			}
			for name in rects:
				if not screen.encloses(rects[name]):
					_fail("%s is not inside a %s screen" % [name, str(s)])
			if main.hud.heat_row_rect().intersects(main.hud.play_start_rect()):
				_fail("the Heat row and START overlap on a %s screen" % str(s))
			if main.hud.heat_arrow_rect(-1).intersects(main.hud.heat_arrow_rect(1)):
				_fail("the two arrows overlap on a %s screen" % str(s))
	main.hud.size = Vector2(1280.0, 720.0)
	main.go_to_title()


# Enter and the gamepad's A start a run that keeps the level
func _check_start() -> void:
	var level = mini(2, main.heat_sys.top_level())
	main.heat = level
	_open_page()
	_press(KEY_ENTER)
	if main.state != "loading":
		_fail("Enter on the PLAY page did not show the loading screen (state '%s')" % main.state)
	main.finish_loading()
	if main.state == "title" or main.daily_mode or main.custom_seed_run:
		_fail("Enter on the PLAY page did not start a normal run (state '%s')" % main.state)
	if main.heat != level:
		_fail("the run started at Heat %d, not the chosen %d" % [main.heat, level])
	main.go_to_title()
	_open_page()
	main.input_sys.on_pad_button(JOY_BUTTON_A)
	if main.state != "loading":
		_fail("the gamepad's A on the PLAY page did not start a run (state '%s')" % main.state)
	main.finish_loading()
	if main.heat != level:
		_fail("the run started with A at Heat %d, not the chosen %d" % [main.heat, level])
	main.go_to_title()


# the mouse: an arrow changes the level, START starts, a click beside the page goes back. Headless Godot may not move
# the mouse (the click handler reads its position from the viewport), so a click is only tried where the mouse really
# arrived; the keyboard and gamepad paths above do not depend on it
func _check_clicks() -> void:
	main.hud.size = Vector2(1280.0, 720.0)
	main.heat = 0
	_open_page()
	if _click_at(main.hud.heat_arrow_rect(1).get_center()):
		if main.heat != 1:
			_fail("a click on the right arrow did not go to Heat 1 (it is %d)" % main.heat)
		if _click_at(main.hud.heat_arrow_rect(-1).get_center()):
			if main.heat != 0 or main.title_page != "play":
				_fail("a click on the left arrow did not go back to Heat 0 (it is %d)" % main.heat)
	if _click_at(main.hud.heat_row_rect().get_center()):
		if main.title_page != "play":
			_fail("a click on the Heat row closed the page")
	if _click_at(main.hud.play_start_rect().get_center()):
		if main.state != "loading":
			_fail("a click on START did not show the loading screen (state '%s')" % main.state)
		main.finish_loading()
		main.go_to_title()
	_open_page()
	if _click_at(Vector2(20.0, 700.0)):
		if main.title_page != "" or main.state != "title":
			_fail("a click beside the page did not go back (page '%s')" % main.title_page)
	main.go_to_title()


# a restart keeps the level, a Daily Run is Heat 0 and the next normal run is back at the chosen level only when it is
# chosen again (the Daily Run has no Heat choice, so it does not remember one)
func _check_restart_and_daily() -> void:
	var level = mini(2, main.heat_sys.top_level())
	main.heat = level
	main.start_game()
	main.restart_run()
	if main.heat != level:
		_fail("RESTART RUN changed the level from %d to %d" % [level, main.heat])
	main.go_to_title()
	main.heat = level
	main.input_sys.title_activate(_entry("daily"))
	if main.state != "loading":
		_fail(
			"DAILY RUN on the title menu did not show the loading screen (state '%s')" % main.state
		)
	main.finish_loading()
	if not main.daily_mode or main.heat != 0:
		_fail(
			"the Daily Run was not Heat 0 (daily %s, level %d)" % [str(main.daily_mode), main.heat]
		)
	main.restart_run()
	if not main.daily_mode or main.heat != 0:
		_fail("a restarted Daily Run was not Heat 0 (level %d)" % main.heat)
	main.go_to_title()


# the `heat` value of settings.cfg as the game wrote it, or -1 when there is none
func _saved_heat() -> int:
	var cf = ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return -1
	var v = cf.get_value("game", "heat", -1)
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return -1
	return int(v)


# the real settings.cfg is kept in memory and written back at the end
func _keep_settings() -> void:
	had_settings = FileAccess.file_exists(SETTINGS_PATH)
	if had_settings:
		kept_settings = FileAccess.get_file_as_bytes(SETTINGS_PATH)


func _restore_settings() -> void:
	if had_settings:
		var f = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		if f:
			f.store_buffer(kept_settings)
			f.close()
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	main.settings.load_settings()


# a left click with the mouse over `pos`; false (and no click) when the mouse could not be moved there
func _click_at(pos: Vector2) -> bool:
	main.get_viewport().warp_mouse(pos)
	if main.get_viewport().get_mouse_position().distance_to(pos) > 2.0:
		return false
	main.input_sys.on_click()
	return true


func _press(code: int) -> void:
	var e = InputEventKey.new()
	e.pressed = true
	e.keycode = code
	main.input_sys.handle_input(e)


func _finish() -> void:
	if problems.is_empty():
		print(
			"heat_picker_check: the PLAY page picks the Heat level, saves it, starts runs with it and keeps the Daily Run at 0"
		)
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("heat_picker_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
