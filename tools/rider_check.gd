extends SceneTree
# Check for the rider world position (README Milestone K, Foundation). Riders carry "pos", "yaw" and
# "hidden" (world space) and the rest of the game reads those instead of working them out from the
# street position. This check rides riders through the tunnel, round the ring and out again, and fails
# if those values ever differ from what the street position gives, or if the model is not where "pos" says.
#
# Run from the project folder:
#   godot --headless --path . --script res://tools/rider_check.gd
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
	var riders: Array = []
	for lane in range(3):
		riders.append(main.rider_sys.spawn_rider(lane, 1))
		riders.append(main.rider_sys.spawn_rider(lane, -1))
	var seen_hidden = false
	var seen_visible = false
	for step in range(STEPS):
		# keep the player out of the way so nobody gets run over mid-check
		main.player.position = Vector3(0.0, 0.0, 0.0)
		for r in riders.duplicate():
			if r["gone"] or not main.riders.has(r):
				riders.erase(r)
				continue
			main.rider_sys.update_rider(r, DT)
			if r["mode"] == "fly" or r["mode"] == "away":
				_compare(main, r, step)
				seen_hidden = seen_hidden or r["hidden"]
				seen_visible = seen_visible or not r["hidden"]
		if step == 300:
			# an armoured hit uses the stored position too
			for r in riders:
				if r["mode"] == "fly" and not r["hidden"]:
					main.rider_sys.hit_rider(r, 1)
					break
	if not seen_hidden or not seen_visible:
		bad.append("riders never both entered and left the tunnel block (check is not covering it)")
	if bad.is_empty():
		print(
			"rider_check: pos, yaw and hidden agree with the street position for %d steps" % STEPS
		)
		quit(0)
	else:
		for line in bad.slice(0, 10):
			printerr("rider_check: " + line)
		quit(1)


func _compare(main, r: Dictionary, step: int) -> void:
	var want_pos = main.arena.tw(r["x"], main.LANE_Z[r["ln"]], 0.0)
	var want_yaw = main.arena.yaw(r["x"])
	var want_hidden = main.arena.hidden(r["x"])
	var tag = "step %d rider %d: " % [step, r["idx"]]
	if r["pos"].distance_to(want_pos) > 0.0001:
		bad.append(tag + "pos %s, street position gives %s" % [r["pos"], want_pos])
	if absf(r["yaw"] - want_yaw) > 0.0001:
		bad.append(tag + "yaw %f, street position gives %f" % [r["yaw"], want_yaw])
	if r["hidden"] != want_hidden:
		bad.append(tag + "hidden %s, street position gives %s" % [r["hidden"], want_hidden])
	var model_pos: Vector3 = r["model"]["root"].position
	if Vector2(model_pos.x - r["pos"].x, model_pos.z - r["pos"].z).length() > 0.0001:
		bad.append(tag + "model is at %s, pos is %s" % [model_pos, r["pos"]])
