extends SceneTree
# Checks the LOADOUT page, the starting perk and the weapon slots (README Milestone I: "Loadout screen replaces the
# coming soon Loadout page", Milestone C: "Loadout screen: choose primary, melee and gadget before a run"):
#   - the title entry is no longer SOON and opens the page on the chosen row,
#   - the rows are "no starting perk" and the owned starting perks, they fit the screen at two window sizes even with
#     every perk owned, and the page draws,
#   - Up / Down, Enter and the mouse choose a row, the choice is saved in meta.json and survives a reload, and a bad
#     "start_perk" in the file is ignored,
#   - every run (a Daily Run and a typed seed too) starts with the chosen perk, and a perk that is no longer owned
#     is not given,
#   - the three weapon slots: what each lists (an owned weapon only), Left / Right and Up / Down, Enter and the
#     mouse take the next weapon, the choice is saved in meta.json, a bad value is ignored, a weapon that is not
#     owned any more falls back to the slot's default, and every run starts with the chosen weapons.
# The weapons of Milestone C do not exist yet, so the check puts made-up ones in the slot tables and takes them out.
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
	await _check_weapon_layout()
	_check_weapons()
	_check_weapon_runs()
	_remove_fake_weapons()
	_restore_user_files()
	_finish()


func _finish() -> void:
	if problems.is_empty():
		print(
			"loadout_check: the Loadout page lists, chooses and saves the perk and the weapons, and every run starts with them"
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
	if not main.perks.has(perk):
		_fail("a Daily Run did not start with the perk")
	main.start_game(false, 0x1234ABCD)
	if not main.perks.has(perk):
		_fail("a typed-seed run did not start with the perk")
	main.meta.start_perk = ""
	main.start_game()
	if not main.perks.is_empty():
		_fail("a run with no start perk began with %s" % str(main.perks))
	await process_frame
	main.go_to_title()


# ---- weapon slots (made-up weapons stand in for the Milestone C ones)
const FAKE_PRIMARY = "check_gun"
const FAKE_LOCKED = "check_gun_locked"
const FAKE_GADGET = "check_gadget"
const FAKE_LOCK_ID = "weapon_check_gun_locked"
var fake_unlock = {}


func _add_fake_weapons() -> void:
	_remove_fake_weapons()
	for id in [FAKE_PRIMARY, FAKE_LOCKED, FAKE_GADGET]:
		main.WEAPONS[id] = main.WEAPONS["dart_gun"].duplicate()
	main.WeaponSlots.PRIMARY_WEAPONS[FAKE_PRIMARY] = "FAKE GUN"
	main.WeaponSlots.PRIMARY_WEAPONS[FAKE_LOCKED] = "LOCKED GUN"
	main.WeaponSlots.GADGET_WEAPONS[FAKE_GADGET] = "FAKE GADGET"
	# the locked gun has to be bought: it is a "weapon" unlock
	fake_unlock = {"id": FAKE_LOCK_ID, "kind": "weapon", "target": FAKE_LOCKED, "cost": 100}
	main.UNLOCKS.append(fake_unlock)


func _remove_fake_weapons() -> void:
	for id in [FAKE_PRIMARY, FAKE_LOCKED, FAKE_GADGET]:
		main.WEAPONS.erase(id)
		main.WeaponSlots.PRIMARY_WEAPONS.erase(id)
		main.WeaponSlots.GADGET_WEAPONS.erase(id)
	if not fake_unlock.is_empty():
		main.UNLOCKS.erase(fake_unlock)
		fake_unlock = {}


func _ids(opts: Array) -> Array:
	var out = []
	for o in opts:
		out.append(o["id"])
	return out


func _check_weapon_layout() -> void:
	_add_fake_weapons()
	_open_page()
	var hud = main.hud
	for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]:
		hud.size = s
		var detail_top = s.y * 0.84 - 26.0 * s.y / 720.0
		for i in range(main.WeaponSlots.SLOTS.size()):
			var r = hud.loadout_slot_rect(i)
			if (
				r.position.x < 0.0
				or r.end.x > s.x
				or r.position.y < s.y * 0.2
				or r.end.y > detail_top
			):
				_fail("weapon slot %d is off the page or into the detail text at %s" % [i, str(s)])
			if i > 0 and r.intersects(hud.loadout_slot_rect(i - 1)):
				_fail("weapon slots %d and %d overlap at %s" % [i - 1, i, str(s)])
			if hud.loadout_slot_at(r.get_center()) != i:
				_fail(
					(
						"the middle of weapon slot %d picks %d"
						% [i, hud.loadout_slot_at(r.get_center())]
					)
				)
			if hud.loadout_at(r.get_center()) != -1:
				_fail("the middle of weapon slot %d also picks a perk row" % i)
			if r.intersects(hud.loadout_rect(0)):
				_fail("weapon slot %d runs into the perk list at %s" % [i, str(s)])
		for f in range(2):
			hud.queue_redraw()
			await process_frame
	if hud.loadout_slot_at(Vector2(2.0, 2.0)) != -1:
		_fail("a point in the corner picked a weapon slot")
	main.go_to_title()
	if hud.loadout_slot_at(hud.loadout_slot_rect(0).get_center()) != -1:
		_fail("the weapon slots answer on the title menu")
	_remove_fake_weapons()


