extends SceneTree
# Checks the intro screen and the menu backdrop (README V5.0). Run from the project folder, best through the runner:
#   python tools/run_checks.py menu_backdrop
# or by hand:
#   godot --headless --path . --script res://tools/menu_backdrop_check.gd
# It checks that
#   - a check (no main scene) starts on the title menu with no intro, and a real launch asks for the intro unless a
#     developer start option was applied (`Main.wants_intro`)
#   - while the intro is up, the title menu finds no button, a key before the first moments is ignored, a modifier key, a
#     repeated key and a mouse button release are ignored, and then a key, a mouse click and a gamepad button each end it
#   - nothing turns the intro on again: going to the title (what QUIT TO TITLE does) leaves it off
#   - the intro (fading in and later), the title menu and the title pages, which all draw the backdrop, draw at five
#     window shapes and a tiny one (a script error in the drawing code shows up here), and the formula the skyline and the
#     stars come from gives the same number every time
#   - no menu is drawn over the game any more: the only `_dim(` call left in hud.gd is the map held down in a round
# Pixels cannot be read under --headless (there is no renderer), so what the picture looks like is for the owner's eyes:
# start the game from the editor and look at the intro, the title menu, a page, the run map, the shop and the pause menu.
# Exits with status 1 and prints the problems when a check fails.

const SIZES = [
	Vector2(1280.0, 720.0),
	Vector2(1920.0, 1080.0),
	Vector2(1024.0, 768.0),
	Vector2(1280.0, 1024.0),
	Vector2(700.0, 800.0)
]
const TITLE_PAGES = ["loadout", "unlocks", "challenges", "scores", "controls", "settings"]

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_check_start()
	_check_wants_intro()
	_check_input()
	_check_stays_off()
	await _check_drawing()
	_check_no_menu_over_the_game()
	_finish()


func _fail(text: String) -> void:
	problems.append(text)


func _key(code: int, pressed: bool = true, echo: bool = false) -> void:
	var e = InputEventKey.new()
	e.pressed = pressed
	e.echo = echo
	e.keycode = code
	main.input_sys.handle_input(e)


func _click(pressed: bool = true) -> void:
	var e = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = Vector2(640.0, 360.0)
	main.input_sys.handle_input(e)


func _pad_button(pressed: bool = true) -> void:
	var e = InputEventJoypadButton.new()
	e.button_index = JOY_BUTTON_A
	e.pressed = pressed
	main.input_sys.handle_input(e)


# the intro up, `seconds` after the start of the game
func _intro_at(seconds: float) -> void:
	main.go_to_title()
	main.intro_active = true
	main.time = seconds


func _check_start() -> void:
	if main.intro_active:
		_fail("a check that loads main.tscn with --script must start without the intro screen")
	if main.state != "title" or main.title_page != "":
		_fail(
			(
				"the game must start on the title menu (state '%s', page '%s')"
				% [main.state, main.title_page]
			)
		)


func _check_wants_intro() -> void:
	if not main.wants_intro(true, false):
		_fail("the game started as the main scene must show the intro")
	if main.wants_intro(true, true):
		_fail("a developer start option (--dev-coins ...) must go straight to the title menu")
	if main.wants_intro(false, false):
		_fail("a scene that is not the game (a check) must not show the intro")
	if main.wants_intro(false, true):
		_fail("a scene that is not the game must not show the intro, with or without start options")


