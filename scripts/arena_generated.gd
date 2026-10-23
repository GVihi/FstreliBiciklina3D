extends "res://scripts/arena.gd"
# A generated arena (README Milestone K): the Arena interface on top of a layout from arena_gen.gd. It is built
# in small steps; this file says in each section what is done. Everything here reads only the layout and the
# arena rules, so one seed gives one arena. Not used by the game yet (see docs/PROCEDURAL_ARENAS.md).

const ArenaGenScript = preload("res://scripts/arena_gen.gd")

var layout: Dictionary = {}
var rules: Dictionary = {}
var _gates: Array = []


func _init(the_layout: Dictionary = {}, the_rules: Dictionary = {}) -> void:
	layout = the_layout
	rules = the_rules if not the_rules.is_empty() else ArenaGenScript.load_rules()
	_gates = _world_gates()


# ---------------------------------------------------------------- the ground
# what the ground is at world point p: "grass", "plaza", "sidewalk", "road", "tunnel" or "building"
func surface_at(p: Vector3) -> String:
	return ArenaGenScript.surface_at(layout, p.x, p.z)


# the share of its speed a rider keeps on the ground at p (0 where nothing can ride)
func rider_speed_at(p: Vector3) -> float:
	return ArenaGenScript.rider_speed_at(layout, rules, p.x, p.z)


# true: riders chase the player over open ground and steer round obstacles themselves
func rider_pursuit() -> bool:
	return true


func rider_avoidance() -> bool:
	return true


# ---------------------------------------------------------------- the start and the gates
# the middle of the clear start area, on the ground
func start_position() -> Vector3:
	var s = layout["start"]["pos"]
	return Vector3(float(s[0]), 0.0, float(s[1]))


# where riders enter and leave, in world space (see Arena.gates)
func gates() -> Array:
	return _gates


func _world_gates() -> Array:
	var out = []
	for gate in layout.get("gates", []):
		out.append(
			{
				"pos": Vector3(float(gate["pos"][0]), 0.0, float(gate["pos"][1])),
				"outward": Vector3(float(gate["outward"][0]), 0.0, float(gate["outward"][1])),
				"half_width": float(gate["half_width"])
			}
		)
	return out
