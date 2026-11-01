extends "res://scripts/arena.gd"
# The training room: a small, dark, gridded box with glowing edges, for the tutorial and for trying a weapon or a
# gadget before buying it. It is the Arena interface on a plain rectangle, so there is nothing to generate: one
# room, always the same, built by world_training.gd.
#
# The room is HALF_X * 2 wide and HALF_Z * 2 long, HEIGHT high, and centred on the origin. The player starts at
# the +z end and looks down the room (yaw 0 looks along -z) at the rider door in the far wall, so the far wall is
# the target wall and the distance from the start to it (START_TO_DOOR) is the longest shot the room gives.
# There is one door, so a round (riders, bosses) still works here: riders come out of the door and nothing else.
# Nothing here is random, and a rider that is still inside the door's recess is hidden, like in a tunnel.

const HALF_X = 10.0  # metres: the room is 20 m wide ...
const HALF_Z = 14.0  # ... and 28 m long
const HEIGHT = 7.0  # ... and 7 m high; a dart above this hits the ceiling
const START_Z = 9.0  # the player starts this far towards +z, 23 m from the far wall
const DOOR_HALF = 1.6  # half the width of the rider door in the far wall
const DOOR_HEIGHT = 3.4  # the opening of the door, from the floor
const DOOR_DEPTH = 6.0  # the recess behind the door: riders start and leave inside it, hidden
const MARGINS = {"player": 0.45, "boss": 0.3, "pickup": 1.0}  # room kept to the wall, as on a generated arena
const EDGE_LIM = 1.5  # metres in from the side walls for lim(), the same idea as a generated arena
const EDGE_PLAYER_LIM = 2.0

var _gates: Array = [
	{"pos": Vector3(0.0, 0.0, -HALF_Z), "outward": Vector3(0.0, 0.0, -1.0), "half_width": DOOR_HALF}
]


# ---------------------------------------------------------------- the room
# true if p is inside the room (margin metres in from the walls; the height is not looked at)
func _in_room(p: Vector3, margin: float = 0.0) -> bool:
	return absf(p.x) <= HALF_X - margin and absf(p.z) <= HALF_Z - margin


# true if p is in the recess behind the door, past the far wall
func _in_recess(p: Vector3) -> bool:
	return absf(p.x) < DOOR_HALF and p.z < -HALF_Z and p.z > -HALF_Z - DOOR_DEPTH


# true if the room keeps its own light: the day and night themes of a round do not touch it
func fixed_lighting() -> bool:
	return true


func style_name() -> String:
	return "training"


func style_label() -> String:
	return "TRAINING ROOM"


# "plaza" in the room (riders keep their full speed there), "tunnel" in the recess, "building" outside
func surface_at(p: Vector3) -> String:
	if _in_room(p):
		return "plaza"
	if _in_recess(p):
		return "tunnel"
	return "building"


func rider_speed_at(p: Vector3) -> float:
	return 1.0 if (_in_room(p) or _in_recess(p)) else 0.0


# riders chase the player over open ground and steer round walls themselves, as on a generated arena
func rider_pursuit() -> bool:
	return true


func rider_avoidance() -> bool:
	return true


# ---------------------------------------------------------------- the start and the door
func start_position() -> Vector3:
	return Vector3(0.0, 0.0, START_Z)


func gates() -> Array:
	return _gates


# the longest straight shot the room gives: from the start to the far wall
func start_to_door() -> float:
	return START_Z + HALF_Z


# ---------------------------------------------------------------- walking and walls
# keep p inside the room, `who` decides how far from the wall. The room is a rectangle, so clamping is also
# sliding along the wall: slide_walk of the base class (which calls this) needs no override.
func clamp_walk(p: Vector3, who: String = "player") -> Vector3:
	var margin: float = MARGINS.get(who, MARGINS["player"])
	return Vector3(
		clampf(p.x, -(HALF_X - margin), HALF_X - margin),
		p.y,
		clampf(p.z, -(HALF_Z - margin), HALF_Z - margin)
	)


# true if a boss on foot at p is blocked: outside the room (the recess is for riders only)
func obstacle_at(p: Vector3) -> bool:
	return not _in_room(p)


# true if a rider at p cannot ride there: outside the room, but not in the door's recess
func rider_blocked(p: Vector3) -> bool:
	return not (_in_room(p) or _in_recess(p))


# true if p is inside the door's recess: not visible, not hittable
func hidden_at(p: Vector3) -> bool:
	return _in_recess(p)


# true if a dart at p is inside something solid: the ceiling, or a wall (the door's opening is not a wall)
func ray_blocked(p: Vector3) -> bool:
	return p.y >= HEIGHT or not (_in_room(p) or _in_recess(p))


# ---------------------------------------------------------------- the people
# no cheerleaders: the room has no crowd, and an empty list hides them
func cheer_spots(_count: int) -> Array:
	return []


# ---------------------------------------------------------------- street-coordinate stubs
# Like a generated arena, the room has no street: street x and z are world x and z, always a point inside the
# room, never an error. They are for code that has not moved to world positions yet.
const FACADE_RHO = 0.0  # the roundabout's circle of facades; the room has none


func tw(x: float, z: float, y: float = 0.0) -> Vector3:
	return Vector3(
		clampf(x, -(HALF_X - 0.5), HALF_X - 0.5), y, clampf(z, -(HALF_Z - 0.5), HALF_Z - 0.5)
	)


func to_track(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


func tangent(_x: float) -> Vector3:
	return Vector3.RIGHT


func inward(_x: float) -> Vector3:
	return Vector3.BACK


func yaw(_x: float) -> float:
	return 0.0


# nothing is hidden by street x (hidden_at looks at the recess)
func hidden(_x: float) -> bool:
	return false


func scale_at(_z: float) -> float:
	return 1.0


func lane_point(p: Vector3, dir: int, _z: float, ahead: float) -> Vector3:
	return clamp_walk(p + Vector3.RIGHT * float(dir) * ahead, "boss")


# metres to the door, as the way out for a rider that gives up
func exit_distance(p: Vector3, _dir: int) -> float:
	var door: Vector3 = _gates[0]["pos"]
	return Vector2(door.x - p.x, door.z - p.z).length()


func lim() -> float:
	return HALF_X - EDGE_LIM


func player_lim() -> float:
	return HALF_X - EDGE_PLAYER_LIM


func clamp_road(p: Vector3, _z_near: float = 1.6, _z_far: float = -6.6) -> Vector3:
	return clamp_walk(p, "boss")


func ray_exit_circle(_o: Vector3, _d: Vector3, _radius: float) -> float:
	return -1.0
