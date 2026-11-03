extends SceneTree
# Checks key rebinding (README Milestone E, "Key rebinding"): scripts/keybinds.gd, the REBIND KEYS page and the places
# that read the keys. Run from the project folder:
#   python tools/run_checks.py keybinds
# or: godot --headless --path . --script res://tools/keybinds_check.gd
#
# Table: every control has defaults, no key is on two controls, none is a menu key. Rules: menu keys and modifiers that
# make no sense are refused, a key another control has is swapped or taken, a control keeps at least one key, and 300
# random changes in a row never break those rules. Config: the [keys] section round-trips, and a damaged or hand-edited
# one only puts keys back to their defaults. Page: it opens from the settings panel, a key is rebound, Esc cancels, a
# menu key is refused, RESET TO DEFAULTS works, the cells do not overlap and fit the window at four sizes. Game: the
# movement and the round keys follow the bindings, the Controls page and the shop prompt show them.
# Exits with status 1 and prints the problems when a check fails.

const Keybinds = preload("res://scripts/keybinds.gd")

const SIZES = [Vector2(1280, 720), Vector2(1920, 1080), Vector2(1024, 768), Vector2(3440, 1440)]

var problems = []
var main


func _initialize() -> void:
	Input.use_accumulated_input = false  # a pressed key counts at once, not at the next real frame (as in jump_check)
	Keybinds.reset_defaults()
	_table()
	_rules()
	_random_changes()
	_config()
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	Keybinds.reset_defaults()
	_controls_rows()
	await _page_flow()
	await _game_keys()
	Keybinds.reset_defaults()
	_finish()


func _fail(text: String) -> void:
	if problems.size() < 40:
		problems.append(text)


func _finish() -> void:
	if problems.is_empty():
		print("keybinds_check: the table, the rules, the config, the page and the game keys hold")
		quit(0)
	else:
		for p in problems:
			printerr("keybinds_check: " + p)
		quit(1)


func _ev(code: int, pressed = true, both = true) -> InputEventKey:
	var e = InputEventKey.new()
	e.keycode = code
	if both:
		e.physical_keycode = code
	e.pressed = pressed
	return e


# every code that is on a control, how many times
func _counts() -> Dictionary:
	var seen = {}
	for id in Keybinds.action_ids():
		for c in Keybinds.keys_of(id):
			if int(c) != 0:
				seen[int(c)] = int(seen.get(int(c), 0)) + 1
	return seen


# the rules that must hold after any change; returns the first one that does not
func _broken() -> String:
	for code in _counts():
		if _counts()[code] > 1:
			return "key %d is on two controls" % code
		if Keybinds.why_not(code) != "":
			return "key %d is bound but cannot be" % code
	for id in Keybinds.action_ids():
		var ks = Keybinds.keys_of(id)
		if int(ks[0]) == 0:
			return "%s has no first key (%s)" % [id, str(ks)]
	return ""


# ------------------------------------------------------------------ table
func _table() -> void:
	var ids = Keybinds.action_ids()
	if ids.size() < 14:
		_fail("only %d controls are listed" % ids.size())
	var seen_ids = {}
	for a in Keybinds.ACTIONS:
		if seen_ids.has(a["id"]):
			_fail("the control id %s is listed twice" % a["id"])
		seen_ids[a["id"]] = true
		if str(a["label"]).strip_edges() == "" or (a["keys"] as Array).is_empty():
			_fail("the control %s has no label or no default key" % a["id"])
		if str(a["label"]) != str(a["label"]).to_upper():
			_fail("the label of %s is not in capitals like the rest of the menus" % a["id"])
	var why = _broken()
	if why != "":
		_fail("the defaults break a rule: " + why)
	if not Keybinds.is_default():
		_fail("is_default is false on the defaults")
	for id in ids:
		if Keybinds.keys_of(id) != Keybinds.default_keys_of(id):
			_fail("%s does not start on its default keys" % id)
		for c in Keybinds.keys_of(id):
			if Keybinds.key_label(int(c)) == "":
				_fail("a default key of %s has no name" % id)
	if Keybinds.key_label(0) != "-":
		_fail("no key should read as -")


