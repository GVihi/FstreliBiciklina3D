extends RefCounted
# Settings (saved to user://settings.cfg), graphics quality (F9) and the high score file (user://hi.dat).
# The values themselves stay on main.gd (g) because the HUD reads them there; this file only holds the logic.

const SaveUtil = preload("res://scripts/save_util.gd")
const GOLD = Color(0.95, 0.71, 0.19)
const SETTINGS_PATH = "user://settings.cfg"
const VERSION = 1  # settings.cfg: [meta] version. Version 0 (before versioning) had no [meta] section.

var g = null
# audio / window values read from the file before the sound system exists; apply_loaded() uses them
var _muted = false
var _voices = true
var _fullscreen = false


func _init(game) -> void:
	g = game


func apply_quality() -> void:
	g.get_viewport().msaa_3d = Viewport.MSAA_2X if g.quality == 0 else Viewport.MSAA_DISABLED
	if g.viewmodel != null:
		g.viewmodel.set_msaa(g.get_viewport().msaa_3d)
	var sun: DirectionalLight3D = g.world["sun"]
	sun.shadow_enabled = g.quality < 2
	if g.outline_quad != null:
		g.outline_quad.visible = g.outlines and g.quality < 2
	var env: Environment = g.world["env"]
	env.glow_enabled = g.quality < 2


func cycle_quality() -> void:
	g.quality = (g.quality + 1) % 3
	apply_quality()
	var names = [
		"GRAPHICS: HIGH", "GRAPHICS: MEDIUM (NO MSAA)", "GRAPHICS: LOW (NO MSAA, NO SHADOWS)"
	]
	g.add_note(names[g.quality], GOLD)
	save_settings()


func is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


func set_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	)


func toggle_fullscreen() -> void:
	set_fullscreen(not is_fullscreen())
	save_settings()


# call once the sound system exists: applies the saved sound and window settings
func apply_loaded() -> void:
	g.sfx.muted = _muted
	g.sfx.voices_on = _voices
	if _fullscreen:
		set_fullscreen(true)


func load_settings() -> void:
	var cf = ConfigFile.new()
	var err = cf.load(SETTINGS_PATH)
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			SaveUtil.backup(SETTINGS_PATH, "bad")  # unreadable: keep a copy before the next save replaces it
		return
	SaveUtil.backup_if_newer(SETTINGS_PATH, int(cf.get_value("meta", "version", 0)), VERSION)
	g.fov_hip = clampf(float(cf.get_value("game", "fov", g.fov_hip)), 60.0, 105.0)
	g.sens_mul = clampf(float(cf.get_value("game", "sens", g.sens_mul)), 0.3, 3.0)
	g.toggle_ads = bool(cf.get_value("game", "toggle_ads", g.toggle_ads))
	g.aim_assist = clampf(float(cf.get_value("game", "assist", g.aim_assist)), 0.0, 1.0)
	g.volume = clampf(float(cf.get_value("game", "volume", g.volume)), 0.0, 1.0)
	g.outlines = bool(cf.get_value("game", "outlines", g.outlines))
	g.quality = clampi(int(cf.get_value("game", "quality", g.quality)), 0, 2)
	_muted = bool(cf.get_value("game", "muted", _muted))
	_voices = bool(cf.get_value("game", "voices", _voices))
	_fullscreen = bool(cf.get_value("game", "fullscreen", _fullscreen))
	g.player_name = str(cf.get_value("game", "player_name", g.player_name))


func save_settings() -> void:
	var cf = ConfigFile.new()
	cf.set_value("meta", "version", VERSION)
	cf.set_value("game", "fov", g.fov_hip)
	cf.set_value("game", "sens", g.sens_mul)
	cf.set_value("game", "toggle_ads", g.toggle_ads)
	cf.set_value("game", "assist", g.aim_assist)
	cf.set_value("game", "volume", g.volume)
	cf.set_value("game", "outlines", g.outlines)
	cf.set_value("game", "quality", g.quality)
	cf.set_value("game", "muted", g.sfx.muted)
	cf.set_value("game", "voices", g.sfx.voices_on)
	cf.set_value("game", "fullscreen", is_fullscreen())
	cf.set_value("game", "player_name", g.player_name)
	cf.save(SETTINGS_PATH)


func get_setting(id: String):
	if id == "fov":
		return g.fov_hip
	if id == "sens":
		return g.sens_mul
	if id == "assist":
		return g.aim_assist
	if id == "vol":
		return g.volume
	if id == "tads":
		return g.toggle_ads
	if id == "outline":
		return g.outlines
	if id == "quality":
		return g.quality
	if id == "sound":
		return not g.sfx.muted
	if id == "voices":
		return g.sfx.voices_on
	if id == "fullscreen":
		return is_fullscreen()
	return null


func set_setting(id: String, v) -> void:
	if id == "fov":
		g.fov_hip = clampf(float(v), 60.0, 105.0)
	elif id == "sens":
		g.sens_mul = clampf(float(v), 0.3, 3.0)
	elif id == "assist":
		g.aim_assist = clampf(float(v), 0.0, 1.0)
	elif id == "vol":
		g.volume = clampf(float(v), 0.0, 1.0)
		g.sfx.set_master(g.volume)
	elif id == "tads":
		g.toggle_ads = bool(v)
		g.ads_on = false
	elif id == "outline":
		g.outlines = bool(v)
		apply_quality()
	elif id == "quality":
		g.quality = clampi(int(v), 0, 2)
		apply_quality()
	elif id == "sound":
		if bool(v) == g.sfx.muted:
			g.sfx.toggle_mute()
	elif id == "voices":
		if bool(v) != g.sfx.voices_on:
			g.sfx.toggle_voices()
	elif id == "fullscreen":
		set_fullscreen(bool(v))
	save_settings()


# the value a click on a toggle / choice row switches to
func next_value(id: String):
	if id == "quality":
		return (g.quality + 1) % 3
	return not get_setting(id)


# a click on the settings panel: toggles flip, sliders start a drag. Returns true when the click was used.
func click_setting(sid: String) -> bool:
	if sid == "":
		return false
	if g.hud.is_toggle(sid):
		set_setting(sid, next_value(sid))
	else:
		g.drag_id = sid
		g.hud.apply_slider(sid, g.get_viewport().get_mouse_position())
	return true


func load_hi() -> int:
	if FileAccess.file_exists("user://hi.dat"):
		var f = FileAccess.open("user://hi.dat", FileAccess.READ)
		if f:
			var v = f.get_as_text().to_int()
			f.close()
			return v
	return 0


func save_hi(v: int) -> void:
	var f = FileAccess.open("user://hi.dat", FileAccess.WRITE)
	if f:
		f.store_string(str(v))
		f.close()
