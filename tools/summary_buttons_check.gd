extends SceneTree
# Checks the buttons the run summary ends on: NEW RUN, UNLOCKS and TITLE (README alpha C5.1, Milestone I). Run from the
# project folder, best through the runner (it gives the check an empty save folder):
#   python tools/run_checks.py summary_buttons
# or by hand:
#   godot --headless --path . --script res://tools/summary_buttons_check.gd
# It checks that
#   - at 1280x720 and 1920x1080, and at 4:3, 5:4 and a narrow window, the three buttons are inside the window, do not
#     touch each other, are big enough for their label, stand clear of the table and clear of the lines under it
#     (the challenge, leaderboard and unlock lines), and in a narrow window sit clear of the seed line at the bottom
#   - a point on a button finds that button and a point beside them finds none, the mouse highlights the button it is
#     over, and nothing is found when the screen is not the summary
#   - Up, Down, W, S, Left, Right and the pad's D-pad move the highlight round the three buttons, both ways
#   - nothing reacts for the first 0.8 s, nor while a leaderboard name is typed (a click or Enter then only confirms
#     the name), a click beside the buttons does nothing, and Enter, the pad's A and a click press the highlighted
#     button; TITLE leaves the summary for the title screen, and the other two leave it too
#   - a run that ends (a lost round, the end of the game and a win) starts the summary on the first button
#   - the summary draws at every size, with every button highlighted, ready, not yet ready and with a name box
# game_over and win_run write the meta, score and settings files like run_save_check does, which is why the runner's
# empty save folder matters.
# Exits with status 1 and prints the problems when a check fails.

const SIZES = [
	Vector2(1280.0, 720.0),
	Vector2(1920.0, 1080.0),
	Vector2(1024.0, 768.0),
	Vector2(1280.0, 1024.0),
	Vector2(700.0, 800.0)
]
const SEED = 0x5EED

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_check_layout()
	_check_hit_test()
	_check_moving()
	_check_not_ready()
	_check_pressing()
	_check_new_summary()
	await _check_drawing()
	_finish()


func _fail(text: String) -> void:
	problems.append(text)


func _key(code: int) -> void:
	var e = InputEventKey.new()
	e.pressed = true
	e.keycode = code
	main.input_sys.handle_input(e)


func _pad(button: int) -> void:
	main.input_sys.on_pad_button(button)


# a lost run on its summary, 1 s in, with the first button highlighted
func _to_summary() -> void:
	main.start_game(false, SEED)
	main.score = 5000
	main.kills = 12
	main.round_n = 5
	main.new_unlocks = ["POCKET MAGNET"]
	main.over_reason = "riders"
	main.run_won = false
	main.last_rank = -1
	main.name_entry = false
	main.state = "over"
	main.state_t = 1.0
	main.summary_sel = 0


func _tag(s: Vector2) -> String:
	return "%dx%d" % [int(s.x), int(s.y)]


