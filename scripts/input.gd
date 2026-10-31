extends RefCounted
# Input: mouse, keyboard and gamepad handling, menu clicks and weapon switching.
# Shared game state stays on main.gd (g); this file holds the logic.

const WeaponSlots = preload("res://scripts/weapon_slots.gd")
const Toon = preload("res://scripts/toon.gd")

var g = null


func _init(game) -> void:
	g = game


# ================================================================== input
func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var k = g.SENS * g.sens_mul * (g.cam.fov / g.fov_hip)
			g.yaw -= event.relative.x * k
			g.pitch = clampf(g.pitch - event.relative.y * k, -1.45, 1.45)
		else:
			if g.drag_id != "":
				g.hud.apply_slider(g.drag_id, g.get_viewport().get_mouse_position())
			hover_menu(event.position)
	elif event is InputEventMouseButton:
		if not event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				g.drag_id = ""
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			on_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if (
				g.toggle_ads
				and g.state == "play"
				and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
				and not g.melee
			):
				g.ads_on = not g.ads_on
		elif (
			event.button_index == MOUSE_BUTTON_WHEEL_UP
			or event.button_index == MOUSE_BUTTON_WHEEL_DOWN
		):
			if g.state == "play":
				toggle_weapon()
	elif event is InputEventJoypadButton and event.pressed:
		on_pad_button(event.button_index)
	elif event is InputEventKey and event.pressed and not event.echo:
		if g.state == "over" and g.name_entry:
			name_key(event)  # typing a leaderboard name: no hotkeys
			return
		if g.state == "title" and g.title_page == "seed":
			seed_key(event)  # typing a seed: letters like R, V and S must not trigger their hotkeys
			return
		var kc = event.keycode
		if kc == KEY_R:
			if g.state == "shop":
				g.shop_sys.reroll()
			else:
				manual_reload()
		elif kc == KEY_Q:
			if g.state == "play":
				toggle_weapon()
		elif kc == KEY_SPACE:
			if g.state == "shop":
				g.shop_sys.leave_shop()  # in a round Space is free for jumping (Milestone L)
		elif kc == KEY_V:
			if g.state == "play":
				g.player_sys.try_dash()  # dash moved here from Space (Milestone L); voices are toggled in the settings only
		elif kc == KEY_TAB:
			if g.state == "title":
				g.title_page = "" if g.title_page == "settings" else "settings"
			elif g.state == "play":
				if g.paused:
					if g.pause_page == "" or g.pause_page == "settings":
						g.pause_page = "" if g.pause_page == "settings" else "settings"
				else:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif kc == KEY_ENTER or kc == KEY_KP_ENTER:
			menu_confirm()
		elif kc == KEY_LEFT:
			loadout_switch(-1)
			menu_move(-1)
			confirm_move()
			settings_adjust(-1)
		elif kc == KEY_RIGHT:
			loadout_switch(1)
			menu_move(1)
			confirm_move()
			settings_adjust(1)
		elif kc == KEY_UP or kc == KEY_W:
			title_move(-1)
			summary_move(-1)
			pause_move(-1)
			confirm_move()
			settings_move(-1)
		elif kc == KEY_DOWN or kc == KEY_S:
			title_move(1)
			summary_move(1)
			pause_move(1)
			confirm_move()
			settings_move(1)
		elif kc == KEY_1 or kc == KEY_KP_1:
			if g.state == "map" and g.state_t > 0.3:
				g.pick_node(0)
			elif g.state == "upgrade":
				if g.state_t > 0.35:
					g.shop_sys.pick_upgrade(0)
			elif g.state == "shop":
				g.shop_sys.buy(0)
			elif g.state == "rest" and g.state_t > 0.35:
				g.shop_sys.rest_choose(0)
			elif g.state == "play":
				toggle_weapon(false)
		elif kc == KEY_2 or kc == KEY_KP_2:
			if g.state == "map" and g.state_t > 0.3:
				g.pick_node(1)
			elif g.state == "upgrade":
				if g.state_t > 0.35:
					g.shop_sys.pick_upgrade(1)
			elif g.state == "shop":
				g.shop_sys.buy(1)
			elif g.state == "rest" and g.state_t > 0.35:
				g.shop_sys.rest_choose(1)
			elif g.state == "play":
				toggle_weapon(true)
		elif kc == KEY_3 or kc == KEY_KP_3:
			if g.state == "map" and g.state_t > 0.3:
				g.pick_node(2)
			elif g.state == "upgrade" and g.state_t > 0.35:
				g.shop_sys.pick_upgrade(2)
			elif g.state == "shop":
				g.shop_sys.buy(2)
		elif kc == KEY_4 or kc == KEY_KP_4:
			if g.state == "shop":
				g.shop_sys.buy(3)
		elif kc == KEY_F7:
			g.add_note("VOICE EFFECTS " + ("ON" if g.sfx.toggle_voice_fx() else "OFF"), g.GOLD)
		elif kc == KEY_F9:
			g.settings.cycle_quality()
		elif kc == KEY_F10 and Toon.ENABLED:
			g.settings.set_setting("outline", not g.outlines)
			g.add_note("OUTLINES " + ("ON" if g.outlines else "OFF"), g.GOLD)
		elif kc == KEY_DELETE:
			scores_reset_open()  # High Scores page only; does nothing anywhere else or on an empty list
		elif kc == KEY_ESCAPE:
			if g.state == "play" and g.paused:
				pause_back()
			else:
				title_back()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif kc == KEY_F11:
			g.settings.toggle_fullscreen()


