extends SceneTree
# Checks the Heat MODIFIERS page (README Milestone B, "Difficulty Scaling", chunk H2.4; design in docs/HEAT.md):
#   - the rules the page uses (`Heat.try_step`, `preset_step`, `settle`, `preset_matching`, `custom_set`): a rank goes up by
#     one and down by one, never past the top rank, never into a clash (with the reason from the table), never past the Heat
#     that is open, and going down is always allowed; a set that is a preset is kept as its level, any other set is kept as
#     the player's own with the Heat of its points,
#   - the page opens from the PLAY page (button, M, the gamepad's X), goes back to it (Esc, the gamepad's B, a click beside
#     the page), and a run is not started by any of that,
#   - the keyboard, the gamepad and the mouse change ranks, step through the presets, reset, and wrap round,
#   - a set of the player's own is played by the next run (hearts, effects), a preset plays by level exactly as before, a
#     restart keeps the set, a Daily Run drops it, and a set played by other code is left alone by `start_game`,
#   - everything is written out (rank text, the points of every rank, a tag and a reason for a rank that cannot go up), and
#     the page draws for several sets at two window shapes with every control on the screen and none on another.
# Run from the project folder:
#   godot --headless --path . --script res://tools/heat_mods_check.gd
# or: python tools/run_checks.py heat_mods
# Exits with status 1 and prints the problems when a check fails.

const SETTINGS_PATH = "user://settings.cfg"
const SEED = 0x1234ABCD
const START_HEARTS = 3
const HeatScript = preload("res://scripts/heat.gd")

var problems = []
var main
var kept_settings = PackedByteArray()
var had_settings = false


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_keep_settings()
	main.go_to_title()
	main.meta.heat_open = main.heat_sys.top_level()  # the page is the subject here, so every level is open (the lock is in heat_check)
	main.heat = 0
	main.heat_ranks = {}
	_check_rules()
	_check_steps_everywhere()
	_check_words()
	_check_opens_and_goes_back()
	_check_keyboard_and_gamepad()
	_check_open_limit_and_clash()
	_check_presets_and_reset()
	_check_mouse()
	_check_play()
	await _check_drawing()
	_restore_settings()
	_finish()


# ---------------------------------------------------------------- the rules (heat.gd)


