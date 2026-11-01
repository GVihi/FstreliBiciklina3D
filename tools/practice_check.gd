extends SceneTree
# Checks "try before buying": the TRY IT button of the Unlocks page takes the player and a weapon into the training
# room (main.gd can_try, start_practice, end_practice; input.gd unlock_try; hud.gd unlock_try_rect, pause_items).
# Run from the project folder:
#   python tools/run_checks.py practice
# or: godot --headless --path . --script res://tools/practice_check.gd
# It checks that
#   - only a weapon the game has can be tried (not a planned one, a perk, a shop item or a cosmetic)
#   - the T key, the gamepad's Y button and a click on the button all start it, only on the Unlocks page, and a
#     weapon that cannot be tried says so and stays on the page
#   - every weapon that can be tried ends up in its own slot of the training room, owned or not (melee weapons in the
#     hands), with the state of a fresh run, the pause menu says BACK TO UNLOCKS and has no RESTART RUN or QUIT TO TITLE
#   - nothing hurts or ends it: damage, a pedestrian hit and game_over change nothing, and the riders keep coming out
#     of the door after the last one is down; nothing is scored, paid or saved (coins, unlocks, the leaderboard and
#     the saved run are as before)
#   - BACK TO UNLOCKS puts the world the session had back (the room stays when the session started in it), opens the
#     Unlocks page on the weapon that was tried, and the next run is played on a generated arena, not in the room
#   - a session that cannot swap its world (the roundabout) refuses and stays on the page
#   - the TRAINING ROOM entry of the title menu takes the player in with the Loadout page's weapons and starting perk
#     (not one weapon), the pause menu says BACK TO MENU, leaving lands on the title menu on that entry, and the
#     roundabout refuses
#   - no pedestrian is ever in the training room, whether the session started in it or came in from the menu
# Exits with status 1 and lists the first problems when a check fails.

const MAIN_SCENE = "res://main.tscn"
const GENERATED = "res://scripts/arena_generated.gd"
const TRAINING = "res://scripts/arena_training.gd"
const DT = 1.0 / 60.0

var problems = []
var main = null


func _initialize() -> void:
	await _check_can_try()
	await _check_generated_session()
	await _check_room_session()
	await _check_roundabout_session()
	await _check_menu_training()
	if problems.is_empty():
		print("practice_check: trying a weapon in the training room works as the roadmap describes")
		quit(0)
	else:
		print("practice_check: %d problem(s)" % problems.size())
		for p in problems.slice(0, 15):
			print("  " + p)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


func _make_main(generated: bool, room: bool) -> void:
	main = load(MAIN_SCENE).instantiate()
	main.generated_arena = generated
	main.training_room = room
	root.add_child(main)
	for i in range(3):
		await process_frame


func _free_main() -> void:
	if main != null:
		main.free()
		main = null
	await process_frame


func _arena_path() -> String:
	return main.arena.get_script().resource_path


func _unlock_index(id: String) -> int:
	for i in range(main.UNLOCKS.size()):
		if main.UNLOCKS[i]["id"] == id:
			return i
	return -1


func _open_unlocks(index: int) -> void:
	main.go_to_title()
	main.title_page = "unlocks"
	main.unlock_sel = index
	main.unlock_msg = ""


func _key(code: int) -> void:
	var e = InputEventKey.new()
	e.keycode = code
	e.pressed = true
	main.input_sys.handle_input(e)


# ---------------------------------------------------------------- what can be tried
func _check_can_try() -> void:
	await _make_main(true, false)
	var tryable = []
	for u in main.UNLOCKS:
		var want = u["kind"] == "weapon" and main.WEAPONS.has(str(u["target"]))
		if main.can_try(u) != want:
			_fail("can_try(%s) is %s, expected %s" % [u["id"], main.can_try(u), want])
		if want:
			tryable.append(u["id"])
	if tryable.size() < 4:
		_fail(
			(
				"only %d unlocks can be tried, expected the pool noodle, the gummy worm and more"
				% tryable.size()
			)
		)
	for id in ["weapon_pool_noodle", "weapon_gummy_worm", "weapon_banana_peel", "weapon_dart_gun"]:
		if not tryable.has(id):
			_fail("%s cannot be tried" % id)
	for u in main.UNLOCKS:
		if u["kind"] != "weapon" and main.can_try(u):
			_fail("%s is not a weapon but can be tried" % u["id"])
		if u.get("planned", false) and main.can_try(u):
			_fail("%s is planned but can be tried" % u["id"])
	await _free_main()