# gamepad buttons (sticks and triggers are polled in update_player)
func on_pad_button(btn: int) -> void:
	if btn == JOY_BUTTON_START:
		if g.state == "play":
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if g.state == "play":
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			if btn == JOY_BUTTON_DPAD_UP:
				pause_move(-1)
				confirm_move()
				settings_move(-1)
			elif btn == JOY_BUTTON_DPAD_DOWN:
				pause_move(1)
				confirm_move()
				settings_move(1)
			elif btn == JOY_BUTTON_DPAD_LEFT:
				settings_adjust(-1)
			elif btn == JOY_BUTTON_DPAD_RIGHT:
				settings_adjust(1)
			elif btn == JOY_BUTTON_A:
				pause_activate(g.pause_sel)
			elif btn == JOY_BUTTON_B:
				pause_back()
			return
		if btn == JOY_BUTTON_LEFT_SHOULDER:
			g.player_sys.try_dash()  # dash moved here from A (Milestone L: A is for jumping)
		elif btn == JOY_BUTTON_X:
			manual_reload()
		elif btn == JOY_BUTTON_Y or btn == JOY_BUTTON_RIGHT_SHOULDER:
			toggle_weapon()
		return
	if btn == JOY_BUTTON_DPAD_UP:
		title_move(-1)
		summary_move(-1)
		confirm_move()
		settings_move(-1)
	elif btn == JOY_BUTTON_DPAD_DOWN:
		title_move(1)
		summary_move(1)
		confirm_move()
		settings_move(1)
	elif btn == JOY_BUTTON_DPAD_LEFT:
		loadout_switch(-1)
		menu_move(-1)
		settings_adjust(-1)
	elif btn == JOY_BUTTON_DPAD_RIGHT:
		loadout_switch(1)
		menu_move(1)
		settings_adjust(1)
	elif btn == JOY_BUTTON_A:
		if g.state == "title":
			title_activate(g.title_sel)
		elif g.state == "clear" and g.state_t > 0.8:
			g.shop_sys.enter_upgrade()
		elif g.state == "over" and g.state_t > 0.8:
			if g.name_entry:
				confirm_name()
			else:
				summary_activate(g.summary_sel)
		else:
			menu_confirm()
	elif btn == JOY_BUTTON_B and g.state == "title":
		title_back()
	elif btn == JOY_BUTTON_X and g.state == "title":
		scores_reset_open()
	elif btn == JOY_BUTTON_B and g.state == "shop":
		g.shop_sys.leave_shop()
	elif btn == JOY_BUTTON_X and g.state == "shop":
		g.shop_sys.reroll()


