extends SceneTree
# Checks the reload rules of the dart gun (README Milestone J, manual reload):
#   - an empty magazine reloads by itself and fills up again,
#   - a part-empty magazine is NOT topped up between waves (only R / gamepad X reloads it),
#   - a manual reload (`combat_sys.start_load`, what R and gamepad X call) starts.
# Run from the project folder:
#   godot --headless --path . --script res://tools/reload_check.gd
# or with tools\run_reload_check.bat on Windows.
# Exits with status 1 and prints the problems when a check fails.

const SEED = 0x1234ABCD
const DT = 1.0 / 60.0

var problems = []
var main
var events = {"started": 0, "shell": 0, "finished": 0, "interrupted": 0}


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_start_round()
	await process_frame
	if main.state != "play":
		_fail("could not start a round (state %s)" % main.state)
		_finish()
		return
	if main.MAXSHELLS < 2:
		_fail("the magazine holds %d darts, the check needs at least 2" % main.MAXSHELLS)
		_finish()
		return
	main.combat_sys.reload_started.connect(func(): events["started"] += 1)
	main.combat_sys.reload_shell_loaded.connect(func(): events["shell"] += 1)
	main.combat_sys.reload_finished.connect(func(): events["finished"] += 1)
	main.combat_sys.reload_interrupted.connect(func(): events["interrupted"] += 1)
	_check_no_top_up()
	_check_manual_reload()
	_check_empty_reloads_by_itself()
	_check_no_shooting_while_loading()
	_check_rapid_fire_still_shoots()
	_check_dash_interrupts()
	_check_melee_switch_interrupts()
	_check_empty_gun_is_not_interrupted()
	_check_hooks_full_reload()
	_check_hooks_interrupted_reload()
	_check_reload_display()
	_finish()


# no rider or boss on screen and the next wave still waiting: this is where the gun used to refill itself
func _check_no_top_up() -> void:
	_reset_gun(1)
	main.wait = 1.7
	for f in range(30):
		if main.riders.size() > 0 or main.bosses.size() > 0:
			break  # a wave came out early, the situation this checks is over
		main._process(DT)
	if main.loading:
		_fail("a gun with 1 dart started loading by itself between waves")
	if main.shells != 1:
		_fail("a gun with 1 dart changed to %d darts without a reload" % main.shells)


# R and gamepad X call start_load
func _check_manual_reload() -> void:
	_reset_gun(1)
	main.combat_sys.start_load()
	if not main.loading:
		_fail("a manual reload (start_load) did not start with 1 dart in the magazine")
	_reset_gun(main.MAXSHELLS)
	main.combat_sys.start_load()
	if main.loading:
		_fail("a manual reload started on a full magazine")


# an empty magazine starts loading without any input and fills up again
func _check_empty_reloads_by_itself() -> void:
	_reset_gun(0)
	main._process(DT)
	if not main.loading:
		_fail("an empty magazine did not start loading by itself")
	var frames = 0
	while main.shells < main.MAXSHELLS and frames < 60 * 20:
		main._process(DT)
		frames += 1
	if main.shells < main.MAXSHELLS:
		_fail("an empty magazine had %d of %d darts after 20 s" % [main.shells, main.MAXSHELLS])
	if main.loading and main.shells >= main.MAXSHELLS:
		_fail("the gun kept loading with a full magazine")


# a gun that is loading does not fire: no dart is used, none flies, and the reload goes on
func _check_no_shooting_while_loading() -> void:
	_reset_gun(1)
	main.combat_sys.start_load()
	var darts_before = main.darts.size()
	main.combat_sys.fire()
	if main.shells != 1:
		_fail("a gun that was loading fired: %d darts left instead of 1" % main.shells)
	if main.darts.size() != darts_before:
		_fail("a gun that was loading made a dart fly")
	if not main.loading:
		_fail("trying to shoot stopped the reload")
	# and once the reload is over it fires again
	_reset_gun(2)
	main.combat_sys.fire()
	if main.shells != 1:
		_fail("a gun that was not loading did not fire: %d darts left instead of 1" % main.shells)


# rapid fire does not use the magazine, so loading does not hold it back (firing stops the reload, as before)
func _check_rapid_fire_still_shoots() -> void:
	_reset_gun(1)
	main.combat_sys.start_load()
	main.buffs["rapid"] = 5.0
	main.combat_sys.fire()
	if main.pump_t <= 0.0:
		_fail("rapid fire did not shoot while the gun was loading")
	if main.shells != 1:
		_fail("rapid fire used a dart from the magazine (%d left of 1)" % main.shells)
	main.buffs["rapid"] = 0.0


# a dash stops a reload, and the darts that are already in stay in
func _check_dash_interrupts() -> void:
	_reset_gun(2)
	main.combat_sys.start_load()
	main.dash_cd = 0.0
	main.dash_t = 0.0
	main.player_sys.try_dash()
	if main.dash_t <= 0.0:
		_fail("the check could not start a dash")
		return
	if main.loading:
		_fail("a dash did not stop the reload")
	if main.shells != 2:
		_fail("a dash changed the darts in the magazine: %d instead of 2" % main.shells)
	main.dash_t = 0.0
	main.dash_cd = 0.0