func _check_rules() -> void:
	var h = main.heat_sys
	var top = h.top_level()
	# a preset is found by its ranks, rank 0 and a missing id are the same, a set of your own is not found
	for lv in range(top + 1):
		if h.preset_matching(h.preset_ranks(lv)) != lv:
			_fail("preset_matching did not find preset %d from its own ranks" % lv)
	if h.preset_matching({"swift": 1, "crowd": 0}) != 1:
		_fail("a rank 0 should read like a missing modifier: {swift 1, crowd 0} is preset 1")
	if h.preset_matching({"swift": 2}) != -1:
		_fail("{swift 2} is not a preset but preset_matching found one")
	# going up and down by one, without changing the set that was passed in
	var start = {"swift": 1}
	var up = h.try_step(start, "swift", 1, 12)
	if not up["ok"] or int(up["ranks"].get("swift", 0)) != 2 or up["why"] != "":
		_fail("swift 1 +1 with 12 open gave %s" % str(up))
	if start != {"swift": 1}:
		_fail("try_step changed the set that was passed in")
	var down = h.try_step({"swift": 1}, "swift", -1, 12)
	if not down["ok"] or down["ranks"].has("swift"):
		_fail("swift 1 -1 should leave swift out of the set (rank 0), got %s" % str(down))
	var off = h.try_step({}, "swift", -1, 12)
	if off["ok"] or off["kind"] != "off" or str(off["why"]).is_empty():
		_fail("a modifier that is off cannot go down, got %s" % str(off))
	var topped = h.try_step({"swift": h.max_rank("swift")}, "swift", 1, 99)
	if topped["ok"] or topped["kind"] != "top" or str(topped["why"]).is_empty():
		_fail("a modifier at its top rank cannot go up, got %s" % str(topped))
	var unknown = h.try_step({}, "no_such_modifier", 1, 12)
	if unknown["ok"] or str(unknown["why"]).is_empty():
		_fail("a modifier that does not exist can go up, got %s" % str(unknown))
	# the Heat that is open: going up past it is refused with a reason, going down never is
	var shut = h.try_step({}, "swift", 1, 0)
	if shut["ok"] or shut["kind"] != "open" or not str(shut["why"]).contains("NOT OPEN"):
		_fail(
			(
				"a rank worth 1 Heat with only Heat 0 open should be refused as not open, got %s"
				% str(shut)
			)
		)
	if not h.try_step({}, "swift", 1, 1)["ok"]:
		_fail("a rank worth 1 Heat with Heat 1 open was refused")
	if not h.try_step({"swift": h.max_rank("swift")}, "swift", -1, 0)["ok"]:
		_fail("going down was refused when the set is worth more than the open Heat")
	# every clash of the table is refused, with its own reason
	for c in h.clashes:
		var ranks = {c["a_id"]: int(c["a_rank"]), c["b_id"]: maxi(int(c["b_rank"]) - 1, 0)}
		if int(ranks[c["b_id"]]) == 0:
			ranks.erase(c["b_id"])
		var step = h.try_step(ranks, str(c["b_id"]), 1, 99)
		if step["ok"] or step["kind"] != "clash" or step["why"] != c["why"]:
			_fail("the clash %s was not refused with its reason, got %s" % [str(c), str(step)])
	# presets one step from a preset, and from a set of your own
	if (
		h.preset_step(h.preset_ranks(2), 1, top) != 3
		or h.preset_step(h.preset_ranks(2), -1, top) != 1
	):
		_fail("preset 2 should step to 3 and to 1")
	if h.preset_step(h.preset_ranks(0), -1, top) != -1:
		_fail("there is no preset below Heat 0")
	if h.preset_step(h.preset_ranks(top), 1, top) != -1:
		_fail("there is no preset above the top one")
	if h.preset_step(h.preset_ranks(2), 1, 2) != -1:
		_fail("preset 3 was offered with only Heat 2 open")
	var own = {"swift": 2}  # worth 2 points, not a preset
	if (
		h.preset_step(own, -1, top) != h.total_points(own)
		or h.preset_step(own, 1, top) != h.total_points(own) + 1
	):
		_fail(
			(
				"a set of your own worth %d should step down to the preset of the same Heat and up to the next"
				% h.total_points(own)
			)
		)
	# what Main keeps: a preset is a level, anything else is the player's own set with the Heat of its points
	var kept = h.settle(h.preset_ranks(3))
	if kept["heat"] != 3 or not kept["ranks"].is_empty():
		_fail("settle(preset 3) should give Heat 3 and no set of your own, got %s" % str(kept))
	kept = h.settle(own)
	if kept["heat"] != h.total_points(own) or kept["ranks"] != own:
		_fail("settle({swift 2}) should keep the set at the Heat of its points, got %s" % str(kept))
	kept = h.settle({})
	if kept["heat"] != 0 or not kept["ranks"].is_empty():
		_fail("settle({}) should be Heat 0 with no set, got %s" % str(kept))
	# custom_set: only a legal set, with a rank in it, worth the Heat of the run, that is not a preset
	main.heat_ranks = own
	main.heat = h.total_points(own)
	if h.custom_set() != own:
		_fail("a chosen set that matches the Heat of the run was not read back")
	main.heat = 0
	if not h.custom_set().is_empty():
		_fail("a chosen set worth %d was read at Heat 0" % h.total_points(own))
	main.heat = 1
	main.heat_ranks = h.preset_ranks(1)
	if not h.custom_set().is_empty():
		_fail("a preset was read as a set of your own")
	main.heat_ranks = {}
	main.heat = 0


# every set, every modifier, both directions: a step that is allowed changes that one modifier by one rank, leaves a legal
# set, and never goes up past the open Heat
func _check_steps_everywhere() -> void:
	var h = main.heat_sys
	var all = []
	_all_sets(h.modifier_ids(), 0, {}, all)
	var checked = 0
	for open_total in [0, 3, 12]:
		for ranks in all:
			if not h.is_legal(ranks):
				continue
			for id in h.modifier_ids():
				for d in [-1, 1]:
					var step = h.try_step(ranks, id, d, open_total)
					checked += 1
					if not step["ok"]:
						if str(step["why"]).is_empty() or step["ranks"] != ranks:
							_fail(
								(
									"a refused step must say why and change nothing: %s %s %d"
									% [str(ranks), id, d]
								)
							)
						continue
					var next = step["ranks"]
					if int(next.get(id, 0)) != int(ranks.get(id, 0)) + d:
						_fail(
							(
								"%s %s %d moved by other than one rank: %s"
								% [str(ranks), id, d, str(next)]
							)
						)
					for other in h.modifier_ids():
						if other != id and int(next.get(other, 0)) != int(ranks.get(other, 0)):
							_fail("%s %s %d changed %s too" % [str(ranks), id, d, other])
					if not h.is_legal(next):
						_fail(
							"%s %s %d gave a set with a clash: %s" % [str(ranks), id, d, str(next)]
						)
					if d > 0 and h.total_points(next) > open_total:
						_fail(
							(
								"%s %s +1 went past the open Heat %d: %s"
								% [str(ranks), id, open_total, str(next)]
							)
						)
	if checked < 1000:
		_fail("only %d steps were checked, the table should give thousands" % checked)