# ---------------------------------------------------------------- a normal game: the generated arena
func _check_generated_session() -> void:
	await _make_main(true, false)
	var coins = main.meta.balance
	var scores_n = main.scores.entries.size()
	var owned_before = main.meta.owned.duplicate() if "owned" in main.meta else null
	if _arena_path() != GENERATED:
		_fail("the game did not start on a generated arena (%s)" % _arena_path())
	# a button that is not on the Unlocks page does nothing
	main.go_to_title()
	_key(KEY_T)
	if main.practice or main.state != "title":
		_fail("T started a practice round outside the Unlocks page")
	# the nothing-to-try message
	var perk = -1
	for i in range(main.UNLOCKS.size()):
		if not main.can_try(main.UNLOCKS[i]):
			perk = i
			break
	if perk >= 0:
		_open_unlocks(perk)
		_key(KEY_T)
		if main.practice or main.state != "title" or main.unlock_msg == "":
			_fail("T on an unlock that cannot be tried did not stay on the page with a message")
	# each weapon that can be tried
	for u in main.UNLOCKS:
		if not main.can_try(u):
			continue
		_open_unlocks(_unlock_index(u["id"]))
		_key(KEY_T)
		await _check_practice_of(u)
		if main.practice:
			main.input_sys.pause_activate(_pause_index("leave_practice"))
		_check_back_on_page(u, false)
	# the gamepad button and the mouse click start it too
	var noodle = _unlock_index("weapon_pool_noodle")
	_open_unlocks(noodle)
	var pad = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_Y
	pad.pressed = true
	main.input_sys.handle_input(pad)
	if not main.practice:
		_fail("the gamepad's Y button did not start the practice round")
	main.input_sys.pause_activate(_pause_index("leave_practice"))
	# the button is on the screen and clear of BUY; a click needs the mouse, which a headless run cannot move, so the
	# click itself is only tried when warp_mouse works here
	var tr: Rect2 = main.hud.unlock_try_rect()
	var br: Rect2 = main.hud.unlock_buy_rect()
	if tr.intersects(br) or not Rect2(Vector2.ZERO, main.hud.size).encloses(tr):
		_fail("the TRY IT button overlaps BUY or is off the screen (%s, BUY %s)" % [tr, br])
	_open_unlocks(noodle)
	main.get_viewport().warp_mouse(tr.get_center())
	if main.get_viewport().get_mouse_position().distance_to(tr.get_center()) < 2.0:
		var click = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = tr.get_center()
		main.input_sys.handle_input(click)
		if not main.practice:
			_fail("a click on the TRY IT button did not start the practice round")
		else:
			main.input_sys.pause_activate(_pause_index("leave_practice"))
	# nothing was paid, scored or saved
	if main.meta.balance != coins:
		_fail("the coins changed from %d to %d" % [coins, main.meta.balance])
	if main.scores.entries.size() != scores_n:
		_fail("the leaderboard changed")
	if owned_before != null and main.meta.owned != owned_before:
		_fail("what the player owns changed")
	if FileAccess.file_exists("user://run.json"):
		_fail("a saved run was written")
	# the next run is not in the room
	main.start_game(false, 4242)
	if _arena_path() != GENERATED or main.training_room:
		_fail("a run after practice is played on %s" % _arena_path())
	await _free_main()


func _pause_index(id: String) -> int:
	var items = main.hud.pause_items()
	for i in range(items.size()):
		if items[i]["id"] == id:
			return i
	return -1


