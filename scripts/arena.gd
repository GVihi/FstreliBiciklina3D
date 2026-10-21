extends RefCounted
# The arena: the space the run is played in. This is the interface the game talks to; an implementation
# decides the shape. Today there is one, the roundabout (arena_roundabout.gd). README Milestone K replaces it
# step by step with generated arenas (docs/PROCEDURAL_ARENAS.md).
#
# The functions below are what the roundabout offers today. They come in two groups:
#   street coordinates (transitional): x is the distance along the road, z the position across it. Riders,
#     bosses and pedestrians still live in these. They go away when movement moves to world positions.
#   world space: bounds, blocking and facade queries on real positions. These stay and grow.
# This base class only documents them and complains if an implementation forgets one.


func _missing(what: String) -> void:
	push_error("arena: %s is not implemented by %s" % [what, get_script().resource_path])


# ---------------------------------------------------------------- street coordinates (transitional)
# street point (x, z) at height y -> world position
func tw(_x: float, _z: float, _y: float = 0.0) -> Vector3:
	_missing("tw")
	return Vector3.ZERO


# world position -> street (x, z) as a Vector2
func to_track(_p: Vector3) -> Vector2:
	_missing("to_track")
	return Vector2.ZERO


# unit vector along the street at x (direction of increasing x)
func tangent(_x: float) -> Vector3:
	_missing("tangent")
	return Vector3.RIGHT


# unit vector across the street towards the player's area at x (direction of increasing z)
func inward(_x: float) -> Vector3:
	_missing("inward")
	return Vector3.BACK


# yaw that turns a street-aligned model into world space at x
func yaw(_x: float) -> float:
	_missing("yaw")
	return 0.0


# true while x is inside the tunnel block: not visible, not hittable
func hidden(_x: float) -> bool:
	_missing("hidden")
	return false


# how far out x can go for things that must stay in view / for the player
func lim() -> float:
	_missing("lim")
	return 0.0


func player_lim() -> float:
	_missing("player_lim")
	return 0.0


# ---------------------------------------------------------------- world space
# pull a world point back onto the road (between the near and far edge of the lanes)
func clamp_road(p: Vector3, _z_near: float = 1.6, _z_far: float = -6.6) -> Vector3:
	_missing("clamp_road")
	return p


# distance along a ray (starting inside the circle of radius R around the origin) to that circle, or -1
func ray_exit_circle(_o: Vector3, _d: Vector3, _radius: float) -> float:
	_missing("ray_exit_circle")
	return -1.0
