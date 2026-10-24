extends RefCounted
# The edge arrows' ranking (README Milestone K, Gameplay on open ground). A threat is a dictionary from
# Main.threat_list(): "urg" (how pressing the thing is by itself, 0 to 1), "dist" (metres to the player over the
# ground) and "closing" (metres per second towards the player, negative moving away).
#
# On the roundabout the arrows have always been drawn by "urg" alone and still are. On open ground a rider can be
# anywhere on a 96 m arena and ten of them can chase at once, so an arrow also has to say how near the thing is
# and whether it is coming: strength is "urg" times a distance factor (1 within NEAR metres, falling to
# FAR_FACTOR at FAR metres and beyond) times an approach factor (up to +APPROACH_BONUS at a closing speed of
# APPROACH_FULL, down to -AWAY_PENALTY moving away at that speed), never below MIN_STRENGTH so that no arrow
# vanishes. The arrows show the strongest MAX_ARROWS.

const NEAR = 8.0  # metres
const FAR = 60.0  # metres
const FAR_FACTOR = 0.3
const APPROACH_FULL = 12.0  # metres per second
const APPROACH_BONUS = 0.35
const AWAY_PENALTY = 0.3
const MIN_STRENGTH = 0.15
const MAX_ARROWS = 8
const RADAR_RANGE_STREET = 26.0  # metres from the centre to the rim of the radar on the roundabout
const RADAR_RANGE_OPEN = 60.0  # the same on open ground, where riders start up to 96 m off


# how strongly the arrow for threat t is drawn, 0 to 1
static func strength(t: Dictionary, open_ground: bool) -> float:
	if not open_ground:
		return t["urg"]
	var far = clampf((t["dist"] - NEAR) / (FAR - NEAR), 0.0, 1.0)
	var dist_factor = lerpf(1.0, FAR_FACTOR, far)
	var approach = clampf(t["closing"] / APPROACH_FULL, -1.0, 1.0)
	var approach_factor = 1.0 + approach * (APPROACH_BONUS if approach > 0.0 else AWAY_PENALTY)
	return clampf(t["urg"] * dist_factor * approach_factor, MIN_STRENGTH, 1.0)


# the threats as copies with a "strength" added, the strongest first (a tie keeps the list's order)
static func ranked(list: Array, open_ground: bool) -> Array:
	var out = []
	for i in range(list.size()):
		var t: Dictionary = list[i].duplicate()
		t["strength"] = strength(t, open_ground)
		t["order"] = i
		out.append(t)
	out.sort_custom(
		func(a, b):
			if a["strength"] != b["strength"]:
				return a["strength"] > b["strength"]
			return a["order"] < b["order"]
	)
	return out


# how far from the radar's centre a threat dist metres away is drawn, 0 (on top of the player) to 1 (the rim).
# The roundabout is as it always was: a straight scale out to RADAR_RANGE_STREET, everything farther on the rim.
# On open ground the scale reaches RADAR_RANGE_OPEN and is squeezed (square root), so the riders close by, which
# matter most, still have room between them and the far ones are on the radar instead of piled on its rim.
static func radar_fraction(dist: float, open_ground: bool) -> float:
	if not open_ground:
		return minf(dist / RADAR_RANGE_STREET, 1.0)
	return sqrt(minf(dist / RADAR_RANGE_OPEN, 1.0))
