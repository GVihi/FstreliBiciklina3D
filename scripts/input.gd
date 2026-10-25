extends RefCounted
# Input: mouse, keyboard and gamepad handling, menu clicks and weapon switching.
# Shared game state stays on main.gd (g); this file holds the logic.

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
			seed_key(event)  # typing a seed: letters like R, M, V and S must not trigger their hotkeys
			return
		var kc = event.keycode
		if kc == KEY_R:
			if g.state == "shop":
				g.shop_sys.reroll()
			else:
				g.combat_sys.start_load()
		elif kc == KEY_Q:
			if g.state == "play":
				toggle_weapon()
		elif kc == KEY_SPACE:
			if g.state == "play":
				g.player_sys.try_dash()
			elif g.state == "shop":
				g.shop_sys.leave_shop()
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
			menu_move(-1)
			confirm_move()
		elif kc == KEY_RIGHT:
			menu_move(1)
			confirm_move()
		elif kc == KEY_UP or kc == KEY_W:
			title_move(-1)
			pause_move(-1)
			confirm_move()
		elif kc == KEY_DOWN or kc == KEY_S:
			title_move(1)
			pause_move(1)
			confirm_move()
		elif kc == KEY_1 or kc == KEY_KP_1:
			if g.state == "map" and g.state_t > 0.3:
				g.pick_node(0)
			elif g.state == "upgrade":
				if g.state_t > 0.35:
					g.shop_sys.pick_upgrade(0)
			elif g.state == "shop":
				g.shop_sys.buy(0)
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
		elif kc == KEY_M:
			g.sfx.toggle_mute()
			g.settings.save_settings()
		elif kc == KEY_V:
			g.sfx.toggle_voices()
			g.settings.save_settings()
		elif kc == KEY_F7:
			g.add_note("VOICE EFFECTS " + ("ON" if g.sfx.toggle_voice_fx() else "OFF"), g.GOLD)
		elif kc == KEY_F9:
			g.settings.cycle_quality()
		elif kc == KEY_F10 and Toon.ENABLED:
			g.settings.set_setting("outline", not g.outlines)
			g.add_note("OUTLINES " + ("ON" if g.outlines else "OFF"), g.GOLD)
		elif kc == KEY_F8:
			g.hi = 0
			g.settings.save_hi(0)
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
			elif btn == JOY_BUTTON_DPAD_DOWN:
				pause_move(1)
				confirm_move()
			elif btn == JOY_BUTTON_A:
				pause_activate(g.pause_sel)
			elif btn == JOY_BUTTON_B:
				pause_back()
			return
		if btn == JOY_BUTTON_A:
			g.player_sys.try_dash()
		elif btn == JOY_BUTTON_X:
			g.combat_sys.start_load()
		elif (
			btn == JOY_BUTTON_Y
			or btn == JOY_BUTTON_RIGHT_SHOULDER
			or btn == JOY_BUTTON_LEFT_SHOULDER
		):
			toggle_weapon()
		return
	if btn == JOY_BUTTON_DPAD_UP:
		title_move(-1)
	elif btn == JOY_BUTTON_DPAD_DOWN:
		title_move(1)
	elif btn == JOY_BUTTON_DPAD_LEFT:
		menu_move(-1)
	elif btn == JOY_BUTTON_DPAD_RIGHT:
		menu_move(1)
	elif btn == JOY_BUTTON_A:
		if g.state == "title":
			title_activate(g.title_sel)
		elif g.state == "clear" and g.state_t > 0.8:
			g.shop_sys.enter_upgrade()
		elif g.state == "over" and g.state_t > 0.8:
			if g.name_entry:
				confirm_name()
			else:
				g.go_to_title()
		else:
			menu_confirm()
	elif btn == JOY_BUTTON_B and g.state == "title":
		title_back()
	elif btn == JOY_BUTTON_B and g.state == "shop":
		g.shop_sys.leave_shop()
	elif btn == JOY_BUTTON_X and g.state == "shop":
		g.shop_sys.reroll()


func menu_move(d: int) -> void:
	if g.state == "map":
		g.map_sel = posmod(g.map_sel + d, maxi(1, g.map_choices.size()))
	elif g.state == "upgrade":
		g.menu_sel = posmod(g.menu_sel + d, maxi(1, g.offers.size()))
	elif g.state == "shop":
		g.menu_sel = posmod(g.menu_sel + d, maxi(1, g.shop_items.size()))


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
	elif g.state == "clear" and g.state_t > 0.8:
		g.shop_sys.enter_upgrade()


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
	var ti = g.hud.title_at(pos)
	if ti >= 0:
		g.title_sel = ti
	var pi = g.hud.pause_at(pos)
	if pi >= 0:
		g.pause_sel = pi
	var ci = g.hud.confirm_at(pos)
	if ci >= 0:
		g.confirm_sel = ci
	if g.state == "map":
		var mi = g.hud.map_choice_at(pos)
		if mi >= 0:
			g.map_sel = mi


# ---- title screen menu (entries are listed in hud.gd TITLE_ITEMS)
func title_move(d: int) -> void:
	if g.state == "title" and g.title_page == "":
		g.title_sel = posmod(g.title_sel + d, g.hud.TITLE_ITEMS.size())
		g.sfx.play("click")


func title_back() -> void:
	if g.state == "title" and g.title_page != "":
		g.title_page = ""
		g.sfx.play("click")


func title_activate(i: int) -> void:
	if g.title_page != "":
		title_back()
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
		g.title_page = id  # loadout / unlocks / scores / settings
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
	if g.pause_page != "":
		g.pause_page = ""
		g.sfx.play("click")
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func pause_activate(i: int) -> void:
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
	if g.state == "play" and g.paused and g.pause_page == "confirm":
		g.confirm_sel = 1 - g.confirm_sel
		g.sfx.play("click")


func confirm_activate(i: int) -> void:
	if i == 0:
		pause_back()  # NO: back to the pause menu
		return
	if g.time - g.confirm_t0 < 0.3:
		return  # the second click of a double click on RESTART RUN / QUIT TO TITLE must not confirm
	g.confirm_sel = i
	var id = g.confirm_id
	g.pause_page = ""
	if id == "restart":
		g.start_game(g.daily_mode, g.run_seed if g.custom_seed_run else -1)
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
		if g.name_entry:
			confirm_name()
		else:
			g.go_to_title()
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


func toggle_weapon(to = null) -> void:
	if to == null:
		g.melee = not g.melee
	else:
		g.melee = to
	if g.melee:
		g.combat_sys.interrupt_load()
	g.sfx.play("click")
