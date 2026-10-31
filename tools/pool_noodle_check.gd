extends SceneTree
# Checks the Pool Noodle (README Milestone C, New Melee Weapons, "Pool Noodle: Implement weapon, and the sweep"):
#   - it is in data/weapons.json as a melee weapon with damage 1, the longest reach and the longest deflect range of
#     the melee weapons so far and a `sweep_arc`, it has its own HUD and Loadout names and has to be bought
#     (weapon_pool_noodle, tier 1, 60 coins),
#   - a swing hits a slice in front of the player: riders inside the arc are hit, riders beside or behind the player
#     are not, a rider just past the reach is not, and Melee Reach moves the edge out,
#   - the sweep hits EVERY rider inside the arc, each exactly once per swing, for the weapon's damage (1), and a second
#     swing inside the cooldown hits nothing,
#   - the gummy worm still hits its circular zone (a rider to the side that the noodle hits and the worm misses),
#   - the deflect range is the noodle's own and a phone just outside it is not sent back,
#   - the swing animation follows the noodle's swing time and the first-person model of the noodle is shown with the
#     noodle in the slot and the worm's club with the worm (and only one of them at a time),
#   - it survives a saved run.
# It uses its own run file (user://pool_noodle_check.json) and never touches the real user://run.json.
# Not checked: how the noodle looks and feels in the hand, whether the swing is fun, the numbers (first guesses), and
# a boss inside the arc (bosses go through the same `melee_hits` test as riders, but no boss is spawned here).
# Run from the project folder:
#   godot --headless --path . --script res://tools/pool_noodle_check.gd
# or with: python tools/run_checks.py pool_noodle
# Exits with status 1 and prints the problems when a check fails.

const WeaponSlots = preload("res://scripts/weapon_slots.gd")
const Weapons = preload("res://scripts/weapons.gd")
const RunSave = preload("res://scripts/run_save.gd")
const NOODLE = "pool_noodle"
const WORM = "melee"
const UNLOCK_ID = "weapon_pool_noodle"
const TEST_PATH = "user://pool_noodle_check.json"
const SEED_A = 0x1234ABCD
const PAD = 0.9  # the body of a rider, as combat.gd's swing uses it

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	RunSave.test_path = TEST_PATH
	_check_table()
	_check_unlock()
	_ready_to_swing(NOODLE)
	_check_slice()
	_check_melee_reach()
	_check_every_rider_once()
	_check_worm_unchanged()
	_check_deflect()
	_check_animation_and_model()
	_check_run_save()
	_remove_test_file()
	RunSave.test_path = ""
	main.equip_melee(WORM)  # the game keeps running until quit
	_finish()


# a fresh "play" state with the melee weapon `id` in hand and nothing else around
func _ready_to_swing(id: String) -> void:
	main.start_game(false, SEED_A)
	if not main.equip_melee(id):
		_fail("%s cannot be put in the melee slot" % id)
	main.state = "play"
	main.paused = false
	main.melee = true
	main.swing_cd = 0.0
	main.swing_t = 0.0
	main.up["rubber"] = 0
	for r in main.riders.duplicate():
		main.riders.erase(r)
		main.free_rider(r)
	main.phones.clear()


# a point `dist` metres from the player, `deg` degrees to the right of where the player looks (0 = straight ahead)
func _at(dist: float, deg: float) -> Vector3:
	var f = -main.player.global_transform.basis.z
	f.y = 0.0
	f = f.normalized().rotated(Vector3.UP, -deg_to_rad(deg))
	var p = main.player.position + f * dist
	p.y = 0.0
	return p


func _rider_at(pos: Vector3, hp: int) -> Dictionary:
	var r = main.rider_sys.spawn_rider(1, 1)
	r["pos"] = pos
	r["mode"] = "fly"
	r["hidden"] = false
	r["hp"] = hp
	return r


func _clear_riders() -> void:
	for r in main.riders.duplicate():
		main.riders.erase(r)
		main.free_rider(r)


func _swing() -> void:
	main.swing_cd = 0.0
	main.combat_sys.swing()


