extends SceneTree
# Checks the weapon slots (README Milestone C, "Add primary weapon slot", "Add melee weapon slot", "Add gadget slot"):
#   - the slot table (scripts/weapon_slots.gd) only names weapons that exist in data/weapons.json, and the
#     default is one of them,
#   - a new run starts with the default weapon in the slot and the numbers of that weapon (magazine, pump time),
#   - the code that fires, reloads and upgrades the gun reads the slot (`primary_stats`), not a fixed name,
#   - equipping refuses an id that cannot be in the slot and changes nothing,
#   - the weapon in the slot is saved with the run and comes back; an old file without it, a wrong value and a
#     value of the wrong type all give the default,
#   - the HUD name of the weapon comes from the slot, and the dart gun still plays as before (fire, shells, reload).
# It uses its own run file (user://weapon_slots_check.json) and never touches the real user://run.json.
# Run from the project folder:
#   godot --headless --path . --script res://tools/weapon_slots_check.gd
# or with tools\run_weapon_slots_check.bat on Windows.
# Exits with status 1 and prints the problems when a check fails.

const WeaponSlots = preload("res://scripts/weapon_slots.gd")
const Weapons = preload("res://scripts/weapons.gd")
const RunSave = preload("res://scripts/run_save.gd")
const TEST_PATH = "user://weapon_slots_check.json"
const SEED_A = 0x1234ABCD

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	RunSave.test_path = TEST_PATH
	_remove_test_file()
	_check_table()
	_check_new_run()
	_check_equip()
	_check_dart_gun_plays()
	_check_run_save()
	_check_old_and_bad_files()
	_check_melee_slot()
	_check_gadget_slot()
	_remove_test_file()
	RunSave.test_path = ""
	_finish()


# every weapon the slot lists has tuning numbers, and the default is one of them
func _check_table() -> void:
	var tuning = Weapons.load_table()
	if not WeaponSlots.PRIMARY_WEAPONS.has(WeaponSlots.PRIMARY_DEFAULT):
		_fail(
			"the default primary weapon %s is not in PRIMARY_WEAPONS" % WeaponSlots.PRIMARY_DEFAULT
		)
	for id in WeaponSlots.PRIMARY_WEAPONS:
		if not tuning.has(id):
			_fail("primary weapon %s has no entry in data/weapons.json" % id)
		if str(WeaponSlots.PRIMARY_WEAPONS[id]).strip_edges() == "":
			_fail("primary weapon %s has no HUD name" % id)
	if WeaponSlots.is_primary_weapon("melee"):
		_fail("melee is accepted in the primary slot")
	for bad in ["", "nope", 5, null, 1.5, [], {}]:
		if WeaponSlots.is_primary_weapon(bad):
			_fail("%s is accepted as a primary weapon" % str(bad))
		if WeaponSlots.primary_or_default(bad) != WeaponSlots.PRIMARY_DEFAULT:
			_fail("%s does not fall back to the default weapon" % str(bad))


# a new run has the default weapon in the slot, with its own starting numbers
func _check_new_run() -> void:
	main.start_game(false, SEED_A)
	if main.primary != WeaponSlots.PRIMARY_DEFAULT:
		_fail("a new run has %s in the primary slot" % str(main.primary))
	var w = main.primary_stats()
	if main.MAXSHELLS != int(w["start_clip"]):
		_fail(
			(
				"the magazine of a new run is %d, the weapon says %d"
				% [main.MAXSHELLS, int(w["start_clip"])]
			)
		)
	if not is_equal_approx(main.pump_base, float(w["pump_start"])):
		_fail(
			(
				"the pump time of a new run is %s, the weapon says %s"
				% [str(main.pump_base), str(w["pump_start"])]
			)
		)
	if main.primary_stats() != main.WEAPONS[WeaponSlots.PRIMARY_DEFAULT]:
		_fail("primary_stats() is not the table entry of the weapon in the slot")


# equipping the weapon that is there works, a bad id is refused and nothing moves
func _check_equip() -> void:
	main.start_game(false, SEED_A)
	main.MAXSHELLS = 9
	main.shells = 4
	main.pump_base = 0.15
	for bad in ["", "nope", "melee", 3, null]:
		if main.equip_primary(bad):
			_fail("equip_primary accepted %s" % str(bad))
	if main.primary != WeaponSlots.PRIMARY_DEFAULT or main.MAXSHELLS != 9 or main.shells != 4:
		_fail("a refused equip changed the slot, the magazine or the shells")
	if not is_equal_approx(main.pump_base, 0.15):
		_fail("a refused equip changed the pump time")
	main.loading = true
	if not main.equip_primary(WeaponSlots.PRIMARY_DEFAULT):
		_fail("equipping the weapon that is already in the slot was refused")
	if main.MAXSHELLS != 9 or main.shells != 4 or not main.loading:
		_fail("equipping the weapon already in the slot reset the gun (upgrades would be lost)")
	main.loading = false


