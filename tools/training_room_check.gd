extends SceneTree
# Checks the training room (scripts/arena_training.gd, scripts/world_training.gd, and how main.gd uses them).
# Run from the project folder:
#   python tools/run_checks.py training_room
# or: godot --headless --path . --script res://tools/training_room_check.gd
# It checks that
#   - the arena answers every question of the Arena interface the way a closed rectangular room must: the start is
#     inside, clamp_walk keeps every kind of body off the walls (and slides along them), a dart is stopped by every
#     wall and by the ceiling but not by the open door, a boss cannot enter the door's recess and a rider can, the
#     recess hides what is in it, and a rider starts hidden at the door and rides out straight into the room
#   - the world is what the picture asks for: one environment with a dark background and glow on, one shell whose
#     size is the room's (and the door's recess), no wall across the door, every face turned the right way round
#     (clockwise seen from inside, with its normal pointing into the room), grid lines on every surface and none
#     outside the room, glowing edges above the glow threshold on all 12 edges, a distance line and a number every
#     5 m from the start, and everything the theme and settings code looks for
#   - main.gd takes the room: --training-room asks for it on the game and only there (or a check's flag), the title
#     screen is the room with one world, the cheerleaders are hidden, the round's theme leaves the light alone
#     (every theme gives the same environment), a run keeps the room (it does not switch to a generated arena),
#     and 20 seconds of scripted play nothing breaks: riders come out of the door and stay in the room or its
#     recess, none is inside a wall or stuck, and the player stays inside
# Exits with status 1 and lists the first problems when a check fails.

const Room = preload("res://scripts/arena_training.gd")
const WorldTraining = preload("res://scripts/world_training.gd")
const Lighting = preload("res://scripts/lighting.gd")
const MAIN_SCENE = "res://main.tscn"
const SECONDS = 20.0
const DT = 1.0 / 60.0
const EPS = 0.001

var problems = []
var main = null


func _initialize() -> void:
	_check_arena()
	_check_world()
	await _check_game()
	if problems.is_empty():
		print(
			"training_room_check: the room, its world and its use in the game are as the roadmap describes"
		)
		quit(0)
	else:
		print("training_room_check: %d problem(s)" % problems.size())
		for p in problems.slice(0, 15):
			print("  " + p)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


# Mesh colours are stored with 8 bits per channel, so they come back rounded to 1/255.
func _same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