# ------------------------------------------------------------------ rules
func _rules() -> void:
	Keybinds.reset_defaults()
	for code in [
		KEY_ESCAPE, KEY_TAB, KEY_ENTER, KEY_UP, KEY_F11, KEY_DELETE, KEY_T, KEY_ALT, 0, -5
	]:
		if Keybinds.assign("jump", 0, code)["ok"]:
			_fail("key %d was accepted for jump" % code)
	if Keybinds.keys_of("jump") != Keybinds.default_keys_of("jump"):
		_fail("a refused key changed jump")
	var r = Keybinds.assign("jump", 0, KEY_Z)
	if not r["ok"] or Keybinds.keys_of("jump")[0] != KEY_Z:
		_fail("Z could not be given to jump")
	if Keybinds.owner_of(KEY_SPACE) != {}:
		_fail("Space still has an owner after jump gave it up")
	if not Keybinds.matches(_ev(KEY_Z), "jump") or Keybinds.matches(_ev(KEY_SPACE), "jump"):
		_fail("a key event does not follow the jump binding")
	if not Keybinds.matches(_ev(KEY_Z, true, false), "jump"):
		_fail("an event with no physical key is not matched by its key code")
	if Keybinds.matches(_ev(KEY_Z), "dash"):
		_fail("the jump key also matches dash")
	# a key another control has: swapped
	Keybinds.reset_defaults()
	r = Keybinds.assign("dash", 0, KEY_R)
	if not r["ok"] or not str(r["msg"]).begins_with("SWAPPED WITH"):
		_fail("giving dash the reload key was not a swap: %s" % str(r))
	if Keybinds.keys_of("dash")[0] != KEY_R or Keybinds.keys_of("reload")[0] != KEY_V:
		_fail("the swap of dash and reload did not trade the keys")
	# taking a key from a control that has a second one
	Keybinds.reset_defaults()
	r = Keybinds.assign("jump", 1, KEY_C)
	if not r["ok"] or not str(r["msg"]).begins_with("TAKEN FROM"):
		_fail("taking C from crouch was not reported: %s" % str(r))
	if Keybinds.keys_of("crouch") != [KEY_CTRL, 0]:
		_fail("crouch should be left with Ctrl only, it has %s" % str(Keybinds.keys_of("crouch")))
	# ... but not from a control that would be left with none
	Keybinds.reset_defaults()
	r = Keybinds.assign("jump", 1, KEY_G)
	if r["ok"] or Keybinds.keys_of("gadget")[0] != KEY_G:
		_fail("the only key of the gadget was taken away")
	# the same key in the other spot of the same control
	Keybinds.reset_defaults()
	r = Keybinds.assign("crouch", 0, KEY_C)
	if not r["ok"] or Keybinds.keys_of("crouch") != [KEY_C, KEY_CTRL]:
		_fail("crouch's two keys did not trade places: %s" % str(Keybinds.keys_of("crouch")))
	# clearing
	Keybinds.reset_defaults()
	if not Keybinds.clear("crouch", 0) or Keybinds.keys_of("crouch") != [KEY_C, 0]:
		_fail("clearing the first key of crouch should leave C as the first key")
	if Keybinds.clear("crouch", 0):
		_fail("the last key of crouch was cleared")
	if Keybinds.clear("jump", 1):
		_fail("an empty spot was reported as cleared")
	Keybinds.reset_defaults()
	if _broken() != "":
		_fail("reset_defaults left a broken table")


# 300 random changes in a row: no key on two controls, none refused, every control has a key
func _random_changes() -> void:
	Keybinds.reset_defaults()
	var rng = RandomNumberGenerator.new()
	rng.seed = 0x4B455953
	var pool = [KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_Q, KEY_R, KEY_V, KEY_W]
	pool.append_array(
		[KEY_1, KEY_2, KEY_3, KEY_KP_1, KEY_SPACE, KEY_SHIFT, KEY_CTRL, KEY_ESCAPE, KEY_TAB, 0]
	)
	var ids = Keybinds.action_ids()
	for step in range(300):
		var id = str(ids[rng.randi() % ids.size()])
		var slot = rng.randi() % Keybinds.SLOTS
		if rng.randf() < 0.2:
			Keybinds.clear(id, slot)
		else:
			Keybinds.assign(id, slot, int(pool[rng.randi() % pool.size()]))
		var why = _broken()
		if why != "":
			_fail("after change %d (%s, spot %d): %s" % [step, id, slot, why])
			break
	Keybinds.reset_defaults()


