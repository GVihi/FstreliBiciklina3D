extends SceneTree
# Checks the UNLOCKS page of the title menu (README Milestone I: "Unlock screen replaces the coming soon
# Unlocks page"):
#   - the title entry is no longer marked SOON (LOADOUT still is), and it opens the page,
#   - every unlock gets a row, the rows are inside the screen, do not overlap and stay clear of the detail text,
#     at two window sizes, and the page draws at both,
#   - Up / Down walk the list and wrap, Left / Right switch the column, the mouse picks and hovers a row,
#     Enter without coins says so and changes nothing, Esc goes back, the BUY button is on the page,
#   - the state of a row: owned, coming soon, can afford, or locked,
#   - an empty table still draws.
# Not checked: how it looks (spacing, text clipping), which needs a look in game.
# Run from the project folder:
#   godot --headless --path . --script res://tools/unlocks_page_check.gd
# or with tools\run_unlocks_page_check.bat on Windows.
# Exits with status 1 and prints the problems when a check fails.

const UnlocksTable = preload("res://scripts/unlocks.gd")

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	var balance = main.meta.balance
	var owned = main.meta.owned.duplicate()
	_check_title_entry()
	await _check_layout()
	_check_navigation()
	_check_states()
	await _check_empty()
	main.meta.balance = balance  # nothing was saved, only the copy in memory is put back
	main.meta.owned = owned
	_finish()


func _finish() -> void:
	if problems.is_empty():
		print(
			"unlocks_page_check: the Unlocks page opens, lays out, navigates and shows the states"
		)
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("unlocks_page_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


func _entry(id: String) -> int:
	for i in range(main.hud.TITLE_ITEMS.size()):
		if main.hud.TITLE_ITEMS[i]["id"] == id:
			return i
	return -1


func _open_page() -> void:
	main.go_to_title()
	main.input_sys.title_activate(_entry("unlocks"))


func _check_title_entry() -> void:
	var i = _entry("unlocks")
	if i < 0:
		_fail("the title menu has no UNLOCKS entry")
		return
	if main.hud.TITLE_ITEMS[i].get("soon", false):
		_fail("UNLOCKS is still marked SOON")
	if main.hud.TITLE_ITEMS[_entry("loadout")].get("soon", false):
		_fail("LOADOUT is still marked SOON")
	_open_page()
	if main.title_page != "unlocks":
		_fail("activating UNLOCKS opened '%s'" % main.title_page)
	if main.unlock_sel != 0:
		_fail("the page did not open on the first unlock")
	if main.UNLOCKS.size() < 20:
		_fail("only %d unlocks reached the game" % main.UNLOCKS.size())


# rows are all there, on screen, apart from each other and above the detail text, at two window shapes
func _check_layout() -> void:
	_open_page()
	var hud = main.hud
	for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]:
		hud.size = s
		var rows = hud.unlocks_layout()["rows"]
		if rows.size() != main.UNLOCKS.size():
			_fail("%d rows for %d unlocks at %s" % [rows.size(), main.UNLOCKS.size(), str(s)])
			continue
		var detail_top = s.y * 0.8 - 26.0 * s.y / 720.0  # where the name of the selected unlock starts
		for i in range(rows.size()):
			var r = rows[i]
			if r.position.x < 0.0 or r.end.x > s.x or r.position.y < s.y * 0.2:
				_fail("row %d is off the page at %s: %s" % [i, str(s), str(r)])
			if r.end.y > detail_top:
				_fail("row %d runs into the detail text at %s" % [i, str(s)])
			for j in range(i + 1, rows.size()):
				if r.intersects(rows[j]):
					_fail("rows %d and %d overlap at %s" % [i, j, str(s)])
			if hud.unlock_at(r.get_center()) != i:
				_fail(
					"a click in the middle of row %d picks %d" % [i, hud.unlock_at(r.get_center())]
				)
		var br = hud.unlock_buy_rect()
		if br.position.x < 0.0 or br.end.x > s.x or br.end.y > s.y:
			_fail("the BUY button is off the page at %s: %s" % [str(s), str(br)])
		for r in rows:
			if r.intersects(br):
				_fail("the BUY button covers a row at %s" % str(s))
		if br.position.y < s.y * 0.8 + 30.0 * s.y / 720.0:
			_fail("the BUY button sits on the detail text at %s" % str(s))
		for f in range(2):
			hud.queue_redraw()
			await process_frame
	# a point beside the list picks nothing
	if hud.unlock_at(Vector2(2.0, 2.0)) != -1:
		_fail("a point in the corner picked an unlock")
	# and the page only answers while it is open
	main.go_to_title()
	if hud.unlock_at(hud.unlocks_layout()["rows"][0].get_center()) != -1:
		_fail("the rows answer on the title menu")


