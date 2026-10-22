extends Node3D
# Arena viewer (development tool, not part of the game).
# Open tools/viewer/arena_viewer.tscn in Godot and press F6 (Run Current Scene).
# Type a seed and press Enter: the arena that ArenaGen.generate() makes for that seed is drawn from above,
# every cell in the colour of its ground, buildings as blocks, gates (tunnels) with an arrow and a number,
# and the start area as a pink square with a pole in the middle.
#
#   Seed box        a seed as the game shows it (up to 8 hex digits, e.g. 7F3A91C2), or "today" for the
#                   daily seed. Enter draws it.
#   Random / Daily  buttons: a random seed, today's daily seed
#   Left / Right    the previous / next seed (counted up or down by one)
#   C               switch between the ground colours and the navigation clearance (how many cells from
#                   the nearest building: red 1, touching, to green 9)
#   W               switch between this flat plan and the real arena the game would build from the layout
#                   (scripts/world_gen.gd and world_dress.gd): lit surfaces, curbs, road paint, the start frame,
#                   buildings with windows and the tunnel blocks
#   Mouse drag      orbit        Mouse wheel   zoom        R   reset the camera (looking down, north up)
#
# What the numbers on screen mean is in docs/PROCEDURAL_ARENAS.md. Nothing here is used by the game.

const ArenaGen = preload("res://scripts/arena_gen.gd")
const DailyScript = preload("res://scripts/daily.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const WorldDress = preload("res://scripts/world_dress.gd")

const MODE_GROUND = 0
const MODE_CLEARANCE = 1
const BUILDING_HEIGHT = 4.0
const START_COLOR = Color("#FF2D95")
const GATE_COLOR = Color("#19D3E6")
const TUNNEL_BLOCK_COLOR = Color(0.04, 0.04, 0.05)  # the tunnel blocks are black; a hair lighter so the swatch shows
const SIDE_SHADE = [0.78, 0.62, 0.7, 0.55]  # north, east, south, west faces of a building
const GROUND_COLORS = {
	"g": Color("#7FB069"),
	"p": Color("#E3D3A1"),
	"s": Color("#BDBDB5"),
	"r": Color("#3E4147"),
	"b": Color("#8A6F63"),
	"t": Color("#E8A21F"),
}
const GROUND_NAMES = {
	"g": "grass", "p": "plaza", "s": "sidewalk", "r": "road", "b": "building", "t": "tunnel"
}
const SKY_TOP = Color("#4f98d8")
const SKY_HORIZON = Color("#dbe9ee")
const DEFAULT_YAW = 0.0
const DEFAULT_PITCH = -1.45
const DEFAULT_DIST = 150.0
# the camera looks a little north of the middle, so the arena sits below the text at the top of the screen
const FOCUS = Vector3(0.0, 0.0, -13.0)

var rules = {}
var layout = {}
var seed_value = 0
var mode = MODE_GROUND
var world_view = false  # showing the real ground (W) instead of the flat plan
var ground_stats = {}  # triangles and draw calls of the real ground, while it is shown
var dress_stats = {}  # the same for the buildings and tunnels standing on it
var root: Node3D = null
var cam: Camera3D
var info: Label
var legend: HBoxContainer
var seed_box: LineEdit
var yaw = DEFAULT_YAW
var pitch = DEFAULT_PITCH
var dist = DEFAULT_DIST


func _ready() -> void:
	rules = ArenaGen.load_rules()
	_build_scene()
	_build_ui()
	if rules.is_empty():
		info.text = "data/arena_rules.json is missing or unusable, see the Output panel"
		return
	show_seed(DailyScript.today_seed())


# ------------------------------------------------------------------ seeds and layouts
# Turns what was typed into a seed (0 to 4294967295), or -1 if it is not one. The game shows seeds as
# hex text (DailyScript.seed_text), so hex is what is read; "today" is the daily seed.
static func parse_seed(text: String) -> int:
	var t = text.strip_edges().to_lower()
	if t == "today" or t == "daily":
		return DailyScript.today_seed()
	if t.begins_with("0x"):
		t = t.substr(2)
	if t.is_empty() or t.length() > 8:
		return -1
	for i in range(t.length()):
		if not "0123456789abcdef".contains(t[i]):
			return -1  # is_valid_hex_number() would let a minus sign through
	return t.hex_to_int()


func show_seed(value: int) -> void:
	seed_value = value & 0xFFFFFFFF
	seed_box.text = DailyScript.seed_text(seed_value)
	seed_box.release_focus()
	layout = ArenaGen.generate(seed_value, rules)
	_rebuild()


# ------------------------------------------------------------------ building the picture
# Everything that depends on the layout is under `root`, which is thrown away and rebuilt for every seed.
func _rebuild() -> void:
	if root != null:
		root.queue_free()
		root = null
	if layout.is_empty():
		info.text = (
			"Seed %s: no usable layout in %d attempts"
			% [DailyScript.seed_text(seed_value), int(rules.get("max_attempts", 8))]
		)
		_fill_legend()
		return
	root = Node3D.new()
	add_child(root)
	ground_stats = {}
	dress_stats = {}
	if world_view:
		var built = WorldGen.build_ground(layout)
		root.add_child(built["root"])
		ground_stats = {"tris": built["tris"], "draw_calls": built["draw_calls"]}
		var dressed = WorldDress.build(layout)
		root.add_child(dressed["root"])
		dress_stats = {"tris": dressed["tris"], "draw_calls": dressed["draw_calls"]}
		var sun = DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-58.0, 35.0, 0.0)
		root.add_child(sun)
	else:
		var mi = MeshInstance3D.new()
		mi.mesh = build_mesh(layout, mode)
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
		root.add_child(mi)
	_add_gate_labels()
	_fill_legend()
	_update_info()


