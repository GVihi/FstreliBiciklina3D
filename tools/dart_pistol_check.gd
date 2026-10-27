extends SceneTree
# Checks the Dart Nerf Pistol (README Milestone C, New Weapons, "Dart Nerf Pistol: Implement weapon"):
#   - the pistol has numbers in data/weapons.json, a place in the primary slot and its own HUD and Loadout names,
#   - it is a small, quick weapon next to the dart gun (smaller clip, semi-automatic) and the dart gun is not,
#   - putting it in the slot gives it its own magazine and pump time, and a new run still starts with the dart gun,
#   - the first-person model changes with the weapon in the slot (the pistol has its own model, the dart gun keeps its),
#   - it fires one dart per pull from its own magazine, reloads with its own step and survives a saved run.
# It uses its own run file (user://dart_pistol_check.json) and never touches the real user://run.json.
# Not checked: the gamepad trigger rule of a semi-automatic weapon (it needs a real trigger pull), the look of the
# gun in the hand (the pistol uses the dart gun model for now) and the feel of the numbers.
# Run from the project folder:
#   godot --headless --path . --script res://tools/dart_pistol_check.gd
# or with tools\run_dart_pistol_check.bat on Windows.
# Exits with status 1 and prints the problems when a check fails.

const WeaponSlots = preload("res://scripts/weapon_slots.gd")
const Weapons = preload("res://scripts/weapons.gd")
const RunSave = preload("res://scripts/run_save.gd")
const PISTOL = "dart_pistol"
const TEST_PATH = "user://dart_pistol_check.json"
const SEED_A = 0x1234ABCD

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	RunSave.test_path = TEST_PATH
	_check_table()
	_check_equip()
	_check_model()
	_check_fire_and_reload()
	_check_run_save()
	_remove_test_file()
	RunSave.test_path = ""
	_finish()


func _check_table() -> void:
	var tuning = Weapons.load_table()
	if not tuning.has(PISTOL):
		_fail("data/weapons.json has no %s" % PISTOL)
		return
	if not WeaponSlots.is_primary_weapon(PISTOL):
		_fail("the pistol cannot be in the primary slot")
	if WeaponSlots.label(PISTOL) != "PISTOL":
		_fail("the HUD calls the pistol %s" % WeaponSlots.label(PISTOL))
	if WeaponSlots.display_name(WeaponSlots.PRIMARY, PISTOL) != "DART NERF PISTOL":
		_fail("the Loadout page calls the pistol %s" % WeaponSlots.display_name("primary", PISTOL))
	if WeaponSlots.display_desc(WeaponSlots.PRIMARY, PISTOL) == "":
		_fail("the pistol has no Loadout text")
	if WeaponSlots.PRIMARY_DEFAULT != PISTOL:
		_fail(
			(
				"the starting weapon is %s, not the pistol (README alpha C1)"
				% WeaponSlots.PRIMARY_DEFAULT
			)
		)
	var p = tuning[PISTOL]
	var d = tuning["dart_gun"]
	if int(p["semi_auto"]) != 1 or int(d["semi_auto"]) != 0:
		_fail(
			(
				"semi_auto is %s for the pistol and %s for the dart gun"
				% [p["semi_auto"], d["semi_auto"]]
			)
		)
	if int(p["start_clip"]) >= int(d["start_clip"]):
		_fail("the pistol clip (%d) is not smaller than the dart gun's" % int(p["start_clip"]))
	if int(p["max_clip"]) <= int(p["start_clip"]) or int(p["clip_step"]) < 1:
		_fail("the pistol clip cannot grow with upgrades")
	if float(p["pump_min"]) >= float(p["pump_start"]) or float(p["pump_step"]) <= 0.0:
		_fail("the pistol fire rate cannot grow with upgrades")
	if int(p["damage"]) < 1:
		_fail("the pistol does no damage")
	for key in d:
		if not p.has(key):
			_fail("the pistol has no %s" % key)


func _check_equip() -> void:
	main.start_game(false, SEED_A)
	if main.primary != PISTOL:
		_fail("a new run starts with %s, not the pistol" % main.primary)
	if not main.equip_primary("dart_gun") or main.primary != "dart_gun":
		_fail("equip_primary refused the dart gun")
	if not main.equip_primary(PISTOL):
		_fail("equip_primary refused the pistol")
		return
	var w = main.primary_stats()
	if main.primary != PISTOL or w != main.WEAPONS[PISTOL]:
		_fail("primary_stats is not the pistol table entry")
	if main.MAXSHELLS != int(w["start_clip"]) or main.shells != main.MAXSHELLS:
		_fail("the pistol magazine is %d/%d" % [main.shells, main.MAXSHELLS])
	if not is_equal_approx(main.pump_base, float(w["pump_start"])):
		_fail("the pistol pump time is %s" % str(main.pump_base))
	if main.player_sys.cur_pump() != float(w["pump_start"]):
		_fail("cur_pump is %s, not the pistol's pump time" % str(main.player_sys.cur_pump()))
	main.equip_primary("dart_gun")
	main.reset_run()
	if main.primary != PISTOL:
		_fail("reset_run left %s in the slot, not the pistol" % main.primary)