# the dart gun still fires, uses a shell, reloads and does its damage through the slot
func _check_dart_gun_plays() -> void:
	main.start_game(false, SEED_A)
	main.state = "play"
	main.paused = false
	main.melee = false
	var before = main.shells
	main.pump_t = 0.0
	main.loading = false
	main.combat_sys.fire()
	if main.shells != before - 1:
		_fail("a shot left %d shells, expected %d" % [main.shells, before - 1])
	if main.pump_t <= 0.0:
		_fail("a shot did not start the pump time")
	var step = main.combat_sys.reload_step()
	var w = main.primary_stats()
	if not is_equal_approx(step, float(w["reload_step"])):
		_fail("reload_step is %s, the weapon says %s" % [str(step), str(w["reload_step"])])
	main.combat_sys.start_load()
	if not main.loading:
		_fail("a reload did not start with shells missing")
	main.combat_sys.interrupt_load()
	if main.loading:
		_fail("interrupt_load did not stop the reload")


# the slot is written to the saved run and read back
func _check_run_save() -> void:
	main.start_game(false, SEED_A)
	var saved = RunSave.capture(main)
	if saved.get("primary", "") != WeaponSlots.PRIMARY_DEFAULT:
		_fail("the saved run holds primary %s" % str(saved.get("primary", "<missing>")))
	var cleaned = RunSave.clean(saved)
	if cleaned.get("primary", "") != WeaponSlots.PRIMARY_DEFAULT:
		_fail("a cleaned saved run holds primary %s" % str(cleaned.get("primary", "<missing>")))
	main.primary = "something_else"  # as if a later version had saved a weapon this one does not know
	main.reset_run()
	RunSave.apply(main, cleaned)
	if main.primary != WeaponSlots.PRIMARY_DEFAULT:
		_fail("after loading a saved run the primary slot holds %s" % str(main.primary))
	if not RunSave.write_file(saved):
		_fail("the saved run could not be written to the check file")
	var back = RunSave.load_file()
	if back.get("primary", "") != WeaponSlots.PRIMARY_DEFAULT:
		_fail(
			(
				"the saved run read back from the file holds primary %s"
				% str(back.get("primary", "<missing>"))
			)
		)


# a run saved before the slot existed, and hand-edited values, load as the default
func _check_old_and_bad_files() -> void:
	main.start_game(false, SEED_A)
	var base = RunSave.capture(main)
	var old = base.duplicate()
	old.erase("primary")
	if RunSave.clean(old).get("primary", "") != WeaponSlots.PRIMARY_DEFAULT:
		_fail("an old saved run without a primary weapon does not load as the default")
	for bad in ["nope", "melee", "", 7, 1.5, null, [], {}, true]:
		var edited = base.duplicate()
		edited["primary"] = bad
		var c = RunSave.clean(edited)
		if c.get("primary", "") != WeaponSlots.PRIMARY_DEFAULT:
			_fail(
				(
					"a saved primary of %s does not load as the default (%s)"
					% [str(bad), str(c.get("primary"))]
				)
			)


# the melee slot: table, start of a run, equip, the swing through the slot, the save
func _check_melee_slot() -> void:
	var tuning = Weapons.load_table()
	if not WeaponSlots.MELEE_WEAPONS.has(WeaponSlots.MELEE_DEFAULT):
		_fail("the default melee weapon is not in MELEE_WEAPONS")
	for id in WeaponSlots.MELEE_WEAPONS:
		if not tuning.has(id):
			_fail("melee weapon %s has no entry in data/weapons.json" % id)
		if str(WeaponSlots.MELEE_WEAPONS[id]).strip_edges() == "":
			_fail("melee weapon %s has no HUD name" % id)
	if WeaponSlots.is_melee_weapon("dart_gun") or WeaponSlots.is_primary_weapon("melee_x"):
		_fail("a weapon is accepted in the wrong slot")
	for bad in ["", "nope", "dart_gun", 5, null, 1.5, [], {}]:
		if WeaponSlots.is_melee_weapon(bad):
			_fail("%s is accepted as a melee weapon" % str(bad))
		if WeaponSlots.melee_or_default(bad) != WeaponSlots.MELEE_DEFAULT:
			_fail("%s does not fall back to the default melee weapon" % str(bad))
	main.start_game(false, SEED_A)
	if main.melee_weapon != WeaponSlots.MELEE_DEFAULT:
		_fail("a new run has %s in the melee slot" % str(main.melee_weapon))
	if main.melee_stats() != main.WEAPONS[WeaponSlots.MELEE_DEFAULT]:
		_fail("melee_stats() is not the table entry of the weapon in the slot")
	for bad in ["", "nope", "dart_gun", 3, null]:
		if main.equip_melee(bad):
			_fail("equip_melee accepted %s" % str(bad))
	if main.melee_weapon != WeaponSlots.MELEE_DEFAULT:
		_fail("a refused equip changed the melee slot")
	if not main.equip_melee(WeaponSlots.MELEE_DEFAULT):
		_fail("equipping the weapon already in the melee slot was refused")
	# the swing takes its cooldown and time from the slot
	main.state = "play"
	main.paused = false
	main.melee = true
	main.swing_cd = 0.0
	main.swing_t = 0.0
	main.combat_sys.fire()
	var m = main.melee_stats()
	if (
		not is_equal_approx(main.swing_cd, float(m["cooldown"]))
		or not is_equal_approx(main.swing_t, float(m["swing_time"]))
	):
		_fail(
			(
				"a swing set cooldown %s and time %s, the weapon says %s and %s"
				% [str(main.swing_cd), str(main.swing_t), str(m["cooldown"]), str(m["swing_time"])]
			)
		)
	main.melee = false
	# saved with the run; old file and bad values give the default
	var saved = RunSave.capture(main)
	if saved.get("melee_weapon", "") != WeaponSlots.MELEE_DEFAULT:
		_fail("the saved run holds melee_weapon %s" % str(saved.get("melee_weapon", "<missing>")))
	main.melee_weapon = "something_else"
	main.reset_run()
	if main.melee_weapon != WeaponSlots.MELEE_DEFAULT:
		_fail("reset_run left %s in the melee slot" % str(main.melee_weapon))
	main.melee_weapon = "something_else"
	RunSave.apply(main, RunSave.clean(saved))
	if main.melee_weapon != WeaponSlots.MELEE_DEFAULT:
		_fail("after loading a saved run the melee slot holds %s" % str(main.melee_weapon))
	var old = saved.duplicate()
	old.erase("melee_weapon")
	if RunSave.clean(old).get("melee_weapon", "") != WeaponSlots.MELEE_DEFAULT:
		_fail("an old saved run without a melee weapon does not load as the default")
	for bad in ["nope", "dart_gun", "", 7, 1.5, null, [], {}, true]:
		var edited = saved.duplicate()
		edited["melee_weapon"] = bad
		if RunSave.clean(edited).get("melee_weapon", "") != WeaponSlots.MELEE_DEFAULT:
			_fail("a saved melee_weapon of %s does not load as the default" % str(bad))