func _all_sets(ids: Array, i: int, ranks: Dictionary, out: Array) -> void:
	if i >= ids.size():
		out.append(ranks.duplicate())
		return
	for r in range(main.heat_sys.max_rank(ids[i]) + 1):
		var next = ranks.duplicate()
		if r > 0:
			next[ids[i]] = r
		_all_sets(ids, i + 1, next, out)


# ---------------------------------------------------------------- written out, so colour is never the only sign


func _check_words() -> void:
	var h = main.heat_sys
	for id in h.modifier_ids():
		if h.rank_text(id, 0) != "OFF":
			_fail("rank 0 of %s is written %s, expected OFF" % [id, h.rank_text(id, 0)])
		for r in range(1, h.max_rank(id) + 1):
			if h.rank_text(id, r) != "RANK %d OF %d" % [r, h.max_rank(id)]:
				_fail("rank %d of %s is written %s" % [r, id, h.rank_text(id, r)])
			if h.rank_desc(id, r).is_empty():
				_fail("rank %d of %s has no description" % [r, id])
			var line = h.points_line(id, r)
			if not line.contains("[%d]" % h.points_of(id, r)) or line.count("/") != h.max_rank(id):
				_fail("the points line of %s at rank %d is wrong: %s" % [id, r, line])
		if h.rank_desc(id, 0).is_empty() or h.modifier_name(id).is_empty():
			_fail("%s has no name or no text for rank 0" % id)
	var text = h.set_text(h.preset_ranks(h.top_level()))
	for id in h.modifier_ids():
		if h.preset_ranks(h.top_level()).has(id) and not text.contains(h.modifier_name(id)):
			_fail("the text of the top preset leaves out %s: %s" % [id, text])
	if not h.set_text({}).is_empty():
		_fail("an empty set should have no text")
	# the Heat line and the line under the list say what is going on for every row, with no colour needed
	main.heat = 0
	main.heat_ranks = {}
	main.go_to_title()
	main.title_page = "heat_mods"
	var rows = main.hud.heat_mods_rows()
	for i in range(rows.size()):
		if main.hud.heat_mods_status(i).is_empty():
			_fail("row %d of the modifiers page has no status line" % i)
	if main.hud.heat_mods_total_text().is_empty():
		_fail("the modifiers page has no Heat line")
	main.go_to_title()


# ---------------------------------------------------------------- the page opens and goes back


func _open_play() -> void:
	main.go_to_title()
	main.input_sys.title_activate(_entry("play"))


func _open_page() -> void:
	_open_play()
	_press(KEY_M)


func _entry(id: String) -> int:
	for i in range(main.hud.TITLE_ITEMS.size()):
		if main.hud.TITLE_ITEMS[i]["id"] == id:
			return i
	return -1


func _check_opens_and_goes_back() -> void:
	main.heat = 0
	main.heat_ranks = {}
	_open_play()
	if main.title_page != "play":
		_fail(
			(
				"PLAY did not open the PLAY page, the modifiers page cannot be reached (page '%s')"
				% main.title_page
			)
		)
		return
	_press(KEY_M)
	if main.title_page != "heat_mods" or main.state != "title":
		_fail(
			(
				"M on the PLAY page did not open the modifiers page (state '%s', page '%s')"
				% [main.state, main.title_page]
			)
		)
	_press(KEY_ESCAPE)
	if main.title_page != "play" or main.state != "title":
		_fail(
			(
				"Esc on the modifiers page did not go back to the PLAY page (page '%s')"
				% main.title_page
			)
		)
	main.input_sys.on_pad_button(JOY_BUTTON_X)
	if main.title_page != "heat_mods":
		_fail(
			(
				"the gamepad's X on the PLAY page did not open the modifiers page (page '%s')"
				% main.title_page
			)
		)
	main.input_sys.on_pad_button(JOY_BUTTON_B)
	if main.title_page != "play":
		_fail(
			(
				"the gamepad's B on the modifiers page did not go back to the PLAY page (page '%s')"
				% main.title_page
			)
		)
	# M opens the page from the PLAY page only
	main.go_to_title()
	_press(KEY_M)
	if main.title_page != "":
		_fail("M on the title menu opened a page (%s)" % main.title_page)
	main.go_to_title()


