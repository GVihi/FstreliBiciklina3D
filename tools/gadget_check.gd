extends SceneTree
# Checks the gadget use key and the first gadget, the banana peel trap (README Milestone C, "New Gadgets" and "Gadget
# use key"):
#   - data: the unlock (weapon_banana_peel, tier 1, 75 coins, not planned), the entry in data/weapons.json (3 uses a
#     round, a cooldown, a placing distance, a trigger radius, a stun time) and the slot table of scripts/weapon_slots.gd,
#   - buying: 74 coins are refused, 75 buy it, and it appears on the Loadout page's gadget list next to NO GADGET,
#   - an empty slot: the use key does nothing at all (no peel, no sound state, nothing drawn in the HUD),
#   - the use key (G and D-pad up) drops a peel in front of the player, counts the use, starts the cooldown, refuses a
#     use while cooling down and when the uses are gone, does nothing while the game is paused, and a new round gives
#     the uses back and takes the old peels off the ground,
#   - the HUD text names the gadget, the uses left, and the key or the cooldown,
#   - a rider that rides over a peel crashes: it is stunned for stun_time seconds (stops, does not throw, then rides
#     on), the peel is used up, only the first of two riders on one peel is stunned, and a rider that is leaving, hidden
#     or already stunned does not set one off,
#   - a pedestrian on a peel is never affected and leaves the peel where it is,
#   - the same seed, place and yaw give the same result twice (nothing in a gadget is a chance roll).
# It keeps the real meta.json (and its backups) first and puts them back at the end.
# Not checked: how the peel and the HUD line look, the sound, and the numbers (first guesses to tune by playing).
# Run from the project folder:
#   godot --headless --path . --script res://tools/gadget_check.gd
# or with: python tools/run_checks.py gadget
# Exits with status 1 and prints the problems when a check fails.

const WeaponSlots = preload("res://scripts/weapon_slots.gd")
const ID = "banana_peel"
const UNLOCK_ID = "weapon_banana_peel"
const PRICE = 75
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
	_check_data()
	_check_buying()
	_check_empty_slot()
	_check_use_key()
	_check_new_round()
	_check_hud_text()
	_check_crash()
	_check_riders_that_do_not_trigger()
	_check_pedestrian()
	_check_same_seed()
	_restore_user_files()
	_finish()


func _finish() -> void:
	if problems.is_empty():
		print("gadget_check: the banana peel trap and the gadget use key work")
		quit(0)
	else:
		for line in problems.slice(0, 12):
			printerr("gadget_check: " + line)
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


func _unlock(id: String) -> Dictionary:
	for u in main.UNLOCKS:
		if u["id"] == id:
			return u
	return {}


func _fresh(balance: int = 0) -> void:
	main.meta.balance = balance
	main.meta.total_earned = balance
	main.meta.owned = {}
	main.meta.weapon_choice = {}
	main.meta.start_perk = ""


# a run in a round: the gadget in the slot, no riders, no phones, the player at the origin looking along `yaw`
func _play(with_gadget: bool = true, yaw: float = 0.0) -> void:
	main.start_game(false, SEED_A)
	main.equip_gadget(ID if with_gadget else "")
	main.state = "play"
	main.paused = false
	for r in main.riders.duplicate():
		main.riders.erase(r)
		main.free_rider(r)
	main.phones.clear()
	main.civs.clear()
	main.gadget_sys.begin_round()
	main.player.position = Vector3.ZERO
	main.yaw = yaw
	main.player.rotation.y = yaw


func _key(code: int) -> void:
	var ev = InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	main.input_sys.handle_input(ev)


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _rider_at(pos: Vector3) -> Dictionary:
	var r = main.rider_sys.spawn_rider(1, 1)
	r["pos"] = pos
	r["mode"] = "fly"
	r["hidden"] = false
	r["entered"] = true
	r["limit"] = 1.0e9
	r["spd"] = 10.0
	r["tgt"] = 10.0
	r["chg"] = 1.0e9
	return r