# ---------------------------------------------------------------- the arena
func _check_arena() -> void:
	var a = Room.new()
	var s = a.start_position()
	if not (absf(s.x) < Room.HALF_X and absf(s.z) < Room.HALF_Z and s.y == 0.0):
		_fail("the start %s is not on the floor of the room" % s)
	if a.ray_blocked(s + Vector3(0, 1.5, 0)) or a.obstacle_at(s) or a.rider_blocked(s):
		_fail("the start is inside something solid")
	if absf(a.start_to_door() - (Room.START_Z + Room.HALF_Z)) > EPS:
		_fail(
			(
				"start_to_door is %.2f, not the distance from the start to the far wall"
				% a.start_to_door()
			)
		)
	if a.fixed_lighting() != true:
		_fail("the room does not keep its own light")
	if a.style_label() == "" or a.style_name() == "":
		_fail("the room has no name for the screen")
	if not a.rider_pursuit() or not a.rider_avoidance():
		_fail("riders do not pursue and avoid walls in the room")
	if a.gates().size() != 1:
		_fail("the room has %d gates, expected the one door" % a.gates().size())
		return
	if (
		not a.cheer_spots(5).is_empty()
		or not a.cache_spots(3, s, RandomNumberGenerator.new()).is_empty()
	):
		_fail("the room has cheerleader spots or supply caches")
	# clamp_walk: every body, from far outside and from every side, ends inside by its own margin and moves nothing
	# that was already inside
	for who in ["player", "boss", "pickup"]:
		var m: float = Room.MARGINS[who]
		for p in [
			Vector3(99, 1, 0),
			Vector3(-99, 1, 0),
			Vector3(0, 1, 99),
			Vector3(0, 1, -99),
			Vector3(50, 1, 50)
		]:
			var c = a.clamp_walk(p, who)
			if absf(c.x) > Room.HALF_X - m + EPS or absf(c.z) > Room.HALF_Z - m + EPS or c.y != 1.0:
				_fail(
					(
						"clamp_walk(%s, %s) = %s: not inside by %.2f m, or the height changed"
						% [p, who, c, m]
					)
				)
		var inside = Vector3(1.5, 0.3, -2.5)
		if a.clamp_walk(inside, who) != inside:
			_fail("clamp_walk moved a point that is inside the room (%s)" % who)
	# a body pushing into a wall slides along it at full speed instead of stopping
	var from = Vector3(Room.HALF_X - 0.45, 0, 0)
	var slid = a.slide_walk(from, from + Vector3(1.0, 0, 2.0))
	if absf(slid.x - from.x) > EPS or absf(slid.z - 2.0) > EPS:
		_fail("a step into the side wall did not slide along it: %s" % slid)
	# darts: walls, ceiling and the far side of the door stop them, the open room and the door's recess do not
	var mid = Vector3(0, 1.5, 0)
	for p in [
		Vector3(Room.HALF_X + 0.1, 1.5, 0),
		Vector3(-Room.HALF_X - 0.1, 1.5, 0),
		Vector3(0, 1.5, Room.HALF_Z + 0.1),
		Vector3(5, 1.5, -Room.HALF_Z - 0.1),
		Vector3(0, Room.HEIGHT + 0.1, 0),
		Vector3(0, 1.5, -Room.HALF_Z - Room.DOOR_DEPTH - 0.1),
	]:
		if not a.ray_blocked(p):
			_fail("a dart at %s is not stopped" % p)
	for p in [mid, Vector3(9, 6.9, 13), Vector3(0, 1.5, -Room.HALF_Z - 1.0)]:
		if a.ray_blocked(p):
			_fail("a dart at %s is stopped in the open" % p)
	# the door: a rider may enter the recess, a boss may not; the recess hides, the room does not
	var door = a.gates()[0]
	if door["outward"] != Vector3(0, 0, -1) or not is_equal_approx(door["pos"].z, -Room.HALF_Z):
		_fail("the door is not in the middle of the far wall, facing out")
	var rider = Rider.new()
	var at: Vector3 = door["pos"] + door["outward"] * rider.GATE_SPAWN
	if not a.hidden_at(at) or a.rider_blocked(at) or a.rider_speed_at(at) <= 0.0:
		_fail("a rider's start at the door (%s) is not hidden ground it can ride on" % at)
	var out = false
	for i in range(1, int(14.0 / 0.25)):
		var p: Vector3 = at - door["outward"] * 0.25 * float(i)
		if a.rider_blocked(p) or a.rider_speed_at(p) <= 0.0:
			_fail("the straight ride out of the door is blocked at %s" % p)
			break
		if not a.hidden_at(p):
			out = true
			break
	if not out:
		_fail("a rider does not come out of the door within 14 m")
	if a.hidden_at(mid) or a.hidden_at(Vector3(0, 0, -Room.HALF_Z + 0.5)):
		_fail("the room itself hides a rider")
	if not a.obstacle_at(at) or a.obstacle_at(mid):
		_fail("a boss may enter the recess, or cannot stand in the room")
	if (
		a.surface_at(mid) != "plaza"
		or a.surface_at(at) != "tunnel"
		or a.surface_at(Vector3(40, 0, 0)) != "building"
	):
		_fail(
			"surface_at does not say plaza in the room, tunnel in the recess and building outside"
		)
	if (
		not a.rider_blocked(Vector3(5, 0, -Room.HALF_Z - 1.0))
		or a.rider_speed_at(Vector3(40, 0, 0)) != 0.0
	):
		_fail("a rider can ride outside the room beside the door")
	# the street stubs never leave the room and never fail
	for x in [-99.0, 0.0, 99.0]:
		for z in [-99.0, 0.0, 99.0]:
			var w = a.tw(x, z, 0.5)
			if absf(w.x) >= Room.HALF_X or absf(w.z) >= Room.HALF_Z or w.y != 0.5:
				_fail("tw(%s, %s) = %s is not inside the room" % [x, z, w])
	if a.to_track(Vector3(3, 0, 4)) != Vector2(3, 4):
		_fail("to_track is not (x, z)")
	if a.exit_distance(s, 1) <= 0.0:
		_fail("a rider at the start has no way out to give up through")
	if a.lim() <= 0.0 or a.player_lim() <= 0.0 or a.player_lim() > a.lim():
		_fail("lim %.1f and player_lim %.1f are not sensible" % [a.lim(), a.player_lim()])


