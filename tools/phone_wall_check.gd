extends SceneTree
# Check for thrown phones and buildings (README Milestone K, Gameplay on open ground: "Thrown phones and boss
# volleys respect buildings on open ground"). Run from the project folder:
#   godot --headless --path . --script res://tools/phone_wall_check.gd
# Exits with status 1 and prints the first problems.
#
# It builds a flat test arena that says rider_pursuit() with one long wall (2.8 m thick, 28 m long, as high as a
# building) along the z axis, and checks, with the player on the east side of the wall:
#   - phones.gd throw_clear is false from the west side, true from the east side;
#   - a rider whose wind-up ends on the west side holds its phone (nothing is thrown, throw_t is set back to 0.3)
#     and one on the east side throws it;
#   - a boss in phase 2 on the west side does not throw a phone and tries again in 0.3 s; on the east side it throws;
#   - a phone thrown from the west side smashes on the wall (it is gone while its flight is still under way and the
#     player lost no heart), and one thrown from the east side is still flying part way through;
#   - on the roundabout (the arena the game starts with) throw_clear is true wherever the thrower is.

const DT = 1.0 / 60.0
const WALL_HALF_X = 1.4
const WALL_HALF_Z = 14.0

var bad: Array = []
var main = null
var mock = null


func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	seed(11)
	main.start_game()
	main.state = "play"
	main.hits.resize(400)
	main.hits.fill(false)
	var roundabout = main.arena
	_check_roundabout()
	mock = _make_arena()
	if mock == null:
		bad.append("could not build the test arena")
	else:
		main.arena = mock
		_check_throw_clear()
		_check_rider()
		_check_boss()
		_check_flight()
		main.arena = roundabout
	if bad.is_empty():
		print(
			"phone_wall_check: phones are held and smashed by buildings on open ground, the roundabout is unchanged"
		)
		quit(0)
	else:
		print("phone_wall_check: %d problem(s)" % bad.size())
		for p in bad.slice(0, 12):
			print("  " + p)
		quit(1)


# a flat arena with open ground everywhere and one long wall; ray_blocked is true inside it below the lowest roof
func _make_arena():
	var src = 'extends "res://scripts/arena_roundabout.gd"\n'
	src += "func rider_pursuit() -> bool:\n\treturn true\n"
	src += "func rider_avoidance() -> bool:\n\treturn true\n"
	src += "func obstacle_at(p: Vector3) -> bool:\n"
	src += "\treturn absf(p.x) < %f and absf(p.z) < %f\n" % [WALL_HALF_X, WALL_HALF_Z]
	src += "func ray_blocked(p: Vector3) -> bool:\n"
	src += "\treturn p.y < 6.5 and absf(p.x) < %f and absf(p.z) < %f\n" % [WALL_HALF_X, WALL_HALF_Z]
	src += "func clamp_walk(p: Vector3, _who: String = 'player') -> Vector3:\n"
	src += "\treturn Vector3(p.x, 0.0, p.z)\n"
	var script = GDScript.new()
	script.source_code = src
	if script.reload() != OK:
		return null
	return script.new()


func _west() -> Vector3:
	return Vector3(-12.0, 0.0, 0.0)


func _east() -> Vector3:
	return Vector3(12.0, 0.0, -10.0)


func _player() -> void:
	main.player.position = Vector3(12.0, 0.0, 0.0)
	main.pvel = Vector3.ZERO


func _clear_phones() -> void:
	main.clear_phones()
	main.phones.clear()


func _rider(pos: Vector3) -> Dictionary:
	var r = main.rider_sys.spawn_rider(0, 1)
	r["can_throw"] = true
	r["pos"] = pos
	r["yaw"] = 0.0
	r["hidden"] = false
	r["entered"] = true
	r["mode"] = "fly"
	return r