func _drop_rider(r: Dictionary) -> void:
	main.riders.erase(r)
	main.free_rider(r)


# ---- data


func _check_data() -> void:
	var u = _unlock(UNLOCK_ID)
	if u.is_empty():
		_fail("data/unlocks.json has no %s" % UNLOCK_ID)
	else:
		if u.get("kind") != "weapon" or u.get("target") != ID:
			_fail("%s is not a weapon unlock for %s" % [UNLOCK_ID, ID])
		if int(u.get("tier", 0)) != 1 or int(u.get("cost", 0)) != PRICE:
			_fail(
				(
					"%s is tier %s, %s coins (want tier 1, %d)"
					% [UNLOCK_ID, u.get("tier"), u.get("cost"), PRICE]
				)
			)
		if u.get("planned", false):
			_fail("%s is still planned" % UNLOCK_ID)
	if not WeaponSlots.is_gadget(ID):
		_fail("%s is not in the gadget slot table" % ID)
		return
	var st = main.WEAPONS.get(ID, {})
	if int(st.get("uses", 0)) != 3:
		_fail("the banana peel has %s uses a round, not 3" % st.get("uses"))
	for key in ["cooldown", "place_dist", "trigger_radius", "stun_time"]:
		if float(st.get(key, 0.0)) <= 0.0:
			_fail("banana_peel.%s is %s, it must be above 0" % [key, st.get(key)])
	if WeaponSlots.gadget_label(ID) != "BANANA":
		_fail("the HUD name is %s" % WeaponSlots.gadget_label(ID))


func _check_buying() -> void:
	_fresh(PRICE - 1)
	var u = _unlock(UNLOCK_ID)
	if main.meta.buy(u) != "locked" or main.meta.balance != PRICE - 1 or main.meta.owns(UNLOCK_ID):
		_fail("buying with %d coins was not refused cleanly" % (PRICE - 1))
	main.meta.balance = PRICE
	if main.meta.buy(u) != "bought" or main.meta.balance != 0:
		_fail("buying with exactly %d coins failed (balance %d)" % [PRICE, main.meta.balance])
	var ids = []
	for o in main.loadout_weapon_options("gadget"):
		ids.append(o["id"])
	if ids != ["", ID]:
		_fail("the Loadout page's gadget list is %s, not [NO GADGET, %s]" % [str(ids), ID])
	main.meta.weapon_choice["gadget"] = ID
	main.start_game(false, SEED_A)
	if main.gadget != ID:
		_fail("a run with the gadget chosen started with '%s' in the slot" % main.gadget)
	_fresh(0)
	main.start_game(false, SEED_A)
	if main.gadget != "":
		_fail("a new player's run started with the gadget '%s'" % main.gadget)


# ---- the use key


func _check_empty_slot() -> void:
	_play(false)
	var gs = main.gadget_sys
	if gs.use() or not gs.peels.is_empty():
		_fail("the use key with an empty slot did something")
	_key(KEY_G)
	main.input_sys.play_pad_button(JOY_BUTTON_DPAD_UP)
	if not gs.peels.is_empty() or gs.cool != 0.0:
		_fail("G or D-pad up with an empty slot did something")
	if gs.hud_text() != "":
		_fail("the HUD would show '%s' for an empty slot" % gs.hud_text())