func _check_input() -> void:
	# the title menu finds no button while the intro is up, and finds one again after it
	_intro_at(2.0)
	main.hud.size = Vector2(1280.0, 720.0)
	var first = main.hud.title_rect(0).get_center()
	if main.hud.title_at(first) != -1:
		_fail("a button of the title menu is found while the intro screen is up")
	main.intro_active = false
	if main.hud.title_at(first) != 0:
		_fail("PLAY is not found on the title menu once the intro is gone")

	# a key in the first moments does not end it
	_intro_at(0.1)
	_key(KEY_SPACE)
	if not main.intro_active:
		_fail(
			(
				"a key in the first moments ended the intro (it must wait %s s)"
				% str(main.INTRO_MIN_TIME)
			)
		)
	_click()
	_pad_button()
	if not main.intro_active:
		_fail("a click or a gamepad button in the first moments ended the intro")

	# things that must not end it
	_intro_at(2.0)
	for code in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK]:
		_key(code)
	_key(KEY_SPACE, true, true)  # a held key repeating
	_key(KEY_SPACE, false)  # a key let go
	_click(false)  # a button let go
	_pad_button(false)
	if not main.intro_active:
		_fail("a modifier key, a repeating key or a button being let go ended the intro")

	# things that end it: a key (Escape too), a click, a gamepad button
	_intro_at(2.0)
	_key(KEY_ENTER)
	if main.intro_active:
		_fail("Enter did not end the intro")
	_intro_at(2.0)
	_key(KEY_ESCAPE)
	if main.intro_active:
		_fail("Escape did not end the intro")
	_intro_at(2.0)
	_click()
	if main.intro_active:
		_fail("a mouse click did not end the intro")
	_intro_at(2.0)
	_pad_button()
	if main.intro_active:
		_fail("a gamepad button did not end the intro")

	# the key that ends it does nothing else: the title menu is where it was
	_intro_at(2.0)
	main.title_sel = 0
	_key(KEY_DOWN)
	if main.intro_active or main.title_sel != 0:
		_fail(
			(
				"the key that ends the intro also moved the menu (title_sel %d, intro %s)"
				% [main.title_sel, str(main.intro_active)]
			)
		)
	if main.state != "title" or main.title_page != "":
		_fail(
			(
				"ending the intro must land on the title menu (state '%s', page '%s')"
				% [main.state, main.title_page]
			)
		)

	# nothing but the intro reacts while it is up: Enter and a click do not press PLAY
	_intro_at(0.1)
	main.title_sel = 0
	_key(KEY_ENTER)
	if main.state != "title" or main.title_page != "":
		_fail("a key in the first moments of the intro started something (state '%s')" % main.state)


func _check_stays_off() -> void:
	_intro_at(2.0)
	_key(KEY_ENTER)
	main.go_to_title()
	main.go_to_title()
	if main.intro_active:
		_fail("going to the title menu turned the intro on again")
	if main.dismiss_intro():
		_fail("dismiss_intro said it ended an intro that was not up")


func _check_drawing() -> void:
	for s in SIZES:
		main.hud.size = s
		# the intro, with and without a gamepad, at the start (fading in) and later
		for t in [0.0, 0.3, 5.0]:
			_intro_at(t)
			main.time = t
			for f in range(2):
				main.hud.queue_redraw()
				await process_frame
		main.intro_active = false
		main.go_to_title()
		# the title menu and every title page
		for page in [""] + TITLE_PAGES:
			main.title_page = page
			for f in range(2):
				main.hud.queue_redraw()
				await process_frame
		main.title_page = ""
	# a very small window must not break the drawing either
	main.hud.size = Vector2(160.0, 120.0)
	main.hud.queue_redraw()
	await process_frame
	# the skyline and the stars come from a fixed formula: the same number every time, from 0 up to but not including 1
	for n in [0.0, 1.0, 7.5, 50.0, 123.0]:
		var a = main.hud._hash01(n)
		var b = main.hud._hash01(n)
		if a != b or a < 0.0 or a >= 1.0:
			_fail(
				(
					"_hash01(%s) is %s and %s, it must be the same number in 0 to 1"
					% [str(n), str(a), str(b)]
				)
			)
	main.hud.size = SIZES[0]
	main.intro_active = false
	main.go_to_title()


# Every menu is drawn on the backdrop. The way a menu used to be drawn, a dim layer over the running game, lets the game
# show through, so none is left but the map held down during a round (it is a view over the round, which keeps running).
func _check_no_menu_over_the_game() -> void:
	var lines = FileAccess.get_file_as_string("res://scripts/hud.gd").split("\n")
	var calls = []
	for i in range(lines.size()):
		var line = lines[i]
		if line.contains("_dim(") and not line.begins_with("func _dim("):
			calls.append(i)
	if calls.size() != 1:
		_fail(
			(
				"hud.gd has %d `_dim(` calls, expected 1 (the map held down in a round): a menu drawn with _dim shows the game behind it, use _menu_backdrop"
				% calls.size()
			)
		)
		return
	var above = lines[calls[0] - 1]
	if not above.contains("map_held()"):
		_fail(
			(
				"the one `_dim(` call left in hud.gd is not the map held down in a round (line %d)"
				% (calls[0] + 1)
			)
		)


func _finish() -> void:
	if problems.is_empty():
		print("menu_backdrop_check: the intro screen and the menu backdrop work as intended")
		quit(0)
	else:
		print("menu_backdrop_check: %d problem(s)" % problems.size())
		for p in problems.slice(0, 12):
			print("  " + p)
		quit(1)