# The arena as one mesh with a colour per vertex: a flat square for every cell, a block for every building
# cell (only the walls that can be seen), the start square and the gate arrows. `mode` picks the colours
# (MODE_GROUND or MODE_CLEARANCE). Static and free of the scene, so tools/arena_viewer_check.gd can test it.
static func build_mesh(lay: Dictionary, view_mode: int) -> ArrayMesh:
	var n = int(lay["cells"])
	var cell = float(lay["cell"])
	var verts = PackedVector3Array()
	var cols = PackedColorArray()
	var idx = PackedInt32Array()
	for cz in range(n):
		var row = str(lay["rows"][cz])
		for cx in range(n):
			var ch = row[cx]
			var base = _cell_color(lay, view_mode, cx, cz, ch)
			if (cx + cz) % 2 == 1:
				base = base.darkened(0.04)  # a faint checkerboard so single cells can be counted
			var x0 = (float(cx) - float(n) / 2.0) * cell
			var z0 = (float(cz) - float(n) / 2.0) * cell
			var top = BUILDING_HEIGHT if ch == "b" else 0.0
			_quad(
				verts,
				cols,
				idx,
				[
					Vector3(x0, top, z0),
					Vector3(x0 + cell, top, z0),
					Vector3(x0 + cell, top, z0 + cell),
					Vector3(x0, top, z0 + cell)
				],
				base
			)
			if ch == "b":
				_walls(lay, verts, cols, idx, cx, cz, x0, z0, cell, base)
	_start_marker(lay, verts, cols, idx)
	_gate_arrows(lay, verts, cols, idx)
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _cell_color(lay: Dictionary, view_mode: int, cx: int, cz: int, ch: String) -> Color:
	if view_mode == MODE_CLEARANCE:
		var d = ArenaGen.nav_clearance(lay, cx, cz)
		if d == 0:
			return GROUND_COLORS["b"]
		return clearance_color(d)
	return GROUND_COLORS[ch]