# the one thing from riders.gd the arena check needs
class Rider:
	const GATE_SPAWN = preload("res://scripts/riders.gd").GATE_SPAWN


# ---------------------------------------------------------------- the world
func _check_world() -> void:
	var holder = Node3D.new()
	root.add_child(holder)
	var w = WorldTraining.build(holder, Room.new())
	for key in ["env", "sky_mat", "sun", "win_mat", "lamp_mat", "lamps", "tris", "draw_calls"]:
		if not w.has(key):
			_fail("the world has no %s" % key)
			return
	var env: Environment = w["env"]
	if env.background_mode != Environment.BG_COLOR or env.background_color.v > 0.1:
		_fail("the room's background is not a dark colour")
	if not env.glow_enabled or env.glow_hdr_threshold < 0.99:
		_fail("glow is off or too low for the edges to be the only glowing thing")
	if _count(holder, "WorldEnvironment") != 1 or _count(holder, "DirectionalLight3D") != 1:
		_fail("the world has not exactly one environment and one sun")
	if w["sun"].light_energy != 0.0 or w["sun"].visible:
		_fail("the sun shines in the room")
	if _count(holder, "OmniLight3D") > 4:
		_fail(
			"the room has more than 4 lights (the Compatibility renderer drops lights past 8 per mesh)"
		)
	if w["tris"] <= 0 or w["draw_calls"] <= 0 or w["draw_calls"] > 20:
		_fail("the world costs %d triangles and %d draw calls" % [w["tris"], w["draw_calls"]])
	var shell: MeshInstance3D = holder.get_node_or_null("Shell")
	var grid: MeshInstance3D = holder.get_node_or_null("Grid")
	var edges: MeshInstance3D = holder.get_node_or_null("Edges")
	var frame: MeshInstance3D = holder.get_node_or_null("DoorFrame")
	var ticks: MeshInstance3D = holder.get_node_or_null("DistanceLines")
	if shell == null or grid == null or edges == null or frame == null or ticks == null:
		_fail("the world is missing the shell, grid, edges, door frame or distance lines")
		root.remove_child(holder)
		holder.free()
		return
	_check_shell(shell.mesh)
	_check_grid(grid.mesh)
	_check_edges(edges, frame)
	_check_ticks(ticks.mesh, holder)
	root.remove_child(holder)
	holder.free()


func _count(node: Node, kind: String) -> int:
	var n = 1 if node.is_class(kind) else 0
	for c in node.get_children():
		n += _count(c, kind)
	return n


