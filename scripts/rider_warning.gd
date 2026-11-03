extends RefCounted
# Directional warning sounds for riders (README Milestone E, Accessibility). A rider that is close, coming towards
# the player and not in front of them rings a bike bell, so a player can hear what the threat arrows and the radar
# show, and a player who misses the visual cues still knows something is on its way.
#
# It reads Main.threat_list(), the list the arrows and the radar read, so the bell and the arrows agree on what a
# threat is. Only riders ring: bosses and phones have their own cues.
#
#   Who rings     A rider within RANGE metres, closing at MIN_CLOSING metres per second or more, whose bearing is at
#                 least FRONT_DEG off the way the player looks (a rider ahead is on the screen and needs no bell).
#   How loud      `loudness`: 1 at NEAR metres or closer, falling to FAR_LOUDNESS at RANGE, times a speed factor from
#                 SPEED_FLOOR (just closing) to 1 (closing at FULL_CLOSING or faster). The setting adds LEVEL_DB.
#   How often     `interval`: INTERVAL_FAR seconds apart at RANGE, INTERVAL_NEAR at NEAR or closer.
#   Where from    The bell is played from the rider's position with the 3D sound, so Godot pans it left or right by
#                 where the rider is. Stereo cannot tell front from behind, so a rider that is behind the player
#                 (BEHIND_DEG or more off straight ahead) rings lower, PITCH_BEHIND times the pitch.
#   How many      At most MAX_BELLS riders ring at once, the loudest ones, one cadence timer for each place in that
#                 ranking (so ten riders closing in make two bells, not ten). A timer keeps running while its place
#                 is empty, so a rider that flickers in and out of the rules cannot ring faster than INTERVAL_NEAR.
#   No random     Nothing here rolls a random number: the same situation gives the same bells.
#
# The RIDER WARNING setting (`g.warn_level`, saved as `rider_warning` under `[game]`): OFF, QUIET or NORMAL.

const LEVEL_NAMES = ["OFF", "QUIET", "NORMAL"]
const LEVEL_DB = [-80.0, -9.0, 0.0]  # added to the bell's volume for each level
const DEFAULT_LEVEL = 2
const BASE_DB = -10.0  # the bell's volume at full loudness and level NORMAL

const RANGE = 30.0  # metres: farther than this a rider does not ring
const NEAR = 6.0  # metres: this close or closer the bell is as loud as it gets and as quick as it gets
const FAR_LOUDNESS = 0.25
const MIN_CLOSING = 2.5  # metres per second towards the player: slower than this does not ring
const FULL_CLOSING = 12.0  # the closing speed that gives the full speed factor
const SPEED_FLOOR = 0.7
const FRONT_DEG = 50.0  # a rider this close to straight ahead is not heard: it can be seen
const BEHIND_DEG = 120.0  # a rider this far off straight ahead or more is behind the player
const PITCH_BEHIND = 0.85
const MAX_BELLS = 2
const INTERVAL_FAR = 1.4  # seconds between two rings of one rider at RANGE
const INTERVAL_NEAR = 0.5
const SLOT_PITCH = [1.0, 1.12]  # the second bell is a little higher, so two bells can be told apart

var g = null
var timers = []  # seconds until each place in the ranking may ring again
var ring_count = 0  # bells rung since the last reset (the check reads it)
var last_ring = {}  # the last bell: "pos", "db", "pitch", "slot", "dist", "closing", "bearing"


func _init(main = null) -> void:
	g = main
	reset()


func reset() -> void:
	timers = []
	for i in range(MAX_BELLS):
		timers.append(0.0)
	ring_count = 0
	last_ring = {}


# how far `pos` is off straight ahead, as seen from `from` for a player who looks along `yaw`: 0 is dead ahead, 180
# right behind, the same on both sides. A point on top of the player counts as at the side.
static func bearing_deg(from: Vector3, yaw: float, pos: Vector3) -> float:
	var to = Vector2(pos.x - from.x, pos.z - from.z)
	if to.length() < 0.01:
		return 90.0
	var ahead = Vector2(-sin(yaw), -cos(yaw))
	return absf(rad_to_deg(ahead.angle_to(to)))