func _check_use_key() -> void:
	_play(true, 0.7)
	var gs = main.gadget_sys
	var st = main.gadget_stats()
	if gs.uses_left != 3:
		_fail("a round starts with %d uses, not 3" % gs.uses_left)
	_key(KEY_G)
	if gs.peels.size() != 1 or gs.uses_left != 2:
		_fail(
			(
				"G did not drop one peel and count one use (peels %d, uses left %d)"
				% [gs.peels.size(), gs.uses_left]
			)
		)
	if gs.cool <= 0.0:
		_fail("the cooldown did not start")
	else:
		var fwd = -main.player.global_transform.basis.z
		fwd.y = 0.0
		var want = _flat(fwd.normalized() * float(st["place_dist"]))
		if gs.peels.size() == 1 and _flat(gs.peels[0]["pos"]).distance_to(want) > 0.05:
			_fail(
				(
					"the peel is at %s, not %s metres ahead (%s)"
					% [str(gs.peels[0]["pos"]), st["place_dist"], str(want)]
				)
			)
	_key(KEY_G)
	if gs.peels.size() != 1 or gs.uses_left != 2:
		_fail("a second press during the cooldown used the gadget")
	gs.update(float(st["cooldown"]) + 0.01)
	if gs.cool != 0.0 or not gs.ready():
		_fail("the cooldown did not run out")
	main.input_sys.play_pad_button(JOY_BUTTON_DPAD_UP)  # headless cannot capture the mouse, which on_pad_button asks for
	if gs.peels.size() != 2 or gs.uses_left != 1:
		_fail(
			(
				"D-pad up did not use the gadget (peels %d, uses left %d)"
				% [gs.peels.size(), gs.uses_left]
			)
		)
	main.paused = true
	gs.update(5.0)
	_key(KEY_G)
	main.paused = false
	if gs.peels.size() != 2 or gs.uses_left != 1:
		_fail("the gadget was used while the game was paused")
	_key(KEY_G)
	gs.update(5.0)
	if gs.peels.size() != 3 or gs.uses_left != 0:
		_fail(
			"the third use did not work (peels %d, uses left %d)" % [gs.peels.size(), gs.uses_left]
		)
	_key(KEY_G)
	if gs.peels.size() != 3 or gs.ready():
		_fail("a fourth use was allowed with no uses left")
	main.state = "map"
	gs.uses_left = 1
	gs.cool = 0.0
	_key(KEY_G)
	main.state = "play"
	if gs.peels.size() != 3:
		_fail("the gadget was used outside a round")


func _check_new_round() -> void:
	_play(true)
	var gs = main.gadget_sys
	gs.use()
	var node = gs.peels[0]["node"]
	main.start_round()
	main.paused = false
	if not gs.peels.is_empty() or not is_instance_valid(node) or not node.is_queued_for_deletion():
		_fail("a new round left the old peel on the ground")
	if gs.uses_left != 3 or gs.cool != 0.0:
		_fail(
			(
				"a new round did not give the uses back (uses %d, cooldown %s)"
				% [gs.uses_left, gs.cool]
			)
		)


func _check_hud_text() -> void:
	_play(true)
	var gs = main.gadget_sys
	var t = gs.hud_text()
	if not t.contains("BANANA") or not t.contains("3/3") or not t.contains("[G]"):
		_fail("the ready HUD text is '%s'" % t)
	gs.use()
	t = gs.hud_text()
	if not t.contains("2/3") or t.contains("[G]") or not t.contains("s"):
		_fail("the HUD text while cooling down is '%s'" % t)
	gs.uses_left = 0
	gs.cool = 0.0
	if not gs.hud_text().contains("EMPTY"):
		_fail("the HUD text with no uses left is '%s'" % gs.hud_text())


# ---- the trap