# the counter in the corner of a slot does not count the empty row ("NO MELEE", "NO GADGET") as an owned weapon
func _check_owned_counter() -> void:
	var hud = main.hud
	var cases = [
		["melee with nothing owned", main.loadout_weapon_options("melee"), 0, "NONE OWNED"],
		["gadget with nothing owned", main.loadout_weapon_options("gadget"), 0, "NONE OWNED"],
		["the pistol alone", main.loadout_weapon_options("primary").slice(0, 1), 0, "1 OF 1 OWNED"],
		["the pistol and the dart gun", main.loadout_weapon_options("primary"), 1, "2 OF 2 OWNED"],
		["an empty row first, two owned, the empty row", _rows(["", "a", "b"]), 0, "2 OWNED"],
		["an empty row first, two owned, the first", _rows(["", "a", "b"]), 1, "1 OF 2 OWNED"],
		["an empty row first, two owned, the second", _rows(["", "a", "b"]), 2, "2 OF 2 OWNED"],
	]
	for c in cases:
		var got = hud.loadout_owned_text(c[1], c[2])
		if got != c[3]:
			_fail("the counter for %s says %s, not %s" % [c[0], got, c[3]])


# rows like those of loadout_weapon_options, with only the ids filled in
func _rows(ids: Array) -> Array:
	var out = []
	for id in ids:
		out.append({"id": id, "name": str(id), "desc": ""})
	return out


