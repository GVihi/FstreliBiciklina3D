extends SceneTree
# Checks the LOADOUT page and the starting perk (README Milestone I: "Loadout screen replaces the coming soon
# Loadout page"):
#   - the title entry is no longer SOON and opens the page on the chosen row,
#   - the rows are "no starting perk" and the owned starting perks, they fit the screen at two window sizes even with
#     every perk owned, and the page draws,
#   - Up / Down, Enter and the mouse choose a row, the choice is saved in meta.json and survives a reload, and a bad
#     "start_perk" in the file is ignored,
#   - a normal run starts with the chosen perk, a Daily Run and a typed seed do not, and a perk that is no longer
#     owned is not given.
# It keeps the real meta.json (and its backups) first and puts them back at the end.
# Run from the project folder:
#   godot --headless --path . --script res://tools/loadout_check.gd
# or with tools\run_loadout_check.bat on Windows.
# Exits with status 1 and prints the problems when a check fails.

var problems = []
var main
var kept = {}


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_keep_user_files()
	_check_options()
	await _check_layout()
	_check_choosing()
	_check_save()
	await _check_runs()
	_restore_user_files()
	_finish()


func _finish() -> void:
	if problems.is_empty():
		print(
			"loadout_check: the Loadout page lists, chooses and saves, and normal runs start with the perk"
		)
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("loadout_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


func _paths() -> Array:
	return [main.meta.PATH, main.meta.PATH + ".bad.bak", main.meta.PATH + ".v2.bak"]


func _keep_user_files() -> void:
	for path in _paths():
		if FileAccess.file_exists(path):
			kept[path] = FileAccess.get_file_as_bytes(path)


func _restore_user_files() -> void:
	for path in _paths():
		if kept.has(path):
			var f = FileAccess.open(path, FileAccess.WRITE)
			if f:
				f.store_buffer(kept[path])
				f.close()
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.meta.load_meta()


func _entry(id: String) -> int:
	for i in range(main.hud.TITLE_ITEMS.size()):
		if main.hud.TITLE_ITEMS[i]["id"] == id:
			return i
	return -1


func _perk_unlocks() -> Array:
	var out = []
	for u in main.UNLOCKS:
		if u["kind"] == "starting_perk":
			out.append(u)
	return out


func _own(count: int) -> void:
	main.meta.owned = {}
	main.meta.start_perk = ""
	var perks = _perk_unlocks()
	for i in range(mini(count, perks.size())):
		main.meta.owned[perks[i]["id"]] = true


func _open_page() -> void:
	main.go_to_title()
	main.input_sys.title_activate(_entry("loadout"))


func _check_options() -> void:
	if main.hud.TITLE_ITEMS[_entry("loadout")].get("soon", false):
		_fail("LOADOUT is still marked SOON")
	_own(0)
	var opts = main.loadout_options()
	if opts.size() != 1 or opts[0]["id"] != "":
		_fail("with nothing owned the rows are %s" % str(opts))
	_own(2)
	opts = main.loadout_options()
	var perks = _perk_unlocks()
	if opts.size() != 3 or opts[1]["id"] != perks[0]["id"] or opts[2]["id"] != perks[1]["id"]:
		_fail("with two perks owned the rows are %s" % str(opts))
	if opts.size() == 3 and opts[1]["name"] != perks[0]["name"]:
		_fail("a row does not carry the perk's name")


func _check_layout() -> void:
	_own(100)  # every starting perk
	_open_page()
	var n = main.loadout_options().size()
	var hud = main.hud
	for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]:
		hud.size = s
		var detail_top = s.y * 0.84 - 26.0 * s.y / 720.0
		var last = Rect2()
		for i in range(n):
			var r = hud.loadout_rect(i)
			if r.position.x < 0.0 or r.end.x > s.x or r.position.y < s.y * 0.2:
				_fail("row %d is off the page at %s" % [i, str(s)])
			if i > 0 and r.intersects(hud.loadout_rect(i - 1)):
				_fail("rows %d and %d overlap at %s" % [i - 1, i, str(s)])
			if hud.loadout_at(r.get_center()) != i:
				_fail("the middle of row %d picks %d" % [i, hud.loadout_at(r.get_center())])
			last = r
		if last.end.y > detail_top:
			_fail("the last row runs into the detail text at %s" % str(s))
		for f in range(2):
			hud.queue_redraw()
			await process_frame
	if hud.loadout_at(Vector2(2.0, 2.0)) != -1:
		_fail("a point in the corner picked a row")
	main.go_to_title()
	if hud.loadout_at(hud.loadout_rect(0).get_center()) != -1:
		_fail("the rows answer on the title menu")