# the pistol has its own first-person model, shown while it is in the slot (a new run starts with it), and the dart
# gun's model is shown while the dart gun is in the slot
func _check_model() -> void:
	main.start_game(false, SEED_A)
	main.state = "play"
	main.paused = false
	main.melee = false
	main.player_sys.update_gun(0.016)
	if main.gun_id != PISTOL or main.gun != main.guns.get(PISTOL):
		_fail("a new run does not show the pistol model (gun_id %s)" % main.gun_id)
	if not main.guns.has(PISTOL) or main.guns[PISTOL]["root"] == main.guns["dart_gun"]["root"]:
		_fail("the pistol has no model of its own")
		return
	if not main.guns[PISTOL]["root"].visible or main.guns["dart_gun"]["root"].visible:
		_fail(
			(
				"with the pistol in the slot the pistol is %s and the dart gun %s"
				% [main.guns[PISTOL]["root"].visible, main.guns["dart_gun"]["root"].visible]
			)
		)
	if not is_equal_approx(float(main.gun["pump_z"]), -0.05):
		_fail("the pistol slide rests at z %s" % str(main.gun["pump_z"]))
	if not is_equal_approx(float(main.guns["dart_gun"]["pump_z"]), -0.30):
		_fail("the dart gun pump no longer rests at -0.30")
	main.equip_primary("dart_gun")
	main.player_sys.update_gun(0.016)  # the model follows the slot by itself, whoever put the weapon there
	if main.gun_id != "dart_gun" or main.gun != main.guns["dart_gun"]:
		_fail("the dart gun in the slot does not show the dart gun model (gun_id %s)" % main.gun_id)
	if not main.guns["dart_gun"]["root"].visible or main.guns[PISTOL]["root"].visible:
		_fail(
			(
				"with the dart gun in the slot the dart gun is %s and the pistol %s"
				% [main.guns["dart_gun"]["root"].visible, main.guns[PISTOL]["root"].visible]
			)
		)
	main.equip_primary(PISTOL)
	main.melee = true
	main.player_sys.update_gun(0.016)
	if main.guns[PISTOL]["root"].visible:
		_fail("the pistol is shown while the melee weapon is held")
	main.melee = false
	main.equip_primary("dart_gun")
	main.reset_run()
	main.player_sys.update_gun(0.016)
	if (
		main.gun_id != PISTOL
		or not main.guns[PISTOL]["root"].visible
		or main.guns["dart_gun"]["root"].visible
	):
		_fail("a new run does not bring the pistol model back")


func _check_fire_and_reload() -> void:
	main.start_game(false, SEED_A)
	main.equip_primary(PISTOL)  # already in the slot after start_game, so this changes nothing
	main.shells = main.MAXSHELLS  # a round start fills the magazine; this check never starts a round
	main.state = "play"
	main.paused = false
	main.melee = false
	main.loading = false
	main.pump_t = 0.0
	var before = main.shells
	var darts_before = main.shots_fired
	main.combat_sys.fire()
	if main.shells != before - 1:
		_fail("a pistol shot left %d darts, expected %d" % [main.shells, before - 1])
	if main.shots_fired != darts_before + 1:
		_fail("one pull fired %d darts" % (main.shots_fired - darts_before))
	if not is_equal_approx(main.pump_t, float(main.primary_stats()["pump_start"])):
		_fail("the pump time after a shot is %s" % str(main.pump_t))
	main.combat_sys.fire()  # still pumping: nothing happens
	if main.shells != before - 1 or main.shots_fired != darts_before + 1:
		_fail("the pistol fired again before its pump time was over")
	var step = main.combat_sys.reload_step()
	if not is_equal_approx(step, float(main.primary_stats()["reload_step"])):
		_fail("the pistol reload step is %s" % str(step))
	main.combat_sys.start_load()
	if not main.loading:
		_fail("the pistol did not start a reload")
	main.combat_sys.add_shells(99)
	if main.shells != main.MAXSHELLS:
		_fail("ammo fills the pistol to %d, not %d" % [main.shells, main.MAXSHELLS])
	if main.loading:
		_fail("a full pistol is still reloading")


func _check_run_save() -> void:
	main.start_game(false, SEED_A)
	main.equip_primary(PISTOL)
	var saved = RunSave.capture(main)
	if saved.get("primary", "") != PISTOL:
		_fail("the saved run holds primary %s" % str(saved.get("primary", "<missing>")))
	var cleaned = RunSave.clean(saved)
	if cleaned.get("primary", "") != PISTOL:
		_fail("a cleaned saved run holds primary %s" % str(cleaned.get("primary", "<missing>")))
	main.reset_run()
	RunSave.apply(main, cleaned)
	if main.primary != PISTOL:
		_fail("after loading the saved run the slot holds %s" % main.primary)


func _remove_test_file() -> void:
	for path in [TEST_PATH, TEST_PATH + ".bak", TEST_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish() -> void:
	if problems.is_empty():
		print(
			"dart_pistol_check: the Dart Nerf Pistol is in the game and plays through the primary slot"
		)
		quit(0)
	else:
		for line in problems.slice(0, 15):
			printerr("dart_pistol_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
