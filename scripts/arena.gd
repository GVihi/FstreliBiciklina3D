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


# world metres per street metre on the lane at street z (the ring is tighter near the island). Riders are
# given a speed in street metres per second, which this turns into the speed over the ground.
func scale_at(_z: float) -> float:
	_missing("scale_at")
	return 1.0


# The point a rider or pedestrian on the lane at street z steers at: `ahead` world metres further along the
# lane in direction dir (+1 or -1) from the world point p. This is what keeps it on its lane; rider pursuit
# (README Milestone K) replaces it with "ride towards the player" and then this goes away.
func lane_point(_p: Vector3, _dir: int, _z: float, _ahead: float) -> Vector3:
	_missing("lane_point")
	return Vector3.ZERO


# street metres a rider at world point p still has to ride in direction dir before it has left the arena
# through the gate it is heading for (used when a rider gives up and rides away)
func exit_distance(_p: Vector3, _dir: int) -> float:
	_missing("exit_distance")
	return 0.0


# how far out x can go for things that must stay in view / for the player
func lim() -> float:
	_missing("lim")
	return 0.0


func player_lim() -> float:
	_missing("player_lim")
	return 0.0


# ---------------------------------------------------------------- world space
# where the player starts each round
func start_position() -> Vector3:
	_missing("start_position")
	return Vector3.ZERO


# keep a point on the walkable ground, sliding along an edge instead of stopping dead. The arena owns the
# bounds; "who" only picks how much room the thing needs: "player" (the walkable ground itself), "boss"
# (a boss on foot, which may stand a little closer to the edge) or "pickup" (a landing spot, kept a little
# inside the player's ground so it can always be reached).
func clamp_walk(p: Vector3, _who: String = "player") -> Vector3:
	_missing("clamp_walk")
	return p


# true if riders and pedestrians have to steer round obstacle_at() on their own. The roundabout keeps its
# lanes clear of everything except the tunnel they pass through, so it says no; generated arenas will say yes.
func rider_avoidance() -> bool:
	_missing("rider_avoidance")
	return false


# true if riders chase the player over open ground (README Milestone K, rider pursuit): they ride at the player
# on any surface, pass, turn round in an arc and come back, and they come out of the gates. False keeps the
# lane steering the roundabout needs. Generated arenas say yes.
func rider_pursuit() -> bool:
	return false


# the share of its speed a rider keeps on the ground at world point p (road and plaza 1.0, sidewalk 0.9, grass
# 0.75 in data/arena_rules.json). Only used where riders pursue over open ground; the roundabout's lanes use
# scale_at instead.
func rider_speed_at(_p: Vector3) -> float:
	return 1.0


# true if a rider at world point p cannot ride there. Riders do not go where a boss cannot (obstacle_at) except
# through the gates: an arena whose gates a boss may not enter overrides this to leave them open.
func rider_blocked(p: Vector3) -> bool:
	return obstacle_at(p)


# true if the world point p is inside a gate's tunnel: not visible, not hittable
func hidden_at(p: Vector3) -> bool:
	return hidden(to_track(p).x)


# true if a dart at world point p is inside something solid
func ray_blocked(_p: Vector3) -> bool:
	_missing("ray_blocked")
	return false


# true if a boss on foot at world point p is blocked: inside an obstacle or outside the boundary
func obstacle_at(_p: Vector3) -> bool:
	_missing("obstacle_at")
	return false


# what the ground is at world point p: "grass", "plaza", "sidewalk", "road", "tunnel" or "building"
func surface_at(_p: Vector3) -> String:
	_missing("surface_at")
	return ""


# where the cheerleaders stand, as an Array of up to `count` world positions on the ground, or an empty Array when
# the arena has its own place for them (the roundabout's far sidewalk, which main.gd builds). They face the start.
func cheer_spots(_count: int) -> Array:
	return []


# where riders enter and leave: an Array of {"pos": Vector3 (centre of the opening, on the ground),
# "outward": Vector3 (unit vector pointing out of the arena), "half_width": float (metres)}
func gates() -> Array:
	_missing("gates")
	return []


# pull a world point back onto the road (between the near and far edge of the lanes)
func clamp_road(p: Vector3, _z_near: float = 1.6, _z_far: float = -6.6) -> Vector3:
	_missing("clamp_road")
	return p


# distance along a ray (starting inside the circle of radius R around the origin) to that circle, or -1
func ray_exit_circle(_o: Vector3, _d: Vector3, _radius: float) -> float:
	_missing("ray_exit_circle")
	return -1.0
