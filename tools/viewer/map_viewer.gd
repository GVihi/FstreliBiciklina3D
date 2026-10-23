extends Control
# Run map viewer (development tool, not part of the game).
# Open tools/viewer/map_viewer.tscn in Godot and press F6 (Run Current Scene).
# Type a seed and press Enter: the run map that MapGen.generate() makes for that seed is drawn, floor 1 at the
# bottom and the final boss at the top, with a circle for every node (letter = type) and a line for every edge.
# Click a node to see what is in it (theme, riders, open gates, modifier, boss kind or seed) on the right, and
# the nodes you can come from and go to are highlighted.
#
#   Seed box        a seed as the game shows it (up to 8 hex digits, e.g. 7F3A91C2), or "today" for the daily
#                   seed. Enter draws it. The same text works in tools/viewer/arena_viewer.tscn, which draws
#                   the arena of the same seed.
#   Random / Daily  buttons: a random seed, today's daily seed
#   Left / Right    the previous / next seed (counted up or down by one), when the seed box is not being typed in
#   Click           select a node. Click empty space to clear the selection.
#
# What the map rules mean is in docs/MAP_GENERATION.md. Nothing here is used by the game.

const MapGen = preload("res://scripts/map_gen.gd")
const ArenaViewer = preload("res://tools/viewer/arena_viewer.gd")
const DailyScript = preload("res://scripts/daily.gd")
const Content = preload("res://scripts/content.gd")

const PANEL_WIDTH = 400.0
const TOP = 110.0
const BOTTOM_MARGIN = 40.0
const SIDE_MARGIN = 40.0
const NODE_RADIUS = 20.0
const NODE_COLORS = {
	"normal": Color("#7FB069"),
	"elite": Color("#D1495B"),
	"shop": Color("#EDAE49"),
	"event": Color("#00A6A6"),
	"rest": Color("#6C9BD2"),
	"boss": Color("#8E44AD"),
}
const TYPE_NAMES = {
	"normal": "NORMAL FIGHT",
	"elite": "ELITE FIGHT",
	"shop": "SHOP",
	"event": "EVENT",
	"rest": "REST STOP",
	"boss": "BOSS",
}

var map = {}
var seed_value = 0
var selected = Vector2i(-1, -1)  # x = floor index, y = lane; (-1, -1) means nothing
var info: Label
var detail: Label
var seed_box: LineEdit


func _ready() -> void:
	_build_ui()
	resized.connect(queue_redraw)
	show_seed(DailyScript.today_seed())


# ------------------------------------------------------------------ seeds and maps
func show_seed(value: int) -> void:
	seed_value = value & 0xFFFFFFFF
	seed_box.text = DailyScript.seed_text(seed_value)
	seed_box.release_focus()
	selected = Vector2i(-1, -1)
	map = MapGen.generate(seed_value)
	if map.is_empty():
		info.text = (
			"Seed %s: no valid map, see the Output panel" % DailyScript.seed_text(seed_value)
		)
	else:
		info.text = (
			"Seed %s: %d floors, %d nodes, %d arena gates%s"
			% [
				DailyScript.seed_text(seed_value),
				map["floors"].size(),
				_node_count(map),
				int(map.get("gates", 0)),
				_attempt_text(map),
			]
		)
	_update_detail()
	queue_redraw()


static func _node_count(m: Dictionary) -> int:
	var total = 0
	for nodes in m["floors"]:
		total += nodes.size()
	return total


# " (made by retry 2)" when the first attempt failed validation, "" otherwise
static func _attempt_text(m: Dictionary) -> String:
	var attempt = int(m.get("attempt", 0))
	return "" if attempt == 0 else " (made by retry %d)" % attempt