func _check_table() -> void:
	var tuning = Weapons.load_table()
	if not tuning.has(NOODLE):
		_fail("data/weapons.json has no %s" % NOODLE)
		return
	if not WeaponSlots.is_melee_weapon(NOODLE) or WeaponSlots.is_primary_weapon(NOODLE):
		_fail("the noodle is not (only) a melee weapon")
	if WeaponSlots.melee_label(NOODLE) != "NOODLE":
		_fail("the HUD calls it %s" % WeaponSlots.melee_label(NOODLE))
	if WeaponSlots.display_name("melee", NOODLE) != "POOL NOODLE":
		_fail("the Loadout page calls it %s" % WeaponSlots.display_name("melee", NOODLE))
	if WeaponSlots.display_desc("melee", NOODLE) == "":
		_fail("the Loadout page has no text for the noodle")
	var n = tuning[NOODLE]
	var w = tuning[WORM]
	if int(n["damage"]) != 1:
		_fail("the noodle does %s damage, the roadmap says 1" % str(n["damage"]))
	if float(n.get("sweep_arc", 0.0)) <= 0.0 or float(n.get("sweep_arc", 0.0)) >= 360.0:
		_fail("the noodle has no sensible sweep_arc: %s" % str(n.get("sweep_arc", "<missing>")))
	if float(w.get("sweep_arc", 0.0)) != 0.0:
		_fail("the gummy worm has a sweep_arc and should not")
	for id in tuning:
		if WeaponSlots.is_melee_weapon(id) and id != NOODLE:
			var other = tuning[id]
			var other_reach = float(other["zone_forward"]) + float(other["zone_radius"]) * 0.8
			var reach = float(n["zone_forward"]) + float(n["zone_radius"]) * 0.8
			if reach <= other_reach:
				_fail("the noodle's reach %s is not longer than %s's %s" % [reach, id, other_reach])
			if float(n["deflect_range"]) <= float(other["deflect_range"]):
				_fail("the noodle's deflect range is not the longest: %s has more" % id)


func _check_unlock() -> void:
	var found = {}
	for u in main.UNLOCKS:
		if u["id"] == UNLOCK_ID:
			found = u
	if found.is_empty():
		_fail("data/unlocks.json has no %s" % UNLOCK_ID)
		return
	if found["kind"] != "weapon" or found["target"] != NOODLE or found["planned"]:
		_fail("the unlock entry is %s" % str(found))
	if int(found["tier"]) != 1 or int(found["cost"]) != 60:
		_fail(
			(
				"the noodle is tier %d at %d coins, the roadmap says tier 1 (60)"
				% [int(found["tier"]), int(found["cost"])]
			)
		)
	main.meta.owned.erase(UNLOCK_ID)
	if main.weapon_owned(NOODLE):
		_fail("the noodle is owned before it was bought")
	main.meta.weapon_choice = {}
	var ids = []
	for o in main.loadout_weapon_options("melee"):
		ids.append(o["id"] if typeof(o) == TYPE_DICTIONARY else o)
	if ids.has(NOODLE):
		_fail("the Loadout page lists a noodle that was not bought")
	main.meta.owned[UNLOCK_ID] = true
	if not main.weapon_owned(NOODLE):
		_fail("the noodle is not owned after buying %s" % UNLOCK_ID)
	ids = []
	for o in main.loadout_weapon_options("melee"):
		ids.append(o["id"] if typeof(o) == TYPE_DICTIONARY else o)
	if not ids.has(NOODLE) or ids[0] != WORM:
		_fail("the melee list of the Loadout page after buying is %s" % str(ids))
	main.meta.owned.erase(UNLOCK_ID)


# the slice: inside the arc and the reach is hit, beside, behind and past the reach is not
func _check_slice() -> void:
	var w = main.WEAPONS[NOODLE]
	var half = float(w["sweep_arc"]) * 0.5
	var reach = main.combat_sys.sweep_reach()
	var want = float(w["zone_forward"]) + float(w["zone_radius"]) * 0.8
	if not is_equal_approx(reach, want):
		_fail("the sweep reach is %s, not forward + 0.8 radius = %s" % [str(reach), str(want)])
	# (distance, degrees to the right, should it be hit)
	var cases = [
		[3.0, 0.0, true],
		[3.0, half - 12.0, true],
		[3.0, -(half - 12.0), true],
		[1.2, 0.0, true],
		[reach + PAD - 0.25, 0.0, true],
		[reach + PAD + 0.3, 0.0, false],
		[3.0, 95.0, false],
		[3.0, -95.0, false],
		[3.0, 180.0, false],
		[3.0, half + 40.0, false],
	]
	for c in cases:
		_clear_riders()
		var r = _rider_at(_at(float(c[0]), float(c[1])), 9)
		_swing()
		var hit = int(r["hp"]) < 9
		if hit != bool(c[2]):
			_fail(
				(
					"a rider %.1f m away, %.0f degrees to the right %s hit by the noodle"
					% [float(c[0]), float(c[1]), "was not" if c[2] else "was"]
				)
			)
	_clear_riders()


