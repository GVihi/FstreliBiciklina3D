extends RefCounted
# The roundabout.
#
# The game logic still thinks in "street" coordinates, exactly like the old straight arena:
#     x = distance along the road (metres, measured on the middle lane)
#     z = across the road: 2.75 is the barrier, 0.5 / -2.5 / -5.5 are the three lanes, -13 is the facade
# This file bends that street into a circle. The player stands on the central island, looking out at the
# ring road. World position of a street point (x, z):
#     angle  = x / RHO_REF           (0 = straight ahead of where you start, + = to your right)
#     radius = RHO_B + BARRIER_Z - z (the barrier is at RHO_B, lanes further out)
#     world  = (radius * sin(angle), 0, -radius * cos(angle))
# Street axes rotate with the angle, so anything that faces along the street gets yaw = -angle.
#
# The ring road dives into a tunnel at the back (angle = PI): riders enter and leave there.

const RHO_B = 8.0  # radius of the barrier around the island
const BARRIER_Z = 2.75
const RHO_REF = 13.25  # radius of the middle lane, where x is measured
const L = TAU * RHO_REF  # full lap in street metres
const HX = L * 0.5  # x runs from -HX to +HX, the tunnel is at both ends
const GATE_HALF = 4.2  # tunnel block reaches this far (street metres) either side of the seam
const FACADE_RHO = 23.85  # front face of the buildings around the ring
const GATE_RHO_IN = 8.7  # where the tunnel block begins (just outside the barrier)


static func rho(z: float) -> float:
	return RHO_B + BARRIER_Z - z


static func z_of_rho(r: float) -> float:
	return RHO_B + BARRIER_Z - r


static func angle(x: float) -> float:
	return x / RHO_REF


# street (x, z) at height y -> world
static func tw(x: float, z: float, y: float = 0.0) -> Vector3:
	var th = x / RHO_REF
	var r = RHO_B + BARRIER_Z - z
	return Vector3(r * sin(th), y, -r * cos(th))


# unit vector along the street (direction of increasing x)
static func tangent(x: float) -> Vector3:
	var th = x / RHO_REF
	return Vector3(cos(th), 0.0, sin(th))


# unit vector towards the player's island (direction of increasing z)
static func inward(x: float) -> Vector3:
	var th = x / RHO_REF
	return Vector3(-sin(th), 0.0, cos(th))


# yaw that turns a street-aligned model into world space
static func yaw(x: float) -> float:
	return -x / RHO_REF


# world -> street (x, z)
static func to_track(p: Vector3) -> Vector2:
	var r = Vector2(p.x, p.z).length()
	var th = atan2(p.x, -p.z)
	return Vector2(th * RHO_REF, BARRIER_Z + RHO_B - r)


# metres of world travel per street metre at this z (the ring is tighter near the island)
static func scale_at(z: float) -> float:
	return rho(z) / RHO_REF


# inside the tunnel block: not visible, not hittable
static func hidden(x: float) -> bool:
	return absf(x) > HX - GATE_HALF


# how far out the street coordinate can go for things that must stay in view
static func lim() -> float:
	return HX - GATE_HALF - 1.0


# the player can't walk into the planter in front of the tunnel
static func player_lim() -> float:
	return HX - GATE_HALF - 1.8


# pull a world point back into the road ring (radius between the near and far edge of the lanes)
static func clamp_road(p: Vector3, z_near: float = 1.6, z_far: float = -6.6) -> Vector3:
	var r = Vector2(p.x, p.z).length()
	if r < 0.001:
		return p
	var rc = clampf(r, rho(z_near), rho(z_far))
	if absf(rc - r) < 0.0001:
		return p
	return Vector3(p.x * rc / r, p.y, p.z * rc / r)


# distance along a ray (starting inside the circle of radius R around the origin) to that circle, or -1
static func ray_exit_circle(o: Vector3, d: Vector3, R: float) -> float:
	var ox = o.x
	var oz = o.z
	var a = d.x * d.x + d.z * d.z
	if a < 0.000001:
		return -1.0
	var b = 2.0 * (ox * d.x + oz * d.z)
	var c = ox * ox + oz * oz - R * R
	var disc = b * b - 4.0 * a * c
	if disc < 0.0:
		return -1.0
	var t = (-b + sqrt(disc)) / (2.0 * a)
	return t if t > 0.0 else -1.0
