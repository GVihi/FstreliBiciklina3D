extends "res://scripts/arena.gd"
# The roundabout: the current arena. A thin wrapper that answers the Arena functions with the maths in
# ring.gd (read that file for how street coordinates bend into a circle). The constants below are
# roundabout-only and are used directly by code that has not been generalised yet; they go away with it.

const Ring = preload("res://scripts/ring.gd")

const RHO_B = Ring.RHO_B
const BARRIER_Z = Ring.BARRIER_Z
const RHO_REF = Ring.RHO_REF
const HX = Ring.HX  # half a lap: street x runs -HX..HX, the tunnel is at both ends
const GATE_HALF = Ring.GATE_HALF
const FACADE_RHO = Ring.FACADE_RHO
const GATE_RHO_IN = Ring.GATE_RHO_IN
const WALK_R_MIN = 2.3  # the player cannot get closer than this to the centre (the fountain)
const WALK_R_MAX = 22.3  # ... or further than this (the buildings)


func tw(x: float, z: float, y: float = 0.0) -> Vector3:
	return Ring.tw(x, z, y)


func to_track(p: Vector3) -> Vector2:
	return Ring.to_track(p)


func tangent(x: float) -> Vector3:
	return Ring.tangent(x)


func inward(x: float) -> Vector3:
	return Ring.inward(x)


func yaw(x: float) -> float:
	return Ring.yaw(x)


func hidden(x: float) -> bool:
	return Ring.hidden(x)


func lim() -> float:
	return Ring.lim()


func player_lim() -> float:
	return Ring.player_lim()


func start_position() -> Vector3:
	return Ring.tw(0.0, 6.0)


# keep a point on the walkable ground: outside the fountain, inside the buildings, and out of the
# tunnel / planter wedge at the back. The ring limits (from the centre) for each kind of caller; the
# numbers are the ones the callers used to pass in, so nothing moves.
func clamp_walk(p: Vector3, who: String = "player") -> Vector3:
	var rmin = WALK_R_MIN  # the fountain
	var rmax = WALK_R_MAX  # the buildings
	if who == "boss":
		rmin = 2.1
		rmax = 22.6
	elif who == "pickup":
		rmin = WALK_R_MIN + 0.3
		rmax = WALK_R_MAX - 0.4
	var r = Vector2(p.x, p.z).length()
	if r < 0.001:
		return Vector3(0.0, p.y, -rmin)
	var rc = clampf(r, rmin, rmax)
	if absf(rc - r) > 0.0001:
		p = Vector3(p.x * rc / r, p.y, p.z * rc / r)
	var tr = Ring.to_track(p)
	var lim = Ring.player_lim()
	if absf(tr.x) > lim:
		tr.x = clampf(tr.x, -lim, lim)
		p = Ring.tw(tr.x, tr.y, p.y)
	return p


# solid for darts: the fountain, the planter and the tunnel block
func ray_blocked(p: Vector3) -> bool:
	var r = Vector2(p.x, p.z).length()
	if r < 1.45 and p.y < 1.1:
		return true
	if r < 0.3 and p.y < 2.4:
		return true
	var a = absf(wrapf(atan2(p.x, -p.z) - PI, -PI, PI))
	if (
		r >= 1.0
		and r < Ring.GATE_RHO_IN
		and a < PI - (Ring.player_lim() / Ring.RHO_REF + 0.06)
		and p.y < 1.18
	):
		return true
	if r >= Ring.GATE_RHO_IN and a < Ring.GATE_HALF / Ring.RHO_REF and p.y < 7.5:
		return true
	return false


# the boss obstacle test: the fountain, the buildings and the planter wedge in front of the tunnel
func obstacle_at(p: Vector3) -> bool:
	var r = Vector2(p.x, p.z).length()
	if r < 2.3 or r > Ring.FACADE_RHO - 1.35:
		return true
	return absf(Ring.to_track(p).x) > Ring.player_lim() - 0.05


# the ground layers are the ones world.gd lays down: lawn and paving on the island, a strip between the
# barrier and the road, the road, the far sidewalk, then the buildings
func surface_at(p: Vector3) -> String:
	var r = Vector2(p.x, p.z).length()
	var a = absf(wrapf(atan2(p.x, -p.z) - PI, -PI, PI))
	if r >= Ring.GATE_RHO_IN and a < Ring.GATE_HALF / Ring.RHO_REF:
		return "tunnel"
	if r < 2.2:
		return "grass"
	if r < Ring.RHO_B:
		return "plaza"
	if r < Ring.rho(2.0):
		return "sidewalk"
	if r < Ring.rho(-7.0):
		return "road"
	if r < Ring.rho(-13.0):
		return "sidewalk"
	return "building"


# one gate: the tunnel at the back, where the ring road dives under the buildings
func gates() -> Array:
	var mid = Ring.tw(Ring.HX, -2.5)
	return [
		{
			"pos": mid,
			"outward": Vector3(mid.x, 0.0, mid.z).normalized(),
			"half_width": Ring.GATE_HALF,
		}
	]


func rho(z: float) -> float:
	return Ring.rho(z)


func clamp_road(p: Vector3, z_near: float = 1.6, z_far: float = -6.6) -> Vector3:
	return Ring.clamp_road(p, z_near, z_far)


func ray_exit_circle(o: Vector3, d: Vector3, radius: float) -> float:
	return Ring.ray_exit_circle(o, d, radius)