# ---------------------------------------------------------------- keyboard and gamepad


func _check_keyboard_and_gamepad() -> void:
	var h = main.heat_sys
	main.meta.heat_open = h.top_level()
	main.heat = 0
	main.heat_ranks = {}
	_open_page()
	var n = main.hud.heat_mods_rows().size()
	if main.heat_sel != 0:
		_fail("the page should open on the first row, not %d" % main.heat_sel)
	_press(KEY_UP)
	if main.heat_sel != n - 1:
		_fail("Up from the first row should wrap to the last (%d), got %d" % [n - 1, main.heat_sel])
	_press(KEY_DOWN)
	if main.heat_sel != 0:
		_fail("Down from the last row should wrap to the first, got %d" % main.heat_sel)
	main.input_sys.on_pad_button(JOY_BUTTON_DPAD_DOWN)
	if main.heat_sel != 1:
		_fail("the D-pad down should move to the second row, got %d" % main.heat_sel)
	main.input_sys.on_pad_button(JOY_BUTTON_DPAD_UP)
	if main.heat_sel != 0:
		_fail("the D-pad up should move back to the first row, got %d" % main.heat_sel)
	# the first modifier (SWIFT RIDERS): Right goes up a rank, and rank 1 is the preset of Heat 1, so it is kept as the level
	var id = str(main.hud.heat_mods_rows()[0]["id"])
	_press(KEY_RIGHT)
	if main.heat != 1 or not main.heat_ranks.is_empty() or int(h.chosen_ranks().get(id, 0)) != 1:
		_fail(
			(
				"Right on the first row should give the preset of Heat 1, got Heat %d and %s"
				% [main.heat, str(main.heat_ranks)]
			)
		)
	_press(KEY_RIGHT)
	var want = h.total_points({id: 2})
	if main.heat != want or main.heat_ranks != {id: 2} or h.custom_set() != {id: 2}:
		_fail(
			(
				"rank 2 of %s should be a set of your own worth Heat %d, got Heat %d and %s"
				% [id, want, main.heat, str(main.heat_ranks)]
			)
		)
	if h.label(-1, true) != "HEAT %d  CUSTOM" % want:
		_fail("a set of your own should be called CUSTOM, got '%s'" % h.label(-1, true))
	if _saved_heat() != want:
		_fail(
			(
				"the Heat of the chosen set was not saved in settings.cfg (%d, expected %d)"
				% [_saved_heat(), want]
			)
		)
	main.input_sys.on_pad_button(JOY_BUTTON_DPAD_LEFT)
	if main.heat != 1 or not main.heat_ranks.is_empty():
		_fail(
			(
				"the D-pad left should go back to rank 1, the preset of Heat 1 (Heat %d, %s)"
				% [main.heat, str(main.heat_ranks)]
			)
		)
	_press(KEY_LEFT)
	if main.heat != 0 or not main.heat_ranks.is_empty():
		_fail("Left at rank 1 should switch the modifier off, back to Heat 0 (Heat %d)" % main.heat)
	var before = main.heat
	_press(KEY_LEFT)
	if main.heat != before:
		_fail("Left on a modifier that is off changed the Heat to %d" % main.heat)
	# Enter and the gamepad's A go up a rank, and from the top rank back to off
	for i in range(h.max_rank(id)):
		_press(KEY_ENTER)
	if int(h.chosen_ranks().get(id, 0)) != h.max_rank(id):
		_fail(
			(
				"Enter %d times should reach the top rank %d of %s"
				% [h.max_rank(id), h.max_rank(id), id]
			)
		)
	main.input_sys.on_pad_button(JOY_BUTTON_A)
	if h.chosen_ranks().has(id):
		_fail("Enter / A at the top rank should wrap round to off, but %s is still on" % id)
	if main.title_page != "heat_mods" or main.state != "title":
		_fail(
			(
				"Enter on the modifiers page left the page (state '%s', page '%s')"
				% [main.state, main.title_page]
			)
		)
	# a change in the level picker leaves a set of your own behind
	main.heat_ranks = {}
	_press(KEY_RIGHT)
	_press(KEY_RIGHT)
	_press(KEY_ESCAPE)
	if main.heat_ranks.is_empty():
		_fail("setup: the page should hold a set of your own now")
	_press(KEY_RIGHT)
	if not main.heat_ranks.is_empty():
		_fail("the level picker left the set of your own in place at Heat %d" % main.heat)
	main.heat = 0
	main.heat_ranks = {}
	main.go_to_title()