# ------------------------------------------------------------------ geometry (static, so the check can test it)
# Where the node of floor `f` (0-based) and lane `i` is drawn inside an area of `area_size`. The right-hand
# panel is kept free. Floors go up the screen, lanes are spread evenly from left to right.
static func node_pos(m: Dictionary, f: int, i: int, area_size: Vector2) -> Vector2:
	var floors = m["floors"]
	var graph_width = area_size.x - PANEL_WIDTH - 2.0 * SIDE_MARGIN
	var width = floors[f].size()
	var x = SIDE_MARGIN + graph_width * float(i + 1) / float(width + 1)
	var top = TOP
	var bottom = area_size.y - BOTTOM_MARGIN
	var steps = maxi(1, floors.size() - 1)
	var y = bottom - (bottom - top) * float(f) / float(steps)
	return Vector2(x, y)


# The node under `point`, as Vector2i(floor, lane), or (-1, -1)
static func node_at(m: Dictionary, point: Vector2, area_size: Vector2) -> Vector2i:
	if m.is_empty():
		return Vector2i(-1, -1)
	var floors = m["floors"]
	for f in range(floors.size()):
		for i in range(floors[f].size()):
			if node_pos(m, f, i, area_size).distance_to(point) <= NODE_RADIUS:
				return Vector2i(f, i)
	return Vector2i(-1, -1)


# The nodes with an edge into floor f lane i (their lanes on floor f - 1)
static func parents_of(m: Dictionary, f: int, i: int) -> Array:
	var out = []
	if f <= 0:
		return out
	var below = m["floors"][f - 1]
	for k in range(below.size()):
		if below[k]["next"].has(i):
			out.append(k)
	return out


# ------------------------------------------------------------------ text
# What is in a node, in words, for the panel on the right. `f` is 0-based.
static func node_text(m: Dictionary, f: int, i: int) -> String:
	var node = m["floors"][f][i]
	var t = str(node["type"])
	var lines = ["FLOOR %d, LANE %d" % [f + 1, i], str(TYPE_NAMES.get(t, t.to_upper())), ""]
	var c = node.get("content", {})
	if c.has("theme"):
		var idx = int(c["theme"])
		var theme_name = Content.THEMES[idx]["name"] if idx < Content.THEMES.size() else "?"
		lines.append("Lighting: %s (theme %d)" % [theme_name, idx])
	if c.has("riders"):
		var parts = []
		for kind in c["riders"]["mix"]:
			if int(c["riders"]["mix"][kind]) > 0:
				parts.append("%d %s" % [int(c["riders"]["mix"][kind]), kind])
		lines.append("Riders: %d (%s)" % [int(c["riders"]["count"]), ", ".join(parts)])
		var open = []
		for g in c["gates"]:
			open.append(str(int(g) + 1))
		lines.append(
			(
				"Open gates: %s of %d (numbered as in the arena viewer)"
				% [", ".join(open), int(m.get("gates", 0))]
			)
		)
		if c["modifiers"].is_empty():
			lines.append("Modifier: none")
		else:
			lines.append("Modifier: %s" % ", ".join(PackedStringArray(c["modifiers"])))
	if c.has("boss"):
		lines.append("Boss: %s%s" % [c["boss"], " (final)" if c.has("final") else ""])
	if c.has("seed"):
		lines.append("Content seed: %08X (drawn later, Milestone D)" % int(c["seed"]))
	lines.append("")
	var nexts = []
	for j in node["next"]:
		nexts.append(str(j))
	lines.append(
		"Goes on to lane: %s" % (", ".join(nexts) if not nexts.is_empty() else "nothing (the end)")
	)
	var parents = []
	for k in parents_of(m, f, i):
		parents.append(str(k))
	lines.append(
		"Comes from lane: %s" % (", ".join(parents) if not parents.is_empty() else "the start")
	)
	return "\n".join(lines)


func _update_detail() -> void:
	if map.is_empty() or selected.x < 0:
		detail.text = "Click a node to see what is in it."
	else:
		detail.text = node_text(map, selected.x, selected.y)


