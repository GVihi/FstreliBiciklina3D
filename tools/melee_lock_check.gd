extends SceneTree
# Checks that the melee weapon is locked at the start (README Milestone C, "Melee weapon is locked at the start"):
#   - the gummy worm is an unlock of its own (weapon_gummy_worm, target `melee`, tier 1, 30 coins) and is not planned,
#   - a new player's run starts with the dart pistol only: the melee slot is empty, melee_stats() is empty, and the
#     Loadout page lists only NO MELEE for the slot,
#   - with an empty slot Q, the wheel, 1 and 2 keep the dart gun in the hands, a swing does nothing, the shop does not
#     offer MELEE REACH, and the HUD does not offer [Q] SWITCH (the HUD text itself is not drawn here),
#   - buying costs exactly 30 coins (29 is refused and nothing is spent), puts the worm on the Loadout page and, while
#     nothing is chosen for the slot, chooses it, so the next run starts with it and Q switches again,
#   - a run asking for the worm while it is not owned starts with an empty slot (a chosen weapon that is not owned
#     falls back to the slot's default), and another melee weapon bought first fills the empty slot the same way,
#   - an empty slot survives a saved run and a run saved before the lock (no melee_weapon field) loads with the worm.
# It keeps the real meta.json (and its backups) first and puts them back at the end, and uses its own run file
# (user://melee_lock_check.json).
# Not checked: how the empty slot looks in the HUD and on the Loadout page (an in-game look by a person), and the price
# against real coin income (a first guess).
# Run from the project folder:
#   godot --headless --path . --script res://tools/melee_lock_check.gd
# or with: python tools/run_checks.py melee_lock
# Exits with status 1 and prints the problems when a check fails.

const WeaponSlots = preload("res://scripts/weapon_slots.gd")
const RunSave = preload("res://scripts/run_save.gd")
const WORM = "melee"
const NOODLE = "pool_noodle"
const UNLOCK_ID = "weapon_gummy_worm"
const NOODLE_UNLOCK_ID = "weapon_pool_noodle"
const PRICE = 30
const TEST_PATH = "user://melee_lock_check.json"
const SEED_A = 0x1234ABCD

var problems = []
var main
var kept = {}


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_keep_user_files()
	RunSave.test_path = TEST_PATH
	_check_unlock_entry()
	_check_new_player()
	_check_empty_slot_in_play()
	_check_buying()
	_check_not_owned_falls_back()
	_check_other_melee_fills_slot()
	_check_run_save()
	RunSave.test_path = ""
	_remove_test_file()
	_restore_user_files()
	_finish()


