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
	_check_no_top_up()
	_check_manual_reload()
	_check_empty_reloads_by_itself()
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


func _reset_gun(count: int) -> void:
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