func _check_shell(mesh: ArrayMesh) -> void:
	var box = mesh.get_aabb()
	var want = AABB(
		Vector3(-Room.HALF_X, 0.0, -Room.HALF_Z - Room.DOOR_DEPTH),
		Vector3(Room.HALF_X * 2.0, Room.HEIGHT, Room.HALF_Z * 2.0 + Room.DOOR_DEPTH)
	)
	if not box.is_equal_approx(want):
		_fail("the shell is %s, not the room and its recess %s" % [box, want])
	var arrays = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var wrong_way = 0
	var across_door = 0
	for i in range(0, v.size(), 3):
		var cross = (v[i + 1] - v[i]).cross(v[i + 2] - v[i])
		# clockwise seen from the front means the right-hand normal points away from the viewer
		if cross.dot(n[i]) >= 0.0 or cross.length() < 0.0001:
			wrong_way += 1
		# a face of the far wall that covers the middle of the door
		if (
			absf(v[i].z + Room.HALF_Z) < EPS
			and absf(v[i + 1].z + Room.HALF_Z) < EPS
			and absf(v[i + 2].z + Room.HALF_Z) < EPS
		):
			if _in_triangle_xy(Vector2(0.0, 1.0), v[i], v[i + 1], v[i + 2]):
				across_door += 1
	if wrong_way > 0:
		_fail("%d triangle(s) of the shell face the wrong way or are empty" % wrong_way)
	if across_door > 0:
		_fail("a wall is drawn across the door")
	# every face points into the room or its recess: from the middle of the room (and the recess) the normal turns back
	for i in range(0, v.size(), 3):
		var centre = (v[i] + v[i + 1] + v[i + 2]) / 3.0
		var inside_pt = (
			Vector3(0.0, Room.DOOR_HEIGHT * 0.5, centre.z)
			if centre.z < -Room.HALF_Z
			else Vector3(0.0, Room.HEIGHT * 0.5, 0.0)
		)
		if (inside_pt - centre).dot(n[i]) < -EPS and absf(centre.x) < Room.HALF_X + 1.0:
			_fail("a face at %s has its normal pointing out of the room" % centre)
			break