# the gadget slot: empty at the start of a run (no gadget exists yet), only emptying works, the save
func _check_gadget_slot() -> void:
	var tuning = Weapons.load_table()
	for id in WeaponSlots.GADGET_WEAPONS:
		if not tuning.has(id):
			_fail("gadget %s has no entry in data/weapons.json" % id)
		if str(WeaponSlots.GADGET_WEAPONS[id]).strip_edges() == "":
			_fail("gadget %s has no HUD name" % id)
		if WeaponSlots.is_primary_weapon(id) or WeaponSlots.is_melee_weapon(id):
			_fail("gadget %s is also in another slot" % id)
	for bad in ["", "nope", "dart_gun", "melee", 5, null, 1.5, [], {}]:
		if WeaponSlots.is_gadget(bad):
			_fail("%s is accepted as a gadget" % str(bad))
		if WeaponSlots.gadget_or_none(bad) != WeaponSlots.NO_GADGET:
			_fail("%s does not fall back to an empty gadget slot" % str(bad))
	if WeaponSlots.gadget_label("nope") != "":
		_fail("an unknown gadget has a HUD name")
	main.start_game(false, SEED_A)
	if main.gadget != WeaponSlots.NO_GADGET or not main.gadget_stats().is_empty():
		_fail("a new run has %s in the gadget slot" % str(main.gadget))
	for bad in ["nope", "dart_gun", "melee", 3, null]:
		if main.equip_gadget(bad):
			_fail("equip_gadget accepted %s" % str(bad))
	if main.gadget != WeaponSlots.NO_GADGET:
		_fail("a refused equip changed the gadget slot")
	if not main.equip_gadget(WeaponSlots.NO_GADGET):
		_fail("emptying the gadget slot was refused")
	# the save: a gadget this version does not know (a later version saved it) loads as an empty slot
	var saved = RunSave.capture(main)
	if saved.get("gadget", "<missing>") != WeaponSlots.NO_GADGET:
		_fail("the saved run holds gadget %s" % str(saved.get("gadget", "<missing>")))
	main.gadget = "something_else"
	main.reset_run()
	if main.gadget != WeaponSlots.NO_GADGET:
		_fail("reset_run left %s in the gadget slot" % str(main.gadget))
	main.gadget = "something_else"
	RunSave.apply(main, RunSave.clean(saved))
	if main.gadget != WeaponSlots.NO_GADGET:
		_fail("after loading a saved run the gadget slot holds %s" % str(main.gadget))
	var old = saved.duplicate()
	old.erase("gadget")
	if RunSave.clean(old).get("gadget", "<missing>") != WeaponSlots.NO_GADGET:
		_fail("an old saved run without a gadget does not load as an empty slot")
	for bad in ["nope", "dart_gun", 7, 1.5, null, [], {}, true]:
		var edited = saved.duplicate()
		edited["gadget"] = bad
		if RunSave.clean(edited).get("gadget", "<missing>") != WeaponSlots.NO_GADGET:
			_fail("a saved gadget of %s does not load as an empty slot" % str(bad))


func _remove_test_file() -> void:
	for path in [TEST_PATH, TEST_PATH + ".bak", TEST_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish() -> void:
	if problems.is_empty():
		print("weapon_slots_check: the weapon slots, their save and the dart gun work")
		quit(0)
	else:
		for line in problems.slice(0, 15):
			printerr("weapon_slots_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