# in the room with this weapon, then play for a while
func _check_practice_of(u: Dictionary) -> void:
	var name = str(u["id"])
	if not main.practice or main.state != "play":
		_fail(
			(
				"%s: TRY did not start a practice round (practice %s, state %s)"
				% [name, main.practice, main.state]
			)
		)
		return
	if _arena_path() != TRAINING or not main.training_room:
		_fail("%s: the practice round is not in the training room (%s)" % [name, _arena_path()])
	if main.player.position != main.arena.start_position():
		_fail("%s: the player is not on the room's start" % name)
	var id = str(u["target"])
	var slot = str(main.WeaponSlots.WEAPON_INFO[id]["slot"])
	var held = (
		main.primary
		if slot == "primary"
		else (main.melee_weapon if slot == "melee" else main.gadget)
	)
	if held != id:
		_fail("%s: the %s slot holds '%s', not '%s'" % [name, slot, held, id])
	if slot == "melee" and not main.melee:
		_fail("%s: the melee weapon is not in the player's hands" % name)
	if main.objective_sys.has_goal() or main.objective_sys.caches.size() > 0:
		_fail("%s: the room has an extraction point or supply caches" % name)
	if main.hearts != main.MAXHEARTS or main.score != 0 or main.round_n != 1:
		_fail("%s: the practice round does not start like a fresh run" % name)
	# the pause menu
	var ids = []
	for it in main.hud.pause_items():
		ids.append(it["id"])
	if not ids.has("leave_practice") or ids.has("restart") or ids.has("title"):
		_fail("%s: the pause menu is %s" % [name, ids])
	# nothing hurts and nothing ends it
	main.force_captured = true
	main.invuln = 0.0
	main.damage_player("TEST", "riders")
	main.damage_player("TEST", "riders")
	main.damage_player("TEST", "riders")
	main.game_over("riders")
	main.end_round()
	main.win_run()
	main.objective_reached()
	if main.hearts != main.MAXHEARTS or main.state != "play":
		_fail(
			(
				"%s: damage or game_over hurt or ended the practice round (hearts %d, state %s)"
				% [name, main.hearts, main.state]
			)
		)
	var civs = main.civs_hit
	main.civ_sys.hit_civ({"pos": Vector3(0.0, 0.0, 0.0), "state": "walk", "t": 0.0, "hop": 0.0})
	if main.hearts != main.MAXHEARTS or main.civs_hit != civs or main.state != "play":
		_fail("%s: a pedestrian hit cost something in the training room" % name)
	# riders come out of the door, and after the last one is gone the next one comes
	var seen = 0
	var waves = 0
	for f in range(int(20.0 / DT)):
		main.player.position = main.clamp_walk(Vector3(0.0, 0.0, 6.0))
		main._process(DT)
		if main.riders.size() > 0:
			seen += 1
		if f % 120 == 119 and main.riders.size() > 0:
			main.clear_riders()
			main.next_idx = main.PER_ROUND  # as if every rider of an ordinary round had been sent
			main.after_wave()
			waves += 1
		if main.state != "play":
			break
	if main.state != "play":
		_fail("%s: the practice round ended by itself (state %s)" % [name, main.state])
	if seen == 0 or waves < 3:
		_fail(
			(
				"%s: riders stopped coming (frames with riders %d, waves cleared %d)"
				% [name, seen, waves]
			)
		)
	if main.hearts != main.MAXHEARTS:
		_fail("%s: a life was lost during 20 seconds of play" % name)


func _check_back_on_page(u: Dictionary, in_room_session: bool) -> void:
	var name = str(u["id"])
	if main.practice or main.state != "title" or main.title_page != "unlocks":
		_fail(
			(
				"%s: BACK TO UNLOCKS did not land on the Unlocks page (practice %s, state %s, page '%s')"
				% [name, main.practice, main.state, main.title_page]
			)
		)
		return
	if main.UNLOCKS[main.unlock_sel]["id"] != u["id"]:
		_fail("%s: the Unlocks page is not on the weapon that was tried" % name)
	if main.riders.size() > 0 or main.bosses.size() > 0:
		_fail("%s: riders are left after leaving the room" % name)
	if in_room_session:
		if _arena_path() != TRAINING or not main.training_room:
			_fail("%s: a session that started in the room is not in the room afterwards" % name)
	elif _arena_path() != GENERATED or main.training_room:
		_fail("%s: the session's arena is %s after leaving the room" % [name, _arena_path()])


# ---------------------------------------------------------------- a session that started in the room
func _check_room_session() -> void:
	await _make_main(true, true)
	var u = main.UNLOCKS[_unlock_index("weapon_dart_gun")]
	_open_unlocks(_unlock_index("weapon_dart_gun"))
	_key(KEY_T)
	if not main.practice or _arena_path() != TRAINING:
		_fail("the room session could not start a practice round")
	main.input_sys.pause_activate(_pause_index("leave_practice"))
	_check_back_on_page(u, true)
	await _free_main()


# ---------------------------------------------------------------- the roundabout cannot be swapped
func _check_roundabout_session() -> void:
	await _make_main(false, false)
	_open_unlocks(_unlock_index("weapon_dart_gun"))
	_key(KEY_T)
	if main.practice or main.state != "title" or main.title_page != "unlocks":
		_fail("the roundabout session started a practice round or left the Unlocks page")
	if main.unlock_msg == "":
		_fail("the roundabout session said nothing when the room could not open")
	await _free_main()