# ---------------------------------------------------------------- the open Heat and the clashes, through the page


func _row_of(id: String) -> int:
	var rows = main.hud.heat_mods_rows()
	for i in range(rows.size()):
		if rows[i].get("id", "") == id:
			return i
	return -1


func _check_open_limit_and_clash() -> void:
	var h = main.heat_sys
	# a player with only Heat 1 open can switch SWIFT RIDERS on and not past it
	main.meta.heat_open = 1
	main.heat = 0
	main.heat_ranks = {}
	_open_page()
	main.heat_sel = _row_of("swift")
	_press(KEY_RIGHT)
	if main.heat != 1:
		_fail(
			"with Heat 1 open, rank 1 of swift (1 Heat) should be allowed, got Heat %d" % main.heat
		)
	_press(KEY_RIGHT)
	if main.heat != 1 or not main.heat_ranks.is_empty():
		_fail(
			(
				"with Heat 1 open, rank 2 of swift was allowed (Heat %d, %s)"
				% [main.heat, str(main.heat_ranks)]
			)
		)
	if not main.hud.heat_mods_status(main.heat_sel).contains("NOT OPEN"):
		_fail(
			(
				"the line under the list should say the Heat is not open: '%s'"
				% main.hud.heat_mods_status(main.heat_sel)
			)
		)
	if main.hud.heat_mods_tag("swift") != "NOT OPEN YET":
		_fail("the row should be tagged NOT OPEN YET, got '%s'" % main.hud.heat_mods_tag("swift"))
	_press(KEY_ENTER)
	if main.heat != 1:
		_fail("Enter should not go past the open Heat either (Heat %d)" % main.heat)
	# with every level open, a clash is refused with the reason of the table. The page can only hold a set worth as much as the
	# top level of the ladder, so a clash is tried from the set one rank short of it, when that set fits
	main.meta.heat_open = h.top_level()
	var tried = 0
	for c in h.clashes:
		var b_id = str(c["b_id"])
		var base = {str(c["a_id"]): int(c["a_rank"])}
		if int(c["b_rank"]) > 1:
			base[b_id] = int(c["b_rank"]) - 1
		if h.total_points(base) > h.top_level():
			continue
		var kept = h.settle(base)
		main.heat = int(kept["heat"])
		main.heat_ranks = kept["ranks"]
		main.heat_sel = _row_of(b_id)
		_press(KEY_RIGHT)
		tried += 1
		if h.chosen_ranks() != base:
			_fail(
				"%s went up into the clash with %s: %s" % [b_id, c["a_id"], str(h.chosen_ranks())]
			)
		if not main.hud.heat_mods_status(main.heat_sel).contains(str(c["why"])):
			_fail(
				(
					"the line under the list does not give the reason of the clash: '%s'"
					% main.hud.heat_mods_status(main.heat_sel)
				)
			)
		if main.hud.heat_mods_tag(b_id) != "CLASH":
			_fail(
				(
					"the row of %s should be tagged CLASH, got '%s'"
					% [b_id, main.hud.heat_mods_tag(b_id)]
				)
			)
	if tried == 0:
		_fail("no clash of the table could be tried on the page")
	main.heat = 0
	main.heat_ranks = {}
	main.go_to_title()


# ---------------------------------------------------------------- PRESET and RESET