func _check_weapons() -> void:
	var inp = main.input_sys
	_own(0)
	main.meta.weapon_choice = {}
	# nothing bought: every slot lists only its default; the dart gun is a weapon unlock (README alpha C2), so the
	# primary slot lists only the Dart Nerf Pistol, the starting weapon
	var wp = main.WeaponSlots
	if _ids(main.loadout_weapon_options("primary")) != ["dart_pistol"]:
		_fail("primary lists %s" % str(_ids(main.loadout_weapon_options("primary"))))
	if main.weapon_owned("dart_gun"):
		_fail("the dart gun is owned from the start")
	main.meta.weapon_choice = {"primary": "dart_gun"}
	if main.loadout_weapon_id("primary") != "dart_pistol":
		_fail("a dart gun that is not bought was still chosen for the primary slot")
	main.meta.weapon_choice = {}
	# buying it (the weapon_dart_gun unlock) puts it in the list, after the pistol
	main.meta.owned["weapon_dart_gun"] = true
	if not main.weapon_owned("dart_gun"):
		_fail("the dart gun is not owned after buying weapon_dart_gun")
	if _ids(main.loadout_weapon_options("primary")) != ["dart_pistol", "dart_gun"]:
		_fail(
			(
				"primary after buying the dart gun lists %s"
				% str(_ids(main.loadout_weapon_options("primary")))
			)
		)
	if _ids(main.loadout_weapon_options("melee")) != [""]:  # the gummy worm is bought (tools/melee_lock_check.gd)
		_fail("melee lists %s" % str(_ids(main.loadout_weapon_options("melee"))))
	if main.loadout_weapon_options("melee")[0]["name"] != "NO MELEE":
		_fail("the empty melee row is called %s" % main.loadout_weapon_options("melee")[0]["name"])
	if _ids(main.loadout_weapon_options("gadget")) != [""]:
		_fail("gadget lists %s" % str(_ids(main.loadout_weapon_options("gadget"))))
	if main.loadout_weapon_options("gadget")[0]["name"] != "NO GADGET":
		_fail(
			"the empty gadget row is called %s" % main.loadout_weapon_options("gadget")[0]["name"]
		)
	if main.loadout_weapon_options("primary")[0]["name"] != "DART NERF PISTOL":
		_fail("the pistol row is called %s" % main.loadout_weapon_options("primary")[0]["name"])
	_check_owned_counter()
	_open_page()
	if main.loadout_col != 0 or main.loadout_slot != 0:
		_fail("the page did not open on the perk list")
	inp.loadout_switch(1)
	if main.loadout_col != 1:
		_fail("Right did not move to the weapon slots")
	inp.loadout_switch(1)
	if main.loadout_col != 1:
		_fail("Right again left the weapon slots")
	if main.loadout_weapon_options("primary")[1]["name"] != "DART GUN":
		_fail("the dart gun row is called %s" % main.loadout_weapon_options("primary")[1]["name"])
	inp.loadout_pick()  # the next owned weapon after the pistol is the dart gun
	if main.loadout_weapon_id("primary") != "dart_gun":
		_fail("choosing took '%s', not the dart gun" % main.loadout_weapon_id("primary"))
	inp.loadout_pick()  # and round to the pistol again
	if main.loadout_weapon_id("primary") != "dart_pistol":
		_fail("choosing again took '%s', not the pistol" % main.loadout_weapon_id("primary"))
	_add_fake_weapons()
	inp.title_move(1)
	inp.title_move(1)
	if main.loadout_slot != 2:
		_fail("Down twice in the weapon slots went to %d" % main.loadout_slot)
	inp.title_move(1)
	if main.loadout_slot != 0:
		_fail("Down from the last slot went to %d, not round to the first" % main.loadout_slot)
	if main.loadout_sel != 0:
		_fail("moving in the weapon slots moved the perk list")
	# the made-up gun is owned from the start, the locked one has to be bought
	if _ids(main.loadout_weapon_options("primary")) != ["dart_pistol", "dart_gun", FAKE_PRIMARY]:
		_fail("primary lists %s" % str(_ids(main.loadout_weapon_options("primary"))))
	inp.menu_confirm()  # Enter on PRIMARY: the next owned weapon, the dart gun
	if main.loadout_weapon_id("primary") != "dart_gun":
		_fail("Enter chose '%s', not the dart gun" % main.loadout_weapon_id("primary"))
	inp.menu_confirm()  # the made-up gun after it
	if main.meta.weapon_choice.get("primary", "") != FAKE_PRIMARY:
		_fail("Enter chose '%s' for primary" % str(main.meta.weapon_choice.get("primary", "")))
	if main.loadout_weapon_id("primary") != FAKE_PRIMARY:
		_fail("loadout_weapon_id is '%s'" % main.loadout_weapon_id("primary"))
	inp.menu_confirm()  # wraps back to the default
	if main.loadout_weapon_id("primary") != "dart_pistol":
		_fail("Enter again gave '%s', not the first weapon" % main.loadout_weapon_id("primary"))
	# buying the locked gun adds it to the list
	main.meta.owned[FAKE_LOCK_ID] = true
	if (
		_ids(main.loadout_weapon_options("primary"))
		!= ["dart_pistol", "dart_gun", FAKE_PRIMARY, FAKE_LOCKED]
	):
		_fail("after buying, primary lists %s" % str(_ids(main.loadout_weapon_options("primary"))))
	# the gadget slot: the empty slot first, then the made-up gadget
	main.loadout_slot = 2
	inp.loadout_pick()
	if main.loadout_weapon_id("gadget") != FAKE_GADGET:
		_fail("the gadget slot chose '%s'" % main.loadout_weapon_id("gadget"))
	inp.loadout_pick()
	if main.loadout_weapon_id("gadget") != "":
		_fail("the gadget slot did not wrap round to NO GADGET")
	# the mouse: hovering selects a slot and the list, a click chooses
	main.meta.owned[_perk_unlocks()[0]["id"]] = true  # a perk row to hover
	main.hud.size = Vector2(1280.0, 720.0)
	main.loadout_col = 0
	inp.hover_menu(main.hud.loadout_slot_rect(0).get_center())
	if main.loadout_col != 1 or main.loadout_slot != 0:
		_fail(
			(
				"hovering weapon slot 0 selected list %d slot %d"
				% [main.loadout_col, main.loadout_slot]
			)
		)
	inp.hover_menu(main.hud.loadout_rect(1).get_center())
	if main.loadout_col != 0 or main.loadout_sel != 1:
		_fail("hovering perk row 1 selected list %d row %d" % [main.loadout_col, main.loadout_sel])
	# the choice is saved and read back
	main.loadout_slot = 0
	main.loadout_col = 1
	inp.loadout_pick()
	var chosen = main.loadout_weapon_id("primary")
	main.meta.save_meta()
	main.meta.load_meta()
	if str(main.meta.weapon_choice.get("primary", "")) != chosen:
		_fail("the primary choice '%s' did not survive a reload" % chosen)
	_write(
		'{"version": 1, "loadout": {"primary": 5, "melee": ["x"], "gadget": null, "other": "y"}}'
	)
	main.meta.load_meta()
	if not main.meta.weapon_choice.is_empty():
		_fail("bad values in the file were kept: %s" % str(main.meta.weapon_choice))
	_write('{"version": 1, "loadout": "nonsense"}')
	main.meta.load_meta()
	if not main.meta.weapon_choice.is_empty():
		_fail("a loadout that is not an object was kept")
	# a weapon that is no longer owned or no longer exists falls back to the default
	main.meta.weapon_choice = {"primary": FAKE_LOCKED, "melee": "nope", "gadget": "also_nope"}
	main.meta.owned = {}
	if main.loadout_weapon_id("primary") != "dart_pistol":
		_fail("a weapon that is not owned is still the primary choice")
	if main.loadout_weapon_id("melee") != "" or main.loadout_weapon_id("gadget") != "":
		_fail("an unknown weapon is still chosen for melee or gadget")
	inp.title_back()
	_remove_fake_weapons()


