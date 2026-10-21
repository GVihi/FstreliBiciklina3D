extends SceneTree
# Check for the pedestrian and cheerleader world positions (README Milestone K, Foundation). A
# pedestrian carries "pos", "yaw" and "hidden" (world space) and the rest of the game reads those instead
# of working them out from the street position; a cheerleader carries a fixed "pos". This check walks
# pedestrians across the whole street, startles and sends some fleeing, and fails if the values ever
# differ from what the street position gives or the model is not where "pos" says. It also checks that
# the cheerleaders stand where their "pos" says and have lost their street "x".
#
# Run from the project folder:
#   godot --headless --path . --script res://tools/pedestrian_check.gd
# Exits with status 1 and prints the first problems when something is wrong.

const STEPS = 900
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
	var seen_hidden = false
	var seen_visible = false
	for k in range(6):
		main.civ_sys.spawn_civ()
	for step in range(STEPS):
		main.civ_t = 99.0  # no new random pedestrians: only the ones spawned above
		main.civ_sys.update_civs(DT)
		if step == 200 and main.civs.size() > 0:
			main.civ_sys.hit_civ(main.civs[0])  # startled, then flees
		for c in main.civs:
			_compare(main, c, "step %d civ: " % step)
			checked += 1
			seen_hidden = seen_hidden or c["hidden"]
			seen_visible = seen_visible or not c["hidden"]
		main.hearts = 5  # a hit costs a life, so keep the run alive
		main.state = "play"
	if checked == 0:
		bad.append("no pedestrian was ever checked")
	if not seen_visible:
		bad.append("no pedestrian was ever visible (check is not covering it)")
	for m in main.cheerleaders:
		if m.has("x"):
			bad.append("a cheerleader has the street key x again")
		if not m.has("pos"):
			bad.append("a cheerleader has no pos")
			continue
		var model_pos: Vector3 = m["root"].position
		if Vector2(model_pos.x - m["pos"].x, model_pos.z - m["pos"].z).length() > 0.0001:
			bad.append("cheerleader model is at %s, pos is %s" % [model_pos, m["pos"]])
		if model_pos.y < -0.0001:
			bad.append("cheerleader is below the ground: %s" % model_pos)
	if bad.is_empty():
		print(
			(
				"pedestrian_check: pos, yaw and hidden agree with the street position for %d steps"
				% checked
			)
		)
		quit(0)
	else:
		for line in bad.slice(0, 10):
			printerr("pedestrian_check: " + line)
		quit(1)


func _compare(main, c: Dictionary, tag: String) -> void:
	var want_pos = main.arena.tw(c["x"], c["z"], 0.0)
	var want_yaw = (0.0 if c["dir"] > 0 else PI) + main.arena.yaw(c["x"])
	var want_hidden = main.arena.hidden(c["x"])
	if c["pos"].distance_to(want_pos) > 0.0001:
		bad.append(tag + "pos %s, street position gives %s" % [c["pos"], want_pos])
	if absf(c["yaw"] - want_yaw) > 0.0001:
		bad.append(tag + "yaw %f, street position gives %f" % [c["yaw"], want_yaw])
	if c["hidden"] != want_hidden:
		bad.append(tag + "hidden %s, street position gives %s" % [c["hidden"], want_hidden])
	var model_pos: Vector3 = c["model"]["root"].position
	if Vector2(model_pos.x - c["pos"].x, model_pos.z - c["pos"].z).length() > 0.0001:
		bad.append(tag + "model is at %s, pos is %s" % [model_pos, c["pos"]])
