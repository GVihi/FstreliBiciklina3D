extends SceneTree
# Checks the run map viewer (tools/viewer/map_viewer.gd): what it draws and says for a seed, not how it looks.
# Run from the project folder:
#   godot --headless --path . --script res://tools/map_viewer_check.gd
# Optional argument after "--": how many seeds to check (default 200).
# For every seed it checks that
#   - every node has its own place inside the area, floors go up the screen and lanes go left to right
#   - node_at finds a node from its own position, and finds nothing in empty space
#   - the text of every node names its floor and type, and says where it goes on to and comes from
#   - the text says what the content holds: riders and open gates for fights, the boss kind, the seed for the rest
# It also runs the whole scene: typing a seed shows the map MapGen makes for it, a bad seed is refused, Left
# and Right step the seed, and clicking a node selects it and fills the panel.
# Exits with status 1 and lists the first problems when a check fails.

const MapGen = preload("res://scripts/map_gen.gd")
const Viewer = preload("res://tools/viewer/map_viewer.gd")
const DailyScript = preload("res://scripts/daily.gd")

const AREA = Vector2(1280.0, 720.0)

var problems = []


func _initialize() -> void:
	var count = 200
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		count = int(args[0])
	var rules = MapGen.load_rules()
	if rules.is_empty():
		quit(1)
		return
	for k in range(count):
		var seed_value = (k * 2654435761 + 4242) & 0xFFFFFFFF
		var map = MapGen.generate(seed_value, rules, 2 + (seed_value % 4))
		if map.is_empty():
			_fail(seed_value, "no map was generated")
			continue
		_check_positions(seed_value, map)
		_check_text(seed_value, map)
	await _check_scene()
	if problems.is_empty():
		print(
			(
				"map_viewer_check: %d seeds, every node has its own place and a text, and the scene takes a seed, refuses a bad one and selects a node on click"
				% count
			)
		)
		quit(0)
	else:
		for i in range(mini(problems.size(), 20)):
			print("FAIL: " + problems[i])
		print("map_viewer_check: %d problems" % problems.size())
		quit(1)


func _fail(seed_value: int, text: String) -> void:
	problems.append("seed %08X: %s" % [seed_value, text])


func _check_positions(seed_value: int, map: Dictionary) -> void:
	var floors = map["floors"]
	var seen = {}
	for f in range(floors.size()):
		for i in range(floors[f].size()):
			var p = Viewer.node_pos(map, f, i, AREA)
			if p.x < 0.0 or p.y < 0.0 or p.x > AREA.x - Viewer.PANEL_WIDTH or p.y > AREA.y:
				_fail(
					seed_value,
					"floor %d lane %d is drawn outside the graph area at %s" % [f + 1, i, p]
				)
			if seen.has(p):
				_fail(seed_value, "floor %d lane %d is drawn on top of another node" % [f + 1, i])
			seen[p] = true
			if i > 0 and p.x <= Viewer.node_pos(map, f, i - 1, AREA).x:
				_fail(
					seed_value, "floor %d lanes %d and %d are not left to right" % [f + 1, i - 1, i]
				)
			if f > 0 and p.y >= Viewer.node_pos(map, f - 1, 0, AREA).y:
				_fail(seed_value, "floor %d is not above floor %d" % [f + 1, f])
			if Viewer.node_at(map, p, AREA) != Vector2i(f, i):
				_fail(
					seed_value,
					"node_at does not find floor %d lane %d at its own position" % [f + 1, i]
				)
	if Viewer.node_at(map, Vector2(AREA.x - 5.0, 5.0), AREA) != Vector2i(-1, -1):
		_fail(seed_value, "node_at found a node in empty space")


func _check_text(seed_value: int, map: Dictionary) -> void:
	var floors = map["floors"]
	for f in range(floors.size()):
		for i in range(floors[f].size()):
			var text = Viewer.node_text(map, f, i)
			var node = floors[f][i]
			var t = str(node["type"])
			var where = "floor %d lane %d" % [f + 1, i]
			if not text.contains("FLOOR %d, LANE %d" % [f + 1, i]):
				_fail(seed_value, "%s: the text does not name the node" % where)
			if not text.contains("Goes on to lane") or not text.contains("Comes from lane"):
				_fail(
					seed_value,
					"%s: the text does not say where the node leads and comes from" % where
				)
			if (
				(t == "normal" or t == "elite" or t == "boss")
				and (not text.contains("Riders:") or not text.contains("Open gates:"))
			):
				_fail(seed_value, "%s: a fight's text has no riders or gates" % where)
			if t == "boss" and not text.contains("Boss: " + str(node["content"]["boss"])):
				_fail(seed_value, "%s: a boss's text has no boss kind" % where)
			if (t == "shop" or t == "rest" or t == "event") and not text.contains("Content seed:"):
				_fail(seed_value, "%s: the text has no content seed" % where)
			if f > 0 and Viewer.parents_of(map, f, i).is_empty():
				_fail(seed_value, "%s has no parent" % where)


# the scene as it runs: type a seed, get that map; click a node, get its text
func _check_scene() -> void:
	var scene = load("res://tools/viewer/map_viewer.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	if scene.map.is_empty() or scene.seed_value != DailyScript.today_seed():
		problems.append("the viewer does not start on today's daily seed")
	scene._on_seed_submitted("7F3A91C2")
	await process_frame
	if JSON.stringify(scene.map) != JSON.stringify(MapGen.generate(0x7F3A91C2)):
		problems.append("typing 7F3A91C2 did not show the map MapGen makes for it")
	if scene.seed_box.text != "7F3A91C2" or not scene.info.text.contains("Seed 7F3A91C2"):
		problems.append("the seed box or the text does not name the seed: " + scene.info.text)
	var before = scene.map
	scene._on_seed_submitted("not a seed")
	await process_frame
	if scene.map != before or not scene.info.text.contains("is not a seed"):
		problems.append("a bad seed was not refused")
	scene._unhandled_key_input(_key(KEY_RIGHT))
	await process_frame
	if scene.seed_value != 0x7F3A91C3:
		problems.append("Right did not show the next seed")
	scene._unhandled_key_input(_key(KEY_LEFT))
	await process_frame
	if scene.seed_value != 0x7F3A91C2:
		problems.append("Left did not go back to the previous seed")
	scene.size = AREA
	var target = Viewer.node_pos(scene.map, 4, 0, AREA)
	scene._gui_input(_click(target))
	if scene.selected != Vector2i(4, 0) or not scene.detail.text.contains("BOSS"):
		problems.append("clicking the mid boss did not select it: " + scene.detail.text)
	scene._gui_input(_click(Vector2(AREA.x - 5.0, 5.0)))
	if scene.selected != Vector2i(-1, -1) or not scene.detail.text.contains("Click a node"):
		problems.append("clicking empty space did not clear the selection")
	scene.queue_free()


func _key(code: int) -> InputEventKey:
	var e = InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _click(point: Vector2) -> InputEventMouseButton:
	var e = InputEventMouseButton.new()
	e.position = point
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e