# ---------------------------------------------------------------- the TRAINING ROOM entry of the title menu
func _training_entry() -> int:
	for i in range(main.hud.TITLE_ITEMS.size()):
		if main.hud.TITLE_ITEMS[i]["id"] == "training":
			return i
	return -1


func _check_menu_training() -> void:
	await _make_main(true, false)
	var entry = _training_entry()
	if entry < 0:
		_fail("the title menu has no TRAINING ROOM entry")
		await _free_main()
		return
	var coins = main.meta.balance
	var scores_n = main.scores.entries.size()
	main.go_to_title()
	main.input_sys.title_activate(entry)
	if not main.practice or main.state != "play" or _arena_path() != TRAINING:
		_fail("TRAINING ROOM on the title menu did not start the room")
		await _free_main()
		return
	if not main.practice_unlock.is_empty():
		_fail("TRAINING ROOM on the title menu says a weapon is being tried")
	# the loadout of the Loadout page: the three slots and the starting perk of a normal run
	if main.primary != main.loadout_weapon_id(main.WeaponSlots.PRIMARY):
		_fail("the primary weapon in the room is %s, not the loadout's" % main.primary)
	if main.melee_weapon != main.loadout_weapon_id(main.WeaponSlots.MELEE):
		_fail("the melee weapon in the room is %s, not the loadout's" % main.melee_weapon)
	if main.gadget != main.loadout_weapon_id(main.WeaponSlots.GADGET):
		_fail("the gadget in the room is %s, not the loadout's" % main.gadget)
	var perk = main.start_perk_id()
	if perk != "" and not main.perks.has(perk):
		_fail("the starting perk %s is not active in the room" % perk)
	# the pause menu leaves for the menu, not for the Unlocks page
	var items = main.hud.pause_items()
	var leave = _pause_index("leave_practice")
	if leave < 0 or items[leave]["label"] != "BACK TO MENU":
		_fail("the pause menu in the room from the title menu does not say BACK TO MENU")
	if _pause_index("restart") >= 0 or _pause_index("title") >= 0:
		_fail("the pause menu in the room has RESTART RUN or QUIT TO TITLE")
	# nobody walks through the room
	main.civ_sys.spawn_civ()
	for i in range(600):
		main.civ_sys.update_civs(DT)
	if main.civs.size() > 0:
		_fail("%d pedestrian(s) in the training room" % main.civs.size())
	# nothing was paid, scored or saved
	if main.meta.balance != coins or main.scores.entries.size() != scores_n:
		_fail("the coins or the leaderboard changed in the room")
	if FileAccess.file_exists("user://run.json"):
		_fail("a saved run was written from the room")
	main.input_sys.pause_activate(leave)
	if (
		main.practice
		or main.state != "title"
		or main.title_page != ""
		or main.title_sel != entry
		or _arena_path() != GENERATED
		or main.training_room
	):
		_fail(
			(
				"BACK TO MENU did not land on the title menu on TRAINING ROOM (practice %s, state %s, page '%s', entry %d)"
				% [main.practice, main.state, main.title_page, main.title_sel]
			)
		)
	# the next run is a normal one on a generated arena, and it has pedestrians again
	main.start_game(false, 4242)
	if _arena_path() != GENERATED or main.training_room:
		_fail("a run after the room is played on %s" % _arena_path())
	await _free_main()
	# a session that started in the room has no pedestrian from the first frame
	await _make_main(true, true)
	if main.civs.size() > 0:
		_fail("a session that started in the room has %d pedestrian(s)" % main.civs.size())
	main.go_to_title()
	main.input_sys.title_activate(_training_entry())
	if not main.practice:
		_fail("the room session could not use TRAINING ROOM on the title menu")
	main.input_sys.pause_activate(_pause_index("leave_practice"))
	if _arena_path() != TRAINING or not main.training_room or main.title_page != "":
		_fail("a session that started in the room is not in the room after BACK TO MENU")
	await _free_main()
	# the roundabout cannot be swapped: the entry only clicks
	await _make_main(false, false)
	main.go_to_title()
	main.input_sys.title_activate(_training_entry())
	if main.practice or main.state != "title" or main.title_page != "":
		_fail("the roundabout session started the room or left the title menu")
	await _free_main()
