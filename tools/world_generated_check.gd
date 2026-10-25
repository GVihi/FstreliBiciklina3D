extends SceneTree
# Checks the world built for a generated arena (README Milestone K, "Generated arena class": build the world from
# the arena). Run from the project folder:
#   godot --headless --path . --script res://tools/world_generated_check.gd
# Optional argument after "--": how many seeds to try (default 40).
# For every seed it builds WorldGenerated for a GeneratedArena and checks that
#   - the result has the keys and kinds main.gd and Lighting.apply_theme use for the roundabout's world
#     (env, sky_mat, sun, win_mat, lamp_mat, lamps), plus the cost (tris, draw_calls)
#   - the environment sits in a WorldEnvironment and the sun is a child of the root, the lamp lights are hidden
#     children of the root, one per lamp WorldDress places, and the windows and lamp heads start dark
#   - the cost is true: draw_calls is the number of mesh instances and tris the number of triangles in them
#   - the ground reaches past the buildings (a plane below the ground, wider than the arena), and nothing else
#     is outside the arena or taller than a building
#   - building it again gives the same world (same nodes, places and sizes)
#   - every theme in Content.THEMES applies through Lighting.apply_theme: the sun is the theme's, and a theme
#     with lamps turns on min(Lighting.MAX_LAMP_LIGHTS, lamps) lights, one without turns none on
# Exits with status 1 and prints the first problems.

const ArenaGen = preload("res://scripts/arena_gen.gd")
const GeneratedArena = preload("res://scripts/arena_generated.gd")
const WorldGenerated = preload("res://scripts/world_generated.gd")
const WorldDress = preload("res://scripts/world_dress.gd")
const Lighting = preload("res://scripts/lighting.gd")
const Content = preload("res://scripts/content.gd")

const MAX_HEIGHT = 16.0  # the tallest thing is a building: 15 m for the bridge girders, 16 m is the most a style may ask

var problems = []


func _initialize() -> void:
	var count = 40
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		count = int(args[0])
	var rules = ArenaGen.load_rules()
	if rules.is_empty():
		quit(1)
		return
	var built = 0
	for k in range(count):
		var seed_value = (k * 2654435761 + 99) & 0xFFFFFFFF
		var layout = ArenaGen.generate(seed_value, rules)
		if layout.is_empty():
			problems.append("seed %08X: no layout" % seed_value)
			continue
		var arena = GeneratedArena.new(layout, rules)
		var root = Node3D.new()
		var world = WorldGenerated.build(root, arena)
		for p in _verify(world, root, arena):
			problems.append("seed %08X: %s" % [seed_value, p])
		var root2 = Node3D.new()
		WorldGenerated.build(root2, arena)
		if _fingerprint(root) != _fingerprint(root2):
			problems.append(
				"seed %08X: building the same arena twice gave different worlds" % seed_value
			)
		if world.has("sun") and world.has("lamps") and world.has("sky_mat") and world.has("env"):
			if world.has("win_mat") and world.has("lamp_mat"):
				for p in _check_themes(world, arena):
					problems.append("seed %08X: %s" % [seed_value, p])
		root.free()
		root2.free()
		built += 1
	if problems.size() > 0:
		print("world_generated_check: %d problem(s)" % problems.size())
		for p in problems.slice(0, 12):
			print("  " + p)
		quit(1)
		return
	print("world_generated_check: %d generated worlds are built as the game expects" % built)
	quit(0)