# the walls of building cell (cx, cz) that face a cell that is not a building (the outer side of the border
# ring is skipped: nobody sees it from inside)
static func _walls(
	lay: Dictionary,
	verts: PackedVector3Array,
	cols: PackedColorArray,
	idx: PackedInt32Array,
	cx: int,
	cz: int,
	x0: float,
	z0: float,
	cell: float,
	base: Color
) -> void:
	var n = int(lay["cells"])
	var h = BUILDING_HEIGHT
	var x1 = x0 + cell
	var z1 = z0 + cell
	var sides = [
		[0, -1, [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, h, z0), Vector3(x0, h, z0)]],
		[1, 0, [Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x1, h, z1), Vector3(x1, h, z0)]],
		[0, 1, [Vector3(x1, 0, z1), Vector3(x0, 0, z1), Vector3(x0, h, z1), Vector3(x1, h, z1)]],
		[-1, 0, [Vector3(x0, 0, z1), Vector3(x0, 0, z0), Vector3(x0, h, z0), Vector3(x0, h, z1)]],
	]
	for k in range(4):
		var nx = cx + int(sides[k][0])
		var nz = cz + int(sides[k][1])
		if nx < 0 or nz < 0 or nx >= n or nz >= n:
			continue
		if str(lay["rows"][nz])[nx] == "b":
			continue
		var shade = float(SIDE_SHADE[k])
		var c = Color(base.r * shade, base.g * shade, base.b * shade)
		_quad(verts, cols, idx, sides[k][2], c)


# a pink frame round the clear start square (just above the ground) and a pole in its middle
static func _start_marker(
	lay: Dictionary, verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array
) -> void:
	var cell = float(lay["cell"])
	var half = float(lay["start"]["half"]) + 0.5
	var c = Vector2(float(lay["start"]["pos"][0]), float(lay["start"]["pos"][1]))
	var r = half * cell
	var w = 0.35
	var y = 0.06
	var strips = [
		[c.x - r, c.y - r, c.x + r, c.y - r + w],
		[c.x - r, c.y + r - w, c.x + r, c.y + r],
		[c.x - r, c.y - r, c.x - r + w, c.y + r],
		[c.x + r - w, c.y - r, c.x + r, c.y + r],
	]
	for s in strips:
		_quad(
			verts,
			cols,
			idx,
			[
				Vector3(s[0], y, s[1]),
				Vector3(s[2], y, s[1]),
				Vector3(s[2], y, s[3]),
				Vector3(s[0], y, s[3])
			],
			START_COLOR
		)
	# the pole: four walls, 0.3 m square, 3 m tall, and a flat top
	var p = 0.15
	var top = 3.0
	var a = Vector3(c.x - p, 0.0, c.y - p)
	var b = Vector3(c.x + p, 0.0, c.y - p)
	var d = Vector3(c.x + p, 0.0, c.y + p)
	var e = Vector3(c.x - p, 0.0, c.y + p)
	var up = Vector3(0.0, top, 0.0)
	_quad(verts, cols, idx, [a, b, b + up, a + up], START_COLOR)
	_quad(verts, cols, idx, [b, d, d + up, b + up], START_COLOR)
	_quad(verts, cols, idx, [d, e, e + up, d + up], START_COLOR)
	_quad(verts, cols, idx, [e, a, a + up, e + up], START_COLOR)
	_quad(verts, cols, idx, [a + up, b + up, d + up, e + up], START_COLOR)


# a flat arrow on every gate, pointing out of the arena
static func _gate_arrows(
	lay: Dictionary, verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array
) -> void:
	var y = 0.08
	for gt in lay["gates"]:
		var at = Vector2(float(gt["pos"][0]), float(gt["pos"][1]))
		var out = Vector2(float(gt["outward"][0]), float(gt["outward"][1]))
		var side = Vector2(-out.y, out.x)
		var width = minf(float(gt["half_width"]), 3.0) * 0.8
		var tail = at - out * 1.8  # a gate is 4 m deep, so the arrow stays inside the tunnel block
		var tip = at + out * 1.8
		var l = tail + side * width
		var r = tail - side * width
		var base = len(verts)
		verts.append(Vector3(tip.x, y, tip.y))
		verts.append(Vector3(l.x, y, l.y))
		verts.append(Vector3(r.x, y, r.y))
		for _i in range(3):
			cols.append(GATE_COLOR)
		idx.append_array(PackedInt32Array([base, base + 1, base + 2]))