# each level of Melee Reach moves the edge of the slice out by `reach_per_level` * 0.8
func _check_melee_reach() -> void:
	var w = main.WEAPONS[NOODLE]
	var base = main.combat_sys.sweep_reach()
	main.up["rubber"] = 2
	var longer = main.combat_sys.sweep_reach()
	if not is_equal_approx(longer - base, 2.0 * float(w["reach_per_level"]) * 0.8):
		_fail("two levels of Melee Reach moved the reach by %s" % str(longer - base))
	_clear_riders()
	var just_past = _rider_at(_at(base + PAD + 0.3, 0.0), 9)
	_swing()
	if int(just_past["hp"]) != 8:
		_fail("a rider just past the base reach was not hit with Melee Reach at level 2")
	_clear_riders()
	var past_both = _rider_at(_at(longer + PAD + 0.3, 0.0), 9)
	_swing()
	if int(past_both["hp"]) != 9:
		_fail("a rider past the lengthened reach was hit")
	_clear_riders()
	main.up["rubber"] = 0


# the sweep: every rider in the arc is hit, once per swing, for the weapon's damage
func _check_every_rider_once() -> void:
	_clear_riders()
	var inside = []
	for spot in [[3.0, -45.0], [3.5, -15.0], [3.0, 0.0], [4.0, 20.0], [3.2, 45.0]]:
		inside.append(_rider_at(_at(float(spot[0]), float(spot[1])), 9))
	var behind = _rider_at(_at(3.0, 180.0), 9)
	var beside = _rider_at(_at(3.0, 90.0), 9)
	_swing()
	for r in inside:
		if int(r["hp"]) != 8:
			_fail("a rider inside the arc has hp %d after one swing, not 8" % int(r["hp"]))
	if int(behind["hp"]) != 9 or int(beside["hp"]) != 9:
		_fail("a rider behind or beside the player was hit by the sweep")
	var before = main.swing_cd
	main.combat_sys.swing()  # inside the cooldown: nothing may happen
	if main.swing_cd != before:
		_fail("a second swing went off during the cooldown")
	for r in inside:
		if int(r["hp"]) != 8:
			_fail("a rider was hit again by a swing inside the cooldown (hp %d)" % int(r["hp"]))
	_swing()
	for r in inside:
		if int(r["hp"]) != 7:
			_fail("a second full swing left a rider at hp %d, not 7" % int(r["hp"]))
	_clear_riders()


# the worm keeps its circle: a rider to the side that the noodle's slice takes is outside the worm's circle
func _check_worm_unchanged() -> void:
	var spot = _at(3.0, 55.0)
	_clear_riders()
	var r = _rider_at(spot, 9)
	_swing()
	if int(r["hp"]) != 8:
		_fail("the noodle missed a rider 3 m away at 55 degrees (inside its arc)")
	_ready_to_swing(WORM)
	var spot_w = _at(3.0, 55.0)
	var r2 = _rider_at(spot_w, 9)
	_swing()
	if int(r2["hp"]) != 9:
		_fail(
			"the gummy worm hit a rider 3 m away at 55 degrees: its zone is not a circle ahead any more"
		)
	_clear_riders()
	var ahead = _rider_at(_at(3.2, 0.0), 9)
	_swing()
	var worm_damage = int(main.WEAPONS[WORM]["damage"])
	if int(ahead["hp"]) != 9 - worm_damage:
		_fail("the gummy worm lost its normal hit: a rider ahead lost %d" % (9 - int(ahead["hp"])))
	_clear_riders()
	_ready_to_swing(NOODLE)