func menu_move(d: int) -> void:
	if g.state == "title" and g.title_page == "unlocks":
		var other = g.hud.unlock_other_column(g.unlock_sel)  # Left / Right: to the other column
		if other != g.unlock_sel:
			g.unlock_sel = other
			g.sfx.play("click")
	elif g.state == "map":
		g.map_sel = posmod(g.map_sel + d, maxi(1, g.map_choices.size()))
	elif g.state == "upgrade":
		g.menu_sel = posmod(g.menu_sel + d, maxi(1, g.offers.size()))
	elif g.state == "shop":
		g.menu_sel = posmod(g.menu_sel + d, maxi(1, g.shop_items.size()))
	elif g.state == "rest":
		g.menu_sel = posmod(g.menu_sel + d, maxi(1, g.rest_opts.size()))
	elif g.state == "over":
		summary_move(d)


func menu_confirm() -> void:
	if g.state == "map":
		if g.state_t > 0.3:
			g.pick_node(g.map_sel)
	elif g.state == "title":
		title_activate(g.title_sel)
	elif g.state == "play" and g.paused:
		pause_activate(g.pause_sel)
	elif g.state == "upgrade" and g.state_t > 0.35:
		g.shop_sys.pick_upgrade(g.menu_sel)
	elif g.state == "shop":
		g.shop_sys.buy(g.menu_sel)
	elif g.state == "rest" and g.state_t > 0.35:
		g.shop_sys.rest_choose(g.menu_sel)
	elif g.state == "clear" and g.state_t > 0.8:
		g.shop_sys.enter_upgrade()
	elif g.state == "over":
		summary_activate(g.summary_sel)


# ---- run summary buttons: NEW RUN, UNLOCKS, TITLE (listed in hud.gd SUMMARY_ITEMS, drawn by _draw_summary_buttons)
# Up / Down / W / S and the pad's D-pad (and Left / Right through menu_move) move the highlight, Enter or the pad's A
# press it, the mouse highlights what it is over and a click presses it. Nothing reacts for the first 0.8 s or while a
# leaderboard name is typed (hud.summary_active).
func summary_move(d: int) -> void:
	if not g.hud.summary_active():
		return
	g.summary_sel = posmod(g.summary_sel + d, g.hud.SUMMARY_ITEMS.size())
	g.sfx.play("click")


# a left click on the summary: the name box confirms a typed name, a button is pressed, anything else does nothing
func click_summary(pos: Vector2) -> void:
	if g.name_entry:
		confirm_name()
		return
	var i = g.hud.summary_at(pos)
	if i >= 0:
		summary_activate(i)


func summary_activate(i: int) -> void:
	if not g.hud.summary_active():
		return
	if i < 0 or i >= g.hud.SUMMARY_ITEMS.size():
		return
	g.summary_sel = i
	var id = g.hud.SUMMARY_ITEMS[i]["id"]
	if id == "new_run":
		g.restart_run()  # a new seed in a normal run, the same seed again in a Daily Run or a run on a typed-in seed
	elif id == "unlocks":
		open_unlocks_from_summary()  # Esc goes back to the title menu, not to this summary
	else:
		g.go_to_title()


# ---- leaderboard name entry (run summary)
const MAX_NAME = 10


func name_key(event: InputEventKey) -> void:
	if g.state_t < 0.8:
		return  # keys still held from the last second of the run must not type
	var kc = event.keycode
	if kc == KEY_ENTER or kc == KEY_KP_ENTER or kc == KEY_ESCAPE:
		confirm_name()
	elif kc == KEY_BACKSPACE:
		g.name_buf = g.name_buf.substr(0, maxi(0, g.name_buf.length() - 1))
	elif event.unicode > 31 and g.name_buf.length() < MAX_NAME:
		var ch = char(event.unicode).to_upper()
		var ok = (
			ch.to_lower() != ch.to_upper()
			or "0123456789-_.".contains(ch)
			or (ch == " " and g.name_buf != "")
		)
		if ok:
			g.name_buf += ch


# ---- custom seed page (title screen): up to 8 hex digits, the same text the game shows as a seed
const MAX_SEED_DIGITS = 8