func _check_crash() -> void:
	_play(true)
	var gs = main.gadget_sys
	var st = main.gadget_stats()
	gs.use()
	var spot: Vector3 = gs.peels[0]["pos"]
	var far = _rider_at(spot + Vector3(30.0, 0.0, 0.0))
	gs.update_peels()
	if far.get("stun_t", 0.0) != 0.0 or gs.peels.size() != 1:
		_fail("a rider 30 m away set the peel off")
	_drop_rider(far)
	var a = _rider_at(spot + Vector3(0.4, 0.0, 0.0))
	var b = _rider_at(spot - Vector3(0.4, 0.0, 0.0))
	gs.update_peels()
	var stunned = int(a.get("stun_t", 0.0) > 0.0) + int(b.get("stun_t", 0.0) > 0.0)
	if stunned != 1:
		_fail("%d of two riders on one peel were stunned, want exactly the first" % stunned)
	if not gs.peels.is_empty():
		_fail("the peel was not used up")
	var r = a if a.get("stun_t", 0.0) > 0.0 else b
	var other = b if r == a else a
	if absf(r["stun_t"] - float(st["stun_time"])) > 0.001:
		_fail("the stun lasts %s s, not %s" % [r["stun_t"], st["stun_time"]])
	# a rider that was winding up a throw drops it
	r["wind_t"] = 0.4
	var start_pos = r["pos"]
	var t = 0.0
	while t < 1.0:
		main.rider_sys.update_rider(r, 0.05)
		t += 0.05
	if float(r["spd"]) > 0.01:
		_fail("a stunned rider still rides at %s m/s after a second" % r["spd"])
	if _flat(r["pos"]).distance_to(_flat(start_pos)) > 3.0:
		_fail("a stunned rider slid %s m" % _flat(r["pos"]).distance_to(_flat(start_pos)))
	if r["wind_t"] != 0.0 or not main.phones.is_empty():
		_fail("a stunned rider kept winding up or threw a phone")
	while t < float(st["stun_time"]) + 0.2:
		main.rider_sys.update_rider(r, 0.05)
		t += 0.05
	if r["stun_t"] != 0.0:
		_fail("the stun did not end (%s s left)" % r["stun_t"])
	for i in range(20):
		main.rider_sys.update_rider(r, 0.05)
	if float(r["spd"]) < 1.0:
		_fail("a rider did not ride on after the stun (%s m/s)" % r["spd"])
	_drop_rider(r)
	_drop_rider(other)


func _check_riders_that_do_not_trigger() -> void:
	_play(true)
	var gs = main.gadget_sys
	gs.use()
	var spot: Vector3 = gs.peels[0]["pos"]
	var leaving = _rider_at(spot)
	leaving["mode"] = "away"
	var hidden = _rider_at(spot)
	hidden["hidden"] = true
	var down = _rider_at(spot)
	down["stun_t"] = 2.0
	gs.update_peels()
	if gs.peels.size() != 1:
		_fail("a leaving, hidden or already stunned rider used the peel up")
	if (
		leaving.get("stun_t", 0.0) != 0.0
		or hidden.get("stun_t", 0.0) != 0.0
		or down["stun_t"] != 2.0
	):
		_fail("a rider that should not trigger the peel was changed")
	for r in [leaving, hidden, down]:
		_drop_rider(r)


func _check_pedestrian() -> void:
	_play(true)
	var gs = main.gadget_sys
	gs.use()
	var spot: Vector3 = gs.peels[0]["pos"]
	main.civ_sys.spawn_civ()
	if main.civs.is_empty():
		_fail("could not make a pedestrian to test with")
		return
	var c = main.civs[0]
	c["pos"] = spot
	var before = c.duplicate()
	gs.update_peels()
	if gs.peels.size() != 1:
		_fail("a pedestrian on the peel set it off")
	if c["pos"] != before["pos"] or main.civs.size() != 1:
		_fail("a pedestrian on the peel was changed")
	main.civs.clear()


# the same seed, place and yaw: the same peel spot and the same stun, twice
func _check_same_seed() -> void:
	var runs = []
	for i in range(2):
		_play(true, 1.9)
		var gs = main.gadget_sys
		gs.use()
		var spot: Vector3 = gs.peels[0]["pos"]
		var r = _rider_at(spot + Vector3(0.3, 0.0, 0.2))
		gs.update_peels()
		runs.append([spot, r.get("stun_t", -1.0), gs.peels.size(), gs.uses_left, gs.cool])
		_drop_rider(r)
	if runs[0] != runs[1]:
		_fail("two runs of the same seed gave %s and %s" % [str(runs[0]), str(runs[1])])