# ------------------------------------------------------------------ settings.cfg
func _config() -> void:
	Keybinds.reset_defaults()
	Keybinds.assign("jump", 0, KEY_Z)
	Keybinds.assign("crouch", 1, KEY_X)
	var changed = {}
	for id in Keybinds.action_ids():
		changed[id] = Keybinds.keys_of(id)
	var cf = ConfigFile.new()
	Keybinds.save_to(cf)
	Keybinds.reset_defaults()
	Keybinds.load_from(cf)
	for id in changed:
		if Keybinds.keys_of(id) != changed[id]:
			_fail("%s did not survive saving and loading: %s" % [id, str(Keybinds.keys_of(id))])
	# no section at all: the defaults
	Keybinds.load_from(ConfigFile.new())
	if not Keybinds.is_default():
		_fail("a file with no [keys] section did not give the defaults")
	# damaged entries put that control on its defaults and leave the others alone
	var bad = ConfigFile.new()
	bad.set_value("keys", "jump", "banana")
	bad.set_value("keys", "dash", [KEY_ESCAPE, 0])
	bad.set_value("keys", "reload", [0, 0])
	bad.set_value("keys", "gadget", [KEY_Z])
	bad.set_value("keys", "map", [1.5, 0])
	bad.set_value("keys", "melee", [0, KEY_Y])
	bad.set_value("keys", "sprint", [KEY_F, KEY_F])
	var t = Keybinds.parse(bad)
	for id in ["jump", "dash", "reload", "gadget", "map", "sprint"]:
		if t[id] != Keybinds.default_keys_of(id):
			_fail("a damaged entry for %s was not put back to the default: %s" % [id, str(t[id])])
	if t["melee"] != [KEY_Y, 0]:
		_fail("an entry with only the second spot should move up, got %s" % str(t["melee"]))
	# two controls on one key: everything goes back to the defaults
	var clash = ConfigFile.new()
	clash.set_value("keys", "jump", [KEY_Z, 0])
	clash.set_value("keys", "dash", [KEY_Z, 0])
	clash.set_value("keys", "map", [KEY_H, 0])
	if Keybinds.parse(clash) != Keybinds._defaults():
		_fail("a clash in the file did not put every control back to its defaults")
	Keybinds.reset_defaults()


# ------------------------------------------------------------------ Controls page and shop prompt
func _controls_rows() -> void:
	var hud = main.hud
	var live = hud.controls_keyboard_rows()
	if live.size() != hud.CONTROLS_KEYBOARD.size():
		_fail("the live Controls rows are not as many as the listed ones")
	else:
		for i in range(live.size()):
			if live[i] != hud.CONTROLS_KEYBOARD[i]:
				_fail(
					(
						"with the default keys, row %d reads %s, the list says %s"
						% [i, str(live[i]), str(hud.CONTROLS_KEYBOARD[i])]
					)
				)
	Keybinds.assign("jump", 0, KEY_Z)
	Keybinds.assign("reload", 0, KEY_F)
	var rows = hud.controls_keyboard_rows()
	var saw_jump = false
	var saw_reload = false
	var saw_side = false
	for row in rows:
		if str(row[1]).begins_with("JUMP") and str(row[0]).begins_with("Z"):
			saw_jump = true
		if str(row[1]).begins_with("RELOAD") and str(row[0]) == "F":
			saw_reload = true
		if str(row[1]).begins_with("SIDE DASH") and str(row[0]).ends_with("+ Z"):
			saw_side = true
	if not saw_jump or not saw_reload or not saw_side:
		_fail(
			(
				"the Controls page does not show the new keys (jump %s, reload %s, side dash %s)"
				% [saw_jump, saw_reload, saw_side]
			)
		)
	Keybinds.reset_defaults()