func seed_key(event: InputEventKey) -> void:
	var kc = event.keycode
	if kc == KEY_ESCAPE:
		title_back()
	elif kc == KEY_ENTER or kc == KEY_KP_ENTER:
		seed_start()
	elif kc == KEY_BACKSPACE:
		g.seed_buf = g.seed_buf.substr(0, maxi(0, g.seed_buf.length() - 1))
	elif kc == KEY_V and (event.ctrl_pressed or event.meta_pressed):
		for i in range(DisplayServer.clipboard_get().length()):
			seed_add_char(DisplayServer.clipboard_get()[i])
	elif event.unicode > 31:
		seed_add_char(char(event.unicode))


# adds one typed character when it is a hex digit and there is room (so a pasted "0x7F3A..." drops the x)
func seed_add_char(ch: String) -> void:
	var up = ch.to_upper()
	if (
		g.seed_buf.length() < MAX_SEED_DIGITS
		and up.length() == 1
		and "0123456789ABCDEF".contains(up)
	):
		g.seed_buf += up


# starts a normal-looking run on the typed seed (it is not ranked, see Main.ranked_run)
func seed_start() -> void:
	if g.seed_buf == "":
		g.sfx.play("click")
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	g.start_game(false, g.seed_buf.hex_to_int())


func confirm_name() -> void:
	var nm = g.name_buf.strip_edges()
	if nm == "":
		nm = "PLAYER"
	g.player_name = nm
	g.name_entry = false
	g.scores.set_name(g.last_rank, nm)
	g.settings.save_settings()
	g.sfx.play("click")


# Moving the mouse over a title / pause button selects it, so the keyboard and the mouse share
# one highlight (title_sel / pause_sel). Staying in the gap between two buttons keeps the last one.
func hover_menu(pos: Vector2) -> void:
	var ri = g.hud.setting_row_at(pos)
	if ri >= 0:
		g.setting_sel = ri
	var ti = g.hud.title_at(pos)
	if ti >= 0:
		g.title_sel = ti
	var pi = g.hud.pause_at(pos)
	if pi >= 0:
		g.pause_sel = pi
	var ci = g.hud.confirm_at(pos)
	if ci >= 0:
		g.confirm_sel = ci
	var si = g.hud.scores_confirm_at(pos)
	if si >= 0:
		g.confirm_sel = si
	var ui = g.hud.unlock_at(pos)
	if ui >= 0:
		g.unlock_sel = ui
	var ni = g.hud.summary_at(pos)
	if ni >= 0:
		g.summary_sel = ni
	var li = g.hud.loadout_at(pos)
	if li >= 0:
		g.loadout_sel = li
		g.loadout_col = 0
	var wi = g.hud.loadout_slot_at(pos)
	if wi >= 0:
		g.loadout_slot = wi
		g.loadout_col = 1
	if g.state == "map":
		var mi = g.hud.map_choice_at(pos)
		if mi >= 0:
			g.map_sel = mi


# ---- title screen menu (entries are listed in hud.gd TITLE_ITEMS)
func title_move(d: int) -> void:
	if g.state == "title" and g.title_page == "":
		# top to bottom: CONTINUE (when a run is saved, drawn above PLAY), then the entries in order
		var order = []
		if g.hud.title_has_continue():
			order.append(g.hud.TITLE_CONTINUE)
		for n in range(g.hud.TITLE_ITEMS.size()):
			order.append(n)
		var at = maxi(0, order.find(g.title_sel))
		g.title_sel = order[posmod(at + d, order.size())]
		g.sfx.play("click")
	elif g.state == "title" and g.title_page == "loadout":
		if g.loadout_col == 1:
			g.loadout_slot = posmod(g.loadout_slot + d, WeaponSlots.SLOTS.size())
		else:
			g.loadout_sel = posmod(g.loadout_sel + d, g.loadout_options().size())
		g.sfx.play("click")
	elif g.state == "title" and g.title_page == "unlocks" and not g.UNLOCKS.is_empty():
		g.unlock_sel = posmod(g.unlock_sel + d, g.UNLOCKS.size())
		g.sfx.play("click")