func _check_layout() -> void:
	_to_summary()
	var hud = main.hud
	for s in SIZES:
		hud.size = s
		var k = s.y / 720.0
		var tag = _tag(s)
		var cx = s.x * 0.5
		var y0 = s.y * hud.SUMMARY_TABLE_TOP
		var table_half = hud.SUMMARY_HALF_WIDTH * k
		# the table: its rows from the first baseline (20 px text) to the last one, and the line under each
		var table = Rect2(
			cx - table_half - 4.0 * k,
			y0 - 20.0 * k,
			2.0 * table_half + 8.0 * k,
			float(hud.SUMMARY_ROWS) * hud.SUMMARY_ROW_STEP * k
		)
		# the first line under the table (the challenge lines, the leaderboard, the unlock lines) has its baseline 14 px
		# under the last row and its top 18 px above that
		var below_top = y0 + float(hud.SUMMARY_ROWS) * hud.SUMMARY_ROW_STEP * k - 4.0 * k
		var rects = []
		for i in range(hud.SUMMARY_ITEMS.size()):
			rects.append(hud.summary_rect(i))
		var column = rects[0].position.x > cx + table_half
		for i in range(rects.size()):
			var r: Rect2 = rects[i]
			var name = "%s: %s" % [tag, hud.SUMMARY_ITEMS[i]["label"]]
			if r.position.x < 0.0 or r.position.y < 0.0 or r.end.x > s.x or r.end.y > s.y:
				_fail("%s is not inside the window (%s)" % [name, str(r)])
			if r.end.x > s.x - 16.0 * k:
				_fail("%s is closer than 16 px to the right edge (%s)" % [name, str(r)])
			if r.size.y < 40.0 * k:
				_fail("%s is only %f high" % [name, r.size.y])
			var label_w = (
				hud
				. font
				. get_string_size(
					hud.SUMMARY_ITEMS[i]["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * k)
				)
				. x
			)
			if label_w > r.size.x - 16.0 * k:
				_fail("%s: the label is %f wide, the button %f" % [name, label_w, r.size.x])
			if r.intersects(table):
				_fail("%s touches the table (%s against %s)" % [name, str(r), str(table)])
			if abs(r.size.x - rects[0].size.x) > 0.01 or abs(r.size.y - rects[0].size.y) > 0.01:
				_fail("%s is not the size of the first button" % name)
			for j in range(i + 1, rects.size()):
				if r.grow(2.0 * k).intersects(rects[j]):
					_fail("%s touches the button %s" % [name, hud.SUMMARY_ITEMS[j]["label"]])
		if column:
			# beside the table: level with it, below the two lines under the title, and ending above the first line
			# under the table, so no line under the table can reach them whatever it says
			if rects[0].position.y < s.y * 0.22 + 8.0 * k:
				_fail(
					(
						"%s: the column starts at %f, too close to the title lines"
						% [tag, rects[0].position.y]
					)
				)
			if rects[rects.size() - 1].end.y > below_top:
				_fail(
					(
						"%s: the column ends at %f, the lines under the table start at %f"
						% [tag, rects[rects.size() - 1].end.y, below_top]
					)
				)
			if rects[0].position.x < cx + table_half + 20.0 * k:
				_fail("%s: the column is less than 20 px from the table" % tag)
			for i in range(1, rects.size()):
				if rects[i].position.y <= rects[i - 1].position.y:
					_fail("%s: the buttons are not in order from the top" % tag)
		else:
			# the narrow window: one row, under the table, above the seed line (baseline 97.5 % of the height, 14 px)
			for i in range(rects.size()):
				if rects[i].position.y < below_top:
					_fail(
						(
							"%s: the row starts at %f, inside the table (%f)"
							% [tag, rects[i].position.y, below_top]
						)
					)
				if rects[i].end.y > s.y * 0.975 - 16.0 * k:
					_fail("%s: the row reaches the seed line" % tag)
			for i in range(1, rects.size()):
				if rects[i].position.x <= rects[i - 1].position.x:
					_fail("%s: the buttons are not in order from the left" % tag)
	# the two sizes that matter are drawn as a column
	for s in [SIZES[0], SIZES[1]]:
		hud.size = s
		if hud.summary_rect(0).position.x < s.x * 0.5:
			_fail("%s: the buttons are not a column to the right of the table" % _tag(s))
	hud.size = SIZES[0]


func _check_hit_test() -> void:
	_to_summary()
	var hud = main.hud
	for s in SIZES:
		hud.size = s
		var tag = _tag(s)
		for i in range(hud.SUMMARY_ITEMS.size()):
			var c = hud.summary_rect(i).get_center()
			if hud.summary_at(c) != i:
				_fail("%s: the middle of button %d finds %d" % [tag, i, hud.summary_at(c)])
			main.summary_sel = 0
			main.input_sys.hover_menu(c)
			if main.summary_sel != i:
				_fail("%s: the mouse over button %d highlights %d" % [tag, i, main.summary_sel])
		if hud.summary_at(Vector2(4.0, 4.0)) != -1:
			_fail("%s: the top left corner finds a button" % tag)
		if hud.summary_at(Vector2(s.x * 0.5, s.y * 0.5)) != -1:
			_fail("%s: the middle of the table finds a button" % tag)
		var gap_y = (hud.summary_rect(0).end.y + hud.summary_rect(1).position.y) * 0.5
		var gap_x = hud.summary_rect(0).get_center().x
		if hud.summary_rect(1).position.y > hud.summary_rect(0).end.y:
			if hud.summary_at(Vector2(gap_x, gap_y)) != -1:
				_fail("%s: the gap between two buttons finds a button" % tag)
	hud.size = SIZES[0]
	main.state = "title"
	if hud.summary_at(hud.summary_rect(0).get_center()) != -1:
		_fail("a button is found on the title screen")
	main.state = "over"


func _check_moving() -> void:
	_to_summary()
	var n = main.hud.SUMMARY_ITEMS.size()
	if n != 3:
		_fail("expected 3 buttons, found %d" % n)
	var steps = [
		["KEY_DOWN", KEY_DOWN, 1],
		["KEY_S", KEY_S, 2],
		["KEY_DOWN again (wraps to the first)", KEY_DOWN, 0],
		["KEY_UP (wraps to the last)", KEY_UP, 2],
		["KEY_W", KEY_W, 1],
		["KEY_RIGHT", KEY_RIGHT, 2],
		["KEY_LEFT", KEY_LEFT, 1]
	]
	for st in steps:
		_key(st[1])
		if main.summary_sel != st[2]:
			_fail("%s: the highlight is %d, expected %d" % [st[0], main.summary_sel, st[2]])
	var pad_steps = [
		["D-pad down", JOY_BUTTON_DPAD_DOWN, 2],
		["D-pad up", JOY_BUTTON_DPAD_UP, 1],
		["D-pad right", JOY_BUTTON_DPAD_RIGHT, 2],
		["D-pad left", JOY_BUTTON_DPAD_LEFT, 1]
	]
	for st in pad_steps:
		_pad(st[1])
		if main.summary_sel != st[2]:
			_fail("%s: the highlight is %d, expected %d" % [st[0], main.summary_sel, st[2]])


# nothing reacts too early, nor while a name is typed
func _check_not_ready() -> void:
	_to_summary()
	main.state_t = 0.3
	_key(KEY_DOWN)
	if main.summary_sel != 0:
		_fail("Down moved the highlight 0.3 s into the summary")
	_key(KEY_ENTER)
	_pad(JOY_BUTTON_A)
	main.input_sys.click_summary(main.hud.summary_rect(2).get_center())
	if main.state != "over":
		_fail("a key, the pad or a click left the summary 0.3 s in (state %s)" % main.state)
	if main.hud.summary_active():
		_fail("summary_active is true 0.3 s in")
	# a name being typed: Enter and a click confirm the name and nothing else
	_to_summary()
	main.name_entry = true
	main.name_buf = "AB"
	main.last_rank = -1
	if main.hud.summary_active():
		_fail("summary_active is true while a name is typed")
	_key(KEY_DOWN)
	main.input_sys.summary_move(1)
	if main.summary_sel != 0:
		_fail("Down moved the highlight while a name is typed")
	_key(KEY_ENTER)
	if main.name_entry or main.state != "over":
		_fail(
			(
				"Enter did not just confirm the name (name_entry %s, state %s)"
				% [str(main.name_entry), main.state]
			)
		)
	main.name_entry = true
	main.input_sys.click_summary(main.hud.summary_rect(2).get_center())
	if main.name_entry or main.state != "over":
		_fail(
			(
				"a click on a button did not just confirm the name (name_entry %s, state %s)"
				% [str(main.name_entry), main.state]
			)
		)
	main.name_entry = true
	_pad(JOY_BUTTON_A)
	if main.name_entry or main.state != "over":
		_fail(
			(
				"the pad's A did not just confirm the name (name_entry %s, state %s)"
				% [str(main.name_entry), main.state]
			)
		)
	if not main.hud.summary_active():
		_fail("summary_active is false once the name is confirmed")


# Enter, the pad's A and a click press the highlighted button; a click beside them does nothing
func _check_pressing() -> void:
	var hud = main.hud
	hud.size = SIZES[0]
	var order = ["new_run", "unlocks", "title"]
	for i in range(order.size()):
		if hud.SUMMARY_ITEMS[i]["id"] != order[i]:
			_fail("button %d is %s, expected %s" % [i, hud.SUMMARY_ITEMS[i]["id"], order[i]])
	for i in range(hud.SUMMARY_ITEMS.size()):
		var name = hud.SUMMARY_ITEMS[i]["label"]
		_to_summary()
		main.input_sys.click_summary(Vector2(8.0, 8.0))
		main.input_sys.click_summary(Vector2(SIZES[0].x * 0.5, SIZES[0].y * 0.5))
		if main.state != "over":
			_fail("a click beside the buttons left the summary (state %s)" % main.state)
		main.summary_sel = i
		_key(KEY_ENTER)
		_left_summary("Enter on " + name, i)
		_to_summary()
		main.summary_sel = i
		_pad(JOY_BUTTON_A)
		_left_summary("the pad's A on " + name, i)
		_to_summary()
		main.input_sys.click_summary(hud.summary_rect(i).get_center())
		_left_summary("a click on " + name, i)
	# a click presses the button it is on, not the highlighted one
	_to_summary()
	main.summary_sel = 0
	main.input_sys.click_summary(hud.summary_rect(2).get_center())
	if main.summary_sel != 2:
		_fail("a click on TITLE left the highlight on %d" % main.summary_sel)
	if main.state != "title":
		_fail("a click on TITLE did not go to the title screen (state %s)" % main.state)


func _left_summary(what: String, i: int) -> void:
	if main.state == "over":
		_fail("%s did not leave the summary" % what)
	if main.hud.SUMMARY_ITEMS[i]["id"] == "title" and main.state != "title":
		_fail("%s did not go to the title screen (state %s)" % [what, main.state])


# a run that ends starts its summary on the first button
func _check_new_summary() -> void:
	main.start_game(false, SEED)
	main.summary_sel = 2
	main.state = "play"
	main.game_over("riders")
	if main.state != "over":
		_fail("game_over did not end on the summary (state %s)" % main.state)
	if main.summary_sel != 0:
		_fail("a lost run started its summary on button %d" % main.summary_sel)
	main.start_game(false, SEED)
	main.summary_sel = 2
	main.win_run()
	if main.state != "over":
		_fail("win_run did not end on the summary (state %s)" % main.state)
	if main.summary_sel != 0:
		_fail("a won run started its summary on button %d" % main.summary_sel)
	main.start_game(false, SEED)
	main.summary_sel = 2
	main.state = "play"
	main.hearts = 0
	main.round_n = 1
	main.end_round()  # no rider was hit, so the round is lost and the run ends
	if main.state != "over":
		_fail("a lost round did not end on the summary (state %s)" % main.state)
	elif main.summary_sel != 0:
		_fail("a round that ended the run started its summary on button %d" % main.summary_sel)
	main.go_to_title()


# the summary draws at every size with each button highlighted, ready, not ready yet and with the name box
func _check_drawing() -> void:
	for s in SIZES:
		main.hud.size = s
		for mode in ["ready", "early", "name"]:
			for i in range(main.hud.SUMMARY_ITEMS.size()):
				_to_summary()
				main.summary_sel = i
				if mode == "early":
					main.state_t = 0.3
				elif mode == "name":
					main.name_entry = true
					main.last_rank = 0
					main.name_buf = "AB"
				for f in range(2):
					main.hud.queue_redraw()
					await process_frame
	main.hud.size = SIZES[0]
	main.name_entry = false
	main.go_to_title()


func _finish() -> void:
	if problems.is_empty():
		print(
			"summary_buttons_check: the summary's buttons are placed, move, wait and press as intended"
		)
		quit(0)
	else:
		print("summary_buttons_check: %d problem(s)" % problems.size())
		for p in problems.slice(0, 12):
			print("  " + p)
		quit(1)