# ------------------------------------------------------------------ the REBIND KEYS page
func _page_flow() -> void:
	main.go_to_title()
	main.hud.size = Vector2(1280.0, 720.0)
	main.title_page = "settings"
	await process_frame
	var rows = main.hud.setting_rows()
	var at = -1
	for i in range(rows.size()):
		if rows[i]["id"] == "rebind":
			at = i
	if at < 0 or at >= rows.size() - 1 or not rows[at].get("action", false):
		_fail("the settings panel has no REBIND KEYS button above the reset button")
		return
	main.setting_sel = at
	main.input_sys.handle_input(_ev(KEY_ENTER))
	if main.title_page != "keys" or not main.hud.keys_visible():
		_fail("Enter on REBIND KEYS did not open the page (page: %s)" % main.title_page)
		return
	await process_frame
	main.hud.queue_redraw()
	await process_frame
	# rebind the first control's key
	main.input_sys.handle_input(_ev(KEY_ENTER))
	if not main.keys_capture:
		_fail("Enter on a cell did not start waiting for a key")
	main.input_sys.handle_input(_ev(KEY_TAB))
	if not main.keys_capture or main.keys_msg == "":
		_fail("a menu key (Tab) should be refused with a message and keep waiting")
	main.input_sys.handle_input(_ev(KEY_Z))
	if main.keys_capture or Keybinds.keys_of("forward")[0] != KEY_Z:
		_fail("Z did not become the forward key")
	if main.title_page != "keys":
		_fail("rebinding a key left the page")
	# Esc cancels a rebinding, then leaves the page
	main.input_sys.handle_input(_ev(KEY_DOWN))
	main.input_sys.handle_input(_ev(KEY_RIGHT))
	if main.keys_sel != 1 or main.keys_col != 1:
		_fail(
			(
				"Down and Right did not pick the second cell of the second row (%d, %d)"
				% [main.keys_sel, main.keys_col]
			)
		)
	main.input_sys.handle_input(_ev(KEY_ENTER))
	main.input_sys.handle_input(_ev(KEY_ESCAPE))
	if main.keys_capture or main.title_page != "keys":
		_fail("Esc while waiting for a key should only cancel it")
	main.input_sys.handle_input(_ev(KEY_DELETE))  # the second spot of "move left" is empty: nothing to clear, and no crash
	main.input_sys.handle_input(_ev(KEY_ESCAPE))
	if main.title_page != "settings":
		_fail("Esc on the page did not go back to the settings (page: %s)" % main.title_page)
	# RESET TO DEFAULTS
	main.setting_sel = at
	main.input_sys.handle_input(_ev(KEY_ENTER))
	main.keys_sel = Keybinds.ACTIONS.size()
	main.input_sys.handle_input(_ev(KEY_ENTER))
	if not Keybinds.is_default():
		_fail("RESET TO DEFAULTS did not put the keys back")
	# mouse: cells under a point, clicks, and nothing off the window
	main.keys_capture = false
	for s in SIZES:
		main.hud.size = s
		var cells = []
		for i in range(Keybinds.ACTIONS.size() + 1):
			for col in range(1 if i == Keybinds.ACTIONS.size() else Keybinds.SLOTS):
				var r = main.hud.keys_cell_rect(i, col)
				if (
					r.position.x < 0.0
					or r.position.y < 0.0
					or r.end.x > s.x
					or r.end.y > s.y * 0.82
				):
					_fail("cell (%d, %d) does not fit a window of %s: %s" % [i, col, s, str(r)])
				if main.hud.keys_at(r.get_center()) != Vector2i(i, col):
					_fail("the centre of cell (%d, %d) is not found at %s" % [i, col, s])
				for o in cells:
					if o.intersects(r):
						_fail("cell (%d, %d) overlaps another at %s" % [i, col, s])
				cells.append(r)
	main.hud.size = Vector2(1280.0, 720.0)
	var cell = main.hud.keys_cell_rect(3, 1).get_center()
	main.input_sys.keys_click(cell)
	if main.keys_sel != 3 or main.keys_col != 1 or not main.keys_capture:
		_fail("a click on a cell did not start rebinding it")
	main.input_sys.keys_click(cell)
	if main.keys_capture:
		_fail("a click while waiting for a key should cancel")
	main.input_sys.keys_click(Vector2(2.0, 2.0))
	if main.title_page != "settings":
		_fail("a click outside the list did not go back to the settings")
	main.title_page = ""


# ------------------------------------------------------------------ the keys of the game
func _release_all() -> void:
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Z, KEY_I]:
		Input.parse_input_event(_ev(code, false))


func _game_keys() -> void:
	main.go_to_title()
	_release_all()
	Keybinds.reset_defaults()
	# movement follows the binding: Z now walks forward, W no longer does
	Keybinds.assign("forward", 0, KEY_Z)
	Input.parse_input_event(_ev(KEY_Z))
	var mv = main.read_move()
	_release_all()
	if mv.y <= 0.0:
		_fail("the forward key was rebound to Z but Z did not walk forward")
	Input.parse_input_event(_ev(KEY_W))
	mv = main.read_move()
	_release_all()
	if mv.y != 0.0:
		_fail("W still walks forward after the forward key moved to Z")
	# a round's keys follow the binding
	Keybinds.reset_defaults()
	Keybinds.assign("switch", 0, KEY_I)
	main.state = "play"
	if not main.input_sys.play_key(_ev(KEY_I)):
		_fail("the switch key was rebound to I but I is not taken as a round key")
	if main.input_sys.play_key(_ev(KEY_Q)):
		_fail("Q is still taken as the switch key after it moved to I")
	if main.input_sys.play_key(_ev(KEY_ESCAPE)):
		_fail("Esc is taken as a round key")
	# the menus: forward and back move the highlight, the arrows always do
	main.go_to_title()
	Keybinds.reset_defaults()
	Keybinds.assign("back", 0, KEY_I)
	main.title_page = "settings"
	main.setting_sel = 0
	main.input_sys.handle_input(_ev(KEY_I))
	if main.setting_sel != 1:
		_fail("the back key (now I) does not move down in the settings panel")
	main.input_sys.handle_input(_ev(KEY_UP))
	if main.setting_sel != 0:
		_fail("the Up arrow does not move up in the settings panel")
	main.title_page = ""
	Keybinds.reset_defaults()
	main.state = "title"