# one flat or upright square (four corners in order round it), two triangles, one colour
static func _quad(
	verts: PackedVector3Array,
	cols: PackedColorArray,
	idx: PackedInt32Array,
	corners: Array,
	color: Color
) -> void:
	var base = len(verts)
	for v in corners:
		verts.append(v)
		cols.append(color)
	idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


func _add_gate_labels() -> void:
	var number = 1
	for gt in layout["gates"]:
		var label3 = Label3D.new()
		label3.text = "%d %s" % [number, str(gt["side"]).to_upper()]
		label3.font_size = 96
		label3.pixel_size = 0.03
		label3.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label3.no_depth_test = true
		label3.modulate = GATE_COLOR
		label3.outline_modulate = Color(0, 0, 0, 0.95)
		label3.outline_size = 24
		label3.position = Vector3(float(gt["pos"][0]), 6.5, float(gt["pos"][1]))
		root.add_child(label3)
		number += 1
	var start = Label3D.new()
	start.text = "START"
	start.font_size = 96
	start.pixel_size = 0.03
	start.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	start.no_depth_test = true
	start.modulate = START_COLOR
	start.outline_modulate = Color(0, 0, 0, 0.95)
	start.outline_size = 24
	start.position = Vector3(
		float(layout["start"]["pos"][0]), 6.5, float(layout["start"]["pos"][1])
	)
	root.add_child(start)


# ------------------------------------------------------------------ scene and screen
func _build_scene() -> void:
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = SKY_TOP
	sky_mat.sky_horizon_color = SKY_HORIZON
	sky_mat.ground_horizon_color = SKY_HORIZON
	var sky = Sky.new()
	sky.sky_material = sky_mat
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	var we = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.far = 600.0
	add_child(cam)
	_place_camera()


