extends SceneTree
# Check for the final boss (README "Big Design Choice": the final boss has its own model, attacks and arena moment).
# The last floor spawns the golden president, not the minister: its own kind in `Content.BOSS_INFO` (never picked as
# an ordinary boss), a model a quarter taller than the minister's, the decree (a gold shock ring that is dodged by a
# jump, a dash, distance, or a wall, and hurts once otherwise), the final speech at phase 3, and the entrance (a
# spotlight that fades with the intro). Ordinary bosses must not get any of it.
#
# Run from the project folder:
#   godot --headless --path . --script res://tools/final_boss_check.gd
# Exits with status 1 and prints the first problems when something is wrong.

const Models = preload("res://scripts/models.gd")
const DT = 1.0 / 60.0

var bad: Array = []
var main = null


func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	seed(7)
	main.start_game()
	main.state = "play"
	_check_content()
	_check_model()
	_check_spawn_and_entrance()
	_check_ordinary_bosses()
	_check_decree()
	_check_patterns()
	_check_final_speech()
	_check_defeat()
	if bad.is_empty():
		print(
			"final_boss_check: the golden president has its own model, decree, final speech and entrance"
		)
		quit(0)
	else:
		for line in bad.slice(0, 12):
			printerr("final_boss_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	bad.append(text)


# a fresh final boss with the intro over and the player standing `dist` metres away on flat ground
func _president(dist: float):
	main.clear_bosses()
	main.hearts = 3
	main.invuln = 0.0
	main.dash_inv = 0.0
	main.jump_h = 0.0
	main.floor_h = 0.0
	main.round_n = main.MAX_ROUNDS
	main.boss_sys.spawn_boss()
	var b = main.bosses[0]
	b["intro"] = 0.0
	b["wp"] = Vector3(0.0, 0.0, -6.0)
	main.player.position = Vector3(dist, 0.0, -6.0)
	return b


func _check_content() -> void:
	var info = main.BOSS_INFO
	if not info.has("president"):
		_fail("BOSS_INFO has no president")
		return
	if main.BOSS_KINDS.has("president"):
		_fail("the president is in BOSS_KINDS, so an ordinary boss node could pick it")
	for key in info["minister"].keys():
		if not info["president"].has(key):
			_fail("the president has no '%s' in BOSS_INFO" % key)
	if str(info["president"]["name"]) != "PREDSEDNIK POZLATA":
		_fail("the president is called %s" % str(info["president"]["name"]))


# the top of a model in the world: the highest point of any of its meshes
func _top(node: Node) -> float:
	var top = -1000.0
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		top = (mi.global_transform * mi.get_aabb()).end.y
	for ch in node.get_children():
		top = maxf(top, _top(ch))
	return top


func _check_model() -> void:
	var pm = Models.build_boss("president", 0, Models.kit_of(0))
	var mm = Models.build_boss("minister", 0, Models.kit_of(0))
	if not pm.get("fighter", false):
		_fail("the president model is not a fighter rig")
	main.add_child(pm["root"])
	main.add_child(mm["root"])
	var pt = _top(pm["root"])
	var mt = _top(mm["root"])
	if pt < mt * 1.15:
		_fail(
			(
				"the president is %.2f m tall, the minister %.2f m: it should be clearly taller"
				% [pt, mt]
			)
		)
	var wk = float(main.BOSS_INFO["president"]["wk"])
	if wk > pt or wk < pt * 0.7:
		_fail("the weak spot marker (%.2f m) is not on the head of a %.2f m model" % [wk, pt])
	var geo: Node3D = pm["geo"]
	if absf(geo.scale.x - Models.PRESIDENT_SCALE) > 0.001:
		_fail("the president's size is not on the geo pivot")
	if not pm.has("medal"):
		_fail("the president model has no medallion to animate")
	pm["root"].queue_free()
	mm["root"].queue_free()


func _check_spawn_and_entrance() -> void:
	main.clear_bosses()
	main.round_n = main.MAX_ROUNDS
	main.boss_count = 0
	main.boss_sys.spawn_boss()
	var b = main.bosses[0]
	if b["kind"] != "president" or not b["final"]:
		_fail("the last floor spawned a %s (final %s)" % [b["kind"], str(b["final"])])
		return
	var want_hp = int(round(float(main.boss_sys.boss_hp(22)) * main.boss_sys.FINAL_HP_MUL))
	if b["max_hp"] != want_hp:
		_fail("the president has %d health, expected %d" % [b["max_hp"], want_hp])
	if b["ring"] == null or b["beam"] == null:
		_fail("the president has no decree ring or entrance beam")
		return
	if absf(b["intro"] - 3.2) > 0.001:
		_fail("the final boss's intro is %.2f s, expected 3.2" % b["intro"])
	var beam: MeshInstance3D = b["beam"]
	if not beam.visible:
		_fail("the entrance beam is not shown when the final boss arrives")
	for i in range(int(3.4 / DT)):
		main.player.position = Vector3(30.0, 0.0, 30.0)  # far away, so nothing happens but the intro
		main.boss_sys.update_bosses(DT)
	if b["intro"] > 0.0:
		_fail("the intro did not end")
	if beam.visible:
		_fail("the entrance beam is still shown after the intro")
	var ring: Node = b["ring"]
	main.clear_bosses()
	if not (ring.is_queued_for_deletion() and beam.is_queued_for_deletion()):
		_fail("removing the president leaves its ring or beam behind")


func _check_ordinary_bosses() -> void:
	for i in range(6):
		main.clear_bosses()
		main.round_n = 2 + i % 3
		main.boss_count = i
		main.boss_sys.spawn_boss()
		var b = main.bosses[0]
		if b["kind"] == "president" or b["final"]:
			_fail(
				(
					"round %d: an ordinary boss came out as %s (final %s)"
					% [main.round_n, b["kind"], str(b["final"])]
				)
			)
		if b["ring"] != null or b["beam"] != null:
			_fail(
				(
					"round %d: an ordinary %s has the president's ring or beam"
					% [main.round_n, b["kind"]]
				)
			)
	main.clear_bosses()


# runs one decree against a player `dist` metres away (`jump` metres up, `dash` seconds of dash) and returns the
# lives it cost; also checks the ring was seen going out and that the boss is winded afterwards
func _run_decree(dist: float, jump: float, dash: float, label: String) -> int:
	var b = _president(dist)
	main.jump_h = jump
	main.dash_inv = dash
	b["next_pat"] = "decree"
	main.boss_sys.start_tele(b)
	if b["pat"] != "decree" or b["mode"] != "tele":
		_fail(
			(
				"%s: the president did not start a decree (pat %s, mode %s)"
				% [label, b["pat"], b["mode"]]
			)
		)
		return 0
	var saw_ring = false
	var biggest = 0.0
	for i in range(int(4.0 / DT)):
		main.dash_inv = dash  # the dash lasts the whole decree
		main.boss_sys.update_bosses(DT)
		if b["mode"] == "decree":
			var ring: MeshInstance3D = b["ring"]
			saw_ring = saw_ring or ring.visible
			biggest = maxf(biggest, ring.scale.x)
		if b["mode"] == "stagger":
			break
	if b["mode"] != "stagger":
		_fail("%s: the president is still in mode %s after 4 s" % [label, b["mode"]])
	if not saw_ring:
		_fail("%s: the ring was never shown" % label)
	if biggest < main.boss_sys.DECREE_RADIUS - 0.2:
		_fail(
			(
				"%s: the ring only grew to %.2f m, the circle is %.2f m"
				% [label, biggest, main.boss_sys.DECREE_RADIUS]
			)
		)
	var ring2: MeshInstance3D = b["ring"]
	if ring2.visible:
		_fail("%s: the ring stays shown after the decree" % label)
	var lost = 3 - main.hearts
	main.clear_bosses()
	return lost


func _check_decree() -> void:
	var hit = _run_decree(6.0, 0.0, 0.0, "decree, standing 6 m away")
	if hit != 1:
		_fail("standing inside the circle cost %d lives, expected 1" % hit)
	var jumped = _run_decree(6.0, 1.0, 0.0, "decree, jumping")
	if jumped != 0:
		_fail("a jump over the ring still cost %d lives" % jumped)
	var dashed = _run_decree(6.0, 0.0, 5.0, "decree, dashing")
	if dashed != 0:
		_fail("a dash through the ring still cost %d lives" % dashed)
	var far = _run_decree(
		main.boss_sys.DECREE_RADIUS + 3.0, 0.0, 0.0, "decree, standing outside the circle"
	)
	if far != 0:
		_fail("standing outside the circle cost %d lives" % far)


func _check_patterns() -> void:
	var seen = {}
	for ph in [1, 2, 3]:
		var b = _president(6.0)
		b["phase"] = ph
		var n = 0
		for i in range(400):
			if main.boss_sys.boss_pick_pattern(b) == "decree":
				n += 1
		seen[ph] = n
		if n == 0:
			_fail("the president never picked a decree in phase %d" % ph)
	if seen[3] <= seen[1]:
		_fail(
			(
				"the decree is not picked more often in phase 3 (%d) than in phase 1 (%d)"
				% [seen[3], seen[1]]
			)
		)
	# too far away for a decree to matter: it is not picked
	var far = _president(40.0)
	far["phase"] = 2
	for i in range(200):
		if main.boss_sys.boss_pick_pattern(far) == "decree":
			_fail("the president picked a decree with the player 40 m away")
			break
	# the other bosses never do
	for kind in ["mower", "wifi", "minister", "runner"]:
		var o = _president(6.0)
		o["kind"] = kind
		o["phase"] = 3
		for i in range(200):
			if main.boss_sys.boss_pick_pattern(o) == "decree":
				_fail("a %s picked a decree" % kind)
				break
	main.clear_bosses()


func _check_final_speech() -> void:
	var b = _president(6.0)
	b["hp"] = int(float(b["max_hp"]) * 0.34) + 1
	b["mode"] = "charge"
	main.boss_sys.hit_boss(b, 2, false, 0.0)
	if b["phase"] != 3:
		_fail(
			(
				"the president did not reach phase 3 (phase %d, health %d of %d)"
				% [b["phase"], b["hp"], b["max_hp"]]
			)
		)
		main.clear_bosses()
		return
	if b["next_pat"] != "decree":
		_fail("phase 3 did not ask for the final speech (next_pat is '%s')" % str(b["next_pat"]))
	if main.boss_sys.boss_pick_pattern(b) != "decree":
		_fail("the first attack of phase 3 is not a decree")
	if b["next_pat"] != "":
		_fail("the final speech is still asked for after it was picked")
	# a mid boss gets no final speech
	main.clear_bosses()
	main.round_n = 3
	main.boss_count = 2
	main.boss_sys.spawn_boss()
	var m = main.bosses[0]
	m["hp"] = int(float(m["max_hp"]) * 0.34) + 1
	m["mode"] = "charge"
	main.boss_sys.hit_boss(m, 2, false, 0.0)
	if m["next_pat"] != "":
		_fail("a %s got the president's final speech" % m["kind"])
	main.clear_bosses()


func _check_defeat() -> void:
	var b = _president(6.0)
	b["hp"] = 1
	main.final_boss_dead = false
	main.boss_sys.hit_boss(b, 5, false, 0.0)
	if b["mode"] != "dying" or not main.final_boss_dead:
		_fail(
			(
				"a final boss at 1 health did not die (mode %s, final_boss_dead %s)"
				% [b["mode"], str(main.final_boss_dead)]
			)
		)
	var ring: MeshInstance3D = b["ring"]
	var beam: MeshInstance3D = b["beam"]
	if ring.visible or beam.visible:
		_fail("the ring or beam is still shown on a defeated president")
	main.clear_bosses()
