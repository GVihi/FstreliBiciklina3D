extends RefCounted
# Builds the world of the training room (arena_training.gd): a small, dark, gridded box with glowing edges.
# It has the same shape as world.gd and world_generated.gd: build(root, arena) adds the environment, the room and
# its light to root and returns the dictionary main.gd and settings.gd work on ("env", "sky_mat", "sun",
# "win_mat", "lamp_mat", "lamps", "tris", "draw_calls"; see world_generated.gd).
#
# The look: walls, floor and ceiling in a very dark blue, a thin grid on every surface (a faint line every metre,
# a brighter one every 4 m), bright glowing edges where two surfaces meet (they are the only things above the
# glow threshold, so the glow marks the shape of the room and nothing else), and a warm frame round the rider door
# in the far wall. On the floor a faint line every 5 m from the start gives the distance to a target, with the
# number beside it. The light is fixed: ambient light and two soft lights under the ceiling, no sun, no theme
# (the arena says so with fixed_lighting, and main.gd then leaves it alone).
#
# Everything is made from the numbers in arena_training.gd, so changing the size of the room there changes it here.

const Room = preload("res://scripts/arena_training.gd")
const Lighting = preload("res://scripts/lighting.gd")

const BACKGROUND = Color(0.012, 0.013, 0.026)
const AMBIENT = Color(0.8, 0.8, 0.92)
const AMBIENT_ENERGY = 1.7
const FILL_COLOR = Color(0.8, 0.82, 1.0)
const FILL_ENERGY = 2.2
const WALL = Color(0.13, 0.13, 0.17)
const FLOOR = Color(0.06, 0.06, 0.09)
const CEILING = Color(0.07, 0.07, 0.10)
const RECESS = Color(0.012, 0.012, 0.02)
const GRID_MINOR = Color(0.17, 0.18, 0.31)
const GRID_MAJOR = Color(0.30, 0.32, 0.52)
const EDGE = Color(0.88, 0.91, 1.0)
const EDGE_GLOW = 2.4  # emission of the edges: above Lighting's glow threshold of 1.0
const DOOR = Color(1.0, 0.72, 0.32)
const DOOR_GLOW = 2.0
const TICK = Color(0.30, 0.33, 0.56)
const LABEL = Color(0.55, 0.6, 0.95)
const EDGE_THICK = 0.04  # metres: the glowing bars along the edges
const GRID_LIFT = 0.012  # metres: grid lines float this far off the surface so they never fight with it
const MAJOR_EVERY = 4  # metres between the brighter grid lines
const TICK_EVERY = 5.0  # metres between the distance lines on the floor
const TICK_WIDTH = 0.1
const TICKS = 4  # distance lines after the start line (5, 10, 15 and 20 m)


static func build(root: Node3D, _arena = null) -> Dictionary:
	var out = {}
	var tris = 0
	var draws = 0

	# ---------- environment: a dark colour instead of a sky, a cool ambient light, glow on ----------
	var made = Lighting.make_environment()
	var env: Environment = made["env"]
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	env.ambient_light_color = AMBIENT
	env.ambient_light_energy = AMBIENT_ENERGY
	env.glow_intensity = 0.8
	var we = WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	out["env"] = env
	out["sky_mat"] = made["sky_mat"]

	# ---------- a sun the settings can switch shadows on; it gives no light in the room ----------
	var sun = DirectionalLight3D.new()
	Lighting.setup_sun(sun)
	sun.light_energy = 0.0
	sun.shadow_enabled = false
	sun.visible = false
	root.add_child(sun)
	out["sun"] = sun

	# ---------- two soft lights under the ceiling, no shadows: they make the room darker towards the corners ----------
	for z in [-Room.HALF_Z * 0.5, Room.HALF_Z * 0.5]:
		var fill = OmniLight3D.new()
		fill.position = Vector3(0.0, Room.HEIGHT - 0.6, z)
		fill.light_color = FILL_COLOR
		fill.light_energy = FILL_ENERGY
		fill.omni_range = Room.HALF_Z * 1.4
		fill.shadow_enabled = false
		root.add_child(fill)

	# ---------- the shell: floor, ceiling, four walls (the far one round the door) and the door's recess ----------
	var shell = _shell()
	tris += _add(root, shell, _shell_material(), "Shell")
	draws += 1

	# ---------- the grid on every surface ----------
	var grid = _grid()
	_add(root, grid, _line_material(), "Grid")
	draws += 1

	# ---------- the glowing edges and the door frame ----------
	tris += _add(root, _edges(), _glow_material(EDGE, EDGE_GLOW), "Edges")
	tris += _add(root, _door_frame(), _glow_material(DOOR, DOOR_GLOW), "DoorFrame")
	draws += 2

	# ---------- the distance lines on the floor, and their numbers ----------
	tris += _add(root, _ticks(), _flat_material(), "DistanceLines")
	draws += 1
	for i in range(TICKS + 1):
		root.add_child(_tick_label(i))
		draws += 1

	# ---------- what the theme code expects to find (the room is never themed, so these only have to exist) ----------
	out["win_mat"] = StandardMaterial3D.new()
	out["lamp_mat"] = StandardMaterial3D.new()
	out["lamps"] = []
	out["tris"] = tris
	out["draw_calls"] = draws
	return out