# ------------------------------------------------------------------ drawing
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#1d2026"))
	if map.is_empty():
		return
	var floors = map["floors"]
	var font = ThemeDB.fallback_font
	var near = _near_nodes()
	# edges first, so the circles sit on top
	for f in range(floors.size() - 1):
		for i in range(floors[f].size()):
			var a = node_pos(map, f, i, size)
			for j in floors[f][i]["next"]:
				var b = node_pos(map, f + 1, int(j), size)
				var lit = selected == Vector2i(f, i) or selected == Vector2i(f + 1, int(j))
				var col = Color("#f5f5f5") if lit else Color(1, 1, 1, 0.28)
				draw_line(a, b, col, 4.0 if lit else 2.0, true)
	for f in range(floors.size()):
		var label_pos = node_pos(map, f, 0, size)
		draw_string(
			font,
			Vector2(6.0, label_pos.y + 5.0),
			"F%d" % (f + 1),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			Color(1, 1, 1, 0.6)
		)
		for i in range(floors[f].size()):
			var p = node_pos(map, f, i, size)
			var t = str(floors[f][i]["type"])
			var fill = NODE_COLORS.get(t, Color.GRAY)
			var here = selected == Vector2i(f, i)
			if selected.x >= 0 and not here and not near.has(Vector2i(f, i)):
				fill = fill.darkened(0.55)
			draw_circle(
				p,
				NODE_RADIUS + (4.0 if here else 0.0),
				Color.WHITE if here else Color(0, 0, 0, 0.6)
			)
			draw_circle(p, NODE_RADIUS - 2.0, fill)
			var letter = str(MapGen.LETTERS.get(t, "-"))
			draw_string(
				font, p + Vector2(-6.0, 6.0), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.BLACK
			)


# the nodes joined to the selected one by an edge
func _near_nodes() -> Dictionary:
	var out = {}
	if selected.x < 0 or map.is_empty():
		return out
	for j in map["floors"][selected.x][selected.y]["next"]:
		out[Vector2i(selected.x + 1, int(j))] = true
	for k in parents_of(map, selected.x, selected.y):
		out[Vector2i(selected.x - 1, int(k))] = true
	return out


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected = node_at(map, event.position, size)
		_update_detail()
		queue_redraw()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_RIGHT:
		show_seed(seed_value + 1)
	elif event.keycode == KEY_LEFT:
		show_seed(seed_value - 1)


# ------------------------------------------------------------------ interface
func _on_seed_submitted(text: String) -> void:
	var value = ArenaViewer.parse_seed(text)
	if value < 0:
		info.text = "'%s' is not a seed: use up to 8 hex digits (0-9, A-F), or 'today'" % text
		return
	show_seed(value)


func _build_ui() -> void:
	var box = VBoxContainer.new()
	box.position = Vector2(16.0, 12.0)
	add_child(box)
	var row = HBoxContainer.new()
	box.add_child(row)
	seed_box = LineEdit.new()
	seed_box.placeholder_text = "seed, e.g. 7F3A91C2, or today"
	seed_box.custom_minimum_size = Vector2(260.0, 0.0)
	seed_box.max_length = 12
	seed_box.text_submitted.connect(_on_seed_submitted)
	row.add_child(seed_box)
	var random_button = Button.new()
	random_button.text = "Random"
	random_button.focus_mode = Control.FOCUS_NONE
	random_button.pressed.connect(func(): show_seed(DailyScript.random_seed()))
	row.add_child(random_button)
	var daily_button = Button.new()
	daily_button.text = "Daily"
	daily_button.focus_mode = Control.FOCUS_NONE
	daily_button.pressed.connect(func(): show_seed(DailyScript.today_seed()))
	row.add_child(daily_button)
	info = Label.new()
	info.add_theme_font_size_override("font_size", 16)
	box.add_child(info)
	var help = Label.new()
	help.text = "Click a node for its content. Left / Right: previous / next seed."
	help.modulate = Color(1, 1, 1, 0.6)
	box.add_child(help)
	detail = Label.new()
	detail.anchor_left = 1.0
	detail.anchor_right = 1.0
	detail.offset_left = -PANEL_WIDTH + 10.0
	detail.offset_right = -16.0
	detail.offset_top = 16.0
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 16)
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(detail)
