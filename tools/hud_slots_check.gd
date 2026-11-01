extends SceneTree
# Checks the weapon slot display of the in-round HUD (README Milestone C "HUD slot display", `slot_rows`,
# `slot_row_rect` and `_draw_hud_slots` in scripts/hud.gd, `hud_status` in scripts/gadgets.gd):
#   - three rows (gun, melee weapon, gadget), keys 1, 2 and G, the weapon in the hands is the one that is lit,
#   - an empty melee or gadget slot has an empty name and is not ready, a filled slot shows the weapon's name,
#   - the gadget status is empty with no gadget, the uses left when it is ready, the uses and the cooldown after a use,
#     and EMPTY with no uses left,
#   - the rows are stacked without overlapping, inside the window and clear of the bottom centre block, at three
#     window sizes,
#   - a round that is up and running draws without trouble and keeps running with every mix of weapon in the hands
#     and slots filled or empty.
# Only what a script can see is checked: how the rows look is for the owner to judge in the game.
# Run from the project folder:
#   godot --headless --path . --script res://tools/hud_slots_check.gd
# or with `python tools/run_checks.py hud_slots`. Exits with status 1 and prints the problems when a check fails.

const SIZES = [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0), Vector2(800.0, 450.0)]
const SEED = 0x2468ACE1
const GADGET = "banana_peel"

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	await _start_round()
	if main.state == "play":
		_check_rows()
		_check_gadget_status()
		_check_geometry()
		await _check_drawing()
	main.force_captured = false
	_finish()


func _fail(text: String) -> void:
	problems.append(text)


func _start_round() -> void:
	main.start_game(false, SEED)
	await process_frame
	if main.state != "map":
		_fail("could not reach the map screen (state %s)" % main.state)
		return
	main.pick_node(0)
	await process_frame
	main.force_captured = true
	await process_frame
	await process_frame
	if main.state != "play":
		_fail("could not start a round (state %s)" % main.state)


func _check_rows() -> void:
	var hud = main.hud
	main.equip_melee("")
	main.equip_gadget("")
	var rows = hud.slot_rows()
	if rows.size() != 3:
		_fail("the slot display has %d rows, not 3" % rows.size())
		return
	var keys = ["1", "2", "G"]
	for i in range(3):
		if rows[i]["key"] != keys[i]:
			_fail("row %d has the key %s, not %s" % [i, rows[i]["key"], keys[i]])
	if rows[0]["name"] == "" or not rows[0]["held"] or rows[1]["held"]:
		_fail("with the gun in the hands the gun row is not the lit one")
	if rows[1]["name"] != "" or rows[1]["ready"]:
		_fail(
			"an empty melee slot shows '%s' (ready %s)" % [rows[1]["name"], str(rows[1]["ready"])]
		)
	if rows[2]["name"] != "" or rows[2]["status"] != "":
		_fail("an empty gadget slot shows '%s' '%s'" % [rows[2]["name"], rows[2]["status"]])
	# a melee weapon in the slot and in the hands
	var melee_id = ""
	for id in main.WeaponSlots.MELEE_WEAPONS:
		melee_id = id
		break
	if melee_id == "" or not main.equip_melee(melee_id):
		_fail("could not put a melee weapon in the melee slot")
	else:
		main.melee = true
		rows = hud.slot_rows()
		if rows[1]["name"] == "" or not rows[1]["held"] or rows[0]["held"]:
			_fail("with the melee weapon in the hands the melee row is not the lit one")
		if not rows[1]["ready"]:
			_fail("a filled melee slot is not ready")
		main.melee = false
	if not main.equip_gadget(GADGET):
		_fail("could not put %s in the gadget slot" % GADGET)
	else:
		rows = hud.slot_rows()
		if rows[2]["name"] == "" or rows[2]["held"]:
			_fail("the gadget row shows '%s' (held %s)" % [rows[2]["name"], str(rows[2]["held"])])


func _check_gadget_status() -> void:
	var gs = main.gadget_sys
	main.equip_gadget("")
	if gs.hud_status() != "":
		_fail("an empty gadget slot has the status '%s'" % gs.hud_status())
	if not main.equip_gadget(GADGET):
		return
	gs.begin_round()
	var ready_text = gs.hud_status()
	if gs.limit() > 0 and not ready_text.begins_with("%d/%d" % [gs.limit(), gs.limit()]):
		_fail("a ready gadget has the status '%s'" % ready_text)
	if ready_text.contains("EMPTY"):
		_fail("a ready gadget says EMPTY")
	gs.cool = 1.5
	if not gs.hud_status().contains("1.5s"):
		_fail("a gadget on cooldown has the status '%s'" % gs.hud_status())
	gs.cool = 0.0
	if gs.limit() > 0:
		gs.uses_left = 0
		if not gs.hud_status().contains("EMPTY"):
			_fail("a gadget with no uses left has the status '%s'" % gs.hud_status())
		gs.uses_left = gs.limit()


func _check_geometry() -> void:
	var hud = main.hud
	for s in SIZES:
		var k = s.y / 720.0
		var rx = s.x - hud.HUD_MARGIN * k
		var bottom = s.y - hud.HUD_BOTTOM * k - 24.0 * k - 40.0 * k
		var label = "%dx%d" % [int(s.x), int(s.y)]
		var last = Rect2()
		for i in range(3):
			var r = hud.slot_row_rect(i, rx, bottom, k)
			if r.position.x < 0.0 or r.position.y < 0.0 or r.end.x > s.x or r.end.y > s.y:
				_fail("%s: row %d (%s) is not inside the window" % [label, i, str(r)])
			if r.position.x <= s.x * 0.5 + 65.0 * k + 8.0 * k:
				_fail("%s: row %d reaches the bottom centre block" % [label, i])
			if i > 0 and r.end.y > last.position.y:
				_fail("%s: row %d overlaps the row below it" % [label, i])
			last = r


func _check_drawing() -> void:
	var was_melee = main.melee
	var melee_id = ""
	for id in main.WeaponSlots.MELEE_WEAPONS:
		melee_id = id
		break
	for with_melee in [false, true]:
		for with_gadget in [false, true]:
			main.equip_melee(melee_id if with_melee else "")
			main.equip_gadget(GADGET if with_gadget else "")
			for in_hands in [false, true]:
				main.melee = in_hands and with_melee
				for s in SIZES:
					main.hud.size = s
					main.hud.queue_redraw()
					await process_frame
				if main.state != "play":
					_fail("the round ended while the slot rows were drawn (state %s)" % main.state)
					return
	main.melee = was_melee
	main.hud.size = SIZES[0]


func _finish() -> void:
	if problems.is_empty():
		print(
			"hud_slots_check: the slot rows say the right things, fit the window and draw in every mix"
		)
		quit(0)
	else:
		for line in problems.slice(0, 12):
			printerr("hud_slots_check: " + line)
		quit(1)
