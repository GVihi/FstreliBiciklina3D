extends RefCounted
# Input: mouse, keyboard and gamepad handling, menu clicks and weapon switching.
# Shared game state stays on main.gd (g); this file holds the logic.

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
		elif g.drag_id != "":
			g.hud.apply_slider(g.drag_id, g.get_viewport().get_mouse_position())
	elif event is InputEventMouseButton:
		if not event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				g.drag_id = ""
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			on_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if g.toggle_ads and g.state == "play" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not g.melee:
				g.ads_on = not g.ads_on
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if g.state == "play":
				toggle_weapon()
	elif event is InputEventJoypadButton and event.pressed:
		on_pad_button(event.button_index)
	elif event is InputEventKey and event.pressed and not event.echo:
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
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif kc == KEY_ENTER or kc == KEY_KP_ENTER:
			menu_confirm()
		elif kc == KEY_LEFT:
			menu_move(-1)
		elif kc == KEY_RIGHT:
			menu_move(1)
		elif kc == KEY_UP or kc == KEY_W:
			title_move(-1)
		elif kc == KEY_DOWN or kc == KEY_S:
			title_move(1)
		elif kc == KEY_1 or kc == KEY_KP_1:
			if g.state == "upgrade":
				if g.state_t > 0.35:
					g.shop_sys.pick_upgrade(0)
			elif g.state == "shop":
				g.shop_sys.buy(0)
			elif g.state == "play":
				toggle_weapon(false)
		elif kc == KEY_2 or kc == KEY_KP_2:
			if g.state == "upgrade":
				if g.state_t > 0.35:
					g.shop_sys.pick_upgrade(1)
			elif g.state == "shop":
				g.shop_sys.buy(1)
			elif g.state == "play":
				toggle_weapon(true)
		elif kc == KEY_3 or kc == KEY_KP_3:
			if g.state == "upgrade" and g.state_t > 0.35:
				g.shop_sys.pick_upgrade(2)
			elif g.state == "shop":
				g.shop_sys.buy(2)
		elif kc == KEY_4 or kc == KEY_KP_4:
			if g.state == "shop":
				g.shop_sys.buy(3)
		elif kc == KEY_M:
			g.sfx.toggle_mute()
		elif kc == KEY_V:
			g.sfx.toggle_voices()
		elif kc == KEY_F7:
			g.add_note("VOICE EFFECTS " + ("ON" if g.sfx.toggle_voice_fx() else "OFF"), g.GOLD)
		elif kc == KEY_F9:
			g.settings.cycle_quality()
		elif kc == KEY_F10:
			g.settings.set_setting("outline", not g.outlines)
			g.add_note("OUTLINES " + ("ON" if g.outlines else "OFF"), g.GOLD)
		elif kc == KEY_F8:
			g.hi = 0
			g.settings.save_hi(0)
		elif kc == KEY_ESCAPE:
			title_back()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif kc == KEY_F11:
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

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
			return
		if btn == JOY_BUTTON_A:
			g.player_sys.try_dash()
		elif btn == JOY_BUTTON_X:
			g.combat_sys.start_load()
		elif btn == JOY_BUTTON_Y or btn == JOY_BUTTON_RIGHT_SHOULDER or btn == JOY_BUTTON_LEFT_SHOULDER:
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
	if g.state == "upgrade":
		g.menu_sel = posmod(g.menu_sel + d, maxi(1, g.offers.size()))
	elif g.state == "shop":
		g.menu_sel = posmod(g.menu_sel + d, maxi(1, g.shop_items.size()))

func menu_confirm() -> void:
	if g.state == "title":
		title_activate(g.title_sel)
	elif g.state == "upgrade" and g.state_t > 0.35:
		g.shop_sys.pick_upgrade(g.menu_sel)
	elif g.state == "shop":
		g.shop_sys.buy(g.menu_sel)
	elif g.state == "clear" and g.state_t > 0.8:
		g.shop_sys.enter_upgrade()

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
	elif id == "quit":
		g.get_tree().quit()
	else:
		g.title_page = id        # loadout / unlocks / scores / settings
		g.sfx.play("click")

func on_click() -> void:
	var captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if g.state == "title":
		var mp = g.get_viewport().get_mouse_position()
		if g.title_page == "settings":
			if not g.settings.click_setting(g.hud.setting_at(mp)) and not g.hud.panel_rect().has_point(mp):
				title_back()
		elif g.title_page != "":
			title_back()
		else:
			var ti = g.hud.title_at(mp)
			if ti >= 0:
				title_activate(ti)
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
		g.go_to_title()
	elif g.state == "play":
		if not captured:
			if not g.settings.click_setting(g.hud.setting_at(g.get_viewport().get_mouse_position())):
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			g.combat_sys.fire()

func toggle_weapon(to = null) -> void:
	if to == null:
		g.melee = not g.melee
	else:
		g.melee = to
	g.sfx.play("click")