func _finish() -> void:
	if problems.is_empty():
		print(
			"melee_lock_check: the gummy worm is a 30 coin purchase and a new player starts with the pistol only"
		)
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("melee_lock_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


func _paths() -> Array:
	var meta_path = main.meta.PATH
	return [meta_path, meta_path + ".bad.bak", meta_path + ".v2.bak"]


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


func _remove_test_file() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


# a new player: nothing bought, nothing chosen, no coins
func _fresh(balance: int = 0) -> void:
	main.meta.balance = balance
	main.meta.total_earned = balance
	main.meta.owned = {}
	main.meta.weapon_choice = {}
	main.meta.start_perk = ""


func _unlock(id: String) -> Dictionary:
	for u in main.UNLOCKS:
		if u["id"] == id:
			return u
	return {}


func _ids(rows: Array) -> Array:
	var out = []
	for o in rows:
		out.append(o["id"])
	return out


func _play() -> void:
	main.start_game(false, SEED_A)
	main.state = "play"
	main.paused = false
	main.swing_cd = 0.0
	main.swing_t = 0.0


func _check_unlock_entry() -> void:
	var u = _unlock(UNLOCK_ID)
	if u.is_empty():
		_fail("data/unlocks.json has no %s" % UNLOCK_ID)
		return
	if u["kind"] != "weapon" or u["target"] != WORM:
		_fail(
			(
				"%s is %s for %s, expected a weapon unlock for %s"
				% [UNLOCK_ID, u["kind"], u["target"], WORM]
			)
		)
	if int(u["tier"]) != 1 or int(u["cost"]) != PRICE:
		_fail(
			(
				"%s is tier %d at %d coins, expected tier 1 at %d"
				% [UNLOCK_ID, int(u["tier"]), int(u["cost"]), PRICE]
			)
		)
	if bool(u["planned"]):
		_fail("%s is planned, but the gummy worm exists" % UNLOCK_ID)
	if not WeaponSlots.MELEE_WEAPONS.has(WORM) or not main.WEAPONS.has(WORM):
		_fail("the gummy worm is not a melee weapon of data/weapons.json any more")


func _check_new_player() -> void:
	_fresh()
	if main.weapon_owned(WORM):
		_fail("the gummy worm is owned by a new player")
	if WeaponSlots.default_of("melee") != WeaponSlots.NO_MELEE:
		_fail(
			"the melee slot's default is '%s', not an empty slot" % WeaponSlots.default_of("melee")
		)
	var rows = main.loadout_weapon_options("melee")
	if _ids(rows) != [""]:
		_fail("the Loadout page lists %s for a new player's melee slot" % str(_ids(rows)))
	elif rows[0]["name"] != "NO MELEE":
		_fail("the empty melee row is called '%s'" % str(rows[0]["name"]))
	if main.loadout_weapon_id("primary") != "dart_pistol" or main.loadout_weapon_id("melee") != "":
		_fail(
			(
				"a new player's loadout is %s / %s"
				% [main.loadout_weapon_id("primary"), main.loadout_weapon_id("melee")]
			)
		)
	# even a choice of the worm in the file does not give it away
	main.meta.weapon_choice = {"melee": WORM}
	if main.loadout_weapon_id("melee") != "":
		_fail("a chosen worm that is not owned is still equipped")
	for mode in ["normal", "daily", "seed"]:
		if mode == "normal":
			main.start_game()
		elif mode == "daily":
			main.start_game(true)
		else:
			main.start_game(false, SEED_A)
		if (
			main.primary != "dart_pistol"
			or main.melee_weapon != ""
			or main.has_melee()
			or main.gadget != ""
		):
			_fail(
				(
					"a %s run of a new player started with primary %s, melee '%s', gadget '%s'"
					% [mode, main.primary, main.melee_weapon, main.gadget]
				)
			)
		if not main.melee_stats().is_empty():
			_fail("melee_stats() of an empty slot is not empty")
	main.meta.weapon_choice = {}


# Q, the wheel, 1 and 2 with nothing to switch to, and a swing that has nothing to swing
func _check_empty_slot_in_play() -> void:
	_fresh()
	_play()
	var inp = main.input_sys
	inp.toggle_weapon()
	if main.melee:
		_fail("Q put an empty melee slot in the player's hands")
	inp.toggle_weapon(true)
	if main.melee:
		_fail("key 2 put an empty melee slot in the player's hands")
	inp.toggle_weapon(false)
	if main.melee:
		_fail("key 1 changed the weapon in hand")
	main.combat_sys.swing()
	if main.swing_cd != 0.0 or main.swing_t != 0.0:
		_fail(
			(
				"a swing with an empty slot set cooldown %s and time %s"
				% [str(main.swing_cd), str(main.swing_t)]
			)
		)
	if main.combat_sys.deflecting():
		_fail("an empty melee slot deflects phones")
	if main.shop_sys.upgrade_ok("rubber"):
		_fail("MELEE REACH is offered with an empty melee slot")
	# the same state set by hand (an old file, a check) is put right when the slot is emptied
	main.equip_melee(WORM)
	main.melee = true
	if not main.equip_melee(""):
		_fail("equip_melee refused to empty the melee slot")
	if main.melee or main.has_melee() or main.melee_weapon != "":
		_fail(
			"emptying the slot left melee %s and weapon '%s'" % [str(main.melee), main.melee_weapon]
		)
	# other slots are not touched, and a wrong id is still refused
	if main.equip_melee("dart_gun") or main.equip_melee("nope") or main.equip_melee(5):
		_fail("equip_melee accepted something that is not a melee weapon")


func _check_buying() -> void:
	_fresh(PRICE - 1)
	var u = _unlock(UNLOCK_ID)
	if main.meta.buy(u) != "locked" or main.meta.balance != PRICE - 1 or main.meta.owns(UNLOCK_ID):
		_fail(
			(
				"buying with %d coins was not refused cleanly (balance %d)"
				% [PRICE - 1, main.meta.balance]
			)
		)
	main.meta.balance = PRICE
	if main.meta.buy(u) != "bought" or main.meta.balance != 0 or not main.meta.owns(UNLOCK_ID):
		_fail("buying with exactly %d coins failed (balance %d)" % [PRICE, main.meta.balance])
	if not main.weapon_owned(WORM):
		_fail("the worm is not owned after buying it")
	if _ids(main.loadout_weapon_options("melee")) != ["", WORM]:
		_fail(
			(
				"the Loadout page lists %s after buying"
				% str(_ids(main.loadout_weapon_options("melee")))
			)
		)
	if str(main.meta.weapon_choice.get("melee", "")) != WORM:
		_fail("buying the worm with nothing chosen did not choose it")
	# the choice is saved with the purchase
	main.meta.load_meta()
	if not main.meta.owns(UNLOCK_ID) or str(main.meta.weapon_choice.get("melee", "")) != WORM:
		_fail("the purchase or the choice did not survive a reload of meta.json")
	_play()
	if main.melee_weapon != WORM or not main.has_melee():
		_fail("a run after buying the worm started with '%s'" % main.melee_weapon)
	var stats = main.melee_stats()
	if stats.is_empty() or stats != main.WEAPONS[WORM]:
		_fail("melee_stats() is not the worm's table entry")
	if not main.shop_sys.upgrade_ok("rubber"):
		_fail("MELEE REACH is not offered with the worm in the slot")
	main.input_sys.toggle_weapon()
	if not main.melee:
		_fail("Q does not switch to the worm that was bought")
	main.combat_sys.swing()
	if main.swing_cd <= 0.0:
		_fail("the worm does not swing")
	main.input_sys.toggle_weapon()
	if main.melee:
		_fail("Q does not switch back to the dart gun")
	# choosing "NO MELEE" on the Loadout page is allowed and the worm stays owned
	main.meta.choose_weapon("melee", "")
	_play()
	if main.has_melee() or not main.weapon_owned(WORM):
		_fail("choosing NO MELEE did not empty the slot (or lost the purchase)")
	# a second purchase attempt does not charge again
	main.meta.balance = 100
	if main.meta.buy(u) != "owned" or main.meta.balance != 100:
		_fail("a second purchase was not refused as owned")
	# and the choice the player made (empty) is not overwritten by buying nothing
	if str(main.meta.weapon_choice.get("melee", "x")) != "":
		_fail("a refused purchase changed the melee choice")


func _check_not_owned_falls_back() -> void:
	_fresh()
	main.meta.weapon_choice = {"primary": "dart_pistol", "melee": WORM, "gadget": ""}
	for mode in ["normal", "daily", "seed"]:
		if mode == "normal":
			main.start_game()
		elif mode == "daily":
			main.start_game(true)
		else:
			main.start_game(false, SEED_A)
		if main.melee_weapon != "":
			_fail(
				"a %s run started with melee '%s' that was not bought" % [mode, main.melee_weapon]
			)
	main.meta.weapon_choice = {}


# any melee weapon bought into an empty, unchosen slot is chosen, so it is not left unused; the worm bought later
# does not push out a weapon that is already chosen
func _check_other_melee_fills_slot() -> void:
	_fresh(500)
	var noodle = _unlock(NOODLE_UNLOCK_ID)
	if noodle.is_empty():
		_fail("data/unlocks.json has no %s" % NOODLE_UNLOCK_ID)
		return
	if main.meta.buy(noodle) != "bought":
		_fail("the noodle could not be bought with 500 coins")
	if str(main.meta.weapon_choice.get("melee", "")) != NOODLE:
		_fail("the noodle bought into an empty melee slot was not chosen")
	if main.meta.buy(_unlock(UNLOCK_ID)) != "bought":
		_fail("the worm could not be bought after the noodle")
	if str(main.meta.weapon_choice.get("melee", "")) != NOODLE:
		_fail("buying the worm replaced the noodle the player had chosen")
	if _ids(main.loadout_weapon_options("melee")) != ["", WORM, NOODLE]:
		_fail(
			(
				"the Loadout page lists %s with both bought"
				% str(_ids(main.loadout_weapon_options("melee")))
			)
		)
	# a primary weapon bought is not put into the melee slot
	_fresh(1000)
	main.meta.buy(_unlock("weapon_dart_gun"))
	if str(main.meta.weapon_choice.get("melee", "")) != "":
		_fail("buying the dart gun chose something for the melee slot")


func _check_run_save() -> void:
	_fresh(PRICE)
	main.meta.buy(_unlock(UNLOCK_ID))
	_play()
	main.equip_melee(WORM)
	var saved = RunSave.capture(main)
	if saved.get("melee_weapon", "<missing>") != WORM:
		_fail(
			(
				"a run with the worm saved melee_weapon %s"
				% str(saved.get("melee_weapon", "<missing>"))
			)
		)
	# an empty slot is saved as empty and loads as empty, never as the worm
	main.equip_melee("")
	saved = RunSave.capture(main)
	if saved.get("melee_weapon", "<missing>") != "":
		_fail("an empty slot saved melee_weapon %s" % str(saved.get("melee_weapon", "<missing>")))
	var cleaned = RunSave.clean(saved)
	if cleaned.get("melee_weapon", "<missing>") != "":
		_fail(
			"a saved empty melee slot loads as '%s'" % str(cleaned.get("melee_weapon", "<missing>"))
		)
	main.equip_melee(WORM)
	RunSave.apply(main, cleaned)
	if main.melee_weapon != "" or main.melee:
		_fail(
			(
				"loading a run saved with an empty slot left melee_weapon '%s', melee %s"
				% [main.melee_weapon, str(main.melee)]
			)
		)
	# a file that says the worm is in hand with nothing in the slot cannot put an empty slot in the player's hands
	var odd = saved.duplicate()
	odd["melee"] = true
	odd["melee_weapon"] = ""
	if RunSave.clean(odd).get("melee", true) != false:
		_fail("a saved run holding an empty slot in hand loads with melee on")
	# a run saved before the lock has no field and was played with the worm
	var old = saved.duplicate()
	old.erase("melee_weapon")
	if RunSave.clean(old).get("melee_weapon", "<missing>") != WORM:
		_fail("a run saved before the lock does not load with the worm")
	# an id the game does not have is an empty slot
	for bad in ["nope", "dart_gun", 7, null, [], {}]:
		var edited = saved.duplicate()
		edited["melee_weapon"] = bad
		if RunSave.clean(edited).get("melee_weapon", "<missing>") != "":
			_fail("a saved melee_weapon of %s does not load as an empty slot" % str(bad))