# ---------------------------------------------------------------- small helpers
static func _add(root: Node3D, mesh: Mesh, mat: Material, node_name: String) -> int:
	var mi = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return _triangles(mesh)


# triangles of a triangle mesh (the grid is lines and is not counted)
static func _triangles(mesh: Mesh) -> int:
	var n = 0
	for s in range(mesh.get_surface_count()):
		var arrays = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		n += verts.size() / 3
	return n


# One quad a-b-c-d seen from the side the normal n points to. The corners are wound the way Godot calls the front
# face (clockwise seen from the front), whatever order the caller gave them in.
static func _quad(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color
) -> void:
	var order = [a, b, c, a, c, d]
	if (b - a).cross(c - a).dot(n) > 0.0:
		order = [a, d, c, a, c, b]
	for v in order:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(v)


static func _shell_material() -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	m.metallic_specular = 0.15
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _line_material() -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	return m


static func _flat_material() -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _glow_material(col: Color, energy: float) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


# ---------------------------------------------------------------- the shell
static func _shell() -> ArrayMesh:
	var hx = Room.HALF_X
	var hz = Room.HALF_Z
	var h = Room.HEIGHT
	var dh = Room.DOOR_HALF
	var dt = Room.DOOR_HEIGHT
	var dd = Room.DOOR_DEPTH
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# floor and ceiling
	_quad(
		st,
		Vector3(-hx, 0, -hz),
		Vector3(hx, 0, -hz),
		Vector3(hx, 0, hz),
		Vector3(-hx, 0, hz),
		Vector3.UP,
		FLOOR
	)
	_quad(
		st,
		Vector3(-hx, h, -hz),
		Vector3(hx, h, -hz),
		Vector3(hx, h, hz),
		Vector3(-hx, h, hz),
		Vector3.DOWN,
		CEILING
	)
	# the near wall (behind the player at the start) and the two side walls
	_quad(
		st,
		Vector3(-hx, 0, hz),
		Vector3(hx, 0, hz),
		Vector3(hx, h, hz),
		Vector3(-hx, h, hz),
		Vector3.FORWARD,
		WALL
	)
	_quad(
		st,
		Vector3(-hx, 0, -hz),
		Vector3(-hx, 0, hz),
		Vector3(-hx, h, hz),
		Vector3(-hx, h, -hz),
		Vector3.RIGHT,
		WALL
	)
	_quad(
		st,
		Vector3(hx, 0, -hz),
		Vector3(hx, 0, hz),
		Vector3(hx, h, hz),
		Vector3(hx, h, -hz),
		Vector3.LEFT,
		WALL
	)
	# the far wall in three pieces round the door
	_quad(
		st,
		Vector3(-hx, 0, -hz),
		Vector3(-dh, 0, -hz),
		Vector3(-dh, h, -hz),
		Vector3(-hx, h, -hz),
		Vector3.BACK,
		WALL
	)
	_quad(
		st,
		Vector3(dh, 0, -hz),
		Vector3(hx, 0, -hz),
		Vector3(hx, h, -hz),
		Vector3(dh, h, -hz),
		Vector3.BACK,
		WALL
	)
	_quad(
		st,
		Vector3(-dh, dt, -hz),
		Vector3(dh, dt, -hz),
		Vector3(dh, h, -hz),
		Vector3(-dh, h, -hz),
		Vector3.BACK,
		WALL
	)
	# the recess behind the door: floor, roof, two sides and the back, almost black
	_quad(
		st,
		Vector3(-dh, 0, -hz - dd),
		Vector3(dh, 0, -hz - dd),
		Vector3(dh, 0, -hz),
		Vector3(-dh, 0, -hz),
		Vector3.UP,
		RECESS
	)
	_quad(
		st,
		Vector3(-dh, dt, -hz - dd),
		Vector3(dh, dt, -hz - dd),
		Vector3(dh, dt, -hz),
		Vector3(-dh, dt, -hz),
		Vector3.DOWN,
		RECESS
	)
	_quad(
		st,
		Vector3(-dh, 0, -hz - dd),
		Vector3(-dh, 0, -hz),
		Vector3(-dh, dt, -hz),
		Vector3(-dh, dt, -hz - dd),
		Vector3.RIGHT,
		RECESS
	)
	_quad(
		st,
		Vector3(dh, 0, -hz - dd),
		Vector3(dh, 0, -hz),
		Vector3(dh, dt, -hz),
		Vector3(dh, dt, -hz - dd),
		Vector3.LEFT,
		RECESS
	)
	_quad(
		st,
		Vector3(-dh, 0, -hz - dd),
		Vector3(dh, 0, -hz - dd),
		Vector3(dh, dt, -hz - dd),
		Vector3(-dh, dt, -hz - dd),
		Vector3.BACK,
		RECESS
	)
	return st.commit()