# a phone inside the noodle's deflect range goes back, one just outside it does not
func _check_deflect() -> void:
	var reach = float(main.WEAPONS[NOODLE]["deflect_range"])
	if not is_equal_approx(main.combat_sys.deflect_range(), reach):
		_fail(
			"the deflect range is %s, not %s" % [str(main.combat_sys.deflect_range()), str(reach)]
		)
	main.phones.clear()
	var up = Vector3(0, 1.2, 0)
	main.phone_sys.throw_phone(_at(reach + 8.0, 0.0) + up, null)
	main.phone_sys.throw_phone(_at(reach + 8.0, 0.0) + up, null)
	var near = main.phones[0]
	var far = main.phones[1]
	near["pos"] = _at(reach - 0.3, 0.0) + up
	far["pos"] = _at(reach + 0.4, 0.0) + up
	_swing()
	if not near["ret"]:
		_fail("a phone inside the noodle's deflect range was not sent back")
	if far["ret"]:
		_fail("a phone outside the noodle's deflect range was sent back")
	for ph in main.phones.duplicate():
		main.free_phone(ph)
	main.phones.clear()


func _visible_melee_models() -> Array:
	var shown = []
	for key in main.rubbers:
		if main.rubbers[key]["root"].visible:
			shown.append(key)
	return shown


func _check_animation_and_model() -> void:
	var w = main.WEAPONS[NOODLE]
	main.swing_t = 0.0
	main.player_sys.update_gun(0.0)
	if main.rubber != main.rubbers.get("pool_noodle", null):
		_fail("the noodle is in the slot but its first-person model is not the one shown")
	if _visible_melee_models() != ["pool_noodle"]:
		_fail(
			"the visible melee models with the noodle in hand are %s" % str(_visible_melee_models())
		)
	var rb: Node3D = main.rubber["root"]
	_swing()
	main.player_sys.update_gun(0.0)
	if absf(rb.rotation.y) < 0.89 or absf(rb.rotation.y) > 0.91:
		_fail("the noodle is turned %.2f at the start of the swing, not 0.9" % rb.rotation.y)
	main.swing_t = float(w["swing_time"]) * 0.5
	main.player_sys.update_gun(0.0)
	if absf(rb.rotation.y) > 0.02:
		_fail("the noodle is turned %.2f in the middle of its swing, not level" % rb.rotation.y)
	main.swing_t = 0.0
	main.player_sys.update_gun(0.0)
	if absf(rb.rotation.y) > 0.001:
		_fail("the noodle is turned %.2f when its swing is over" % rb.rotation.y)
	# a stiff foam tube: no jelly
	if not main.rubber.get("wobble", []).is_empty():
		_fail("the noodle wobbles like jelly")
	# the worm brings the club back and hides the noodle
	main.equip_melee(WORM)
	main.player_sys.update_gun(0.0)
	if main.rubber != main.rubbers.get(""):
		_fail("the gummy worm is in the slot but the club is not the model shown")
	if _visible_melee_models() != [""]:
		_fail(
			"the visible melee models with the worm in hand are %s" % str(_visible_melee_models())
		)
	# with the primary weapon in hand no melee model shows
	main.melee = false
	main.player_sys.update_gun(0.0)
	if not _visible_melee_models().is_empty():
		_fail("a melee model shows while the gun is in hand: %s" % str(_visible_melee_models()))
	main.melee = true
	main.equip_melee(NOODLE)


func _check_run_save() -> void:
	main.start_game(false, SEED_A)
	main.equip_melee(NOODLE)
	var saved = RunSave.capture(main)
	if saved.get("melee_weapon", "") != NOODLE:
		_fail("the saved run holds melee_weapon %s" % str(saved.get("melee_weapon", "<missing>")))
	var cleaned = RunSave.clean(saved)
	if cleaned.get("melee_weapon", "") != NOODLE:
		_fail(
			(
				"a cleaned saved run holds melee_weapon %s"
				% str(cleaned.get("melee_weapon", "<missing>"))
			)
		)
	main.reset_run()
	if main.melee_weapon == NOODLE:
		_fail("reset_run left the noodle in the slot")
	RunSave.apply(main, cleaned)
	if main.melee_weapon != NOODLE:
		_fail("after loading the saved run the melee slot holds %s" % main.melee_weapon)
	main.player_sys.update_gun(0.0)
	if main.rubber != main.rubbers.get("pool_noodle", null):
		_fail("after loading the saved run the noodle's model is not the one in hand")


func _remove_test_file() -> void:
	for path in [TEST_PATH, TEST_PATH + ".bak", TEST_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish() -> void:
	if problems.is_empty():
		print("pool_noodle_check: the Pool Noodle is in the game and sweeps through the melee slot")
		quit(0)
	else:
		for line in problems.slice(0, 15):
			printerr("pool_noodle_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
