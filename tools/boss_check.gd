extends SceneTree
# Check for the boss world position (README Milestone K, Foundation). A boss is where its "wp" says,
# turned by its "yaw", and the rest of the game reads those (boss_world, the hit boxes, the weak-spot
# marker, the aim assist); the street "x" and "z" are gone from the boss. This check spawns each kind of
# boss, lets it act with the player standing in the middle and then walking about, and fails if the
# boss leaves the ground it may walk on, if "yaw" differs from what the arena gives at "wp", if the model
# is not where "wp" says, or if the street keys come back.
#
# Run from the project folder:
#   godot --headless --path . --script res://tools/boss_check.gd
# Exits with status 1 and prints the first problems when something is wrong.

const STEPS = 600
const DT = 1.0 / 60.0

var bad: Array = []


func _init() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	main.start_game()
	main.state = "play"
	var checked = 0
	for round_i in range(main.BOSS_KINDS.size()):
		main.round_n = 2 + round_i
		main.boss_count = round_i
		main.boss_sys.spawn_boss()
		for step in range(STEPS):
			# the player walks a slow circle so the boss has something to chase
			var a = float(step) * 0.01
			main.player.position = Vector3(cos(a) * 9.0, 0.0, sin(a) * 9.0)
			main.boss_sys.update_bosses(DT)
			for b in main.bosses:
				_compare(main, b, "round %d step %d: " % [main.round_n, step])
				checked += 1
		for b in main.bosses.duplicate():
			main.free_boss(b)
		main.bosses.clear()
	if checked == 0:
		bad.append("no boss was ever checked")
	if bad.is_empty():
		print("boss_check: boss position and yaw agree with wp for %d boss steps" % checked)
		quit(0)
	else:
		for line in bad.slice(0, 10):
			printerr("boss_check: " + line)
		quit(1)


func _compare(main, b: Dictionary, tag: String) -> void:
	var wp: Vector3 = b["wp"]
	if b.has("x") or b.has("z"):
		bad.append(tag + "the boss has street keys again")
	if absf(wp.y) > 0.0001:
		bad.append(tag + "wp is off the ground: %s" % wp)
	if main.clamp_walk(wp, "boss").distance_to(wp) > 0.001:
		bad.append(tag + "wp %s is outside the ground a boss may walk on" % wp)
	var want_yaw = main.arena.yaw(main.arena.to_track(wp).x)
	if absf(b["yaw"] - want_yaw) > 0.0001:
		bad.append(tag + "yaw %f, the arena gives %f at wp" % [b["yaw"], want_yaw])
	var model_pos: Vector3 = b["model"]["root"].position
	if Vector2(model_pos.x - wp.x, model_pos.z - wp.z).length() > 0.2:
		bad.append(tag + "model is at %s, wp is %s" % [model_pos, wp])
	if main.boss_world(b, 1.5).distance_to(wp + Vector3(0.0, 1.5, 0.0)) > 0.0001:
		bad.append(tag + "boss_world does not follow wp")