func _build_ui() -> void:
	var layer = CanvasLayer.new()
	add_child(layer)
	var box = VBoxContainer.new()
	box.position = Vector2(16.0, 12.0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(box)
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
	info.add_theme_font_size_override("font_size", 18)
	info.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	info.add_theme_constant_override("outline_size", 6)
	box.add_child(info)
	legend = HBoxContainer.new()
	legend.add_theme_constant_override("separation", 14)
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(legend)


func _on_seed_submitted(text: String) -> void:
	var value = parse_seed(text)
	if value < 0:
		info.text = '"%s" is not a seed: use up to 8 hex digits (0-9, A-F), or "today"' % text
		return
	show_seed(value)


func _update_info() -> void:
	var problems = ArenaGen.validate(layout, rules)
	var gates = []
	var number = 1
	for gt in layout["gates"]:
		gates.append("%d%s" % [number, str(gt["side"]).to_upper()])
		number += 1
	info.text = (
		"Seed %s%s   attempt %d   ground %d m2 (%d x %d cells of %.0f m)\nroads %d   plazas %d   buildings %d   gates %d (%s)   start at %.0f, %.0f m   validation: %s\nLeft/Right: seed -/+ 1   C: %s   W: %s   drag: orbit   wheel: zoom   R: reset"
		% [
			DailyScript.seed_text(seed_value),
			"  (today's daily seed)" if seed_value == DailyScript.today_seed() else "",
			int(layout["attempt"]) + 1,
			int(layout["walkable_m2"]),
			int(layout["cells"]),
			int(layout["cells"]),
			float(layout["cell"]),
			layout["roads"].size(),
			layout["plazas"].size(),
			layout["buildings"].size(),
			layout["gates"].size(),
			" ".join(gates),
			float(layout["start"]["pos"][0]),
			float(layout["start"]["pos"][1]),
			"ok" if problems.is_empty() else "; ".join(problems),
			"colours by clearance" if mode == MODE_GROUND else "colours by ground",
			_view_text(),
		]
	)


# what W does next, and in the real-ground view how big the ground is
func _view_text() -> String:
	if not world_view:
		return "real ground"
	return (
		"flat plan (real ground: %d triangles, %d draw calls; buildings and tunnels: %d triangles, %d draw calls)"
		% [
			int(ground_stats["tris"]),
			int(ground_stats["draw_calls"]),
			int(dress_stats["tris"]),
			int(dress_stats["draw_calls"])
		]
	)


func _fill_legend() -> void:
	for c in legend.get_children():
		c.queue_free()
	var entries = []
	if world_view:
		for key in ["g", "p", "s", "r", "b", "t"]:
			entries.append([WorldGen.SURFACE_STYLE[key][0], WorldGen.SURFACE_NAMES[key]])
		entries.append([WorldGen.CURB_COLOR, "curb"])
		entries.append([WorldGen.PAINT_COLOR, "road paint"])
		entries.append([WorldGen.HAZARD_COLOR, "start frame"])
		entries.append([WorldDress.BRICK_COLOR, "brick building"])
		entries.append([WorldDress.DARK_WALL_COLOR, "dark building"])
		entries.append([WorldDress.WINDOW_COLOR, "windows"])
		entries.append([TUNNEL_BLOCK_COLOR, "tunnel block"])
		entries.append([GATE_COLOR, "gate label"])
	elif mode == MODE_GROUND:
		for key in ["g", "p", "s", "r", "b", "t"]:
			entries.append([GROUND_COLORS[key], GROUND_NAMES[key]])
		entries.append([GATE_COLOR, "gate arrow"])
		entries.append([START_COLOR, "start area"])
	else:
		for d in [1, 2, 3, 5, 9]:
			entries.append([clearance_color(d), "clearance %d%s" % [d, "+" if d == 9 else ""]])
		entries.append([GROUND_COLORS["b"], "building"])
	for e in entries:
		var item = HBoxContainer.new()
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var swatch = ColorRect.new()
		swatch.color = e[0]
		swatch.custom_minimum_size = Vector2(16.0, 16.0)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(swatch)
		var text = Label.new()
		text.text = " " + str(e[1])
		text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		text.add_theme_constant_override("outline_size", 5)
		item.add_child(text)
		legend.add_child(item)


# red for clearance 1 (touching a building) through yellow to green for 9 and more
static func clearance_color(d: int) -> Color:
	return Color.from_hsv(0.33 * float(clampi(d, 1, 9) - 1) / 8.0, 0.75, 0.92)


func _place_camera() -> void:
	var dir = Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
	cam.position = FOCUS + dir * dist
	cam.look_at(FOCUS, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		yaw -= event.relative.x * 0.01
		pitch = clampf(pitch - event.relative.y * 0.01, -1.5, -0.1)
		_place_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = maxf(10.0, dist * 0.9)
			_place_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = minf(300.0, dist * 1.1)
			_place_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_RIGHT:
			show_seed(seed_value + 1)
		elif event.keycode == KEY_LEFT:
			show_seed(seed_value - 1)
		elif event.keycode == KEY_C and not layout.is_empty():
			world_view = false  # the clearance colours belong to the plan
			mode = MODE_CLEARANCE if mode == MODE_GROUND else MODE_GROUND
			_rebuild()
		elif event.keycode == KEY_W and not layout.is_empty():
			world_view = not world_view
			_rebuild()
		elif event.keycode == KEY_R:
			yaw = DEFAULT_YAW
			pitch = DEFAULT_PITCH
			dist = DEFAULT_DIST
			_place_camera()