func _check_presets_and_reset() -> void:
	var h = main.heat_sys
	var top = h.top_level()
	main.meta.heat_open = top
	main.heat = 0
	main.heat_ranks = {}
	_open_page()
	var n_mod = h.modifier_ids().size()
	var preset_row = n_mod
	var reset_row = n_mod + 1
	if main.hud.heat_mods_rows().size() != n_mod + 2:
		_fail("the page should have a row per modifier, then PRESET, then RESET")
	main.heat_sel = preset_row
	for lv in range(1, top + 1):
		_press(KEY_RIGHT)
		if main.heat != lv or not main.heat_ranks.is_empty():
			_fail(
				(
					"Right on PRESET should go to the preset of Heat %d, got Heat %d and %s"
					% [lv, main.heat, str(main.heat_ranks)]
				)
			)
		if h.chosen_ranks() != h.preset_ranks(lv):
			_fail(
				(
					"after PRESET to Heat %d the set is %s, not that preset"
					% [lv, str(h.chosen_ranks())]
				)
			)
	var at_top = main.heat
	_press(KEY_RIGHT)
	if main.heat != at_top:
		_fail("Right on the last preset changed the Heat to %d" % main.heat)
	_press(KEY_ENTER)
	if main.heat != 0:
		_fail("Enter on PRESET at the last preset should wrap to Heat 0, got Heat %d" % main.heat)
	for lv in range(top, 0, -1):
		main.heat = lv
		main.heat_ranks = {}
		_press(KEY_LEFT)
		if main.heat != lv - 1:
			_fail(
				"Left on PRESET at Heat %d should go to Heat %d, got %d" % [lv, lv - 1, main.heat]
			)
	# a set of your own steps to the preset of the same Heat, then up
	var own = {"swift": 2}
	var kept = h.settle(own)
	main.heat = int(kept["heat"])
	main.heat_ranks = kept["ranks"]
	_press(KEY_LEFT)
	if main.heat != h.total_points(own) or not main.heat_ranks.is_empty():
		_fail(
			(
				"Left on PRESET from a set worth %d should give the preset of Heat %d, got Heat %d"
				% [h.total_points(own), h.total_points(own), main.heat]
			)
		)
	# RESET
	main.heat = int(kept["heat"])
	main.heat_ranks = kept["ranks"]
	main.heat_sel = reset_row
	_press(KEY_ENTER)
	if main.heat != 0 or not main.heat_ranks.is_empty() or not h.chosen_ranks().is_empty():
		_fail(
			(
				"RESET should give Heat 0 and no ranks, got Heat %d and %s"
				% [main.heat, str(h.chosen_ranks())]
			)
		)
	if main.title_page != "heat_mods":
		_fail("RESET left the page (page '%s')" % main.title_page)
	main.go_to_title()


# ---------------------------------------------------------------- the mouse


func _check_mouse() -> void:
	var h = main.heat_sys
	main.hud.size = Vector2(1280.0, 720.0)
	main.meta.heat_open = h.top_level()
	main.heat = 0
	main.heat_ranks = {}
	_open_play()
	if _click_at(main.hud.heat_mods_button_rect().get_center()):
		if main.title_page != "heat_mods":
			_fail(
				(
					"a click on the MODIFIERS button did not open the page (page '%s')"
					% main.title_page
				)
			)
		var i = _row_of("crowd")
		if _click_at(main.hud.heat_mods_arrow_rect(i, 1).get_center()):
			if main.heat_sel != i or int(h.chosen_ranks().get("crowd", 0)) != 1:
				_fail("a click on the right arrow of CROWD should select it and go up a rank")
			if _click_at(main.hud.heat_mods_arrow_rect(i, -1).get_center()):
				if int(h.chosen_ranks().get("crowd", 0)) != 0:
					_fail("a click on the left arrow of CROWD should go back to off")
		var j = main.hud.heat_mods_rows().size() - 1
		main.heat_sel = 0
		main.heat = 3
		main.heat_ranks = {}
		if _click_at(main.hud.heat_mods_row_rect(j).get_center()):
			if main.heat != 0 or main.heat_sel != j:
				_fail("a click on RESET should reset and select the row (Heat %d)" % main.heat)
		if _click_at(main.hud.heat_mods_row_rect(0).get_center()):
			if main.title_page != "heat_mods" or main.heat_sel != 0:
				_fail("a click on a row beside its arrows should only select it")
		if _click_at(Vector2(4.0, 710.0)):
			if main.title_page != "play":
				_fail(
					(
						"a click beside the modifiers page should go back to the PLAY page (page '%s')"
						% main.title_page
					)
				)
	main.go_to_title()


# ---------------------------------------------------------------- playing a set


