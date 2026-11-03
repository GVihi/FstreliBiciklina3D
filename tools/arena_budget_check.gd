extends SceneTree
# Checks the performance budget of docs/PERFORMANCE_BUDGET.md (numbers in data/performance_budget.json) against
# what the game builds, and prints what each arena style costs. It measures content, not frame time: no GPU is
# needed, so it runs headless, and a frame time on the minimum-spec machine is still the owner's check.
#   godot --headless --path . --script res://tools/arena_budget_check.gd
# Optional argument after "--": how many seeds to build (default 40).
# What it checks, over the seeds: the whole world (ground, dressing and modelled buildings, benches and crates)
# stays under the triangle and draw call budget, and the lamp lights that can come on and the sun shadow
# settings (one split, short distance, the only light that casts shadows) and the camera's far plane
# (`cam.far` in scripts/main.gd) match the budget. Entity triangles (riders, bosses, pedestrians, viewmodel) and
# particles are not measured here.

const ArenaGen = preload("res://scripts/arena_gen.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const WorldDress = preload("res://scripts/world_dress.gd")
const WorldModels = preload("res://scripts/world_models.gd")
const Lighting = preload("res://scripts/lighting.gd")

const BUDGET_PATH = "res://data/performance_budget.json"
const MAIN_PATH = "res://scripts/main.gd"

var problems: Array = []


func _initialize() -> void:
	var count = 40
	var args = OS.get_cmdline_user_args()
	if args.size() > 0:
		count = int(args[0])
	var budget = _load_budget()
	if budget.is_empty():
		print("FAIL: %s is missing or not a budget" % BUDGET_PATH)
		quit(1)
		return
	_check_lights_and_shadows(budget)
	_check_draw_distance(budget)
	var summary = _check_arenas(budget, count)
	if problems.is_empty():
		print(
			(
				"arena_budget_check: %d arenas under budget; %s"
				% [count, "; ".join(PackedStringArray(summary))]
			)
		)
		quit(0)
	else:
		for i in range(mini(problems.size(), 20)):
			print("FAIL: " + problems[i])
		print("arena_budget_check: %d problems" % problems.size())
		quit(1)


func _load_budget() -> Dictionary:
	var f = FileAccess.open(BUDGET_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	for key in ["world", "lights", "shadows", "draw_distance_m"]:
		if not parsed.has(key):
			return {}
	return parsed


func _check_lights_and_shadows(budget: Dictionary) -> void:
	var lights = budget["lights"]
	if Lighting.MAX_LAMP_LIGHTS > int(lights["lamp_lights_on_max"]):
		problems.append(
			(
				"Lighting.MAX_LAMP_LIGHTS is %d, the budget allows %d lamp lights on at once"
				% [Lighting.MAX_LAMP_LIGHTS, int(lights["lamp_lights_on_max"])]
			)
		)
	var sun = DirectionalLight3D.new()
	Lighting.setup_sun(sun)
	var shadows = budget["shadows"]
	var splits = 1 if sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL else 4
	if splits > int(shadows["sun_splits"]):
		problems.append(
			(
				"the sun draws its shadow in %d splits, the budget allows %d"
				% [splits, int(shadows["sun_splits"])]
			)
		)
	if sun.directional_shadow_max_distance > float(shadows["sun_max_distance_m"]):
		problems.append(
			(
				"the sun's shadow reaches %.0f m, the budget allows %.0f m"
				% [sun.directional_shadow_max_distance, float(shadows["sun_max_distance_m"])]
			)
		)
	sun.free()
	# the only light that casts shadows is the sun: no lamp or effect light may turn shadows on
	for path in [
		"res://scripts/world_dress.gd", "res://scripts/world.gd", "res://scripts/models.gd"
	]:
		var text = FileAccess.get_file_as_string(path)
		if text.find("shadow_enabled = true") != -1:
			problems.append(
				"%s turns a light's shadow on; the budget allows the sun's shadow only" % path
			)


func _check_draw_distance(budget: Dictionary) -> void:
	var text = FileAccess.get_file_as_string(MAIN_PATH)
	var re = RegEx.new()
	re.compile("cam\\.far\\s*=\\s*([0-9.]+)")
	var m = re.search(text)
	if m == null:
		problems.append(
			"could not find `cam.far = ...` in %s to check the draw distance" % MAIN_PATH
		)
		return
	var far = float(m.get_string(1))
	if far > float(budget["draw_distance_m"]):
		problems.append(
			(
				"the camera far plane is %.0f m, the budget allows %.0f m"
				% [far, float(budget["draw_distance_m"])]
			)
		)


# Builds the whole world of `count` seeds like WorldGenerated does and returns one summary line per style.
func _check_arenas(budget: Dictionary, count: int) -> Array:
	var tri_budget = int(budget["world"]["triangles_max"])
	var call_budget = int(budget["world"]["draw_calls_max"])
	var rules = ArenaGen.load_rules()
	var per_style = {}
	for k in range(count):
		var seed_value = (k * 2654435761 + 777) & 0xFFFFFFFF
		var layout = ArenaGen.generate(seed_value, rules)
		if layout.is_empty():
			problems.append("seed %08X: no layout was generated" % seed_value)
			continue
		var ground = WorldGen.build_ground(layout)
		var planned = WorldModels.plan(layout)
		var dressed = WorldDress.build(layout, WorldModels.skipped_lots(planned))
		var holder = Node3D.new()
		var models = WorldModels.build(holder, planned)
		var tris = int(ground["tris"]) + int(dressed["tris"]) + int(models["tris"])
		var calls = (
			int(ground["draw_calls"]) + int(dressed["draw_calls"]) + int(models["draw_calls"])
		)
		var lamps = (dressed["lamps"] as Array).size()
		var style = String(layout.get("style", ""))
		if tris > tri_budget:
			problems.append(
				(
					"seed %08X (%s): %d triangles, the budget allows %d"
					% [seed_value, style, tris, tri_budget]
				)
			)
		if calls > call_budget:
			problems.append(
				(
					"seed %08X (%s): %d draw calls, the budget allows %d"
					% [seed_value, style, calls, call_budget]
				)
			)
		if not per_style.has(style):
			per_style[style] = {"n": 0, "tri_max": 0, "calls_max": 0, "lamps_max": 0}
		var s = per_style[style]
		s["n"] += 1
		s["tri_max"] = maxi(s["tri_max"], tris)
		s["calls_max"] = maxi(s["calls_max"], calls)
		s["lamps_max"] = maxi(s["lamps_max"], lamps)
		ground["root"].free()
		dressed["root"].free()
		holder.free()
	var lines = []
	for style in per_style:
		var s = per_style[style]
		lines.append(
			(
				"%s %d arenas, at most %d triangles, %d draw calls, %d lamps"
				% [style, s["n"], s["tri_max"], s["calls_max"], s["lamps_max"]]
			)
		)
	return lines
