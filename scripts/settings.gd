extends RefCounted
# Settings (saved to user://settings.cfg), and graphics quality (F9).
# The values themselves stay on main.gd (g) because the HUD reads them there; this file only holds the logic.

const SaveUtil = preload("res://scripts/save_util.gd")
const GOLD = Color(0.95, 0.71, 0.19)
const SETTINGS_PATH = "user://settings.cfg"
const VERSION = 1  # settings.cfg: [meta] version. Version 0 (before versioning) had no [meta] section.
# First-run hints (README early alpha E1): one line the first time the player meets a screen or an object. These are
# the six triggers of E1.3. A hint is "seen" once it was shown, and the flags are saved under [hints] in settings.cfg.
# A missing section, a missing key or a value that is not true / false counts as "not seen", so a hand-edited file can
# only make a hint show again, never break the game. Settings, not progress: RESET ALL PROGRESS keeps them.
const HINT_IDS = ["map", "upgrade", "shop", "rest", "extract", "cache"]
# How long a hint line stays on screen (seconds, the last HINT_FADE of them fading out). The line is only drawn, it never
# takes a click or a key, and it does not pause or slow the game.
const HINT_SECONDS = 5.0
const HINT_FADE = 0.8
const HINT_MAX_CHARS = 90  # one line at the smallest window; E1.3 texts stay under this
# The six hint lines (README early alpha E1.3), one per id of HINT_IDS, each under HINT_MAX_CHARS. They say what the
# screen does not already say: the prompts on the screens name the keys, so these name the idea.
const HINT_TEXTS = {
	"map": "EACH STOP IS A ROUND, A SHOP OR A REST. PICK ONE THAT IS CONNECTED TO YOU",
	"upgrade": "AN UPGRADE STAYS WITH YOU FOR THE REST OF THE RUN. TAKE ONE THAT FITS YOU",
	"shop": "THIS IS WHERE YOUR CASH GOES. WHAT YOU DO NOT SPEND WAITS FOR THE NEXT SHOP",
	"rest": "A REST STOP GIVES ONE CHOICE: REFILL YOUR HEARTS OR PICK AN EXTRA UPGRADE",
	"extract": "THE WAY OUT IS OPEN: RUN TO THE GREEN LIGHT, THE SQUARE ON YOUR RADAR",
	"cache": "A GOLD LIGHT IS A SUPPLY CACHE: WALK INTO IT FOR CASH AND A PICK-UP",
}

var g = null
# audio / window values read from the file before the sound system exists; apply_loaded() uses them
var _muted = false
var _voices = true
var _fullscreen = false


func _init(game) -> void:
	g = game


# F9 presets (README Milestone F1, docs/ART_DIRECTION.md):
#   0 HIGH    2x MSAA, sun shadows from a 2048 map, glow
#   1 MEDIUM  FXAA instead of MSAA (nearly free), sun shadows from a 1024 map, glow
#   2 LOW     no anti-aliasing, no sun shadows, no glow
# FXAA only exists in the Forward+ and Mobile renderers. In the Compatibility renderer (also what Godot
# falls back to when Vulkan does not work) MEDIUM therefore has no anti-aliasing at all.
func apply_quality() -> void:
	var vp = g.get_viewport()
	vp.msaa_3d = Viewport.MSAA_2X if g.quality == 0 else Viewport.MSAA_DISABLED
	var fxaa = g.quality == 1 and RenderingServer.get_rendering_device() != null
	vp.screen_space_aa = (
		Viewport.SCREEN_SPACE_AA_FXAA if fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	)
	if g.viewmodel != null:
		g.viewmodel.set_msaa(vp.msaa_3d)
		g.viewmodel.set_screen_space_aa(vp.screen_space_aa)
	RenderingServer.directional_shadow_atlas_set_size(2048 if g.quality == 0 else 1024, true)
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
		"GRAPHICS: HIGH",
		"GRAPHICS: MEDIUM (FXAA, SMALLER SHADOWS)",
		"GRAPHICS: LOW (NO ANTI-ALIASING, NO SHADOWS, NO GLOW)"
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
	g.rim_outline = bool(cf.get_value("game", "rim_outline", g.rim_outline))
	g.fx_scale = clampf(float(cf.get_value("game", "fx_scale", g.fx_scale)), 0.0, 1.0)
	g.quality = clampi(int(cf.get_value("game", "quality", g.quality)), 0, 2)
	_muted = bool(cf.get_value("game", "muted", _muted))
	_voices = bool(cf.get_value("game", "voices", _voices))
	_fullscreen = bool(cf.get_value("game", "fullscreen", _fullscreen))
	g.player_name = str(cf.get_value("game", "player_name", g.player_name))
	for id in HINT_IDS:
		var seen = cf.get_value("hints", id, false)
		g.hints_seen[id] = typeof(seen) == TYPE_BOOL and seen