func _check_play() -> void:
	var h = main.heat_sys
	main.meta.heat_open = h.top_level()
	main.heat_ranks = {}
	main.heat = 0
	main.own_heat_set_played = false
	h.clear_set()
	# a set of your own (not a preset): FEWER LIVES rank 1 with TOUGH rank 1, worth 2 Heat
	var own = {"lives": 1, "tough": 1}
	if h.preset_matching(own) >= 0 or h.total_points(own) > h.top_level():
		_fail("setup: %s should be a set of your own that is open" % str(own))
		return
	var kept = h.settle(own)
	main.heat = int(kept["heat"])
	main.heat_ranks = kept["ranks"]
	main.start_game(false, SEED)
	if not h.has_set() or h.set_ranks != own or main.heat != h.total_points(own):
		_fail(
			(
				"the run did not play the chosen set (set played %s, ranks %s, Heat %d)"
				% [h.has_set(), str(h.set_ranks), main.heat]
			)
		)
	if main.MAXHEARTS != h.start_hearts() or main.MAXHEARTS >= START_HEARTS:
		_fail(
			(
				"a run with FEWER LIVES started with %d hearts (start_hearts says %d)"
				% [main.MAXHEARTS, h.start_hearts()]
			)
		)
	if not is_equal_approx(h.value("hearts_minus"), 1.0):
		_fail(
			(
				"the effect hearts_minus reads %s while the set is played, expected 1"
				% h.value("hearts_minus")
			)
		)
	# a restart keeps the set
	main.start_game(false, SEED)
	if not h.has_set() or h.set_ranks != own:
		_fail("a restart of the run lost the set of your own")
	# the label names it
	if h.label(-1, true) != "HEAT %d  CUSTOM" % h.total_points(own):
		_fail("the run bar label is '%s', expected CUSTOM after the Heat" % h.label(-1, true))
	# a continued, practice or later run with no set of its own does not keep playing it
	main.reset_run()
	if h.has_set():
		_fail("reset_run left the page's set played")
	# a preset plays by level: no set at all
	main.heat_ranks = {}
	main.heat = 2
	main.start_game(false, SEED)
	if h.has_set():
		_fail("a preset was played as a set (it plays by level)")
	var row = h.level_info(2)
	for key in HeatScript.NEUTRAL:
		if not is_equal_approx(h.value(key), float(row[key])):
			_fail(
				(
					"at Heat 2 the effect %s reads %s, the table says %s"
					% [key, h.value(key), row[key]]
				)
			)
	# Heat 0 changes nothing
	main.heat = 0
	main.start_game(false, SEED)
	for key in HeatScript.NEUTRAL:
		if not is_equal_approx(h.value(key), float(HeatScript.NEUTRAL[key])):
			_fail("at Heat 0 the effect %s reads %s, nothing should change" % [key, h.value(key)])
	if main.MAXHEARTS != START_HEARTS:
		_fail("a Heat 0 run starts with %d hearts, expected %d" % [main.MAXHEARTS, START_HEARTS])
	# a Daily Run drops the set (it is Heat 0 for everybody)
	main.heat = int(kept["heat"])
	main.heat_ranks = kept["ranks"]
	main.start_game(true)
	if (
		h.has_set()
		or main.heat != 0
		or not main.heat_ranks.is_empty()
		or main.MAXHEARTS != START_HEARTS
	):
		_fail(
			(
				"a Daily Run kept the set (set %s, Heat %d, %s, %d hearts)"
				% [h.has_set(), main.heat, str(main.heat_ranks), main.MAXHEARTS]
			)
		)
	# a set that is no longer open (progress was reset) is not played
	main.meta.heat_open = 0
	main.heat = int(kept["heat"])
	main.heat_ranks = kept["ranks"]
	main.start_game(false, SEED)
	if h.has_set():
		_fail("a set worth more than the open Heat was played")
	main.meta.heat_open = h.top_level()
	# a set that other code plays (this check, heat_check) is left alone by start_game
	main.heat_ranks = {}
	main.heat = 0
	h.play_set({"swift": 1})
	main.start_game(false, SEED)
	if not h.has_set() or h.set_ranks != {"swift": 1}:
		_fail("start_game put away a set that the page did not play")
	h.clear_set()
	main.heat = 0
	main.heat_ranks = {}
	main.go_to_title()


# ---------------------------------------------------------------- drawing