func _check_weapon_runs() -> void:
	_add_fake_weapons()
	_own(0)
	main.meta.owned["weapon_gummy_worm"] = true  # the worm has to be bought before a run can start with it
	main.meta.weapon_choice = {"primary": FAKE_PRIMARY, "melee": "melee", "gadget": FAKE_GADGET}
	for mode in ["normal", "daily", "seed"]:
		if mode == "normal":
			main.start_game()
		elif mode == "daily":
			main.start_game(true)
		else:
			main.start_game(false, 0x1234ABCD)
		if (
			main.primary != FAKE_PRIMARY
			or main.gadget != FAKE_GADGET
			or main.melee_weapon != "melee"
		):
			_fail(
				(
					"a %s run started with primary %s, melee %s, gadget %s"
					% [mode, main.primary, main.melee_weapon, main.gadget]
				)
			)
	main.meta.weapon_choice = {}
	main.start_game()
	if main.primary != "dart_pistol" or main.gadget != "":
		_fail("a run with no choice did not start with the defaults")
	# the dart gun (alpha C2): not bought, a run that asks for it still starts with the pistol; bought and chosen,
	# a normal run, a Daily Run and a typed seed all start with it in the primary slot
	main.meta.weapon_choice = {"primary": "dart_gun"}
	main.start_game()
	if main.primary != "dart_pistol":
		_fail("a run started with the dart gun before it was bought (primary %s)" % main.primary)
	main.meta.owned["weapon_dart_gun"] = true
	for mode in ["normal", "daily", "seed"]:
		if mode == "normal":
			main.start_game()
		elif mode == "daily":
			main.start_game(true)
		else:
			main.start_game(false, 0x1234ABCD)
		if main.primary != "dart_gun":
			_fail("a %s run with the bought dart gun started with %s" % [mode, main.primary])
	main.meta.owned.erase("weapon_dart_gun")
	main.meta.weapon_choice = {}
	_remove_fake_weapons()