func title_back() -> void:
	if g.state == "title" and g.title_page != "":
		# from a confirmation go back to the page it was opened from (the list, or the settings), from any other page
		# to the menu
		if g.title_page == "scores_confirm":
			g.title_page = "scores"
		elif g.title_page == "reset_confirm":
			g.title_page = "settings"
		else:
			g.title_page = ""
		g.sfx.play("click")


func title_activate(i: int) -> void:
	if g.hud.settings_visible():
		settings_activate()  # Enter / A on the settings panel switches the highlighted row; Esc / B go back
		return
	if g.title_page == "scores_confirm":
		scores_confirm_activate(g.confirm_sel)  # Enter / A on the highlighted NO or YES
		return
	if g.title_page == "reset_confirm":
		confirm_activate(g.confirm_sel)  # the RESET ALL PROGRESS warnings
		return
	if g.title_page == "loadout":
		loadout_pick()  # Enter / A chooses the highlighted row; Esc / B go back
		return
	if g.title_page == "unlocks":
		unlock_buy()  # Enter / A buys the highlighted unlock; Esc / B go back
		return
	if g.title_page != "":
		title_back()
		return
	if i == g.hud.TITLE_CONTINUE:
		if g.hud.title_has_continue():
			g.title_sel = i
			g.continue_run()
		return
	g.title_sel = i
	var id = g.hud.TITLE_ITEMS[i]["id"]
	if id == "play":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		g.start_game()
	elif id == "daily":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		g.start_game(true)
	elif id == "quit":
		g.get_tree().quit()
	elif id == "seed":
		g.seed_buf = ""
		g.title_page = id
		g.sfx.play("click")
	else:
		if id == "loadout":
			g.loadout_sel = 0
			g.loadout_col = 0
			g.loadout_slot = 0
			var opts = g.loadout_options()
			for n in range(opts.size()):
				if opts[n]["id"] == g.meta.start_perk:
					g.loadout_sel = n  # open on the row that is chosen now
		if id == "unlocks":
			g.unlock_sel = 0
			g.unlock_msg = ""
		g.title_page = id  # loadout / unlocks / scores / settings
		g.sfx.play("click")


# the Unlocks page, opened from the run summary (alpha C5.3): the title screen with the page already open and UNLOCKS
# the highlighted menu entry, so Esc / B / a click beside the page land on the menu right where UNLOCKS is
func open_unlocks_from_summary() -> void:
	g.go_to_title()
	for n in range(g.hud.TITLE_ITEMS.size()):
		if g.hud.TITLE_ITEMS[n]["id"] == "unlocks":
			g.title_sel = n
	g.unlock_sel = 0
	g.unlock_msg = ""
	g.title_page = "unlocks"
	g.sfx.play("click")


# ---- the Loadout page: Left / Right (D-pad) switch between the perk list and the weapon slots
func loadout_switch(d: int) -> void:
	if g.state != "title" or g.title_page != "loadout":
		return
	var col = clampi(g.loadout_col + d, 0, 1)
	if col != g.loadout_col:
		g.loadout_col = col
		g.sfx.play("click")


# ---- choosing on the Loadout page (Enter, gamepad A or a click on a row): the highlighted perk becomes the
# starting perk, or the highlighted weapon slot moves on to the next weapon the player owns for it
func loadout_pick() -> void:
	if g.state != "title" or g.title_page != "loadout":
		return
	if g.loadout_col == 1:
		loadout_cycle(g.loadout_slot)
		return
	var opts = g.loadout_options()
	var o = opts[clampi(g.loadout_sel, 0, opts.size() - 1)]
	g.meta.choose_start_perk(str(o["id"]))
	g.sfx.play("click")


# the weapon slot (an index into WeaponSlots.SLOTS) takes the next owned weapon of its list, wrapping round
func loadout_cycle(slot_index: int) -> void:
	var slot = WeaponSlots.SLOTS[clampi(slot_index, 0, WeaponSlots.SLOTS.size() - 1)]
	var opts = g.loadout_weapon_options(slot)
	if opts.size() < 2:
		return  # only one weapon owned for this slot: nothing to change
	var at = 0
	for n in range(opts.size()):
		if opts[n]["id"] == g.loadout_weapon_id(slot):
			at = n
	g.meta.choose_weapon(slot, str(opts[(at + 1) % opts.size()]["id"]))
	g.sfx.play("click")