func save_settings() -> void:
	var cf = ConfigFile.new()
	cf.set_value("meta", "version", VERSION)
	cf.set_value("game", "fov", g.fov_hip)
	cf.set_value("game", "sens", g.sens_mul)
	cf.set_value("game", "toggle_ads", g.toggle_ads)
	cf.set_value("game", "assist", g.aim_assist)
	cf.set_value("game", "volume", g.volume)
	cf.set_value("game", "outlines", g.outlines)
	cf.set_value("game", "rim_outline", g.rim_outline)
	cf.set_value("game", "fx_scale", g.fx_scale)
	cf.set_value("game", "quality", g.quality)
	cf.set_value("game", "muted", g.sfx.muted)
	cf.set_value("game", "voices", g.sfx.voices_on)
	cf.set_value("game", "fullscreen", is_fullscreen())
	cf.set_value("game", "player_name", g.player_name)
	for id in HINT_IDS:
		cf.set_value("hints", id, hint_seen(id))
	cf.save(SETTINGS_PATH)


# true when this first-run hint was already shown (an id that is not in HINT_IDS counts as not seen)
func hint_seen(id: String) -> bool:
	return bool(g.hints_seen.get(id, false))


# Marks a hint as shown and saves it. Returns true the first time (the caller draws the hint then), and false for a
# hint that was already seen or an id that is not in HINT_IDS (nothing is stored for it).
func mark_hint_seen(id: String) -> bool:
	if not HINT_IDS.has(id) or hint_seen(id):
		return false
	g.hints_seen[id] = true
	save_settings()
	return true


# Puts a hint line on screen for HINT_SECONDS, replacing the one that is showing. Does not touch the "seen" flags.
func show_hint(text: String) -> void:
	g.hint_txt = text
	g.hint_t0 = g.time


# The call E1.3's triggers make: shows `text` the first time `id` comes up and never again (the flag is saved).
# Returns true when the line was shown.
func hint_once(id: String, text: String) -> bool:
	if not mark_hint_seen(id):
		return false
	show_hint(text)
	return true


# What the six triggers call: the HINT_TEXTS line for `id`, shown the first time only (see hint_once).
func trigger_hint(id: String) -> bool:
	return hint_once(id, str(HINT_TEXTS.get(id, "")))


# 0 when no hint is showing, 1 while it is fully shown, falling to 0 over the last HINT_FADE seconds
func hint_alpha() -> float:
	if g.hint_txt == "":
		return 0.0
	var age = g.time - g.hint_t0
	if age < 0.0 or age >= HINT_SECONDS:
		return 0.0
	return clampf((HINT_SECONDS - age) / HINT_FADE, 0.0, 1.0)


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
	if id == "rim":
		return g.rim_outline
	if id == "fx":
		return g.fx_scale
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
	elif id == "rim":
		g.rim_outline = bool(v)
		g.refresh_rims()
	elif id == "fx":
		g.fx_scale = clampf(float(v), 0.0, 1.0)
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
	if g.hud.is_action(sid):  # the RESET ALL PROGRESS button: opens the first warning
		g.input_sys.reset_progress_open()
		return true
	if g.hud.is_toggle(sid):
		set_setting(sid, next_value(sid))
	else:
		g.drag_id = sid
		g.hud.apply_slider(sid, g.get_viewport().get_mouse_position())
	return true
