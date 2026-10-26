extends SceneTree
# Checks the pause-screen map (README Milestone K, "Exploration and extraction"). Run from the project folder:
#   godot --headless --path . --script res://tools/pause_map_check.gd
# or with tools\run_pause_map_check.bat on Windows.
#
# Exploration (scripts/explore_map.gd): a generated round starts with only the ground round the start seen, walking
# somewhere sees the ground there and never un-sees anything, a cache or the extraction point is found only inside
# the objectives' sense range (a taken cache always), and the roundabout has nothing to map. Clearing the round
# forgets it all.
# Page (scripts/hud.gd, scripts/input.gd): the pause menu has a MAP entry that opens the page, the page draws at two
# window sizes (a script error in the drawing code shows up here), Escape and a click go back to the pause menu, and
# Tab does not leave the page.
# Exits with status 1 and prints the problems.

const SEED = 0x2468ACE0

var problems = []


func _initialize() -> void:
	await _roundabout()
	await _generated()
	if problems.is_empty():
		print("pause_map_check: the exploration state and the MAP page of the pause menu hold")
		quit(0)
	else:
		print("pause_map_check: %d problem(s)" % problems.size())
		for p in problems:
			print("  " + p)
		quit(1)


func _fail(text: String) -> void:
	if problems.size() < 40:
		problems.append(text)


func _make_main(generated: bool):
	var m = load("res://main.tscn").instantiate()
	m.generated_arena = generated
	root.add_child(m)
	for i in range(3):
		await process_frame
	return m


func _drop(m) -> void:
	root.remove_child(m)
	m.free()


func _press(key: int) -> void:
	var ev = InputEventKey.new()
	ev.keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)


# the roundabout has no layout, so it has no map
func _roundabout() -> void:
	var m = await _make_main(false)
	if m.explore_sys.enabled() or m.explore_sys.n != 0:
		_fail("roundabout: the exploration state is on (n %d)" % m.explore_sys.n)
	_drop(m)


func _generated() -> void:
	var m = await _make_main(true)
	m.start_game(false, SEED)
	for i in range(3):
		await process_frame
	if m.state == "map":
		m.pick_node(0)
	if m.state != "play":
		_fail("could not start a round (state %s)" % m.state)
		_drop(m)
		return
	var ex = m.explore_sys
	var o = m.objective_sys
	if not ex.enabled() or ex.n != 72:
		_fail("generated round: the exploration state is not set up (n %d)" % ex.n)
		_drop(m)
		return
	# the start: the ground round it is seen, the far corner is not
	var start_cell = ex.cell_of(m.arena.start_position())
	if not ex.cell_seen(start_cell.x, start_cell.y):
		_fail("the cell the round starts in is not seen")
	if ex.cell_seen(0, 0) and ex.cell_seen(ex.n - 1, ex.n - 1):
		_fail("both far corners are seen at the start")
	if ex.seen_count <= 0 or ex.seen_count >= ex.n * ex.n / 4:
		_fail("%d of %d cells are seen at the start" % [ex.seen_count, ex.n * ex.n])
	if ex.cache_found.size() != o.caches.size():
		_fail("%d found flags for %d caches" % [ex.cache_found.size(), o.caches.size()])
	# found only inside the sense range
	_flags_match_distances(m, "at the start")
	# walking to a far point sees the ground there and never takes anything back
	var before = ex.seen_count
	var far: Vector3 = o.goal["pos"]
	m.player.position = far
	ex.update(0.05)
	var fc = ex.cell_of(far)
	if not ex.cell_seen(fc.x, fc.y):
		_fail("the ground at the extraction point is not seen after walking there")
	if ex.seen_count <= before:
		_fail("walking across the arena saw no new ground (%d, then %d)" % [before, ex.seen_count])
	if not ex.goal_found:
		_fail("the extraction point is not found with the player standing on it")
	var after_far = ex.seen_count
	m.player.position = m.arena.start_position()
	ex.update(0.05)
	if ex.seen_count < after_far:
		_fail("walking back un-saw ground (%d, then %d)" % [after_far, ex.seen_count])
	_flags_match_distances(m, "after walking back", true)
	# a cache is found when the player gets near, and a taken one stays found
	for i in range(o.caches.size()):
		var cp: Vector3 = o.caches[i]["pos"]
		m.player.position = cp
		o.update(0.05)  # takes it
		ex.update(0.05)
		if not ex.cache_found[i]:
			_fail("cache %d is not found after taking it" % i)
		if not o.caches[i]["taken"]:
			_fail("cache %d was not taken" % i)
	m.player.position = m.arena.start_position()
	ex.update(0.05)
	for i in range(o.caches.size()):
		if not ex.cache_found[i]:
			_fail("a taken cache (%d) is not found any more after walking away" % i)
	# the pause menu and the page
	await _page(m)
	# the round's end forgets it all
	m.clear_pickups()
	if ex.n != 0 or ex.seen_count != 0 or ex.goal_found or not ex.cache_found.is_empty():
		_fail("clear_pickups left the exploration state behind (n %d)" % ex.n)
	_drop(m)


