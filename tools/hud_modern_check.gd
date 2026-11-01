extends SceneTree
# Checks the in-round HUD in its modern FPS layout (README Milestone F11, `_draw_hud_top`, `_draw_hud_bottom` and the
# pieces under them in scripts/hud.gd):
#   - the new pieces exist and the old full-width top bar and the retro bike icon are gone,
#   - the corners are laid out the same way at three window sizes: the left block, the centre block and the ammo block
#     of the bottom row do not touch each other, and the hint line still sits above the centre block,
#   - a round that is up and running draws without trouble and keeps running while the HUD shows the unusual states:
#     last heart, a combo, hype mode, every pickup, an empty magazine while loading, rapid fire, free darts, the dash
#     on cooldown, the highest style rank, the melee weapon in the hands and a gadget line.
# Only what a script can see is checked: how the HUD looks is for the owner to judge in the game.
# Run from the project folder:
#   godot --headless --path . --script res://tools/hud_modern_check.gd
# or with `python tools/run_checks.py hud_modern`. Exits with status 1 and prints the problems when a check fails.

const SIZES = [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0), Vector2(800.0, 450.0)]
const SEED = 0x2468ACE1

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_check_pieces()
	_check_layout()
	await _check_states()
	_finish()


func _fail(text: String) -> void:
	problems.append(text)


func _check_pieces() -> void:
	var hud = main.hud
	for fn in [
		"_draw_hud_top",
		"_draw_hud_bottom",
		"_draw_hud_vitals",
		"_draw_hud_ammo",
		"_draw_hud_centre"
	]:
		if not hud.has_method(fn):
			_fail("hud.gd has no %s" % fn)
	for fn in ["_draw_top_bar", "_draw_bottom", "_bike_icon"]:
		if hud.has_method(fn):
			_fail("hud.gd still has the old %s" % fn)


# the widths of the three blocks of the bottom row, worked out from the same numbers the drawing uses
func _check_layout() -> void:
	var hud = main.hud
	for s in SIZES:
		var k = s.y / 720.0
		var left_edge = (
			hud.HUD_MARGIN * k - 8.0 * k + 32.0 * k + (main.MAXHEARTS * 48.0 - 4.0) * k + 16.0 * k
		)
		var centre_left = s.x * 0.5 - 65.0 * k
		var centre_right = s.x * 0.5 + 65.0 * k
		var ammo_left = s.x - hud.HUD_MARGIN * k - hud.SLOT_ROW_W * k
		var label = "%dx%d" % [int(s.x), int(s.y)]
		if left_edge >= centre_left - 8.0 * k:
			_fail(
				(
					"%s: the health block (to %.0f) reaches the style badge (from %.0f)"
					% [label, left_edge, centre_left]
				)
			)
		if ammo_left <= centre_right + 8.0 * k:
			_fail(
				(
					"%s: the ammo block (from %.0f) reaches the style bar (to %.0f)"
					% [label, ammo_left, centre_right]
				)
			)
		# the hint line is above the dash label (12 px font, baseline 62 px above the bottom)
		main.hint_txt = "TEST HINT"
		hud.size = s
		var strip = hud.hint_rect(k)
		main.hint_txt = ""
		if strip.end.y > s.y - 74.0 * k:
			_fail(
				(
					"%s: the hint line (to %.0f) reaches the dash label (from %.0f)"
					% [label, strip.end.y, s.y - 74.0 * k]
				)
			)
	main.hud.size = SIZES[0]


func _check_states() -> void:
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
	var states = {
		"normal": {},
		"last heart": {"hearts": 1},
		"combo and style": {"combo": 6, "style": 95.0},
		"hype mode": {"hype_t": 4.5, "hype": 100.0},
		"empty and loading": {"shells": 0, "loading": true},
		"free darts": {"free_shots": 2, "dash_cd": 0.5},
		"all pickups": {"buffs": {"rapid": 4.0, "big": 5.0, "slow": 3.0, "shield": 6.0}},
		"melee in hands": {"melee": true},
	}
	for label in states:
		var saved = _apply(states[label])
		for s in SIZES:
			main.hud.size = s
			main.hud.queue_redraw()
			await process_frame
		_restore(saved)
		if main.state != "play":
			_fail("%s: the round ended while the HUD was drawn (state %s)" % [label, main.state])
			break
	main.hud.size = SIZES[0]
	main.force_captured = false


# sets the values in `changes` on main and returns what they were; "buffs" is a dictionary merged into main.buffs
func _apply(changes: Dictionary) -> Dictionary:
	var saved = {}
	for key in changes:
		if key == "buffs":
			saved[key] = main.buffs.duplicate()
			for b in changes[key]:
				main.buffs[b] = changes[key][b]
		else:
			saved[key] = main.get(key)
			main.set(key, changes[key])
	return saved


func _restore(saved: Dictionary) -> void:
	for key in saved:
		if key == "buffs":
			main.buffs = saved[key]
		else:
			main.set(key, saved[key])


func _finish() -> void:
	if problems.is_empty():
		print("hud_modern_check: the modern HUD is laid out cleanly and draws in every state")
		quit(0)
	else:
		for line in problems.slice(0, 12):
			printerr("hud_modern_check: " + line)
		quit(1)