# ---- buying on the Unlocks page (Enter, gamepad A or a click on the BUY button; texts are in hud.gd)
const UNLOCK_MESSAGES = {
	"bought": "BOUGHT",
	"owned": "YOU ALREADY OWN THIS",
	"soon": "NOT IN THE GAME YET",
	"locked": "NOT ENOUGH COINS"
}


func unlock_buy() -> void:
	if g.state != "title" or g.title_page != "unlocks" or g.UNLOCKS.is_empty():
		return
	var u = g.UNLOCKS[clampi(g.unlock_sel, 0, g.UNLOCKS.size() - 1)]
	var result = g.meta.buy(u)
	g.unlock_msg = UNLOCK_MESSAGES.get(result, "")
	g.unlock_msg_t0 = g.time
	g.sfx.play("pickup" if result == "bought" else "click")


# ---- reset leaderboard (High Scores page of the title screen; texts and buttons are in hud.gd)
# Delete, gamepad X or a click on RESET LEADERBOARD opens a "NO / YES" page. NO is the default, and YES ignores
# input for a moment after the page opens, like the restart confirmation, so a double click cannot erase the list.
func scores_reset_open() -> void:
	if g.state != "title" or g.title_page != "scores" or g.scores.entries.is_empty():
		return
	g.confirm_sel = 0
	g.confirm_t0 = g.time
	g.title_page = "scores_confirm"
	g.sfx.play("click")


func scores_confirm_activate(i: int) -> void:
	if i == 0:
		title_back()  # NO: back to the list
		return
	if g.time - g.confirm_t0 < 0.3:
		return
	g.confirm_sel = i
	g.scores.reset()
	g.title_page = "scores"
	g.sfx.play("click")


# ---- RESET ALL PROGRESS (red row at the bottom of the settings panel, on the title screen and on the pause menu)
# Enter, gamepad A or a click on the row opens a first warning (all progress will be wiped and cannot be recovered).
# YES there opens a second one ("ARE YOU ABSOLUTELY SURE?"); YES there wipes. Both are the NO / YES pages of
# `confirm_activate`: NO is picked first, Esc / B mean NO, and YES ignores input for a moment after a page opens.
# The texts are in hud.gd CONFIRM_TEXT (reset1, reset2), the wipe is main.gd `reset_all_progress`.
func reset_progress_open() -> void:
	if not g.hud.settings_visible():
		return
	g.confirm_id = "reset1"
	g.confirm_sel = 0
	g.confirm_t0 = g.time
	if g.state == "title":
		g.title_page = "reset_confirm"
	else:
		g.pause_page = "confirm"
	g.sfx.play("click")


# NO (or Esc / B) on either warning: back to the settings panel
func reset_progress_back() -> void:
	if g.state == "title":
		g.title_page = "settings"
	else:
		g.pause_page = "settings"
	g.sfx.play("click")


# YES on the second warning. A run in progress (the wipe was started from the pause menu) is dropped too, and the
# player lands on the settings page of the title screen, where "ALL PROGRESS WIPED" is shown.
func reset_progress_do() -> void:
	var from_run = g.state != "title"
	g.reset_all_progress()
	g.pause_page = ""
	if from_run:
		g.abandon_run()
	g.title_page = "settings"
	g.sfx.play("click")


# ---- settings panel (rows are listed in hud.gd ALL_SETTING_ROWS): Up / Down pick a row, Left / Right change it
# (a slider moves one twentieth of its range, a switch goes off / on, GRAPHICS steps through its choices), Enter / A
# flips a switch or steps GRAPHICS. All of them do nothing while the panel is not showing.
func settings_move(d: int) -> void:
	if not g.hud.settings_visible():
		return
	var n = g.hud.setting_rows().size()
	g.setting_sel = posmod(clampi(g.setting_sel, 0, n - 1) + d, n)
	g.sfx.play("click")


