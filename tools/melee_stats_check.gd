extends SceneTree
# Checks that the melee code reads the weapon in the melee slot and not the gummy worm (README Milestone C, New Melee
# Weapons, "Audit the melee code ... make it read melee_stats() everywhere"). Two made-up melee weapons with numbers
# far from the worm's (a fast, long-reaching one and a slow, heavy one) are put in the slot and the check follows
# what the code does with them:
#   - a swing sets the cooldown and the swing time from the weapon,
#   - the swing animation of the viewmodel starts at its full angle, is level in the middle of the swing and ends at
#     rest, however long the swing is (it used to be fixed to the worm's 0.26 s),
#   - the follow-through at the end of a swing, which sends nothing back, keeps the same share of the swing,
#   - a rider in front is hit for the weapon's own damage, inside its own hit zone and not outside it, and Melee Reach
#     (`reach_per_level`) widens the zone and the deflect range,
#   - a thrown phone inside the deflect range goes back and one outside it does not,
#   - the HUD name, and that the "no dart fired" challenge is not broken by swinging.
# The made-up weapons are put in the tables of the running game and taken out again; no file is written.
# Not checked: how a swing looks (the viewmodel is still one worm for every melee weapon) or feels.
# Run from the project folder:
#   godot --headless --path . --script res://tools/melee_stats_check.gd
# or with: python tools/run_checks.py melee_stats
# Exits with status 1 and prints the problems when a check fails.

const WeaponSlots = preload("res://scripts/weapon_slots.gd")
const SEED_A = 0x1234ABCD
const FAST = "check_fast_stick"
const SLOW = "check_slow_hammer"
const WORM = "melee"

var problems = []
var main
var worm_numbers = {}


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	worm_numbers = main.WEAPONS[WORM].duplicate()
	main.WEAPONS[FAST] = {
		"cooldown": 0.15,
		"swing_time": 0.15,
		"zone_forward": 3.2,
		"zone_radius": 2.0,
		"reach_per_level": 0.5,
		"deflect_range": 4.5,
		"damage": 1
	}
	main.WEAPONS[SLOW] = {
		"cooldown": 0.9,
		"swing_time": 0.6,
		"zone_forward": 1.8,
		"zone_radius": 1.0,
		"reach_per_level": 0.2,
		"deflect_range": 1.8,
		"damage": 3
	}
	WeaponSlots.MELEE_WEAPONS[FAST] = "SWATTER"
	WeaponSlots.MELEE_WEAPONS[SLOW] = "HAMMER"
	for id in [WORM, FAST, SLOW]:
		await _check_weapon(id)
	_check_challenge_rule()
	main.equip_melee(WORM)  # the game keeps running until quit: it must not point at a weapon that is gone
	for id in [FAST, SLOW]:
		main.WEAPONS.erase(id)
		WeaponSlots.MELEE_WEAPONS.erase(id)
	_finish()


# a fresh round-less "play" state with the melee weapon `id` in hand and nothing else around
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


func _check_weapon(id: String) -> void:
	var w = main.WEAPONS[id]
	_ready_to_swing(id)
	if WeaponSlots.melee_label(id) != str(WeaponSlots.MELEE_WEAPONS[id]):
		_fail("%s: the HUD name is %s" % [id, WeaponSlots.melee_label(id)])

	# the swing takes its timing from the weapon
	main.combat_sys.swing()
	if not is_equal_approx(main.swing_cd, float(w["cooldown"])):
		_fail(
			(
				"%s: the cooldown after a swing is %s, not %s"
				% [id, str(main.swing_cd), str(w["cooldown"])]
			)
		)
	if not is_equal_approx(main.swing_t, float(w["swing_time"])):
		_fail("%s: the swing lasts %s, not %s" % [id, str(main.swing_t), str(w["swing_time"])])
	var before = main.swing_cd
	main.combat_sys.swing()
	if main.swing_cd != before:
		_fail("%s: a second swing went off during the cooldown" % id)

	# the animation: full angle at the start, level in the middle, at rest at the end
	var rb: Node3D = main.rubber["root"]
	main.player_sys.update_gun(0.0)
	if absf(rb.rotation.y) < 0.89 or absf(rb.rotation.y) > 0.91:
		_fail(
			(
				"%s: the viewmodel is turned %.2f at the start of the swing, not 0.9"
				% [id, rb.rotation.y]
			)
		)
	main.swing_t = float(w["swing_time"]) * 0.5
	main.player_sys.update_gun(0.0)
	if absf(rb.rotation.y) > 0.02:
		_fail(
			(
				"%s: the viewmodel is turned %.2f in the middle of the swing, not level"
				% [id, rb.rotation.y]
			)
		)
	main.swing_t = 0.0
	main.player_sys.update_gun(0.0)
	if absf(rb.rotation.y) > 0.001:
		_fail("%s: the viewmodel is turned %.2f when the swing is over" % [id, rb.rotation.y])

	# the follow-through is a share of the swing
	main.swing_t = float(w["swing_time"])
	if not main.combat_sys.deflecting():
		_fail("%s: a swing that has just started does not send phones back" % id)
	main.swing_t = float(w["swing_time"]) * main.combat_sys.DEFLECT_FOLLOW_THROUGH * 0.9
	if main.combat_sys.deflecting():
		_fail("%s: the follow-through at the end of the swing still sends phones back" % id)
	main.swing_t = float(w["swing_time"]) * main.combat_sys.DEFLECT_FOLLOW_THROUGH * 1.1
	if not main.combat_sys.deflecting():
		_fail("%s: the swing stops sending phones back too early" % id)
	main.swing_t = 0.0

	_check_zone_and_damage(id, w)
	_check_deflect(id, w)
	main.up["rubber"] = 0


