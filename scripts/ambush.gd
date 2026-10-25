extends RefCounted
# The ambush when the extraction point opens (README Milestone K, "Exploration and extraction").
#
# Until now the walk to the extraction point was quiet, because every rider was already down. When the way out opens
# on a generated arena, a few more riders now come out of the gates (a short last wave), one after another, and ride
# at the player. So the walk out is a moment of its own, and the caches become a choice between the gold detour and
# the straight run to the exit.
#
#   Size     MIN_RIDERS at the start of a run, one more every three rounds, at most MAX_RIDERS (`count_for_round`).
#   Timing   The first rider comes out DELAY seconds after the way opens, then one every GAP seconds. A note and a
#            sound say it started; the threat arrows and the radar show the riders as they ride in.
#   Where    Gates the node leaves open that are far from the player (`riders.gd` `ambush_gate`), so there is time to
#            see them. The riders, their kinds and the lane they take come from the round's rider stream (layout_f /
#            layout_i), which is seeded by the run seed and the round: the Daily Run gives everybody the same count,
#            kinds and order. Which gate depends on where the player stands when the rider is sent.
#   Rules    Ambush riders are not among the round's PER_ROUND riders: they are not in `hits`, they do not move
#            `next_idx` and do not change what clears the round (reaching the point still does). When the last one
#            is down the round does NOT end (`after_wave` in main.gd returns while the way out is open). A life lost to
#            an ambush rider still counts against a perfect round, since the round is not over yet.
#
# One round at a time: `start()` is called by `finish_wave_set` when the way opens, `clear()` when the round ends or
# the run is lost. The roundabout has no extraction point and so no ambush.

const DELAY = 2.0  # seconds from the way opening to the first rider
const GAP = 1.6  # seconds between riders
const MIN_RIDERS = 2
const MAX_RIDERS = 4
const WARN = Color(0.9, 0.33, 0.24)

var g = null
var left = 0  # riders still to send
var sent = 0  # riders sent this round
var _wait = 0.0


func _init(game) -> void:
	g = game


# riders in the ambush of round n: 2 in rounds 1 to 4, 3 in rounds 5 to 7, 4 from round 8
func count_for_round(n: int) -> int:
	return clampi(1 + int(floor(float(n + 1) / 3.0)), MIN_RIDERS, MAX_RIDERS)


# true while riders are still to come
func pending() -> bool:
	return left > 0


# The way out has just opened: line up the riders.
func start() -> void:
	clear()
	if not g.objective_sys.enabled() or not g.objective_sys.extracting:
		return
	left = count_for_round(g.round_n)
	_wait = DELAY


func clear() -> void:
	left = 0
	sent = 0
	_wait = 0.0


func update(dt: float) -> void:
	if left <= 0:
		return
	if g.state != "play" or not g.objective_sys.extracting:
		clear()  # the round is over (the player got out), or the way is not open
		return
	_wait -= dt
	if _wait > 0.0:
		return
	if sent == 0:
		g.add_note("AMBUSH - RIDERS AT THE GATES", WARN)
		g.sfx.play("boss_intro", -4.0)
	g.rider_sys.spawn_rider(g.layout_i(3), 1, true)
	left -= 1
	sent += 1
	_wait = GAP