func settings_adjust(d: int) -> void:
	if not g.hud.settings_visible():
		return
	var rows = g.hud.setting_rows()
	var row = rows[clampi(g.setting_sel, 0, rows.size() - 1)]
	var id = str(row["id"])
	if row.get("action", false):
		return  # a button (RESET ALL PROGRESS): Left / Right do nothing, only Enter, A or a click open it
	if row.has("choices"):
		g.settings.set_setting(
			id, posmod(int(g.settings.get_setting(id)) + d, row["choices"].size())
		)
	elif row.get("toggle", false):
		g.settings.set_setting(id, d > 0)
	else:
		var step = (float(row["max"]) - float(row["min"])) / 20.0
		g.settings.set_setting(id, float(g.settings.get_setting(id)) + float(d) * step)
	g.sfx.play("click")


func settings_activate() -> void:
	var rows = g.hud.setting_rows()
	var row = rows[clampi(g.setting_sel, 0, rows.size() - 1)]
	if row.get("action", false):
		reset_progress_open()  # Enter / A on the red RESET ALL PROGRESS row
	elif row.has("choices") or row.get("toggle", false):
		var id = str(row["id"])
		g.settings.set_setting(id, g.settings.next_value(id))
		g.sfx.play("click")


# ---- pause menu (entries are listed in hud.gd PAUSE_ITEMS)
func pause_move(d: int) -> void:
	if g.state == "play" and g.paused and g.pause_page == "":
		g.pause_sel = posmod(g.pause_sel + d, g.hud.PAUSE_ITEMS.size())
		g.sfx.play("click")


# Esc / B: close the settings panel, or resume from the main pause menu
func pause_back() -> void:
	if not (g.state == "play" and g.paused):
		return
	if g.pause_page == "confirm" and (g.confirm_id == "reset1" or g.confirm_id == "reset2"):
		reset_progress_back()  # Esc / B on a RESET ALL PROGRESS warning is NO: back to the settings, nothing wiped
	elif g.pause_page != "":
		g.pause_page = ""
		g.sfx.play("click")
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func pause_activate(i: int) -> void:
	if g.hud.settings_visible():
		settings_activate()  # Enter / A on the settings panel switches the highlighted row; Esc / B go back
		return
	if g.pause_page == "confirm":
		confirm_activate(g.confirm_sel)
		return
	if g.pause_page != "":
		pause_back()
		return
	g.pause_sel = i
	var id = g.hud.PAUSE_ITEMS[i]["id"]
	if id == "resume":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif id == "settings" or id == "controls":
		g.pause_page = id
		g.sfx.play("click")
	elif id == "restart" or id == "title":  # both lose the run, so ask first (NO is the default)
		g.confirm_id = id
		g.confirm_sel = 0
		g.confirm_t0 = g.time
		g.pause_page = "confirm"
		g.sfx.play("click")


# ---- restart / quit confirmation (texts and buttons are in hud.gd CONFIRM_TEXT)
func confirm_move() -> void:
	var asking = g.state == "play" and g.paused and g.pause_page == "confirm"
	var on_title = g.state == "title" and g.title_page in ["scores_confirm", "reset_confirm"]
	if asking or on_title:
		g.confirm_sel = 1 - g.confirm_sel
		g.sfx.play("click")


func confirm_activate(i: int) -> void:
	var id = g.confirm_id
	var is_reset = id == "reset1" or id == "reset2"
	if i == 0:
		if is_reset:
			reset_progress_back()  # NO: back to the settings, nothing is wiped
		else:
			pause_back()  # NO: back to the pause menu
		return
	if g.time - g.confirm_t0 < 0.3:
		return  # the second click of a double click on RESTART RUN / QUIT TO TITLE / a warning must not confirm
	g.confirm_sel = i
	if id == "reset1":  # the first warning: YES shows the second one, with NO picked again
		g.confirm_id = "reset2"
		g.confirm_sel = 0
		g.confirm_t0 = g.time
		g.sfx.play("click")
		return
	if id == "reset2":  # the second warning: YES wipes everything
		reset_progress_do()
		return
	g.pause_page = ""
	if id == "restart":
		g.restart_run()
	elif id == "title":
		g.abandon_run()