# true when threat t (an entry of Main.threat_list) at this bearing rings: a rider, near, closing, not ahead
static func rings(t: Dictionary, bearing: float) -> bool:
	return (
		t["kind"] == "rider"
		and t["dist"] <= RANGE
		and t["closing"] >= MIN_CLOSING
		and bearing >= FRONT_DEG
	)


# 0 to 1: how loud a bell is for a rider this far off and closing this fast (nearer and faster is louder)
static func loudness(dist: float, closing: float) -> float:
	var far = clampf((dist - NEAR) / (RANGE - NEAR), 0.0, 1.0)
	var fast = clampf((closing - MIN_CLOSING) / (FULL_CLOSING - MIN_CLOSING), 0.0, 1.0)
	return lerpf(1.0, FAR_LOUDNESS, far) * lerpf(SPEED_FLOOR, 1.0, fast)


# seconds between two rings of a rider this far off (nearer rings quicker)
static func interval(dist: float) -> float:
	var far = clampf((dist - NEAR) / (RANGE - NEAR), 0.0, 1.0)
	return lerpf(INTERVAL_NEAR, INTERVAL_FAR, far)


# the volume in dB of a bell of this loudness (0 to 1) at a setting level (0 OFF, 1 QUIET, 2 NORMAL)
static func volume_db(loud: float, level: int) -> float:
	var lv = clampi(level, 0, LEVEL_DB.size() - 1)
	if lv == 0:
		return -80.0
	return LEVEL_DB[lv] + BASE_DB + linear_to_db(clampf(loud, 0.01, 1.0))


# the pitch of the bell for place `slot` of the ranking, lower when the rider is behind the player
static func pitch_for(slot: int, bearing: float) -> float:
	var p = float(SLOT_PITCH[clampi(slot, 0, SLOT_PITCH.size() - 1)])
	return p * (PITCH_BEHIND if bearing >= BEHIND_DEG else 1.0)


# The riders that ring right now, the loudest first (a tie keeps the order of the list), as copies of their threat
# entries with "bearing" and "loud" added. `from` is the player's position, `yaw` the way they look.
static func ranked(list: Array, from: Vector3, yaw: float) -> Array:
	var out = []
	for i in range(list.size()):
		var t: Dictionary = list[i]
		if t["kind"] != "rider":
			continue
		var b = bearing_deg(from, yaw, t["pos"])
		if not rings(t, b):
			continue
		var c: Dictionary = t.duplicate()
		c["bearing"] = b
		c["loud"] = loudness(t["dist"], t["closing"])
		c["order"] = i
		out.append(c)
	out.sort_custom(
		func(a, b):
			if a["loud"] != b["loud"]:
				return a["loud"] > b["loud"]
			return a["order"] < b["order"]
	)
	return out


# Once a frame while a round is running (Main.update_game). Counts the timers down, then rings every place of the
# ranking whose timer is up.
func update(dt: float) -> void:
	for i in range(timers.size()):
		timers[i] = maxf(0.0, timers[i] - dt)
	if g == null or g.warn_level <= 0 or g.sfx.muted:
		return
	var cands = ranked(g.threat_list(), g.player.position, g.yaw)
	for i in range(mini(cands.size(), MAX_BELLS)):
		if timers[i] > 0.0:
			continue
		var c: Dictionary = cands[i]
		var db = volume_db(c["loud"], g.warn_level)
		var pitch = pitch_for(i, c["bearing"])
		g.sfx.play_warning(c["pos"], db, pitch)
		timers[i] = interval(c["dist"])
		ring_count += 1
		last_ring = {
			"pos": c["pos"],
			"db": db,
			"pitch": pitch,
			"slot": i,
			"dist": c["dist"],
			"closing": c["closing"],
			"bearing": c["bearing"]
		}