func _check_navigation() -> void:
	_open_page()
	var inp = main.input_sys
	var hud = main.hud
	hud.size = Vector2(1280.0, 720.0)
	var n = main.UNLOCKS.size()
	inp.title_move(-1)
	if main.unlock_sel != n - 1:
		_fail("Up from the first unlock went to %d, not the last" % main.unlock_sel)
	inp.title_move(1)
	if main.unlock_sel != 0:
		_fail("Down from the last unlock went to %d, not the first" % main.unlock_sel)
	inp.title_move(1)
	if main.unlock_sel != 1:
		_fail("Down went to %d, not 1" % main.unlock_sel)
	# Left / Right: first row of the left column to the first row of the right one and back
	main.unlock_sel = 0
	var rows = hud.unlocks_layout()["rows"]
	inp.menu_move(1)
	if (
		main.unlock_sel == 0
		or is_equal_approx(rows[main.unlock_sel].position.x, rows[0].position.x)
	):
		_fail("Right from the first unlock stayed in the same column (%d)" % main.unlock_sel)
	inp.menu_move(-1)
	if (
		main.unlock_sel != 0
		and not is_equal_approx(rows[main.unlock_sel].position.x, rows[0].position.x)
	):
		_fail("Left did not come back to the first column (%d)" % main.unlock_sel)
	# the mouse
	main.unlock_sel = 0
	inp.hover_menu(rows[7].get_center())
	if main.unlock_sel != 7:
		_fail("hovering row 7 selected %d" % main.unlock_sel)
	# Enter and A try to buy: with no coins they say so and change nothing; Esc and B go back
	main.meta.balance = 0
	var before = main.unlock_sel
	inp.menu_confirm()
	inp.title_activate(main.title_sel)
	if main.title_page != "unlocks" or main.unlock_sel != before:
		_fail("Enter changed the page ('%s') or the selection" % main.title_page)
	if (
		main.unlock_msg != "NOT ENOUGH COINS"
		or main.meta.balance != 0
		or not main.meta.owned.is_empty()
	):
		_fail(
			"Enter without coins: message '%s', balance %d" % [main.unlock_msg, main.meta.balance]
		)
	inp.title_back()
	if main.title_page != "":
		_fail("going back left the page open ('%s')" % main.title_page)
	# the list does not move on the title menu, where Up / Down move the menu
	main.title_sel = 0
	var sel = main.unlock_sel
	inp.title_move(1)
	if main.unlock_sel != sel or main.title_sel != 1:
		_fail("Down on the title menu moved the unlock selection or not the menu")


func _check_states() -> void:
	var u = {"id": "x", "cost": 100, "planned": false}
	var table = [
		["owned", true, 0, false],
		["owned", true, 9999, true],
		["soon", false, 9999, true],
		["afford", false, 100, false],
		["afford", false, 101, false],
		["locked", false, 99, false]
	]
	for row in table:
		u["planned"] = row[3]
		var got = UnlocksTable.state_of(u, row[1], row[2])
		if got != row[0]:
			_fail(
				(
					"state_of(owned %s, balance %d, planned %s) is '%s', expected '%s'"
					% [row[1], row[2], row[3], got, row[0]]
				)
			)
	# the game's own meta object answers owns()
	var id = str(main.UNLOCKS[0]["id"])
	main.meta.owned = {}
	if main.meta.owns(id):
		_fail("a fresh game owns %s" % id)
	main.meta.owned = {id: true}
	if not main.meta.owns(id):
		_fail("owns() does not see an owned unlock")
	main.meta.owned = {}


# when the table could not be loaded the page still draws and nothing crashes on the keys
func _check_empty() -> void:
	var kept = main.UNLOCKS
	main.UNLOCKS = []
	_open_page()
	main.input_sys.title_move(1)
	main.input_sys.menu_move(1)
	main.hud.queue_redraw()
	await process_frame
	if main.hud.unlock_at(Vector2(640.0, 300.0)) != -1:
		_fail("an empty table answered a click")
	main.UNLOCKS = kept
	main.go_to_title()
