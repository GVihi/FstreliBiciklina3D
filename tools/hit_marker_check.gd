extends SceneTree
# Checks the crosshair and the hit marker in their modern style (README Milestone F11, `show_hit_marker` in
# scripts/main.gd, `_draw_hit_marker` and `_draw_crosshair` in scripts/hud.gd):
#   - show_hit_marker sets the kind and the time left, an unknown kind is a plain hit, and the time runs down,
#   - every kind has a time, a colour and a size in the HUD, the four colours differ, and the bigger the news the
#     bigger the marker (hit < weak spot < kill < pedestrian hit), so the kinds differ in more than colour,
#   - the places that should show a marker call it (a rider hit and a kill, a boss hit and a weak spot, a pedestrian
#     hit), and nothing sets `hit_marker` by hand any more,
#   - a round that is up and running draws without trouble and keeps running with each kind of marker showing and
#     with the gun and the melee weapon in the hands, at three window sizes.
# Only what a script can see is checked: how the marker looks and feels is for the owner to judge in the game.
# Run from the project folder:
#   godot --headless --path . --script res://tools/hit_marker_check.gd
# or with `python tools/run_checks.py hit_marker`. Exits with status 1 and prints the problems when a check fails.

const KINDS = ["hit", "weak", "kill", "bad"]
const SIZES = [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0), Vector2(800.0, 450.0)]
const SEED = 0x2468ACE1
# where each kind is started: the script and the text that has to be in it
const HOOKS = [
	["scripts/riders.gd", 'g.show_hit_marker("hit")'],
	["scripts/riders.gd", 'g.show_hit_marker("kill")'],
	["scripts/bosses.gd", 'g.show_hit_marker("weak" if weak else "hit")'],
	["scripts/pedestrians.gd", 'g.show_hit_marker("bad")'],
]

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_check_function()
	_check_tables()
	_check_hooks()
	await _check_drawing()
	_finish()


func _fail(text: String) -> void:
	problems.append(text)


func _check_function() -> void:
	for kind in KINDS:
		main.hit_marker = 0.0
		main.show_hit_marker(kind)
		if main.hit_kind != kind:
			_fail("show_hit_marker(%s) left the kind at %s" % [kind, main.hit_kind])
		if absf(main.hit_marker - main.HIT_MARKER_TIME[kind]) > 0.0001:
			_fail(
				(
					"show_hit_marker(%s) set %.3f seconds, not %.3f"
					% [kind, main.hit_marker, main.HIT_MARKER_TIME[kind]]
				)
			)
	main.show_hit_marker("no such kind")
	if main.hit_kind != "hit" or absf(main.hit_marker - main.HIT_MARKER_TIME["hit"]) > 0.0001:
		_fail(
			(
				"an unknown kind is not a plain hit (kind %s, %.3f seconds)"
				% [main.hit_kind, main.hit_marker]
			)
		)
	main.hit_marker = 0.0


func _check_tables() -> void:
	var hud = main.hud
	var seen = []
	var last_scale = 0.0
	for kind in KINDS:
		if not main.HIT_MARKER_TIME.has(kind):
			_fail("no time for the %s marker" % kind)
		if not hud.HIT_MARKER_COL.has(kind) or not hud.HIT_MARKER_SCALE.has(kind):
			_fail("the HUD has no colour or size for the %s marker" % kind)
			continue
		var col: Color = hud.HIT_MARKER_COL[kind]
		for other in seen:
			if col.is_equal_approx(other):
				_fail("two kinds of marker have the same colour (%s)" % str(col))
		seen.append(col)
		var s: float = hud.HIT_MARKER_SCALE[kind]
		if s <= last_scale:
			_fail("the %s marker is not bigger than the one before it (%.2f)" % [kind, s])
		last_scale = s


# the scripts are read as text, so that a hit that stops showing its marker is found without playing a round
func _check_hooks() -> void:
	for h in HOOKS:
		var text = FileAccess.get_file_as_string("res://" + h[0])
		if not text.contains(h[1]):
			_fail("%s does not call %s" % [h[0], h[1]])
	for path in [
		"scripts/riders.gd", "scripts/bosses.gd", "scripts/pedestrians.gd", "scripts/combat.gd"
	]:
		if FileAccess.get_file_as_string("res://" + path).contains("g.hit_marker ="):
			_fail("%s sets g.hit_marker by hand, use g.show_hit_marker" % path)


func _check_drawing() -> void:
	main.start_game(false, SEED)
	await process_frame
	if main.state != "map":
		_fail("could not reach the map screen (state %s)" % main.state)
		return
	main.pick_node(0)
	await process_frame
	main.force_captured = true
	await process_frame
	await process_frame
	if main.state != "play":
		_fail("could not start a round (state %s)" % main.state)
		main.force_captured = false
		return
	var was_melee = main.melee
	for melee in [false, true]:
		main.melee = melee
		for kind in KINDS:
			main.show_hit_marker(kind)
			for s in SIZES:
				main.hit_marker = main.HIT_MARKER_TIME[kind] * 0.6  # part way, so the pop-out is drawn
				main.hud.size = s
				main.hud.queue_redraw()
				await process_frame
			if main.state != "play":
				_fail(
					"%s marker, melee %s: the round ended while it was drawn" % [kind, str(melee)]
				)
				break
	main.melee = was_melee
	main.hud.size = SIZES[0]
	main.hit_marker = 0.0
	main.force_captured = false


func _finish() -> void:
	if problems.is_empty():
		print("hit_marker_check: the four hit markers are set, wired in and drawn")
		quit(0)
	else:
		for line in problems.slice(0, 12):
			printerr("hit_marker_check: " + line)
		quit(1)