func _check_choosing() -> void:
	_own(3)
	var perks = _perk_unlocks()
	_open_page()
	var inp = main.input_sys
	if main.loadout_sel != 0:
		_fail("the page did not open on 'no starting perk'")
	inp.title_move(1)
	inp.title_move(1)
	if main.loadout_sel != 2:
		_fail("Down twice went to %d" % main.loadout_sel)
	inp.menu_confirm()  # Enter
	if main.meta.start_perk != perks[1]["id"] or main.title_page != "loadout":
		_fail("Enter chose '%s' (page '%s')" % [main.meta.start_perk, main.title_page])
	if main.start_perk_id() != perks[1]["target"]:
		_fail("start_perk_id is '%s', expected %s" % [main.start_perk_id(), perks[1]["target"]])
	inp.title_move(-1)
	inp.title_move(-1)
	inp.title_move(-1)  # wraps to the last row
	if main.loadout_sel != 3:
		_fail("Up from the first row went to %d" % main.loadout_sel)
	# the mouse picks a row
	main.hud.size = Vector2(1280.0, 720.0)
	main.loadout_sel = 0
	inp.hover_menu(main.hud.loadout_rect(1).get_center())
	if main.loadout_sel != 1:
		_fail("hovering row 1 selected %d" % main.loadout_sel)
	inp.loadout_pick()
	if main.meta.start_perk != perks[0]["id"]:
		_fail("picking row 1 chose '%s'" % main.meta.start_perk)
	# reopening starts on the chosen row; 'none' clears it
	_open_page()
	if main.loadout_sel != 1:
		_fail("the page reopened on row %d, not the chosen row 1" % main.loadout_sel)
	main.loadout_sel = 0
	inp.loadout_pick()
	if main.meta.start_perk != "" or main.start_perk_id() != "":
		_fail("choosing 'no starting perk' left '%s'" % main.meta.start_perk)
	inp.title_back()
	if main.title_page != "":
		_fail("going back left the page open")
	# a perk that is no longer owned is not given
	main.meta.start_perk = perks[0]["id"]
	main.meta.owned = {}
	if main.start_perk_id() != "":
		_fail("a perk that is not owned any more is still the start perk")


func _write(text: String) -> void:
	var f = FileAccess.open(main.meta.PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _check_save() -> void:
	var perks = _perk_unlocks()
	_own(2)
	main.meta.choose_start_perk(perks[1]["id"])
	main.meta.start_perk = ""
	main.meta.owned = {}
	main.meta.load_meta()
	if main.meta.start_perk != perks[1]["id"] or not main.meta.owns(perks[1]["id"]):
		_fail("after a reload the start perk is '%s'" % main.meta.start_perk)
	_write('{"version": 1, "balance": 5, "total_earned": 5}')
	main.meta.load_meta()
	if main.meta.start_perk != "":
		_fail("an old meta.json gave start perk '%s'" % main.meta.start_perk)
	_write('{"version": 1, "balance": 5, "total_earned": 5, "start_perk": 7}')
	main.meta.load_meta()
	if main.meta.start_perk != "" or main.meta.balance != 5:
		_fail("a number as start_perk was not ignored")


func _check_runs() -> void:
	var perks = _perk_unlocks()
	_own(2)
	main.meta.start_perk = perks[0]["id"]
	var perk = str(perks[0]["target"])
	main.start_game()
	if not main.perks.has(perk):
		_fail("a normal run did not start with %s" % perk)
	if main.perks.size() != 1:
		_fail("a normal run started with %s" % str(main.perks))
	main.start_game(true)
	if main.perks.has(perk):
		_fail("a Daily Run started with the perk")
	main.start_game(false, 0x1234ABCD)
	if main.perks.has(perk):
		_fail("a typed-seed run started with the perk")
	main.meta.start_perk = ""
	main.start_game()
	if not main.perks.is_empty():
		_fail("a run with no start perk began with %s" % str(main.perks))
	await process_frame
	main.go_to_title()