# ---------------------------------------------------------------- the grid
# A line colour by its place in the grid: every MAJOR_EVERY metres (counted on the world's own axes, so the
# lines of neighbouring surfaces meet at the corners) is the brighter one.
static func _grid_color(world_coord: int) -> Color:
	return GRID_MAJOR if posmod(world_coord, MAJOR_EVERY) == 0 else GRID_MINOR


static func _line(st: SurfaceTool, a: Vector3, b: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a)
	st.set_color(col)
	st.add_vertex(b)


static func _grid() -> ArrayMesh:
	var hx = int(Room.HALF_X)
	var hz = int(Room.HALF_Z)
	var h = int(Room.HEIGHT)
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var up = GRID_LIFT
	# floor and ceiling: a line at every whole metre of x and of z
	for y_n in [[0.0, up], [float(h), -up]]:
		var y: float = y_n[0] + y_n[1]
		for x in range(-hx, hx + 1):
			_line(st, Vector3(x, y, -hz), Vector3(x, y, hz), _grid_color(x))
		for z in range(-hz, hz + 1):
			if z == -hz and y_n[0] == 0.0:  # the floor line at the foot of the far wall stops at the door
				_line(st, Vector3(-hx, y, z), Vector3(-Room.DOOR_HALF, y, z), _grid_color(z))
				_line(st, Vector3(Room.DOOR_HALF, y, z), Vector3(hx, y, z), _grid_color(z))
			else:
				_line(st, Vector3(-hx, y, z), Vector3(hx, y, z), _grid_color(z))
	# the near wall
	for x in range(-hx, hx + 1):
		_line(st, Vector3(x, 0, hz - up), Vector3(x, h, hz - up), _grid_color(x))
	for y in range(0, h + 1):
		_line(st, Vector3(-hx, y, hz - up), Vector3(hx, y, hz - up), _grid_color(y))
	# the side walls
	for side in [-1, 1]:
		var wx: float = float(side) * (float(hx) - up)
		for z in range(-hz, hz + 1):
			_line(st, Vector3(wx, 0, z), Vector3(wx, h, z), _grid_color(z))
		for y in range(0, h + 1):
			_line(st, Vector3(wx, y, -hz), Vector3(wx, y, hz), _grid_color(y))
	# the far wall: the lines stop at the door
	var wz: float = float(-hz) + up
	var dh = Room.DOOR_HALF
	var dt = Room.DOOR_HEIGHT
	for x in range(-hx, hx + 1):
		var y0 = dt if absf(float(x)) < dh else 0.0
		_line(st, Vector3(x, y0, wz), Vector3(x, h, wz), _grid_color(x))
	for y in range(0, h + 1):
		if float(y) < dt:
			_line(st, Vector3(-hx, y, wz), Vector3(-dh, y, wz), _grid_color(y))
			_line(st, Vector3(dh, y, wz), Vector3(hx, y, wz), _grid_color(y))
		else:
			_line(st, Vector3(-hx, y, wz), Vector3(hx, y, wz), _grid_color(y))
	return st.commit()


