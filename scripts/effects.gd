extends RefCounted
# Effects: pooled particles, bursts, plastic debris and confetti.
# Shared game state stays on main.gd (g); this file holds the logic.

const Util = preload("res://scripts/util.gd")

var g = null
var particle_pool = []
var shell_mesh: Mesh = null            # the shell model's mesh, taken from assets/models/shell.glb the first time it is needed
var shell_mesh_tried = false

const SHELL_MODEL_PATH = "res://assets/models/shell.glb"

func _init(game) -> void:
	g = game

func spawn_particle(pos: Vector3, vel: Vector3, life: float, m: Material, sz: Vector3, grav: float, spin: float = 0.0, custom_mesh: Mesh = null) -> void:
	var mi: MeshInstance3D
	if particle_pool.size() > 0:
		mi = particle_pool.pop_back()
		mi.visible = true
		mi.scale = Vector3.ONE
		mi.rotation = Vector3.ZERO
	else:
		mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(mi)
	if custom_mesh != null:
		mi.mesh = custom_mesh                  # a modelled mesh brings its own materials
		mi.material_override = null
	else:
		mi.mesh = Util.box_mesh(sz)
		mi.material_override = m
	mi.position = pos
	g.particles.append({"node": mi, "vel": vel, "life": life, "max": life, "grav": grav, "spin": spin})
	while g.particles.size() > 300:
		release_particle(g.particles[0]["node"])
		g.particles.remove_at(0)

# An empty shell thrown out of the gun (shell.glb), tumbling until it lands. Without the model it is a small red block.
func spawn_shell(pos: Vector3, vel: Vector3) -> void:
	var m = get_shell_mesh()
	if m == null:
		spawn_particle(pos, vel, 1.4, g.col_mat("#e5392b"), Vector3(0.03, 0.03, 0.07), 9.8, 14.0)
	else:
		spawn_particle(pos, vel, 1.4, null, Vector3.ONE, 9.8, 14.0, m)
	g.particles[g.particles.size() - 1]["settle"] = true

func get_shell_mesh() -> Mesh:
	if shell_mesh_tried:
		return shell_mesh
	shell_mesh_tried = true
	if not ResourceLoader.exists(SHELL_MODEL_PATH):
		return null
	var scene = load(SHELL_MODEL_PATH)
	if not (scene is PackedScene):
		return null
	var inst: Node = scene.instantiate()
	var mi = _first_mesh(inst)
	if mi != null:
		shell_mesh = mi.mesh
	inst.free()
	return shell_mesh

func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r = _first_mesh(c)
		if r != null:
			return r
	return null

func release_particle(node: Node3D) -> void:
	node.visible = false
	particle_pool.append(node)

func update_particles(dt: float) -> void:
	for i in range(g.particles.size() - 1, -1, -1):
		var p = g.particles[i]
		p["life"] -= dt
		var node: Node3D = p["node"]
		if p["life"] <= 0.0:
			release_particle(node)
			g.particles.remove_at(i)
			continue
		var v: Vector3 = p["vel"]
		v.y -= p["grav"] * dt
		p["vel"] = v
		node.position += v * dt
		if node.position.y < 0.02:
			node.position = Vector3(node.position.x, 0.02, node.position.z)
			p["vel"] = Vector3(v.x * 0.3, 0.0, v.z * 0.3)
			if p.get("settle", false):
				p["spin"] = 0.0                        # a shell stops tumbling when it lands, lies flat and then shrinks away
				p["settle"] = false
				node.rotation = Vector3(0.0, node.rotation.y, 0.0)
		if p["spin"] != 0.0:
			node.rotation += Vector3(p["spin"], p["spin"] * 0.7, 0.0) * dt
		else:
			var f = clampf(p["life"] / p["max"], 0.05, 1.0)
			node.scale = Vector3(f, f, f)

func burst(pos: Vector3, count: int, cols: Array, speed: float, life_lo: float, life_hi: float, size: float) -> void:
	for i in range(count):
		spawn_particle(pos + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3)),
			Vector3(randf_range(-speed, speed), randf_range(0.5, speed * 1.2), randf_range(-speed, speed)),
			randf_range(life_lo, life_hi), g.col_mat(g.pick_one(cols)), Vector3(size, size, size), 10.0)

func plastic_burst(pos: Vector3) -> void:
	burst(pos, 14, ["#2b2f36", "#3a3f47", "#3fa0ff", "#c9ced4"], 4.0, 0.5, 0.8, 0.07)

func confetti() -> void:
	for i in range(70):
		var pos = Vector3(randf_range(-12.0, 12.0), randf_range(5.0, 9.0), randf_range(-9.0, 2.0))
		spawn_particle(pos, Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 0.5), randf_range(-1.0, 1.0)),
			randf_range(2.5, 4.0), g.pick_one(g.confetti_mats), Vector3(0.14, 0.01, 0.09), 1.5, randf_range(-8.0, 8.0))