func on_click() -> void:
	var captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if g.state == "title":
		var mp = g.get_viewport().get_mouse_position()
		if g.title_page == "settings":
			if (
				not g.settings.click_setting(g.hud.setting_at(mp))
				and not g.hud.panel_rect().has_point(mp)
			):
				title_back()
		elif g.title_page == "seed":
			if g.hud.seed_start_rect().has_point(mp):
				seed_start()
			else:
				title_back()
		elif g.title_page == "loadout":
			var li = g.hud.loadout_at(mp)
			var wi = g.hud.loadout_slot_at(mp)
			if li >= 0:
				g.loadout_sel = li
				g.loadout_col = 0
				loadout_pick()
			elif wi >= 0:
				g.loadout_slot = wi
				g.loadout_col = 1
				loadout_pick()
			else:
				title_back()
		elif g.title_page == "unlocks":
			var ui = g.hud.unlock_at(mp)
			if g.hud.unlock_buy_rect().has_point(mp):
				unlock_buy()
			elif ui >= 0:
				g.unlock_sel = ui
				g.sfx.play("click")
			else:
				title_back()
		elif g.title_page == "scores_confirm":
			var si = g.hud.scores_confirm_at(mp)
			if si >= 0:
				scores_confirm_activate(si)  # a click beside the buttons does nothing
		elif g.title_page == "reset_confirm":
			var ri = g.hud.confirm_at(mp)
			if ri >= 0:
				confirm_activate(ri)  # a click beside the buttons does nothing
		elif g.title_page == "scores" and g.hud.scores_reset_rect().has_point(mp):
			scores_reset_open()  # does nothing when the list is empty (the button is not drawn then)
		elif g.title_page != "":
			title_back()
		else:
			var ti = g.hud.title_at(mp)
			if ti >= 0:
				title_activate(ti)
	elif g.state == "map":
		if g.state_t > 0.3:
			g.pick_node(g.hud.map_choice_at(g.get_viewport().get_mouse_position()))
	elif g.state == "clear" and g.state_t > 0.8:
		g.shop_sys.enter_upgrade()
	elif g.state == "upgrade" and g.state_t > 0.35:
		var i = g.hud.card_at(g.get_viewport().get_mouse_position())
		if i >= 0:
			g.shop_sys.pick_upgrade(i)
	elif g.state == "rest" and g.state_t > 0.35:
		var ri = g.hud.card_at(g.get_viewport().get_mouse_position())
		if ri >= 0:
			g.shop_sys.rest_choose(ri)
	elif g.state == "shop":
		var mp = g.get_viewport().get_mouse_position()
		var si = g.hud.card_at(mp)
		if si >= 0:
			g.shop_sys.buy(si)
		elif g.hud.continue_rect().has_point(mp):
			g.shop_sys.leave_shop()
		elif g.hud.reroll_rect().has_point(mp):
			g.shop_sys.reroll()
	elif g.state == "over" and g.state_t > 0.8:
		click_summary(g.get_viewport().get_mouse_position())
	elif g.state == "play":
		if not captured:
			var pmp = g.get_viewport().get_mouse_position()
			if g.pause_page == "settings":
				if (
					not g.settings.click_setting(g.hud.setting_at(pmp))
					and not g.hud.panel_rect().has_point(pmp)
				):
					pause_back()
			elif g.pause_page == "confirm":
				var ci = g.hud.confirm_at(pmp)
				if ci >= 0:
					confirm_activate(ci)
			elif g.pause_page == "controls":
				pause_back()  # a click anywhere closes the controls page
			else:
				var pi = g.hud.pause_at(pmp)
				if pi >= 0:
					pause_activate(pi)
		else:
			g.combat_sys.fire()


# R and gamepad X: reload the dart gun by hand. Does nothing while the melee weapon is held (a reload would run
# unseen and switching to melee stops one anyway); a full magazine, a gun already loading and a state other than
# play are handled by `start_load`. The automatic reload at 0 calls `start_load` itself and is not affected.
func manual_reload() -> void:
	if g.melee:
		return
	g.combat_sys.start_load()


func toggle_weapon(to = null) -> void:
	if to == null:
		g.melee = not g.melee
	else:
		g.melee = to
	if g.melee:
		g.combat_sys.interrupt_load()
	g.sfx.play("click")