# ---------------------------------------------------------------- the glowing edges
# a box of size `size` centred on `at`, added to the surface tool
static func _bar(st: SurfaceTool, at: Vector3, size: Vector3) -> void:
	var bm = BoxMesh.new()
	bm.size = size
	st.append_from(bm, 0, Transform3D(Basis(), at))


# The bars of the glowing edges, each {"at": centre, "size": size}: one along every edge of the room, tucked into
# the corner (the far floor edge is in two pieces, it stops at the door). The check reads the same list.
static func edge_bars() -> Array:
	var hx = Room.HALF_X
	var hz = Room.HALF_Z
	var h = Room.HEIGHT
	var dh = Room.DOOR_HALF
	var t = EDGE_THICK
	var bars = []
	# along x: the near wall's floor and ceiling edges, the far wall's ceiling edge and the two pieces of its floor edge
	for y in [t * 0.5, h - t * 0.5]:
		bars.append({"at": Vector3(0.0, y, hz - t * 0.5), "size": Vector3(hx * 2.0, t, t)})
	bars.append({"at": Vector3(0.0, h - t * 0.5, -hz + t * 0.5), "size": Vector3(hx * 2.0, t, t)})
	var side_w = hx - dh
	for s in [-1.0, 1.0]:
		bars.append(
			{
				"at": Vector3(s * (dh + side_w * 0.5), t * 0.5, -hz + t * 0.5),
				"size": Vector3(side_w, t, t)
			}
		)
	# along z: the four edges where the side walls meet floor and ceiling
	for s in [-1.0, 1.0]:
		for y in [t * 0.5, h - t * 0.5]:
			bars.append(
				{"at": Vector3(s * (hx - t * 0.5), y, 0.0), "size": Vector3(t, t, hz * 2.0)}
			)
	# along y: the four corners
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			bars.append(
				{
					"at": Vector3(sx * (hx - t * 0.5), h * 0.5, sz * (hz - t * 0.5)),
					"size": Vector3(t, h, t)
				}
			)
	return bars


static func _edges() -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for bar in edge_bars():
		_bar(st, bar["at"], bar["size"])
	return st.commit()


# the warm frame round the rider door: two posts and a lintel, a little proud of the wall
static func _door_frame() -> ArrayMesh:
	var hz = Room.HALF_Z
	var dh = Room.DOOR_HALF
	var dt = Room.DOOR_HEIGHT
	var t = EDGE_THICK
	var z = -hz + t * 0.5 + 0.01
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [-1.0, 1.0]:
		_bar(st, Vector3(s * (dh + t * 0.5), dt * 0.5, z), Vector3(t, dt, t))
	_bar(st, Vector3(0.0, dt + t * 0.5, z), Vector3(dh * 2.0 + t * 2.0, t, t))
	return st.commit()


# ---------------------------------------------------------------- the distance lines
# z of the distance line `i` (0 is the start line, then every TICK_EVERY metres towards the far wall)
static func tick_z(i: int) -> float:
	return Room.START_Z - float(i) * TICK_EVERY


static func _ticks() -> ArrayMesh:
	var hx = Room.HALF_X
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(TICKS + 1):
		var z = tick_z(i)
		var y = GRID_LIFT * 2.0
		_quad(
			st,
			Vector3(-hx, y, z - TICK_WIDTH * 0.5),
			Vector3(hx, y, z - TICK_WIDTH * 0.5),
			Vector3(hx, y, z + TICK_WIDTH * 0.5),
			Vector3(-hx, y, z + TICK_WIDTH * 0.5),
			Vector3.UP,
			TICK
		)
	return st.commit()


# the number beside a distance line, flat on the floor by the left wall and readable from the start
static func _tick_label(i: int) -> Label3D:
	var lb = Label3D.new()
	lb.name = "DistanceLabel%d" % i
	lb.text = "START" if i == 0 else "%d M" % int(float(i) * TICK_EVERY)
	lb.font_size = 96
	lb.pixel_size = 0.008
	lb.modulate = LABEL
	lb.shaded = false
	lb.double_sided = true
	lb.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	lb.position = Vector3(-Room.HALF_X + 1.4, GRID_LIFT * 3.0, tick_z(i) - 0.45)
	return lb