func _ahead(offset: float) -> Vector3:
	var f = -main.player.global_transform.basis.z
	f.y = 0.0
	f = f.normalized()
	var p = main.player.position + f * offset
	p.y = 0.0
	return p


func _rider_at(offset: float, hp: int) -> Dictionary:
	var r = main.rider_sys.spawn_rider(1, 1)
	r["pos"] = _ahead(offset)
	r["mode"] = "fly"
	r["hidden"] = false
	r["hp"] = hp
	return r


func _clear_rider(r: Dictionary) -> void:
	main.riders.erase(r)
	main.free_rider(r)


# the hit zone is `zone_radius` wide (times 0.8, plus the rider's own 0.9) in front by `zone_forward`; each level of
# Melee Reach adds `reach_per_level`
func _check_zone_and_damage(id: String, w: Dictionary) -> void:
	for level in [0, 2]:
		main.up["rubber"] = level
		var radius = float(w["zone_radius"]) + level * float(w["reach_per_level"])
		var edge = radius * 0.8 + 0.9
		var forward = float(w["zone_forward"])
		var zone = main.combat_sys.swing_zone()
		if not is_equal_approx(float(zone["r"]), radius):
			_fail(
				(
					"%s, reach level %d: the zone radius is %s, not %s"
					% [id, level, str(zone["r"]), str(radius)]
				)
			)
		var inside = _rider_at(forward + edge - 0.25, 9)
		var outside = _rider_at(forward + edge + 0.35, 9)
		main.swing_cd = 0.0
		main.combat_sys.swing()
		if int(inside["hp"]) != 9 - int(w["damage"]):
			_fail(
				(
					"%s, reach level %d: a rider inside the zone lost %d, not %d"
					% [id, level, 9 - int(inside["hp"]), int(w["damage"])]
				)
			)
		if int(outside["hp"]) != 9:
			_fail("%s, reach level %d: a rider outside the zone was hit" % [id, level])
		_clear_rider(inside)
		_clear_rider(outside)
	main.up["rubber"] = 0


# a phone inside the deflect range (plus Melee Reach) goes back, one just outside it does not
func _check_deflect(id: String, w: Dictionary) -> void:
	for level in [0, 2]:
		main.up["rubber"] = level
		var reach = float(w["deflect_range"]) + level * float(w["reach_per_level"])
		if not is_equal_approx(main.combat_sys.deflect_range(), reach):
			_fail(
				(
					"%s, reach level %d: the deflect range is %s, not %s"
					% [id, level, str(main.combat_sys.deflect_range()), str(reach)]
				)
			)
		main.phones.clear()
		main.phone_sys.throw_phone(_ahead(reach + 8.0) + Vector3(0, 1.2, 0), null)
		main.phone_sys.throw_phone(_ahead(reach + 8.0) + Vector3(0, 1.2, 0), null)
		var near = main.phones[0]
		var far = main.phones[1]
		near["pos"] = _ahead(reach - 0.3) + Vector3(0, 1.2, 0)
		far["pos"] = _ahead(reach + 0.4) + Vector3(0, 1.2, 0)
		main.swing_cd = 0.0
		main.combat_sys.swing()
		if not near["ret"]:
			_fail(
				(
					"%s, reach level %d: a phone inside the deflect range was not sent back"
					% [id, level]
				)
			)
		if far["ret"]:
			_fail(
				"%s, reach level %d: a phone outside the deflect range was sent back" % [id, level]
			)
		for ph in main.phones.duplicate():
			main.free_phone(ph)
		main.phones.clear()
	main.up["rubber"] = 0


# swinging does not count as firing a dart, whichever melee weapon it is
func _check_challenge_rule() -> void:
	for id in [WORM, FAST, SLOW]:
		_ready_to_swing(id)
		main.challenges.begin_round()
		main.combat_sys.swing()
		if main.challenges.gun_used:
			_fail("%s: a swing counted as a dart fired (the no-gun challenge)" % id)


func _finish() -> void:
	main.WEAPONS[WORM] = worm_numbers
	if problems.is_empty():
		print("melee_stats_check: the melee code follows the weapon in the melee slot")
		quit(0)
	else:
		for line in problems.slice(0, 15):
			printerr("melee_stats_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
