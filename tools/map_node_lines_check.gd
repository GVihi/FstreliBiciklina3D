extends SceneTree
# Checks the line that says what the highlighted node does on the map screen (README alpha B6, Milestone D "Map
# Nodes"). Run from the project folder:
#   godot --headless --path . --script res://tools/map_node_lines_check.gd
# It checks that
#   - every node type that can appear on a generated map (all but the event, which is switched off in the alpha) has
#     a line, and the mid boss and the final boss have different ones
#   - at 1280x720 and 1920x1080 the line wraps to at most 3 rows, every row fits the info panel, the panel stays on
#     screen, clear of the map nodes, and the rows sit between the node name and the ROUND line, clear of the style
#     line at the top and of the cash line below
#   - the map screen draws with each choice highlighted at both sizes
# Exits with status 1 and prints the problems when a check fails.

const SEEDS = [1, 2, 3, 0x9E378A43, 77, 1234]
const SIZES = [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]
const TYPES = ["normal", "elite", "shop", "rest", "boss"]

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_check_every_type_has_a_line()
	_check_layout()
	await _check_drawing()
	_finish()


func _fail(text: String) -> void:
	problems.append(text)


func _check_every_type_has_a_line() -> void:
	var seen = {}
	for s in SEEDS:
		main.start_game(false, s)
		for fl in main.run_map["floors"]:
			for node in fl:
				seen[str(node["type"])] = true
	for t in seen:
		if t == "event":
			continue
		if main.hud.map_node_line(t, false) == "":
			_fail("a %s node on the map has no line" % t)
	for t in TYPES:
		if main.hud.map_node_line(t, false) == "":
			_fail("the type %s has no line" % t)
	if main.hud.map_node_line("boss", true) == main.hud.map_node_line("boss", false):
		_fail("the mid boss and the final boss have the same line")
	if main.hud.map_node_line("boss", true) == "":
		_fail("the final boss has no line")


func _check_layout() -> void:
	var hud = main.hud
	for s in SIZES:
		hud.size = s
		var k = s.y / 720.0
		var tag = "%dx%d" % [int(s.x), int(s.y)]
		var px = hud.map_info_x()
		var w = hud.map_info_width()
		if px + w > s.x - 0.02 * s.x:
			_fail("%s: the info panel runs off the right edge (%f + %f of %f)" % [tag, px, w, s.x])
		# clear of the map: every node of the maps of several seeds ends left of the panel
		for seed_value in SEEDS:
			main.start_game(false, seed_value)
			var floors = main.run_map["floors"]
			for f in range(floors.size()):
				for i in range(floors[f].size()):
					var p = hud.map_node_pos(f, i)
					if p.x + 28.0 * k > px:
						_fail(
							(
								"%s seed %X: node %d/%d reaches the info panel"
								% [tag, seed_value, f, i]
							)
						)
		var top = s.y * 0.44  # first row of the line
		var round_line = s.y * 0.57  # baseline of the ROUND line
		var cash_line = s.y * 0.62  # baseline of the cash line (24 px text)
		var style_line = s.y * 0.135  # the ARENA line at the top
		if top - 18.0 * k < style_line + 18.0 * k:
			_fail("%s: the line starts too close to the style line" % tag)
		if round_line + 6.0 * k > cash_line - 24.0 * k:
			_fail("%s: the ROUND line touches the cash line" % tag)
		for t in TYPES:
			for last in [false, true]:
				if last and t != "boss":
					continue
				var rows: Array = hud.map_node_lines(t, last, k)
				var name = "%s %s%s" % [tag, t, " (final)" if last else ""]
				if rows.is_empty() or rows.size() > 3:
					_fail("%s: the line wraps to %d rows, expected 1 to 3" % [name, rows.size()])
					continue
				for row in rows:
					var rw = (
						hud
						. font
						. get_string_size(str(row), HORIZONTAL_ALIGNMENT_LEFT, -1, int(18 * k))
						. x
					)
					if rw > w + 1.0:
						_fail("%s: a row is %f wide, the panel is %f" % [name, rw, w])
				var bottom = top + float(rows.size() - 1) * 24.0 * k + 6.0 * k
				if bottom > round_line - 18.0 * k:
					_fail(
						(
							"%s: the rows (to %f) run into the ROUND line (%f)"
							% [name, bottom, round_line]
						)
					)


# the map screen at both sizes with every choice highlighted, so a drawing error shows up
func _check_drawing() -> void:
	main.start_game(false, SEEDS[0])
	for s in SIZES:
		main.hud.size = s
		for i in range(maxi(1, main.map_choices.size())):
			main.map_sel = i
			for j in range(2):
				main.hud.queue_redraw()
				await process_frame
	main.hud.size = Vector2(1280.0, 720.0)
	if main.state != "map":
		_fail("the run did not start on the map screen (state %s)" % main.state)


func _finish() -> void:
	if problems.is_empty():
		print("map_node_lines_check: every node type has a line that fits the map screen")
		quit(0)
	else:
		print("map_node_lines_check: %d problem(s)" % problems.size())
		for p in problems.slice(0, 12):
			print("  " + p)
		quit(1)