func _in_triangle_xy(p: Vector2, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var pa = Vector2(a.x, a.y)
	var pb = Vector2(b.x, b.y)
	var pc = Vector2(c.x, c.y)
	var d1 = (p - pb).cross(pa - pb)
	var d2 = (p - pc).cross(pb - pc)
	var d3 = (p - pa).cross(pc - pa)
	var neg = d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var pos = d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (neg and pos)


func _check_grid(mesh: ArrayMesh) -> void:
	var box = mesh.get_aabb()
	var room = AABB(
		Vector3(-Room.HALF_X, 0.0, -Room.HALF_Z),
		Vector3(Room.HALF_X * 2.0, Room.HEIGHT, Room.HALF_Z * 2.0)
	)
	if not room.grow(EPS).encloses(box):
		_fail("the grid %s reaches outside the room %s" % [box, room])
	if mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_LINES:
		_fail("the grid is not made of lines")
	var arrays = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var lines = v.size() / 2
	# floor and ceiling alone are 2 * ((20 + 1) + (28 + 1)) lines; every wall adds more
	var floor_ceiling = 2 * (int(Room.HALF_X * 2.0) + 1 + int(Room.HALF_Z * 2.0) + 1)
	if lines <= floor_ceiling:
		_fail(
			(
				"the grid has %d lines, not enough for every surface (floor and ceiling alone are %d)"
				% [lines, floor_ceiling]
			)
		)
	# no line may cross the door's opening on the far wall
	for i in range(0, v.size(), 2):
		var a = v[i]
		var b = v[i + 1]
		if (
			absf(a.z + Room.HALF_Z) < 0.05
			and absf(b.z + Room.HALF_Z) < 0.05
			and a.y < Room.DOOR_HEIGHT - EPS
			and b.y < Room.DOOR_HEIGHT - EPS
		):
			var lo = minf(a.x, b.x)
			var hi = maxf(a.x, b.x)
			if (
				lo < Room.DOOR_HALF - EPS
				and hi > -Room.DOOR_HALF + EPS
				and not (hi <= -Room.DOOR_HALF + EPS or lo >= Room.DOOR_HALF - EPS)
			):
				_fail("a grid line crosses the door opening: %s to %s" % [a, b])
				break
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var major = 0
	var minor = 0
	for c in colors:
		if _same(c, WorldTraining.GRID_MAJOR):
			major += 1
		elif _same(c, WorldTraining.GRID_MINOR):
			minor += 1
	if major == 0 or minor <= major:
		_fail(
			(
				"the grid has %d bright and %d faint line ends: a faint line every metre, a bright one every 4 m"
				% [major, minor]
			)
		)


func _check_edges(edges: MeshInstance3D, frame: MeshInstance3D) -> void:
	for pair in [
		[edges, WorldTraining.EDGE_GLOW, "edges"], [frame, WorldTraining.DOOR_GLOW, "door frame"]
	]:
		var mat: StandardMaterial3D = pair[0].material_override
		if not mat.emission_enabled or mat.emission_energy_multiplier <= 1.0:
			_fail("the %s do not glow above the glow threshold of 1.0" % pair[2])
	var box = edges.mesh.get_aabb()
	var room = AABB(
		Vector3(-Room.HALF_X, 0.0, -Room.HALF_Z),
		Vector3(Room.HALF_X * 2.0, Room.HEIGHT, Room.HALF_Z * 2.0)
	)
	if not box.is_equal_approx(room):
		_fail("the glowing edges are %s, not the box of the room %s" % [box, room])
	# a bar along each of the 12 edges: every one of them has a bar that contains its middle (the far floor edge,
	# which the door cuts, has its two pieces, so its middle is the door and is not lit)
	var mids = []
	for sy in [0.0, Room.HEIGHT]:
		for sz in [-1.0, 1.0]:
			mids.append(Vector3(0.0, sy, sz * Room.HALF_Z))
		for sx in [-1.0, 1.0]:
			mids.append(Vector3(sx * Room.HALF_X, sy, 0.0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mids.append(Vector3(sx * Room.HALF_X, Room.HEIGHT * 0.5, sz * Room.HALF_Z))
	var bars = WorldTraining.edge_bars()
	var lit = 0
	for m in mids:
		var hit = false
		for bar in bars:
			var bb = AABB(bar["at"] - bar["size"] * 0.5, bar["size"]).grow(WorldTraining.EDGE_THICK)
			if bb.has_point(m):
				hit = true
				break
		if m.is_equal_approx(Vector3(0.0, 0.0, -Room.HALF_Z)):
			if hit:
				_fail("a glowing bar crosses the door at the floor")
			lit += 1  # the door interrupts this edge, the two pieces beside it are checked below
		elif hit:
			lit += 1
		else:
			_fail("no glowing edge at the middle of the edge at %s" % m)
	if lit != 12:
		_fail("%d of the 12 edges glow" % lit)
	for s in [-1.0, 1.0]:
		var piece = Vector3(s * (Room.DOOR_HALF + 1.0), 0.0, -Room.HALF_Z)
		var covered = false
		for bar in bars:
			if (
				AABB(bar["at"] - bar["size"] * 0.5, bar["size"])
				. grow(WorldTraining.EDGE_THICK)
				. has_point(piece)
			):
				covered = true
		if not covered:
			_fail("the far floor edge has no glowing piece beside the door at %s" % piece)
	var fb = frame.mesh.get_aabb()
	if (
		absf(fb.position.x + Room.DOOR_HALF + WorldTraining.EDGE_THICK) > 0.02
		or fb.end.y < Room.DOOR_HEIGHT
	):
		_fail("the door frame %s does not go round the door" % fb)


func _check_ticks(mesh: ArrayMesh, holder: Node3D) -> void:
	var v: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var zs = {}
	for p in v:
		zs[snappedf(p.z, 0.5)] = true
	if zs.size() != WorldTraining.TICKS + 1:
		_fail("the floor has %d distance lines, expected %d" % [zs.size(), WorldTraining.TICKS + 1])
	for i in range(WorldTraining.TICKS + 1):
		var want_z = Room.START_Z - float(i) * WorldTraining.TICK_EVERY
		if not zs.has(snappedf(want_z, 0.5)):
			_fail(
				"no distance line at %.1f m from the start" % (float(i) * WorldTraining.TICK_EVERY)
			)
		var lb: Label3D = holder.get_node_or_null("DistanceLabel%d" % i)
		if lb == null:
			_fail("no number for distance line %d" % i)
			continue
		var want_text = "START" if i == 0 else "%d M" % int(float(i) * WorldTraining.TICK_EVERY)
		if lb.text != want_text or absf(lb.position.z - want_z) > 1.0 or lb.position.y < 0.0:
			_fail("the number at line %d says '%s' at %s" % [i, lb.text, lb.position])
		if absf(lb.position.x) > Room.HALF_X:
			_fail("the number at line %d is outside the room" % i)
	# the farthest line is still inside the room (a line beyond the far wall would be a mistake in TICKS)
	if Room.START_Z - float(WorldTraining.TICKS) * WorldTraining.TICK_EVERY < -Room.HALF_Z:
		_fail("a distance line is beyond the far wall")


# ---------------------------------------------------------------- main.gd
func _check_game() -> void:
	var main_script = load("res://scripts/main.gd")
	var none = PackedStringArray()
	var asks = PackedStringArray(["--training-room"])
	var cases = [
		["the game with no arguments", none, true, false, false],
		["the game with --training-room", asks, true, false, true],
		[
			"the game with --training-room and --roundabout",
			PackedStringArray(["--roundabout", "--training-room"]),
			true,
			false,
			true
		],
		["a check's main", none, false, false, false],
		["a check's main that asks for the room", none, false, true, true],
		["--training-room on a check's main without the flag", asks, false, false, false],
	]
	for c in cases:
		var got = main_script.wants_training_room(c[1], c[2], c[3])
		if got != c[4]:
			_fail("%s: the training room is %s, expected %s" % [c[0], got, c[4]])
	main = load(MAIN_SCENE).instantiate()
	main.generated_arena = true  # as in the game, so a run would switch to a generated arena if it were allowed to
	main.training_room = true
	root.add_child(main)
	for i in range(3):
		await process_frame
	if main.arena.get_script().resource_path != "res://scripts/arena_training.gd":
		_fail(
			"the game's arena is %s, not the training room" % main.arena.get_script().resource_path
		)
		return
	if (
		main.world_root == null
		or _count(main, "WorldEnvironment") != 1
		or _count(main, "DirectionalLight3D") < 1
	):
		_fail("the title screen has no single world of the room")
	if main.player.position != main.arena.start_position():
		_fail("on the title screen the player is not on the start")
	for c in main.cheerleaders:
		if c["root"].visible:
			_fail("a cheerleader stands in the training room")
			break
	_check_theme_untouched()
	_check_run()


# every theme of a round leaves the room's light as it is
func _check_theme_untouched() -> void:
	var env: Environment = main.world["env"]
	var before = [
		env.ambient_light_color,
		env.ambient_light_energy,
		env.background_color,
		main.world["sun"].light_energy
	]
	for i in range(main.THEMES.size()):
		main.apply_theme(i)
		var after = [
			env.ambient_light_color,
			env.ambient_light_energy,
			env.background_color,
			main.world["sun"].light_energy
		]
		if after != before:
			_fail("theme %d changed the light of the training room" % i)
			return
	# and the same call does change a world that does not keep its own light, so the check above could fail
	var plain = Room.new()
	if (
		plain.fixed_lighting() != true
		or load("res://scripts/arena.gd").new().fixed_lighting() != false
	):
		_fail("fixed_lighting is not true for the room and false for the base arena")


func _check_run() -> void:
	var world_before = main.world_root
	main.start_game(false, 12345)
	if (
		main.arena.get_script().resource_path != "res://scripts/arena_training.gd"
		or main.world_root != world_before
	):
		_fail("starting a run switched away from the training room")
		return
	if main.player.position != main.arena.start_position():
		_fail("a run did not start on the room's start")
	if main.state != "map":
		_fail("a new run did not open the map screen (state %s)" % main.state)
		return
	main.pick_node(0)
	if main.state != "play":
		_fail("picking a node did not start the round (state %s)" % main.state)
		return
	main.force_captured = true  # headless cannot capture the mouse; without this the game counts as paused
	var frames = int(SECONDS / DT)
	var seen = {}
	var shots = 0
	var problems_before = problems.size()
	for f in range(frames):
		if main.state != "play":
			break
		var ang = float(f) * 0.015
		main.player.position = main.clamp_walk(
			Vector3(0.0, 0.0, 4.0) + Vector3(cos(ang), 0.0, sin(ang)) * 4.0
		)
		var target = _nearest_rider(main.player.position)
		if target != null:
			var to: Vector3 = target["pos"] + Vector3(0.0, 1.0, 0.0) - main.cam.global_position
			main.yaw = atan2(-to.x, -to.z)
			main.pitch = atan2(to.y, Vector2(to.x, to.z).length())
		else:
			main.yaw = 0.3 * sin(float(f) * 0.02)  # sweep the far wall so the shots hit walls
			main.pitch = 0.0
		if f % 24 == 0:
			var before = main.shells
			main.combat_sys.fire()
			if main.shells < before:
				shots += 1
		main._process(DT)
		if f % 5 == 0:
			_sample(f, seen)
			if problems.size() > problems_before + 12:
				break
	if seen.is_empty():
		_fail("no rider came out of the door in %.0f seconds" % SECONDS)
	if shots == 0:
		_fail("no shot was fired in the room")
	var pp: Vector3 = main.player.position
	if not _finite(pp) or main.arena.obstacle_at(pp):
		_fail("the player ended at %s, not on the floor of the room" % pp)
	print(
		"training_room_check: %d riders seen, %d shots, state %s" % [seen.size(), shots, main.state]
	)


func _nearest_rider(from: Vector3):
	var best = null
	var best_d = INF
	for r in main.riders:
		if r.get("hidden", false) or r.get("gone", false):
			continue
		var d = Vector2(r["pos"].x - from.x, r["pos"].z - from.z).length()
		if d < best_d:
			best_d = d
			best = r
	return best


func _sample(f: int, seen: Dictionary) -> void:
	var arena = main.arena
	var pp: Vector3 = main.player.position
	if not _finite(pp) or arena.obstacle_at(pp):
		_fail("frame %d: the player is at %s, not on the floor of the room" % [f, pp])
	for r in main.riders:
		var p: Vector3 = r["pos"]
		if (
			not _finite(p)
			or absf(p.x) > Room.HALF_X + 1.0
			or p.z > Room.HALF_Z + 1.0
			or p.z < -Room.HALF_Z - Room.DOOR_DEPTH
		):
			_fail("frame %d: a rider is at %s, away from the room" % [f, p])
			continue
		if not seen.has(r["idx"]):
			seen[r["idx"]] = true
			if (
				Vector2(arena.gates()[0]["pos"].x - p.x, arena.gates()[0]["pos"].z - p.z).length()
				> 9.0
			):
				_fail("frame %d: a new rider is not near the door (%s)" % [f, p])
		if not r["entered"] and r["age"] > 6.0:
			_fail(
				"frame %d: a rider has been stuck in the door's recess for %.1f s" % [f, r["age"]]
			)
		if not r["hidden"] and arena.rider_blocked(p):
			_fail("frame %d: a rider is inside a wall at %s" % [f, p])
	for b in main.bosses:
		var bp: Vector3 = b["wp"]
		if not _finite(bp) or absf(bp.x) > Room.HALF_X + 1.0 or absf(bp.z) > Room.HALF_Z + 1.0:
			_fail("frame %d: a boss is at %s, away from the room" % [f, bp])