# switching to the melee weapon stops a reload; switching back to the gun does not start one
func _check_melee_switch_interrupts() -> void:
	_reset_gun(2)
	main.combat_sys.start_load()
	main.input_sys.toggle_weapon(true)
	if not main.melee:
		_fail("the check could not switch to the melee weapon")
	if main.loading:
		_fail("switching to melee did not stop the reload")
	main.input_sys.toggle_weapon(false)
	if main.loading:
		_fail("switching back to the gun started a reload")
	main.melee = false


# an empty gun has nothing to shoot, so a dash or a weapon switch must not take its reload away
func _check_empty_gun_is_not_interrupted() -> void:
	_reset_gun(0)
	main.combat_sys.start_load()
	main.dash_cd = 0.0
	main.dash_t = 0.0
	main.player_sys.try_dash()
	if not main.loading:
		_fail("a dash stopped the reload of an empty gun")
	main.input_sys.toggle_weapon(true)
	if not main.loading:
		_fail("switching to melee stopped the reload of an empty gun")
	main.melee = false
	main.dash_t = 0.0
	main.dash_cd = 0.0


# a whole reload gives one start, one event per dart that went in and one finish, and no interrupt
func _check_hooks_full_reload() -> void:
	_reset_gun(0)
	_reset_events()
	var frames = 0
	while main.shells < main.MAXSHELLS and frames < 60 * 20:
		main._process(DT)
		frames += 1
	if events["started"] != 1:
		_fail("a full reload gave %d reload_started events instead of 1" % events["started"])
	if events["shell"] != main.MAXSHELLS:
		_fail(
			(
				"a full reload gave %d reload_shell_loaded events instead of %d"
				% [events["shell"], main.MAXSHELLS]
			)
		)
	if events["finished"] != 1:
		_fail("a full reload gave %d reload_finished events instead of 1" % events["finished"])
	if events["interrupted"] != 0:
		_fail("a full reload gave %d reload_interrupted events" % events["interrupted"])
	# a full magazine has nothing to reload: no events at all
	_reset_events()
	main.combat_sys.start_load()
	if events["started"] != 0:
		_fail("a reload on a full magazine gave a reload_started event")


# a reload stopped by a dash gives a start and an interrupt, and no finish
func _check_hooks_interrupted_reload() -> void:
	_reset_gun(2)
	_reset_events()
	main.combat_sys.start_load()
	main.dash_cd = 0.0
	main.dash_t = 0.0
	main.player_sys.try_dash()
	if events["started"] != 1 or events["interrupted"] != 1 or events["finished"] != 0:
		_fail(
			(
				"an interrupted reload gave events %s, expected one start, one interrupt and no finish"
				% str(events)
			)
		)
	main.dash_t = 0.0
	main.dash_cd = 0.0


# the display: `is_reloading` is true while loading and false under rapid fire, and the number on the gun blinks
# while loading but holds its colour when the gun is not loading (the HUD uses `is_reloading` and `reload_pulse`)
func _check_reload_display() -> void:
	_reset_gun(4)
	if main.combat_sys.is_reloading():
		_fail("is_reloading is true for a gun that is not loading")
	main.combat_sys.start_load()
	if not main.combat_sys.is_reloading():
		_fail("is_reloading is false for a gun that is loading")
	main.buffs["rapid"] = 5.0
	if main.combat_sys.is_reloading():
		_fail("is_reloading is true under rapid fire, which does not use the magazine")
	main.buffs["rapid"] = 0.0
	var pulse_low = 1.0
	var pulse_high = 0.0
	for i in range(60):
		main.time = float(i) / 60.0
		var p = main.combat_sys.reload_pulse()
		pulse_low = minf(pulse_low, p)
		pulse_high = maxf(pulse_high, p)
	if pulse_low < 0.0 or pulse_high > 1.0 or pulse_high - pulse_low < 0.5:
		_fail(
			(
				"the reload pulse does not blink between 0 and 1 (%.2f to %.2f)"
				% [pulse_low, pulse_high]
			)
		)
	var label = main.gun.get("ammo")
	if label == null:
		return  # no ammo label on the gun (the gun model is switched off), nothing more to check
	var base = Color(0.22, 0.91, 1.0)
	_reset_gun(4)
	var still_ok = true
	for i in range(20):
		main._process(DT)
		still_ok = still_ok and label.modulate.is_equal_approx(base)
	if not still_ok:
		_fail("the number on the gun changed colour while the gun was not loading")
	_reset_gun(4)
	main.combat_sys.start_load()
	var lowest = 1.0
	var highest = 0.0
	for i in range(25):  # shorter than the first dart takes, so the number stays at 4 and the colour stays cyan based
		main._process(DT)
		lowest = minf(lowest, label.modulate.r)
		highest = maxf(highest, label.modulate.r)
	if highest - lowest < 0.1:
		_fail(
			(
				"the number on the gun did not blink while the gun was loading (red %.2f to %.2f)"
				% [lowest, highest]
			)
		)


func _reset_events() -> void:
	for k in events.keys():
		events[k] = 0


func _reset_gun(count: int) -> void:
	main.melee = false
	main.shells = count
	main.loading = false
	main.load_t = 0.0
	main.pump_t = 0.0
	main.buffs["rapid"] = 0.0
	main.free_shots = 0


func _start_round() -> void:
	main.start_game(false, SEED)
	if main.state == "map":
		main.pick_node(0)
	# headless Godot cannot capture the mouse, so the test hook plays the round
	main.force_captured = true


func _finish() -> void:
	if problems.is_empty():
		print("reload_check: an empty gun reloads by itself, a part-empty one only by hand")
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("reload_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
