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


func rho(z: float) -> float:
	return Ring.rho(z)


func clamp_road(p: Vector3, z_near: float = 1.6, z_far: float = -6.6) -> Vector3:
	return Ring.clamp_road(p, z_near, z_far)


func ray_exit_circle(o: Vector3, d: Vector3, radius: float) -> float:
	return Ring.ray_exit_circle(o, d, radius)