func _check_roundabout() -> void:
	main.player.position = Vector3(6.0, 0.0, 0.0)
	for start in [Vector3(-6.0, 1.5, 0.0), Vector3(0.0, 1.5, -5.0), Vector3(40.0, 1.5, 40.0)]:
		if not main.phone_sys.throw_clear(start):
			bad.append(
				(
					"roundabout: throw_clear is false from %s, it must always be true there"
					% str(start)
				)
			)


func _check_throw_clear() -> void:
	_player()
	if main.phone_sys.throw_clear(_west() + Vector3(0.0, 1.5, 0.0)):
		bad.append("throw_clear is true with the wall between the thrower and the player")
	if not main.phone_sys.throw_clear(_east() + Vector3(0.0, 1.5, 0.0)):
		bad.append("throw_clear is false with open ground between the thrower and the player")


func _check_rider() -> void:
	_player()
	_clear_phones()
	main.clear_riders()
	var r = _rider(_west())
	r["throw_t"] = 0.0
	main.phone_sys.launch_phone(r)
	if main.phones.size() != 0:
		bad.append("a rider behind the wall threw a phone")
	if absf(r["throw_t"] - 0.3) > 0.001:
		bad.append("a rider that held its phone has throw_t %.2f, expected 0.3" % r["throw_t"])
	main.clear_riders()
	var e = _rider(_east())
	main.phone_sys.launch_phone(e)
	if main.phones.size() != 1:
		bad.append("a rider with a clear line threw %d phones, expected 1" % main.phones.size())
	_clear_phones()
	main.clear_riders()


func _check_boss() -> void:
	_player()
	_clear_phones()
	main.round_n = 4
	main.boss_sys.spawn_boss()
	var b = main.bosses.back()
	b["intro"] = 0.0
	b["kind"] = "minister"
	b["phase"] = 2
	b["wp"] = _west()
	b["throw_t"] = 0.0
	main.state = "play"
	main.boss_sys.boss_throws(b, 0.0)
	if main.phones.size() != 0:
		bad.append("a boss behind the wall threw a phone")
	if absf(b["throw_t"] - 0.3) > 0.001:
		bad.append("a boss that held its phone has throw_t %.2f, expected 0.3" % b["throw_t"])
	b["wp"] = _east()
	b["throw_t"] = 0.0
	main.boss_sys.boss_throws(b, 0.0)
	if main.phones.size() != 1:
		bad.append("a boss with a clear line threw %d phones, expected 1" % main.phones.size())
	if b["throw_t"] < 2.0:
		bad.append("a boss that threw has throw_t %.2f, expected 2.4 or more" % b["throw_t"])
	_clear_phones()
	for boss in main.bosses.duplicate():
		main.free_boss(boss)
	main.bosses.clear()


func _check_flight() -> void:
	_player()
	main.hearts = 99
	main.invuln = 0.0
	main.state = "play"
	# from behind the wall (thrown anyway, as a boss volley is): it smashes on the wall
	_clear_phones()
	main.phone_sys.throw_phone(_west() + Vector3(0.0, 1.5, 0.0), {})
	if main.phones.size() != 1:
		bad.append("the test phone was not thrown")
		return
	var ph = main.phones[0]
	var frames = 0
	while not main.phones.is_empty() and frames < 240:
		main.phone_sys.update_phones(DT)
		frames += 1
	if not main.phones.is_empty():
		bad.append("a phone thrown through the wall was still flying after 4 s")
	elif ph["p"] >= 1.0:
		bad.append(
			"a phone thrown through the wall flew all the way to the player (p %.2f)" % ph["p"]
		)
	if main.hearts != 99:
		bad.append("a phone that hit the wall still cost the player a heart")
	# from the open side: part way through its flight it is still there
	_clear_phones()
	_player()
	main.phone_sys.throw_phone(_east() + Vector3(0.0, 1.5, 0.0), {})
	for f in range(20):
		main.phone_sys.update_phones(DT)
	if main.phones.size() != 1:
		bad.append("a phone thrown across open ground was gone after 20 frames")
	_clear_phones()