# a cache or the goal is found exactly when it is inside the sense range now, unless `sticky` (they stay found)
func _flags_match_distances(m, when: String, sticky: bool = false) -> void:
	var ex = m.explore_sys
	var o = m.objective_sys
	for i in range(o.caches.size()):
		var near = o.dist_to(o.caches[i]["pos"]) < o.SENSE_RANGE
		if near and not ex.cache_found[i]:
			_fail("cache %d is in sense range but not found (%s)" % [i, when])
		if not near and ex.cache_found[i] and not sticky and not o.caches[i]["taken"]:
			_fail("cache %d is found from outside the sense range (%s)" % [i, when])
	var gnear = o.dist_to(o.goal["pos"]) < o.SENSE_RANGE
	if gnear and not ex.goal_found:
		_fail("the extraction point is in sense range but not found (%s)" % when)
	if not gnear and ex.goal_found and not sticky:
		_fail("the extraction point is found from outside the sense range (%s)" % when)


func _page(m) -> void:
	m.force_captured = true  # headless Godot cannot capture the mouse, so the test hook plays the round
	await process_frame
	await process_frame
	m.pause_on_focus_loss()
	await process_frame
	await process_frame
	if not m.paused:
		_fail("could not pause the round")
		return
	var hud = m.hud
	hud.size = Vector2(1280.0, 720.0)
	var item = -1
	for i in range(hud.PAUSE_ITEMS.size()):
		if hud.PAUSE_ITEMS[i]["id"] == "map":
			item = i
	if item < 0:
		_fail("the pause menu has no MAP entry")
		return
	for i in range(hud.PAUSE_ITEMS.size() - 1):
		if hud.pause_rect(i).end.y > hud.pause_rect(i + 1).position.y:
			_fail("pause buttons %d and %d overlap" % [i, i + 1])
	var last = hud.pause_rect(hud.PAUSE_ITEMS.size() - 1)
	if last.end.y > hud.size.y * 0.80 - 10.0:
		_fail("the last pause button ends at %.0f, on the ESC TO RESUME text" % last.end.y)
	m.input_sys.pause_activate(item)
	if m.pause_page != "map":
		_fail("choosing MAP in the pause menu opened '%s'" % m.pause_page)
	for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]:
		hud.size = s
		var r = hud.map_rect()
		if r.position.x < 0.0 or r.end.x > s.x or r.end.y > s.y * 0.9:
			_fail("the map square %s does not fit a %s window" % [str(r), str(s)])
		for f in range(2):
			hud.queue_redraw()
			await process_frame
	hud.size = Vector2(1280.0, 720.0)
	if not m.paused:
		_fail("opening the MAP page resumed the game")
	_press(KEY_TAB)
	if m.pause_page != "map":
		_fail("Tab on the MAP page changed the page to '%s'" % m.pause_page)
	m.input_sys.pause_back()
	if m.pause_page != "" or not m.paused:
		_fail("Escape on the MAP page did not go back to the pause menu")
	m.input_sys.pause_activate(item)
	m.input_sys.on_click()
	if m.pause_page != "" or not m.paused:
		_fail("a click did not close the MAP page (page '%s')" % m.pause_page)
	# the other entries still do what they did
	var settings_item = -1
	for i in range(hud.PAUSE_ITEMS.size()):
		if hud.PAUSE_ITEMS[i]["id"] == "settings":
			settings_item = i
	m.input_sys.pause_activate(settings_item)
	if m.pause_page != "settings":
		_fail("the SETTINGS entry opened '%s'" % m.pause_page)
	m.input_sys.pause_back()