func _check_drawing() -> void:
	var h = main.heat_sys
	var top = h.top_level()
	main.meta.heat_open = top
	var cases = [
		[0, {}],
		[2, h.settle({"swift": 2})["ranks"]],
		[top, {}],
		[0, {"lives": 2}],
	]
	for case in cases:
		var kept = h.settle(case[1]) if not case[1].is_empty() else {"heat": case[0], "ranks": {}}
		main.heat = int(kept["heat"])
		main.heat_ranks = kept["ranks"]
		for sel in [0, main.hud.heat_mods_rows().size() - 1]:
			_open_page()
			main.heat_sel = sel
			for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0), Vector2(1024.0, 768.0)]:
				main.hud.size = s
				for f in range(2):
					main.hud.queue_redraw()
					await process_frame
				_check_layout(s)
	main.hud.size = Vector2(1280.0, 720.0)
	main.heat = 0
	main.heat_ranks = {}
	main.go_to_title()


func _check_layout(s: Vector2) -> void:
	var screen = Rect2(Vector2.ZERO, s)
	var hud = main.hud
	var rows = hud.heat_mods_rows()
	var panel = hud.heat_mods_panel_rect()
	if not screen.encloses(panel):
		_fail("the modifiers page does not fit a %s screen: %s" % [str(s), str(panel)])
	for i in range(rows.size()):
		var r = hud.heat_mods_row_rect(i)
		if not panel.encloses(r):
			_fail("row %d is not inside the page on a %s screen" % [i, str(s)])
		if i + 1 < rows.size() and r.intersects(hud.heat_mods_row_rect(i + 1)):
			_fail("rows %d and %d overlap on a %s screen" % [i, i + 1, str(s)])
		if rows[i]["kind"] != "reset":
			var left = hud.heat_mods_arrow_rect(i, -1)
			var right = hud.heat_mods_arrow_rect(i, 1)
			if not r.encloses(left) or not r.encloses(right) or left.intersects(right):
				_fail(
					"the arrows of row %d are not inside it or overlap on a %s screen" % [i, str(s)]
				)
	# the PLAY page's new button
	var b = hud.heat_mods_button_rect()
	if not screen.encloses(b):
		_fail("the MODIFIERS button is not inside a %s screen" % str(s))
	if b.intersects(hud.play_start_rect()) or b.intersects(hud.heat_row_rect()):
		_fail("the MODIFIERS button overlaps START or the Heat row on a %s screen" % str(s))
	# the words under the list never come back empty, and a rank that cannot go up always says why
	var hs = main.heat_sys
	for i in range(rows.size()):
		if hud.heat_mods_status(i).is_empty():
			_fail("row %d has no status line" % i)
	for id in hs.modifier_ids():
		var step = hs.try_step(hs.chosen_ranks(), id, 1, hs.open_level())
		if not step["ok"] and (hud.heat_mods_tag(id).is_empty() or str(step["why"]).is_empty()):
			_fail("%s cannot go up but the page does not say why" % id)


# ---------------------------------------------------------------- helpers


func _saved_heat() -> int:
	var cf = ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return -1
	var v = cf.get_value("game", "heat", -1)
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return -1
	return int(v)


# the real settings.cfg is kept in memory and written back at the end
func _keep_settings() -> void:
	had_settings = FileAccess.file_exists(SETTINGS_PATH)
	if had_settings:
		kept_settings = FileAccess.get_file_as_bytes(SETTINGS_PATH)


func _restore_settings() -> void:
	if had_settings:
		var f = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		if f:
			f.store_buffer(kept_settings)
			f.close()
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	main.settings.load_settings()


# a left click with the mouse over `pos`; false (and no click) when the mouse could not be moved there (headless Godot may not)
func _click_at(pos: Vector2) -> bool:
	main.get_viewport().warp_mouse(pos)
	if main.get_viewport().get_mouse_position().distance_to(pos) > 2.0:
		return false
	main.input_sys.on_click()
	return true


func _press(code: int) -> void:
	var e = InputEventKey.new()
	e.pressed = true
	e.keycode = code
	main.input_sys.handle_input(e)


func _finish() -> void:
	if problems.is_empty():
		print(
			"heat_mods_check: the modifiers page changes ranks and presets by keyboard, gamepad and mouse, keeps to the open Heat and the clashes, writes everything out and plays the chosen set"
		)
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("heat_mods_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
