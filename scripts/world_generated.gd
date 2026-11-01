extends RefCounted
# Builds the world of a generated arena (README Milestone K, "Generated arena class": build the world from the
# arena). It is the generated arena's counterpart of world.gd and has the same shape: build(root, arena) adds
# the sky, the sun, the ground and everything standing on it to root and returns the dictionary main.gd and
# Lighting.apply_theme work on.
#
#   "env", "sky_mat", "sun"    the environment, its sky and the sun (Lighting.make_environment, Lighting.setup_sun)
#   "win_mat", "lamp_mat"      the materials of the windows and the lamp heads (the theme sets their glow)
#   "lamps"                    the hidden lamp lights, one per lamp (the theme turns some on)
#   "tris", "draw_calls"       what the ground and the boxes of the world cost: triangles and mesh instances
#   "model_tris", "model_draw_calls"   what the models of world_models.gd cost (MultiMeshes), counted apart
#
# Everything is made from the arena's layout alone (WorldGen for the ground, WorldDress for buildings, tunnels,
# lamps and trees, WorldModels for the modelled buildings, benches and crates), so one arena gives one world. The world starts dark: call Lighting.apply_theme with a theme
# (and the start as the focus) to light it. Not used by the game yet; main.gd switches to it in the next step.

const WorldGen = preload("res://scripts/world_gen.gd")
const WorldDress = preload("res://scripts/world_dress.gd")
const WorldModels = preload("res://scripts/world_models.gd")
const Lighting = preload("res://scripts/lighting.gd")


static func build(root: Node3D, arena) -> Dictionary:
	var layout: Dictionary = arena.layout
	if layout.is_empty():
		push_error("world_generated: the arena has no layout")
		return {}
	var out = {}

	# ---------- environment + sun ----------
	var made = Lighting.make_environment()
	var we = WorldEnvironment.new()
	we.environment = made["env"]
	root.add_child(we)
	var sun = DirectionalLight3D.new()
	Lighting.setup_sun(sun)
	root.add_child(sun)
	out["env"] = made["env"]
	out["sky_mat"] = made["sky_mat"]
	out["sun"] = sun

	# ---------- the ground (WorldGen also lays a big plane under it, so no gap shows the sky) ----------
	var ground = WorldGen.build_ground(layout)
	root.add_child(ground["root"])

	# ---------- buildings, tunnels, lamps and trees ----------
	var planned = WorldModels.plan(layout)  # lots that become modelled buildings, benches and crates
	var dressed = WorldDress.build(layout, WorldModels.skipped_lots(planned))
	root.add_child(dressed["root"])
	out["win_mat"] = dressed["win_mat"]
	out["lamp_mat"] = dressed["lamp_mat"]
	out["lamps"] = dressed["lamps"]

	out["tris"] = int(ground["tris"]) + int(dressed["tris"])
	out["draw_calls"] = int(ground["draw_calls"]) + int(dressed["draw_calls"])

	# ---------- the modelled buildings, benches and crates (what they cost is counted apart) ----------
	var models = WorldModels.build(root, planned)
	out["models"] = models
	out["model_tris"] = int(models["tris"])
	out["model_draw_calls"] = int(models["draw_calls"])
	return out