func _verify(world: Dictionary, root: Node3D, arena) -> Array:
	var bad = []
	var kinds = {
		"env": "Environment",
		"sky_mat": "ProceduralSkyMaterial",
		"sun": "DirectionalLight3D",
		"win_mat": "StandardMaterial3D",
		"lamp_mat": "StandardMaterial3D"
	}
	for key in kinds:
		if not world.has(key) or not is_instance_of(world[key], _class(kinds[key])):
			bad.append("the world has no %s (a %s)" % [key, kinds[key]])
	for key in ["lamps", "tris", "draw_calls"]:
		if not world.has(key):
			bad.append("the world has no %s" % key)
	if not bad.is_empty():
		return bad
	# the nodes the game needs in the tree
	var found_env = false
	for c in root.get_children():
		if c is WorldEnvironment and c.environment == world["env"]:
			found_env = true
	if not found_env:
		bad.append("no WorldEnvironment with the world's environment under the root")
	if world["sun"].get_parent() != root:
		bad.append("the sun is not a child of the root")
	var placed = WorldDress.props_of(arena.layout)["lamps"].size()
	var lamps: Array = world["lamps"]
	if lamps.size() != placed:
		bad.append("%d lamp lights for %d lamps" % [lamps.size(), placed])
	for l in lamps:
		if not l is OmniLight3D or not root.is_ancestor_of(l):
			bad.append("a lamp light is not an OmniLight3D under the root")
			break
		if l.visible:
			bad.append("a lamp light starts on")
			break
	if world["win_mat"].emission_energy_multiplier != 0.0:
		bad.append("the windows start lit")
	if world["lamp_mat"].emission_energy_multiplier != 0.0:
		bad.append("the lamp heads start lit")
	# what it costs, and where everything is
	var meshes = _meshes(root)
	var tris = 0
	var half = float(arena.layout["cells"]) * float(arena.layout["cell"]) / 2.0
	var skirt: MeshInstance3D = null  # the big plane under the ground
	for mi in meshes:
		tris += mi.mesh.get_faces().size() / 3
		if mi.mesh.get_aabb().size.x > half * 2.0 + 50.0:
			skirt = mi
			continue
		var box = mi.mesh.get_aabb()
		var lo = box.position + mi.position
		var hi = box.end + mi.position
		if lo.x < -half - 0.5 or hi.x > half + 0.5 or lo.z < -half - 0.5 or hi.z > half + 0.5:
			bad.append("%s reaches outside the arena (%s to %s)" % [mi.name, lo, hi])
		if lo.y < -0.2 or hi.y > MAX_HEIGHT:
			bad.append("%s is at a strange height (%.2f to %.2f)" % [mi.name, lo.y, hi.y])
	if meshes.size() != int(world["draw_calls"]):
		bad.append(
			"draw_calls says %d, there are %d mesh instances" % [world["draw_calls"], meshes.size()]
		)
	if tris != int(world["tris"]):
		bad.append("tris says %d, the meshes have %d" % [world["tris"], tris])
	if skirt == null:
		bad.append("no ground out to the horizon: no plane wider than the arena")
	else:
		var box = skirt.mesh.get_aabb()
		if box.size.x < half * 2.0 + 100.0 or box.size.z < half * 2.0 + 100.0:
			bad.append(
				(
					"the ground plane is only %.0f m wide, the arena is %.0f m"
					% [box.size.x, half * 2.0]
				)
			)
		if skirt.position.y + box.end.y > -0.05:
			bad.append(
				(
					"the ground plane is not below the ground (its top is at %.2f)"
					% (skirt.position.y + box.end.y)
				)
			)
	return bad


func _check_themes(world: Dictionary, arena) -> Array:
	var bad = []
	var at = arena.layout["start"]["pos"]
	var focus = Vector3(float(at[0]), 0.0, float(at[1]))
	var lamps: Array = world["lamps"]
	for th in Content.THEMES:
		Lighting.apply_theme(th, world, focus)
		if absf(world["sun"].light_energy - float(th["sun_e"])) > 0.001:
			bad.append(
				(
					"%s: the sun is %.2f, the theme says %.2f"
					% [th["name"], world["sun"].light_energy, th["sun_e"]]
				)
			)
		var on = 0
		for l in lamps:
			if l.visible:
				on += 1
		var want = mini(Lighting.MAX_LAMP_LIGHTS, lamps.size()) if th["lamps"] else 0
		if on != want:
			bad.append("%s: %d lamp lights on, expected %d" % [th["name"], on, want])
	return bad


func _meshes(node: Node) -> Array:
	var out = []
	for c in node.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_meshes(c))
	return out


# a text that is the same for two builds of the same world: the kinds, places and sizes of all nodes
func _fingerprint(node: Node) -> String:
	var parts = []
	for c in node.get_children():
		var s = c.get_class()
		if c is Node3D:
			s += " %s" % c.position
		if c is MeshInstance3D:
			s += " %d %s" % [c.mesh.get_faces().size(), c.mesh.get_aabb()]
		parts.append(s + "{" + _fingerprint(c) + "}")
	return ",".join(parts)


func _class(kind: String):
	match kind:
		"Environment":
			return Environment
		"ProceduralSkyMaterial":
			return ProceduralSkyMaterial
		"DirectionalLight3D":
			return DirectionalLight3D
	return StandardMaterial3D
