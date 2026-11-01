extends Control
# 2D overlay: HUD, crosshair, floating popups, boss bars, upgrade cards and the title / round screens.
# It only reads state from the main script (g), it never changes it.

var g = null
var font: Font
var arrows: Array = []  # the edge arrows drawn on the last frame, strongest first (tools/threat_check.gd reads it)

const Toon = preload("res://scripts/toon.gd")
const Threats = preload("res://scripts/threats.gd")
const WeaponSlots = preload("res://scripts/weapon_slots.gd")

const GOLD = Color(0.95, 0.71, 0.19)
const RED = Color(0.9, 0.33, 0.24)
const GRAY = Color(0.49, 0.48, 0.44)
const TEXT = Color(0.96, 0.95, 0.92)
const ACCENT = Color(1.0, 0.42, 0.17)
const FPS_GREEN = Color(0.35, 0.78, 0.42)
const XP_COL = Color(0.45, 0.78, 1.0)  # XP and level (title screen and run summary)
const PINK = Color(1.0, 0.48, 0.72)
const RELOAD_CYAN = Color(0.22, 0.91, 1.0)  # the RELOAD label while the gun loads, same cyan as the ammo number on the gun
const OBJ_GREEN = Color(0.35, 1.0, 0.55)  # the extraction point once it is open
const OBJ_LOCKED = Color(1.0, 0.45, 0.3)  # ... while riders are still up
const OBJ_GOLD = Color(0.95, 0.71, 0.19)  # supply caches


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = get_theme_default_font()


func _process(d: float) -> void:
	_record_frame(d)
	queue_redraw()


# ---------------------------------------------------------------- helpers
# draw_string() re-shapes the text every call, and we draw every string twice (outline + fill) every frame.
# A TextLine keeps the shaped text, so each distinct string is shaped once and just re-drawn afterwards.
var _lines := {}
# FPS and frametime counter above the radar: the last FRAME_SAMPLES frame times (seconds) in a ring, and the FPS and
# frametime shown, refreshed a few times a second so the digits stay readable
const FRAME_SAMPLES = 60
const FPS_REFRESH = 0.25  # seconds between updates of the numbers
var _frame_ring = PackedFloat32Array()
var _frame_i = 0
var _fps_t = 0.0
var _fps_n = 0
var _fps_shown = 0
var _ms_shown = 0.0


func _line(s: String, fs: int, w: float, ha: int) -> TextLine:
	var key = "%d|%d|%d|%s" % [fs, int(w), ha, s]
	if _lines.has(key):
		return _lines[key]
	if _lines.size() > 400:
		_lines.clear()
	var tl = TextLine.new()
	tl.add_string(s, font, fs)
	if w > 0.0:
		tl.width = w
		tl.alignment = ha
	_lines[key] = tl
	return tl


func _txt(s: String, x: float, y: float, fs: int, col: Color, align: int = 0) -> void:
	var W = 2000.0
	var px = x
	var ha = HORIZONTAL_ALIGNMENT_LEFT
	var w = -1.0
	if align == 1:
		px = x - W * 0.5
		ha = HORIZONTAL_ALIGNMENT_CENTER
		w = W
	elif align == 2:
		px = x - W
		ha = HORIZONTAL_ALIGNMENT_RIGHT
		w = W
	if fs <= 0:
		return
	var tl = _line(s, fs, w, ha)
	var pos = Vector2(px, y - tl.get_line_ascent())  # TextLine draws from the top, draw_string from the baseline
	var rid = get_canvas_item()
	tl.draw_outline(rid, pos, int(fs * 0.14) + 1, Color(0.04, 0.04, 0.06, 0.9))
	tl.draw(rid, pos, col)


func _heart(cx: float, cy: float, sz: float, col: Color) -> void:
	draw_circle(Vector2(cx - sz * 0.25, cy - sz * 0.15), sz * 0.29, col)
	draw_circle(Vector2(cx + sz * 0.25, cy - sz * 0.15), sz * 0.29, col)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(cx - sz * 0.52, cy - sz * 0.02),
				Vector2(cx + sz * 0.52, cy - sz * 0.02),
				Vector2(cx, cy + sz * 0.5)
			]
		),
		col
	)


func _dim(a: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.04, 0.05, a))


# ---------------------------------------------------------------- menu backdrop and intro screen
# One picture behind every menu (README V5.0), so the 3D game never shows through a menu or the intro screen: a dusk sky
# with stars and a low sun, two rows of skyline with a few lit windows, a road running into the distance with a moving
# centre line, and three riders crossing it. It is only drawn (rects, circles, lines and polygons from fixed formulas,
# no textures and no random numbers), so it needs no assets and looks the same on every start. `scrim` darkens it (0 =
# the picture as it is, 1 = black), so a page with a lot of text stays easy to read. Every menu and page uses it (title
# menu and pages, run summary, round clear, upgrade, shop, rest stop, run map, pause menu and its pages); only the map
# held down in a round is still drawn over the game with `_dim`. tools/menu_backdrop_check.gd counts the `_dim` calls
# left in this file, so a new menu that forgets the backdrop is found.
const BACKDROP_SKY_TOP = Color(0.04, 0.05, 0.14)
const BACKDROP_SKY_MID = Color(0.2, 0.1, 0.3)
const BACKDROP_SKY_LOW = Color(0.62, 0.26, 0.28)
const BACKDROP_SUN = Color(1.0, 0.62, 0.22)
const BACKDROP_FAR = Color(0.14, 0.09, 0.24)
const BACKDROP_NEAR = Color(0.07, 0.06, 0.12)
const BACKDROP_GROUND = Color(0.05, 0.045, 0.07)
const BACKDROP_ROAD_FAR = Color(0.3, 0.15, 0.2)
const BACKDROP_ROAD_NEAR = Color(0.07, 0.065, 0.09)
const BACKDROP_RIDER = Color(0.02, 0.02, 0.04)
const BACKDROP_HORIZON = 0.64  # the horizon, as a share of the window height
# the riders: how far down the road each one is (0 = at the horizon, 1 = at the bottom edge), how fast it crosses the
# window (windows per second), where in its crossing it starts, and which way it goes
const BACKDROP_RIDERS = [
	{"u": 0.16, "speed": 0.045, "phase": 0.15, "dir": 1.0},
	{"u": 0.34, "speed": 0.075, "phase": 0.62, "dir": -1.0},
	{"u": 0.62, "speed": 0.11, "phase": 0.35, "dir": 1.0}
]
const INTRO_TAGLINE = "A BIKE SHOOTING ROGUELITE"
const INTRO_PROMPT = "PRESS ANY KEY OR CLICK TO START"


# a number between 0 and 1 that is the same for the same input (a fixed formula, so the picture never changes by itself)
func _hash01(n: float) -> float:
	return fposmod(sin(n * 12.9898) * 43758.5453, 1.0)


func _menu_backdrop(k: float, scrim: float = 0.0) -> void:
	var w = size.x
	var h = size.y
	var cx = w * 0.5
	var hy = h * BACKDROP_HORIZON
	var t = g.time
	# the sky: dark blue at the top into purple, then into the warm glow at the horizon
	var mid_y = hy * 0.55
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, mid_y), Vector2(0, mid_y)]),
		PackedColorArray([BACKDROP_SKY_TOP, BACKDROP_SKY_TOP, BACKDROP_SKY_MID, BACKDROP_SKY_MID])
	)
	draw_polygon(
		PackedVector2Array([Vector2(0, mid_y), Vector2(w, mid_y), Vector2(w, hy), Vector2(0, hy)]),
		PackedColorArray([BACKDROP_SKY_MID, BACKDROP_SKY_MID, BACKDROP_SKY_LOW, BACKDROP_SKY_LOW])
	)
	for i in range(48):
		var star = Vector2(_hash01(i * 3.1 + 0.5) * w, _hash01(i * 7.7 + 1.5) * hy * 0.55)
		var twinkle = 0.5 + 0.5 * sin(t * (0.8 + _hash01(i + 9.0)) + i)
		var star_col = Color(1, 1, 1, 0.2 + 0.4 * twinkle)
		draw_circle(star, (0.9 + _hash01(i * 1.7) * 1.1) * k, star_col)
	# the sun, low on the horizon, with a soft glow of three larger discs behind it
	var sun = Vector2(w * 0.68, hy - h * 0.03)
	var sun_r = h * 0.15
	for glow in range(3, 0, -1):
		draw_circle(sun, sun_r * (1.0 + 0.3 * glow), Color(1.0, 0.5, 0.25, 0.06))
	draw_circle(sun, sun_r, Color(BACKDROP_SUN, 0.92))
	# two rows of skyline: a far one, taller and dark purple, and a near one, lower and darker, with lit windows
	_backdrop_skyline(k, hy, 0.0, BACKDROP_FAR, h * 0.21, false)
	_backdrop_skyline(k, hy, 50.0, BACKDROP_NEAR, h * 0.14, true)
	# the ground and the road, lit warm at the far end and dark near the bottom
	draw_rect(Rect2(0, hy, w, h - hy), BACKDROP_GROUND)
	var far_half = w * 0.03
	var near_half = w * 0.62
	draw_polygon(
		PackedVector2Array(
			[
				Vector2(cx - far_half, hy),
				Vector2(cx + far_half, hy),
				Vector2(cx + near_half, h),
				Vector2(cx - near_half, h)
			]
		),
		PackedColorArray(
			[BACKDROP_ROAD_FAR, BACKDROP_ROAD_FAR, BACKDROP_ROAD_NEAR, BACKDROP_ROAD_NEAR]
		)
	)
	var edge_col = Color(ACCENT, 0.55)
	draw_line(Vector2(cx - far_half, hy), Vector2(cx - near_half, h), edge_col, 3.0 * k)
	draw_line(Vector2(cx + far_half, hy), Vector2(cx + near_half, h), edge_col, 3.0 * k)
	# the centre line: dashes that run towards the player (the closer to the bottom, the longer and wider they are)
	for j in range(12):
		var u0 = fposmod(float(j) / 12.0 + t * 0.12, 1.0)
		var u1 = minf(u0 + 0.04, 1.0)
		var y0 = hy + (h - hy) * u0 * u0
		var y1 = hy + (h - hy) * u1 * u1
		var hw0 = (1.0 + 11.0 * u0 * u0) * k
		var hw1 = (1.0 + 11.0 * u1 * u1) * k
		draw_colored_polygon(
			PackedVector2Array(
				[
					Vector2(cx - hw0, y0),
					Vector2(cx + hw0, y0),
					Vector2(cx + hw1, y1),
					Vector2(cx - hw1, y1)
				]
			),
			Color(1.0, 0.82, 0.45, 0.35 + 0.4 * u0)
		)
	# the riders, farthest first so a near one is drawn over a far one
	for rider in BACKDROP_RIDERS:
		var along = fposmod(t * rider["speed"] + rider["phase"], 1.0)
		var margin = 80.0 * k
		var rx = along * (w + 2.0 * margin) - margin
		if rider["dir"] < 0.0:
			rx = w - rx
		var u = rider["u"]
		var scale_k = (0.35 + 1.5 * u) * k
		_backdrop_rider(
			Vector2(rx, hy + (h - hy) * u), scale_k, rider["dir"], t * 6.0 + along * 40.0
		)
	# the dark corners and edges, then the scrim
	var edge = Color(0, 0, 0, 0.55)
	var clear = Color(0, 0, 0, 0)
	var vw = w * 0.14
	var vh = h * 0.16
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(vw, 0), Vector2(vw, h), Vector2(0, h)]),
		PackedColorArray([edge, clear, clear, edge])
	)
	draw_polygon(
		PackedVector2Array([Vector2(w - vw, 0), Vector2(w, 0), Vector2(w, h), Vector2(w - vw, h)]),
		PackedColorArray([clear, edge, edge, clear])
	)
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, vh), Vector2(0, vh)]),
		PackedColorArray([edge, edge, clear, clear])
	)
	draw_polygon(
		PackedVector2Array([Vector2(0, h - vh), Vector2(w, h - vh), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([clear, clear, edge, edge])
	)
	if scrim > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.03, 0.05, scrim))


# one row of buildings along `base_y`: widths, gaps and heights come from `_hash01` of the building number plus `seed_at`
# (so the two rows differ); `tall` is the height of the tallest one
func _backdrop_skyline(
	k: float, base_y: float, seed_at: float, col: Color, tall: float, lit: bool
) -> void:
	var x = -10.0 * k
	var i = 0
	while x < size.x:
		var n = seed_at + i
		var bw = (34.0 + _hash01(n * 1.3) * 56.0) * k
		var bh = (0.35 + _hash01(n * 2.9) * 0.65) * tall
		draw_rect(Rect2(x, base_y - bh, bw, bh + 2.0), col)
		if lit:
			_backdrop_windows(Rect2(x, base_y - bh, bw, bh), k, n)
		x += bw + (2.0 + _hash01(n * 4.1) * 10.0) * k
		i += 1


# the lit windows of one building: a fixed third of them, glowing a little differently from each other over time
func _backdrop_windows(r: Rect2, k: float, n: float) -> void:
	var columns = int(r.size.x / (13.0 * k))
	var rows = mini(int(r.size.y / (17.0 * k)), 6)
	for row_i in range(rows):
		for col_i in range(columns):
			var hv = _hash01(n * 13.0 + row_i * 5.0 + col_i * 1.7)
			if hv < 0.3:
				var glow = 0.55 + 0.45 * sin(g.time * 0.6 + hv * 40.0)
				var win = Rect2(
					r.position.x + (4.0 + col_i * 13.0) * k,
					r.position.y + (6.0 + row_i * 17.0) * k,
					6.0 * k,
					8.0 * k
				)
				draw_rect(win, Color(1.0, 0.78, 0.4, 0.5 * glow))


# a rider on a bike as a dark outline, standing on `pos` (the ground under the wheels), `s` big, going left (-1) or right
# (1); `pedal` is the angle of the pedals in radians
func _backdrop_rider(pos: Vector2, s: float, dir: float, pedal: float) -> void:
	var col = BACKDROP_RIDER
	var line_w = maxf(1.5, 2.6 * s)
	var wheel_r = 11.0 * s
	var hub_y = pos.y - wheel_r
	var back = Vector2(pos.x - dir * 17.0 * s, hub_y)
	var front = Vector2(pos.x + dir * 17.0 * s, hub_y)
	var crank = Vector2(pos.x, hub_y)
	var seat = Vector2(pos.x - dir * 8.0 * s, hub_y - 14.0 * s)
	var bars = Vector2(pos.x + dir * 11.0 * s, hub_y - 15.0 * s)
	var shoulder = Vector2(pos.x + dir * 4.0 * s, hub_y - 30.0 * s)
	var foot = crank + Vector2(cos(pedal), sin(pedal)) * 5.0 * s
	draw_arc(back, wheel_r, 0.0, TAU, 18, col, line_w)
	draw_arc(front, wheel_r, 0.0, TAU, 18, col, line_w)
	draw_polyline(PackedVector2Array([back, seat, bars, front]), col, line_w)
	draw_line(seat, crank, col, line_w)
	draw_line(crank, bars, col, line_w)
	draw_line(seat, shoulder, col, line_w * 1.8)
	draw_line(shoulder, bars, col, line_w)
	draw_line(seat, foot, col, line_w)
	draw_circle(shoulder + Vector2(dir * 3.0 * s, -7.0 * s), 5.0 * s, col)


# Where the launcher panel sits on the intro screen. For now it holds the start prompt; the login form, the update line
# and PLAY WITHOUT AN ACCOUNT of V5.2 go inside it (it will grow taller), so they have a place that is already drawn.
func intro_panel_rect() -> Rect2:
	var k = size.y / 720.0
	var w = 520.0 * k
	var h = 64.0 * k
	return Rect2((size.x - w) * 0.5, size.y * 0.72, w, h)


func _draw_intro(k: float, cx: float) -> void:
	_menu_backdrop(k, 0.0)
	var logo_y = size.y * 0.34 + sin(g.time * 1.6) * 5.0 * k
	_txt(g.GAME_TITLE, cx + 6.0 * k, logo_y + 7.0 * k, int(190 * k), Color(0, 0, 0, 0.5), 1)
	_txt(g.GAME_TITLE, cx, logo_y, int(190 * k), ACCENT, 1)
	_txt("FSTRELI BICIKLINA 3D", cx, size.y * 0.44, int(34 * k), TEXT, 1)
	_txt(INTRO_TAGLINE, cx, size.y * 0.5, int(18 * k), GOLD, 1)
	var panel = intro_panel_rect()
	draw_rect(panel, Color(0.05, 0.05, 0.08, 0.8))
	draw_rect(panel, ACCENT, false, 3.0 * k)
	var pulse = 0.6 + 0.4 * sin(g.time * 3.0)
	_txt(
		INTRO_PROMPT, cx, panel.position.y + panel.size.y * 0.64, int(24 * k), Color(TEXT, pulse), 1
	)
	if g.pad_on():
		_txt(
			"OR ANY GAMEPAD BUTTON",
			cx,
			panel.position.y + panel.size.y + 26.0 * k,
			int(14 * k),
			GRAY,
			1
		)
	if g.version_label() != "":
		_txt(g.version_label(), size.x - 18.0 * k, size.y * 0.975, int(14 * k), GRAY, 2)
	# the first moments: out of black, so the window opening does not flash
	var fade = 1.0 - clampf(g.time / 0.7, 0.0, 1.0)
	if fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.03, fade))


func _wrap(s: String, max_w: float, fs: int) -> Array:
	var words = s.split(" ")
	var lines = []
	var cur = ""
	for w in words:
		var t = w if cur == "" else cur + " " + w
		if font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w and cur != "":
			lines.append(cur)
			cur = w
		else:
			cur = t
	if cur != "":
		lines.append(cur)
	return lines


# ---------------------------------------------------------------- upgrade cards
func card_rect(i: int, n: int) -> Rect2:
	var k = size.y / 720.0
	var w = 270.0 * k
	var h = 300.0 * k
	var gap = 24.0 * k
	var x0 = (size.x - (n * w + (n - 1) * gap)) * 0.5
	return Rect2(x0 + i * (w + gap), size.y * 0.24, w, h)


func card_at(pos: Vector2) -> int:
	if g == null:
		return -1
	var n = g.shop_items.size()
	if g.state == "upgrade":
		n = g.offers.size()
	elif g.state == "rest":
		n = g.rest_opts.size()
	for i in range(n):
		if card_rect(i, n).has_point(pos):
			return i
	return -1


func _draw_upgrade(k: float) -> void:
	_menu_backdrop(k, 0.55)
	var cx = size.x * 0.5
	_txt("CHOOSE AN UPGRADE", cx, size.y * 0.13, int(40 * k), GOLD, 1)
	if g.rest_upgrade:
		_txt("REST STOP - EXTRA UPGRADE", cx, size.y * 0.18, int(18 * k), TEXT, 1)
	elif g.upgrade_part == "upgrade2":
		_txt("ELITE CLEARED - EXTRA UPGRADE (2 OF 2)", cx, size.y * 0.18, int(18 * k), TEXT, 1)
	elif g.upgrade_extra > 0:
		_txt("ELITE CLEARED - UPGRADE 1 OF 2", cx, size.y * 0.18, int(18 * k), TEXT, 1)
	else:
		_txt("ROUND %d CLEARED" % g.round_n, cx, size.y * 0.18, int(18 * k), TEXT, 1)
	var n = g.offers.size()
	var hov = card_at(get_viewport().get_mouse_position())
	for i in range(n):
		var r = card_rect(i, n)
		var u = g.offers[i]
		var on = hov == i or (hov < 0 and g.menu_sel == i)
		draw_rect(r, Color(0.176, 0.196, 0.22) if on else Color(0.13, 0.14, 0.16))
		draw_rect(r, ACCENT if on else Color(0.29, 0.31, 0.33), false, 3.0 * k)
		_txt(str(i + 1), r.position.x + 24.0 * k, r.position.y + 34.0 * k, int(22 * k), GOLD)
		var ly = r.position.y + 100.0 * k
		for ln in _wrap(u["name"], r.size.x - 30.0 * k, int(22 * k)):
			_txt(ln, r.position.x + r.size.x * 0.5, ly, int(22 * k), TEXT, 1)
			ly += 30.0 * k
		var dy = r.position.y + 175.0 * k
		for ln2 in _wrap(g.shop_sys.item_desc(u), r.size.x - 36.0 * k, int(15 * k)):
			_txt(ln2, r.position.x + r.size.x * 0.5, dy, int(15 * k), Color(0.79, 0.81, 0.83), 1)
			dy += 24.0 * k
		_txt(
			g.shop_sys.upgrade_stat(u["id"]),
			r.position.x + r.size.x * 0.5,
			r.position.y + r.size.y - 30.0 * k,
			int(14 * k),
			ACCENT,
			1
		)
	if int(g.time * 2.0) % 2 == 0:
		_txt("CLICK A CARD OR PRESS 1 2 3", cx, size.y * 0.8, int(20 * k), TEXT, 1)


# ---------------------------------------------------------------- rest stop (state "rest", README alpha B3)
func _draw_rest(k: float) -> void:
	_menu_backdrop(k, 0.55)
	var cx = size.x * 0.5
	_txt("REST STOP", cx, size.y * 0.13, int(40 * k), Color("#6C9BD2"), 1)
	_txt("HEARTS  %d / %d" % [g.hearts, g.MAXHEARTS], cx, size.y * 0.19, int(24 * k), TEXT, 1)
	var n = g.rest_opts.size()
	var hov = card_at(get_viewport().get_mouse_position())
	for i in range(n):
		var r = card_rect(i, n)
		var o = g.rest_opts[i]
		var usable = g.shop_sys.rest_refill_ok() if i == 0 else g.shop_sys.rest_upgrade_ok()
		var on = hov == i or (hov < 0 and g.menu_sel == i)
		draw_rect(r, Color(0.176, 0.196, 0.22) if on else Color(0.13, 0.14, 0.16))
		draw_rect(r, (ACCENT if usable else RED) if on else Color(0.29, 0.31, 0.33), false, 3.0 * k)
		_txt(str(i + 1), r.position.x + 24.0 * k, r.position.y + 34.0 * k, int(22 * k), GOLD)
		var ly = r.position.y + 100.0 * k
		for ln in _wrap(o["name"], r.size.x - 30.0 * k, int(22 * k)):
			_txt(ln, r.position.x + r.size.x * 0.5, ly, int(22 * k), TEXT if usable else GRAY, 1)
			ly += 30.0 * k
		var dy = r.position.y + 175.0 * k
		for ln2 in _wrap(o["desc"], r.size.x - 36.0 * k, int(15 * k)):
			_txt(ln2, r.position.x + r.size.x * 0.5, dy, int(15 * k), Color(0.79, 0.81, 0.83), 1)
			dy += 24.0 * k
		_txt(
			o["stat"] if usable else ("HEARTS ALREADY FULL" if i == 0 else "NO UPGRADES LEFT"),
			r.position.x + r.size.x * 0.5,
			r.position.y + r.size.y - 30.0 * k,
			int(14 * k),
			ACCENT if usable else RED,
			1
		)
	if int(g.time * 2.0) % 2 == 0:
		_txt("CLICK A CARD OR PRESS 1 2", cx, size.y * 0.8, int(20 * k), TEXT, 1)


# ---------------------------------------------------------------- shop
func continue_rect() -> Rect2:
	var k = size.y / 720.0
	return Rect2(size.x * 0.5 - 150.0 * k, size.y * 0.8, 300.0 * k, 48.0 * k)


func reroll_rect() -> Rect2:
	var k = size.y / 720.0
	return Rect2(size.x * 0.5 + 170.0 * k, size.y * 0.8, 250.0 * k, 48.0 * k)


func _draw_shop(k: float) -> void:
	_menu_backdrop(k, 0.55)
	var cx = size.x * 0.5
	_txt("SHOP", cx, size.y * 0.11, int(40 * k), GOLD, 1)
	_txt("CASH  $%d" % g.cash, cx, size.y * 0.17, int(24 * k), TEXT, 1)
	var n = g.shop_items.size()
	var mp = get_viewport().get_mouse_position()
	var hov = card_at(mp)
	for i in range(n):
		var r = card_rect(i, n)
		var it = g.shop_items[i]
		var on = hov == i or (hov < 0 and g.menu_sel == i)
		var afford = g.cash >= it["cost"] and not it["sold"]
		draw_rect(r, Color(0.176, 0.196, 0.22) if on else Color(0.13, 0.14, 0.16))
		draw_rect(r, (ACCENT if afford else RED) if on else Color(0.29, 0.31, 0.33), false, 3.0 * k)
		_txt(str(i + 1), r.position.x + 24.0 * k, r.position.y + 34.0 * k, int(22 * k), GOLD)
		if it["label"] != "":
			_txt(
				it["label"],
				r.position.x + r.size.x - 18.0 * k,
				r.position.y + 34.0 * k,
				int(14 * k),
				PINK if it["perk"] else Color(0.55, 0.78, 0.95),
				2
			)
		var ly = r.position.y + 92.0 * k
		for ln in _wrap(it["name"], r.size.x - 30.0 * k, int(22 * k)):
			_txt(ln, r.position.x + r.size.x * 0.5, ly, int(22 * k), TEXT, 1)
			ly += 28.0 * k
		var dy = r.position.y + 150.0 * k
		for ln2 in _wrap(g.shop_sys.item_desc(it), r.size.x - 36.0 * k, int(15 * k)):
			_txt(ln2, r.position.x + r.size.x * 0.5, dy, int(15 * k), Color(0.79, 0.81, 0.83), 1)
			dy += 22.0 * k
		var ty = r.position.y + 205.0 * k
		for ln3 in _wrap(it["tag"], r.size.x - 36.0 * k, int(13 * k)):
			_txt(ln3, r.position.x + r.size.x * 0.5, ty, int(13 * k), PINK, 1)
			ty += 19.0 * k
		if it["sold"]:
			_txt(
				"SOLD",
				r.position.x + r.size.x * 0.5,
				r.position.y + r.size.y - 26.0 * k,
				int(24 * k),
				GRAY,
				1
			)
		else:
			_txt(
				"$%d" % it["cost"],
				r.position.x + r.size.x * 0.5,
				r.position.y + r.size.y - 26.0 * k,
				int(26 * k),
				GOLD if afford else RED,
				1
			)
	# what you own
	var owned = []
	for id in g.perks.keys():
		owned.append(g.shop_sys.perk_name(id))
	var line = "PERKS: " + (", ".join(owned) if owned.size() > 0 else "NONE YET")
	_txt(line, cx, size.y * 0.72, int(15 * k), TEXT, 1)
	var duos = []
	for d in g.DUOS:
		if g.shop_sys.has_duo(d["name"]):
			duos.append(d["name"] + " (" + d["desc"] + ")")
	if duos.size() > 0:
		_txt("DUOS: " + ", ".join(duos), cx, size.y * 0.76, int(14 * k), GOLD, 1)
	var cr = continue_rect()
	var chov = cr.has_point(mp)
	draw_rect(cr, Color(0.176, 0.196, 0.22) if chov else Color(0.13, 0.14, 0.16))
	draw_rect(cr, ACCENT if chov else Color(0.29, 0.31, 0.33), false, 3.0 * k)
	_txt("CONTINUE  [SPACE]", cx, cr.position.y + 32.0 * k, int(22 * k), TEXT, 1)
	var rr = reroll_rect()
	var rc = g.shop_sys.reroll_cost()
	var rhov = rr.has_point(mp)
	var rok = g.cash >= rc
	draw_rect(rr, Color(0.176, 0.196, 0.22) if rhov else Color(0.13, 0.14, 0.16))
	draw_rect(rr, (ACCENT if rok else RED) if rhov else Color(0.29, 0.31, 0.33), false, 3.0 * k)
	_txt(
		"REROLL  [R]  $%d" % rc,
		rr.position.x + rr.size.x * 0.5,
		rr.position.y + 32.0 * k,
		int(20 * k),
		GOLD if rok else RED,
		1
	)
	_txt("CLICK OR PRESS 1-4 TO BUY", cx, size.y * 0.93, int(14 * k), GRAY, 1)


# ---------------------------------------------------------------- run summary (game over)
# The table of the summary is SUMMARY_HALF_WIDTH * 2 wide, centred, and its first row sits at SUMMARY_TABLE_TOP of
# the window height with SUMMARY_ROW_STEP between rows (all times k = window height / 720). The buttons use the same
# numbers to stay clear of it.
const SUMMARY_HALF_WIDTH = 190.0
const SUMMARY_TABLE_TOP = 0.29
const SUMMARY_ROW_STEP = 28.0
const SUMMARY_ROWS = 10  # rows of the table
# The buttons the summary ends on (alpha C5), top to bottom. Index = `g.summary_sel`.
const SUMMARY_ITEMS = [
	{"id": "new_run", "label": "NEW RUN"},
	{"id": "unlocks", "label": "UNLOCKS"},
	{"id": "title", "label": "TITLE"}
]
const SUMMARY_BTN_W = 240.0
const SUMMARY_BTN_H = 44.0
const SUMMARY_BTN_GAP = 12.0
const SUMMARY_BTN_MIN_W = 130.0  # narrower than this and the column would crowd the table: a row at the bottom instead


# true when the buttons take input: not during the first 0.8 s (keys and clicks still going from the end of the
# fight must not leave the screen) and not while a leaderboard name is being typed (Enter or a click confirms it)
func summary_active() -> bool:
	return g != null and g.state == "over" and g.state_t > 0.8 and not g.name_entry


# The buttons are a column to the right of the table, level with its first row, centred in the free space. The text
# below the table is centred and can be long (challenge lines, three unlock names, a leaderboard rank and a name box
# all at once), so nothing placed under it is safe; beside the table nothing else is drawn. Only in a window too
# narrow for that (under about 4:3) they become a row near the bottom.
func summary_rect(i: int) -> Rect2:
	var k = size.y / 720.0
	var w = SUMMARY_BTN_W * k
	var h = SUMMARY_BTN_H * k
	var gap = SUMMARY_BTN_GAP * k
	var table_right = size.x * 0.5 + SUMMARY_HALF_WIDTH * k
	var free = size.x - table_right
	w = minf(w, free - 40.0 * k)
	if w >= SUMMARY_BTN_MIN_W * k:
		var x = table_right + (free - w) * 0.5
		var top = size.y * SUMMARY_TABLE_TOP - 18.0 * k
		return Rect2(x, top + i * (h + gap), w, h)
	var n = SUMMARY_ITEMS.size()
	var rw = minf(SUMMARY_BTN_W * k, (size.x - 36.0 * k - float(n - 1) * gap) / float(n))
	var total = n * rw + float(n - 1) * gap
	return Rect2((size.x - total) * 0.5 + i * (rw + gap), size.y * 0.885, rw, h)


# the button under `pos`, or -1
func summary_at(pos: Vector2) -> int:
	if g == null or g.state != "over":
		return -1
	for i in range(SUMMARY_ITEMS.size()):
		if summary_rect(i).has_point(pos):
			return i
	return -1


func _draw_summary_buttons(k: float) -> void:
	var live = summary_active()
	var a = 1.0 if live else 0.35  # dim while they would not react yet
	for i in range(SUMMARY_ITEMS.size()):
		var r = summary_rect(i)
		var on = g.summary_sel == i  # the mouse updates summary_sel in input.gd (hover_menu)
		var fill = Color(0.176, 0.196, 0.22) if on else Color(0.13, 0.14, 0.16)
		var edge = ACCENT if on else Color(0.29, 0.31, 0.33)
		var col = TEXT if on else GRAY
		fill.a = a
		edge.a = a
		col.a = a
		draw_rect(r, fill)
		draw_rect(r, edge, false, 3.0 * k)
		_txt(
			SUMMARY_ITEMS[i]["label"],
			r.position.x + r.size.x * 0.5,
			r.position.y + 30.0 * k,
			int(20 * k),
			col,
			1
		)


func _draw_run_summary(k: float, cx: float, blink: bool) -> void:
	if g.run_won:
		_txt("RUN COMPLETE", cx, size.y * 0.15, int(66 * k), GOLD, 1)
		_txt("ALL %d ROUNDS SURVIVED" % g.MAX_ROUNDS, cx, size.y * 0.22, int(20 * k), GOLD, 1)
	else:
		_txt("RUN OVER", cx, size.y * 0.15, int(66 * k), RED, 1)
		if g.OVER_MSG.has(g.over_reason):
			_txt(g.OVER_MSG[g.over_reason], cx, size.y * 0.22, int(20 * k), RED, 1)
	var acc = 0
	if g.shots_fired > 0:
		acc = int(round(100.0 * g.shots_hit / g.shots_fired))
	var coin_label = "META COINS"
	var challenge_coins = g.challenges.coins
	if g.meta.boss_coins > 0 and challenge_coins > 0:
		coin_label = (
			"META COINS (%d FROM BOSSES, %d FROM CHALLENGES)" % [g.meta.boss_coins, challenge_coins]
		)
	elif g.meta.boss_coins > 0:
		coin_label = "META COINS (%d FROM BOSSES)" % g.meta.boss_coins
	elif challenge_coins > 0:
		coin_label = "META COINS (%d FROM CHALLENGES)" % challenge_coins
	var rcols = [GRAY, TEXT, Color(0.35, 0.7, 0.42), GOLD, ACCENT]
	var letters = ["D", "C", "B", "A", "S"]
	var lx = cx - SUMMARY_HALF_WIDTH * k
	var rx = cx + SUMMARY_HALF_WIDTH * k
	var y0 = size.y * SUMMARY_TABLE_TOP
	var step = SUMMARY_ROW_STEP * k  # ten rows now (the XP row was added); 28 instead of 30 keeps the table's end close to where it was
	var rows = [
		["SCORE", str(g.score).pad_zeros(6), TEXT],
		["KILLS", str(g.kills), TEXT],
		["ACCURACY", "%d%%" % acc, TEXT],
		["BEST STYLE RANK", letters[g.best_rank], rcols[g.best_rank]],
		["ROUND REACHED", "%d / %d" % [g.round_n, g.MAX_ROUNDS], TEXT],
		["RUN TIME", g.fmt_time(g.play_time + g.shop_time), TEXT],
		["BEST COMBO", "x%d" % g.best_combo, TEXT],
		[
			"CHALLENGES",
			"%d / %d" % [g.challenges.done.size(), g.challenges.table.size()],
			GOLD if g.challenges.done.size() > 0 else TEXT
		],
		[coin_label, "+%d" % g.meta_earned, GOLD],
		[_xp_row_label(), "+%d" % g.meta.xp_earned, GOLD if g.meta.leveled_up() else XP_COL]
	]
	for i in range(rows.size()):
		var y = y0 + i * step
		draw_rect(Rect2(lx, y + 8.0 * k, rx - lx, 1.0 * k), Color(1, 1, 1, 0.1))
		_txt(rows[i][0], lx, y, int(20 * k), GRAY)
		_txt(rows[i][1], rx, y, int(24 * k), rows[i][2], 2)
	var uy = y0 + rows.size() * step + 14.0 * k
	for line in _challenge_summary_lines():
		_txt(line[0], cx, uy, int(18 * k), line[1], 1)
		uy += 24.0 * k
	if g.score > 0 and g.score >= g.hi and g.ranked_run():
		_txt("NEW HIGH SCORE", cx, uy, int(24 * k), GOLD, 1)
		uy += 34.0 * k
	if g.last_rank >= 0:
		_txt("LEADERBOARD RANK #%d" % (g.last_rank + 1), cx, uy, int(20 * k), GOLD, 1)
		uy += 30.0 * k
		if g.name_entry:
			_txt("TYPE YOUR NAME, ENTER TO CONFIRM", cx, uy, int(14 * k), GRAY, 1)
			var br = Rect2(cx - 150.0 * k, uy + 8.0 * k, 300.0 * k, 36.0 * k)
			draw_rect(br, Color(0.13, 0.14, 0.16))
			draw_rect(br, ACCENT, false, 3.0 * k)
			_txt(g.name_buf, cx, uy + 36.0 * k, int(22 * k), TEXT, 1)
			if blink:
				var tw = (
					_line(g.name_buf, int(22 * k), -1.0, HORIZONTAL_ALIGNMENT_LEFT).get_line_width()
				)
				draw_rect(Rect2(cx + tw * 0.5 + 4.0 * k, uy + 14.0 * k, 3.0 * k, 24.0 * k), TEXT)
		else:
			_txt("SAVED AS  " + g.player_name, cx, uy + 30.0 * k, int(20 * k), TEXT, 1)
		uy += 72.0 * k
	_txt("NOW AFFORDABLE ON THE UNLOCKS PAGE", cx, uy, int(16 * k), GRAY, 1)
	if g.new_unlocks.is_empty():
		_txt("NOTHING NEW THIS RUN", cx, uy + 26.0 * k, int(18 * k), GRAY, 1)
	else:
		var shown = unlock_summary_lines(g.new_unlocks)
		for i in range(shown.size()):
			_txt(shown[i], cx, uy + 26.0 * k + i * 24.0 * k, int(18 * k), GOLD, 1)
	_draw_summary_buttons(k)
	var seed_label = "RUN SEED  " + g.DailyScript.seed_text(g.run_seed)
	if g.daily_mode:
		seed_label = "DAILY RUN SEED  " + g.DailyScript.seed_text(g.run_seed)
	elif g.custom_seed_run:
		seed_label = "CUSTOM SEED  " + g.DailyScript.seed_text(g.run_seed) + "  (NOT RANKED)"
	_txt(seed_label, cx, size.y * 0.975, int(14 * k), GRAY, 1)


# ---------------------------------------------------------------- title screen menu
# The loop comes first (alpha C5.4): CONTINUE (drawn above PLAY when a run is saved), PLAY, LOADOUT, UNLOCKS, then the
# rest. Code and checks find an entry by its id; only a few checks rely on PLAY being entry 0 and QUIT the last.
const TITLE_ITEMS = [
	{"id": "play", "label": "PLAY"},
	{"id": "loadout", "label": "LOADOUT"},
	{"id": "unlocks", "label": "UNLOCKS"},
	{"id": "daily", "label": "DAILY RUN"},
	{"id": "seed", "label": "CUSTOM SEED"},
	{"id": "challenges", "label": "CHALLENGES"},
	{"id": "scores", "label": "HIGH SCORES"},
	{"id": "controls", "label": "CONTROLS"},
	{"id": "settings", "label": "SETTINGS"},
	{"id": "quit", "label": "QUIT"}
]
const TITLE_PAGES = {}
# The CONTINUE button is drawn above PLAY and only while a saved run exists (main.gd `saved_run`). Its index is one past
# the last entry of TITLE_ITEMS, so the indexes of the other entries never change.
const TITLE_CONTINUE = 10


# true when a run is saved and the title menu shows CONTINUE
func title_has_continue() -> bool:
	return g != null and not g.saved_run.is_empty()


# the CONTINUE button: between the logo (it ends at 25 % of the height) and the first button (34.5 %)
func title_continue_rect() -> Rect2:
	var k = size.y / 720.0
	var w = 320.0 * k
	var h = 31.0 * k
	return Rect2((size.x - w) * 0.5, size.y * 0.275, w, h)


# what the CONTINUE button says on its right: the round the run goes on with and how many rounds it has
func title_continue_detail() -> String:
	if g == null or g.saved_run.is_empty():
		return ""
	var next_round = int(g.saved_run["map_floor"]) + 2  # the map screen picks the next floor
	var tag = ""
	if g.saved_run["daily"]:
		tag = "DAILY  "
	elif g.saved_run["custom"]:
		tag = "SEED  "
	return "%sROUND %d / %d" % [tag, mini(next_round, g.saved_run_rounds), g.saved_run_rounds]


func title_rect(i: int) -> Rect2:
	var k = size.y / 720.0
	var w = 320.0 * k
	var h = 31.0 * k  # ten buttons: 31 high with a gap of 4 end where nine of 34 and 5 did
	return Rect2((size.x - w) * 0.5, size.y * 0.345 + i * (h + 4.0 * k), w, h)


func title_at(pos: Vector2) -> int:
	if g == null or g.state != "title" or g.title_page != "" or g.intro_active:
		return -1
	for i in range(TITLE_ITEMS.size()):
		if title_rect(i).has_point(pos):
			return i
	if title_has_continue() and title_continue_rect().has_point(pos):
		return TITLE_CONTINUE
	return -1


func _draw_title_menu(k: float, cx: float) -> void:
	_txt(g.GAME_TITLE, cx, size.y * 0.25, int(120 * k), ACCENT, 1)
	for i in range(TITLE_ITEMS.size()):
		var item = TITLE_ITEMS[i]
		var r = title_rect(i)
		var on = g.title_sel == i  # the mouse updates title_sel in input.gd (hover_menu)
		draw_rect(r, Color(0.176, 0.196, 0.22) if on else Color(0.13, 0.14, 0.16))
		draw_rect(r, ACCENT if on else Color(0.29, 0.31, 0.33), false, 3.0 * k)
		var base = r.position.y + 23.0 * k
		_txt(
			item["label"], r.position.x + r.size.x * 0.5, base, int(20 * k), TEXT if on else GRAY, 1
		)
		if item.get("soon", false):
			_txt("SOON", r.position.x + r.size.x - 12.0 * k, base - 2.0 * k, int(12 * k), GRAY, 2)
	if title_has_continue():
		var cr = title_continue_rect()
		var con = g.title_sel == TITLE_CONTINUE
		draw_rect(cr, Color(0.176, 0.196, 0.22) if con else Color(0.13, 0.14, 0.16))
		draw_rect(cr, ACCENT if con else GOLD, false, 3.0 * k)
		var cbase = cr.position.y + 23.0 * k
		# the label on the left and the round on the right, so the two never run into each other on a 320 px button
		_txt("CONTINUE", cr.position.x + 16.0 * k, cbase, int(20 * k), TEXT if con else GOLD)
		_txt(
			title_continue_detail(),
			cr.position.x + cr.size.x - 12.0 * k,
			cbase - 2.0 * k,
			int(12 * k),
			GRAY,
			2
		)
	_txt("META COINS %d" % g.meta.balance, 18.0 * k, 30.0 * k, int(14 * k), GOLD)
	_draw_title_level(k)
	if g.version_label() != "":
		_txt(g.version_label(), size.x - 18.0 * k, size.y * 0.975, int(14 * k), GRAY, 2)
	_txt(g.daily_label, size.x - 18.0 * k, 30.0 * k, int(14 * k), GRAY, 2)
	if g.daily_arena != "":
		_txt("DAILY ARENA: " + g.daily_arena, size.x - 18.0 * k, 50.0 * k, int(14 * k), GRAY, 2)
	if g.hi > 0:
		_txt("HIGH SCORE " + str(g.hi).pad_zeros(6), cx, size.y * 0.885, int(20 * k), GOLD, 1)
	_txt(
		"WASD MOVE   SHIFT RUN   SPACE JUMP   V DASH   MOUSE AIM   CLICK SHOOT   R RELOAD   Q MELEE",
		cx,
		size.y * 0.93,
		int(14 * k),
		GRAY,
		1
	)
	_txt(
		"GAMEPAD: STICKS MOVE + AIM   RT SHOOT   LT AIM   A JUMP   LB DASH   X RELOAD   Y SWITCH   START PAUSE",
		cx,
		size.y * 0.965,
		int(14 * k),
		GRAY,
		1
	)


# Label of the XP row on the run summary: the level and how far the next one is, or a level-up message
# The lines of the "now affordable" block of the run summary: at most three, so a full summary (leaderboard rank,
# high score and challenge lines at once) is not made any longer by the buttons, which stand beside the table. With more than three names the third
# line says how many are left out.
const UNLOCK_LINES_MAX = 3


func unlock_summary_lines(names: Array) -> Array:
	var lines = []
	if names.size() <= UNLOCK_LINES_MAX:
		for n in names:
			lines.append(str(n).to_upper())
		return lines
	for i in range(UNLOCK_LINES_MAX - 1):
		lines.append(str(names[i]).to_upper())
	lines.append("+ %d MORE" % (names.size() - (UNLOCK_LINES_MAX - 1)))
	return lines


func _xp_row_label() -> String:
	var info = g.meta.xp_info()
	if g.meta.leveled_up():
		return "XP (LEVEL UP! NOW LEVEL %d)" % info["level"]
	if info["max"]:
		return "XP (LEVEL %d, TOP LEVEL)" % info["level"]
	return "XP (LEVEL %d: %d / %d)" % [info["level"], info["into"], info["need"]]


# The level and a progress bar to the next one in the top left corner of the title screen, under the meta coins
func _draw_title_level(k: float) -> void:
	var info = g.meta.xp_info()
	var x = 18.0 * k
	var w = 150.0 * k
	var top = "LEVEL %d" % info["level"]
	if info["max"]:
		top += "  (TOP LEVEL)"
	_txt(top, x, 52.0 * k, int(14 * k), XP_COL)
	var bar = Rect2(x, 60.0 * k, w, 6.0 * k)
	draw_rect(bar, Color(0.13, 0.14, 0.16))
	var frac = 1.0 if info["max"] else float(info["into"]) / float(maxi(1, info["need"]))
	draw_rect(Rect2(bar.position, Vector2(w * clampf(frac, 0.0, 1.0), bar.size.y)), XP_COL)
	draw_rect(bar, Color(0.29, 0.31, 0.33), false, 1.0 * k)
	if info["max"]:
		_txt("XP %d" % g.meta.xp, x, 82.0 * k, int(12 * k), GRAY)
	else:
		_txt("XP %d / %d" % [info["into"], info["need"]], x, 82.0 * k, int(12 * k), GRAY)


# Lines under the run summary table: the challenges done in this run (NEW for the first time ever, with the
# coins) and then the progress of the ones that were not done. Three lines at most, the rest is counted.
const CHALLENGE_LINES = 3


func _challenge_summary_lines() -> Array:
	var lines = []
	var ch = g.challenges
	for c in ch.table:
		if ch.done.has(c["id"]):
			var tag = "NEW  " if ch.new_ids.has(c["id"]) else ""
			lines.append(["%s%s  +%d" % [tag, c["name"], c["reward"]], GOLD])
	for c in ch.table:
		var p = ch.progress_text(c)
		if p != "" and not ch.done.has(c["id"]):
			lines.append(["%s  %s" % [c["name"], p], GRAY])
	if lines.size() > CHALLENGE_LINES:
		var more = lines.size() - (CHALLENGE_LINES - 1)
		lines = lines.slice(0, CHALLENGE_LINES - 1)
		lines.append(["AND %d MORE" % more, GRAY])
	return lines


# A round badge with a small icon (the "icon" of a challenge): gold once the achievement is unlocked, dim before.
func _draw_badge(c: Vector2, r: float, icon: String, on: bool, k: float) -> void:
	var col = GOLD if on else Color(0.38, 0.4, 0.43)
	var w = 2.0 * k
	draw_circle(c, r, Color(0.13, 0.14, 0.16))
	draw_arc(c, r, 0.0, TAU, 32, col, w)
	if icon == "no_gun":
		draw_rect(Rect2(c + Vector2(-0.55, -0.15) * r, Vector2(1.1, 0.3) * r), col)
		draw_line(
			c + Vector2(-0.6, 0.6) * r, c + Vector2(0.6, -0.6) * r, Color(0.13, 0.14, 0.16), 4.0 * k
		)
		draw_line(c + Vector2(-0.6, 0.6) * r, c + Vector2(0.6, -0.6) * r, col, w)
	elif icon == "crate":
		draw_rect(Rect2(c + Vector2(-0.5, -0.5) * r, Vector2(1.0, 1.0) * r), col, false, w)
		draw_line(c + Vector2(-0.5, -0.5) * r, c + Vector2(0.5, 0.5) * r, col, w)
		draw_line(c + Vector2(-0.5, 0.5) * r, c + Vector2(0.5, -0.5) * r, col, w)
	elif icon == "chevrons":
		for dx in [-0.4, 0.1]:
			var pts = PackedVector2Array(
				[
					c + Vector2(dx, -0.5) * r,
					c + Vector2(dx + 0.4, 0.0) * r,
					c + Vector2(dx, 0.5) * r
				]
			)
			draw_polyline(pts, col, w)
	elif icon == "heart":
		draw_circle(c + Vector2(-0.25, -0.15) * r, 0.3 * r, col)
		draw_circle(c + Vector2(0.25, -0.15) * r, 0.3 * r, col)
		draw_colored_polygon(
			PackedVector2Array(
				[
					c + Vector2(-0.53, -0.02) * r,
					c + Vector2(0.53, -0.02) * r,
					c + Vector2(0.0, 0.6) * r
				]
			),
			col
		)
	elif icon == "clock":
		draw_arc(c, 0.55 * r, 0.0, TAU, 24, col, w)
		draw_line(c, c + Vector2(0.0, -0.4) * r, col, w)
		draw_line(c, c + Vector2(0.3, 0.0) * r, col, w)
	else:
		var star = PackedVector2Array()
		for i in range(10):
			var a = -PI * 0.5 + i * PI / 5.0
			var rr = (0.6 if i % 2 == 0 else 0.26) * r
			star.append(c + Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(star, col)


func _draw_challenges_page(k: float, cx: float) -> void:
	_txt("CHALLENGES", cx, size.y * 0.14, int(56 * k), GOLD, 1)
	_txt(
		"EACH ONE PAYS META COINS ONCE PER RUN, WHEN THE RUN ENDS",
		cx,
		size.y * 0.2,
		int(16 * k),
		GRAY,
		1
	)
	var unlocked = g.challenges.unlocked_count()
	_txt(
		"ACHIEVEMENTS  %d / %d" % [unlocked, g.challenges.table.size()],
		cx,
		size.y * 0.25,
		int(20 * k),
		GOLD if unlocked > 0 else GRAY,
		1
	)
	var left = cx - 330.0 * k
	var right = cx + 330.0 * k
	var y0 = size.y * 0.3
	var step = 62.0 * k
	var table = g.challenges.table
	if table.is_empty():
		_txt("NO CHALLENGES LOADED", cx, size.y * 0.5, int(22 * k), GRAY, 1)
	for i in range(table.size()):
		var c = table[i]
		var y = y0 + i * step
		var n = g.challenges.count_of(c)
		draw_rect(Rect2(left, y + 34.0 * k, right - left, 1.0 * k), Color(1, 1, 1, 0.1))
		_draw_badge(Vector2(left + 24.0 * k, y + 8.0 * k), 22.0 * k, c["icon"], n > 0, k)
		_txt(c["name"], left + 62.0 * k, y, int(24 * k), GOLD if n > 0 else TEXT)
		_txt(c["desc"], left + 62.0 * k, y + 26.0 * k, int(16 * k), GRAY)
		_txt("+%d COINS" % c["reward"], right, y, int(20 * k), GOLD, 2)
		var status = "NOT DONE YET"
		if n == 1:
			status = "DONE 1 TIME"
		elif n > 1:
			status = "DONE %d TIMES" % n
		_txt(status, right, y + 26.0 * k, int(16 * k), TEXT if n > 0 else GRAY, 2)
	_txt("CLICK OR PRESS ESC TO GO BACK", cx, size.y * 0.94, int(18 * k), GRAY, 1)


func _draw_scores_page(k: float, cx: float) -> void:
	_txt("HIGH SCORES", cx, size.y * 0.14, int(56 * k), GOLD, 1)
	var y0 = size.y * 0.27
	var c_rank = cx - 300.0 * k
	var c_name = cx - 262.0 * k
	var c_score = cx + 20.0 * k
	var c_round = cx + 100.0 * k
	var c_kills = cx + 170.0 * k
	var c_time = cx + 255.0 * k
	var c_date = cx + 365.0 * k
	_txt("#", c_rank, y0, int(14 * k), GRAY)
	_txt("NAME", c_name, y0, int(14 * k), GRAY)
	_txt("SCORE", c_score, y0, int(14 * k), GRAY, 2)
	_txt("ROUND", c_round, y0, int(14 * k), GRAY, 2)
	_txt("KILLS", c_kills, y0, int(14 * k), GRAY, 2)
	_txt("TIME", c_time, y0, int(14 * k), GRAY, 2)
	_txt("DATE", c_date, y0, int(14 * k), GRAY, 2)
	var list = g.scores.entries
	if list.is_empty():
		_txt(
			"NO SCORES YET - FINISH A RUN TO GET ON THE LIST",
			cx,
			size.y * 0.5,
			int(22 * k),
			GRAY,
			1
		)
	for i in range(list.size()):
		var e = list[i]
		var y = y0 + (i + 1) * 34.0 * k
		var mine = i == g.last_rank
		if mine:
			draw_rect(
				Rect2(c_rank - 12.0 * k, y - 24.0 * k, (c_date - c_rank) + 24.0 * k, 32.0 * k),
				Color(0.95, 0.71, 0.19, 0.14)
			)
		var col = GOLD if mine else TEXT
		_txt(str(i + 1), c_rank, y, int(20 * k), col)
		var nm = str(e.get("name", ""))
		_txt(nm if nm != "" else "-", c_name, y, int(20 * k), col)
		_txt(str(e["score"]).pad_zeros(6), c_score, y, int(22 * k), col, 2)
		_txt(str(e["round"]), c_round, y, int(20 * k), col, 2)
		_txt(str(e["kills"]), c_kills, y, int(20 * k), col, 2)
		# runs saved before the time was kept (or with no time) show a dash
		var t = int(e.get("time", 0))
		_txt(g.fmt_time(float(t)) if t > 0 else "-", c_time, y, int(20 * k), col, 2)
		_txt(str(e["date"]), c_date, y, int(16 * k), GRAY, 2)
	if not list.is_empty():
		var r = scores_reset_rect()
		var on = r.has_point(get_local_mouse_position())
		draw_rect(r, Color(0.176, 0.196, 0.22) if on else Color(0.13, 0.14, 0.16))
		draw_rect(r, ACCENT if on else Color(0.29, 0.31, 0.33), false, 2.0 * k)
		_txt(
			"RESET LEADERBOARD",
			r.position.x + r.size.x * 0.5,
			r.position.y + 25.0 * k,
			int(16 * k),
			TEXT if on else GRAY,
			1
		)
	_txt(
		"CLICK ANYWHERE OR PRESS ESC TO GO BACK   DELETE OR X TO RESET",
		cx,
		size.y * 0.94,
		int(18 * k),
		GRAY,
		1
	)


# the RESET LEADERBOARD button at the bottom of the High Scores page (the click is handled in input.gd)
func scores_reset_rect() -> Rect2:
	var k = size.y / 720.0
	var w = 260.0 * k
	var h = 36.0 * k
	return Rect2((size.x - w) * 0.5, size.y * 0.85, w, h)


# the NO / YES buttons of the reset confirmation (same place as the pause menu confirmation)
func scores_confirm_at(pos: Vector2) -> int:
	if g == null or g.state != "title" or g.title_page != "scores_confirm":
		return -1
	for i in range(2):
		if confirm_rect(i).has_point(pos):
			return i
	return -1


func _draw_scores_confirm(k: float, cx: float) -> void:
	_txt("ERASE ALL HIGH SCORES?", cx, size.y * 0.26, int(60 * k), TEXT, 1)
	_txt(
		"THE WHOLE TOP 10 WILL BE CLEARED (A BACKUP FILE IS KEPT)",
		cx,
		size.y * 0.36,
		int(20 * k),
		RED,
		1
	)
	var labels = ["NO, GO BACK", "YES, ERASE"]
	for i in range(2):
		var r = confirm_rect(i)
		var on = g.confirm_sel == i  # the mouse updates confirm_sel in input.gd (hover_menu)
		draw_rect(r, Color(0.176, 0.196, 0.22) if on else Color(0.13, 0.14, 0.16))
		draw_rect(r, ACCENT if on else Color(0.29, 0.31, 0.33), false, 3.0 * k)
		_txt(
			labels[i],
			r.position.x + r.size.x * 0.5,
			r.position.y + 31.0 * k,
			int(22 * k),
			TEXT if on else GRAY,
			1
		)
	_txt("ESC TO GO BACK", cx, size.y * 0.80, int(16 * k), GRAY, 1)


# the START button of the custom seed page (the click is handled in input.gd)
func seed_start_rect() -> Rect2:
	var k = size.y / 720.0
	return Rect2(size.x * 0.5 - 130.0 * k, size.y * 0.62, 260.0 * k, 46.0 * k)


func _draw_seed_page(k: float, cx: float) -> void:
	_txt("CUSTOM SEED", cx, size.y * 0.2, int(60 * k), GOLD, 1)
	_txt(
		"THE SEED DECIDES THE MAP, THE ARENA AND THE RIDERS.",
		cx,
		size.y * 0.29,
		int(20 * k),
		TEXT,
		1
	)
	_txt(
		"TYPE UP TO 8 DIGITS (0-9, A-F) OR PASTE WITH CTRL+V.",
		cx,
		size.y * 0.34,
		int(16 * k),
		GRAY,
		1
	)
	var box = Rect2(cx - 190.0 * k, size.y * 0.42, 380.0 * k, 64.0 * k)
	draw_rect(box, Color(0.13, 0.14, 0.16))
	draw_rect(box, ACCENT, false, 3.0 * k)
	var shown = g.seed_buf
	if int(g.time * 2.0) % 2 == 0 and shown.length() < 8:
		shown += "_"
	_txt(shown, cx, box.position.y + 46.0 * k, int(40 * k), TEXT, 1)
	_txt(
		"E.G. 7F3A91C2    TODAY'S DAILY SEED IS " + g.DailyScript.seed_text(g.daily_seed),
		cx,
		size.y * 0.56,
		int(14 * k),
		GRAY,
		1
	)
	if g.seed_buf != "":
		var arena = g.arena_style_text(g.seed_buf.hex_to_int())
		if arena != "":
			_txt("ARENA: " + arena, cx, size.y * 0.595, int(18 * k), TEXT, 1)
	var r = seed_start_rect()
	var ready = g.seed_buf != ""
	draw_rect(r, Color(0.176, 0.196, 0.22) if ready else Color(0.13, 0.14, 0.16))
	draw_rect(r, ACCENT if ready else Color(0.29, 0.31, 0.33), false, 3.0 * k)
	_txt("START", cx, r.position.y + 32.0 * k, int(24 * k), TEXT if ready else GRAY, 1)
	_txt(
		"A RUN ON A TYPED SEED IS NOT RANKED: NO HIGH SCORE AND NO TOP 10.",
		cx,
		size.y * 0.78,
		int(14 * k),
		GRAY,
		1
	)
	_txt(
		"ENTER OR CLICK START   ESC OR CLICK ELSEWHERE TO GO BACK",
		cx,
		size.y * 0.84,
		int(18 * k),
		GRAY,
		1
	)


# ---------------------------------------------------------------- controls page (title menu and pause menu)
# {key, action} rows; keep them in step with input.gd and player.gd when a control changes
const CONTROLS_KEYBOARD = [
	["WASD", "MOVE"],
	["SHIFT", "SPRINT (WHILE MOVING FORWARD)"],
	["CTRL / C", "CROUCH (WHILE SPRINTING: SLIDE)"],
	["SPACE", "JUMP (OUT OF A SLIDE, AND DASH IN THE AIR)"],
	["V", "DASH (A NEAR MISS IS A PERFECT DODGE)"],
	["A / D + SPACE", "SIDE DASH (USES THE DASH BAR)"],
	["MOUSE", "AIM"],
	["LEFT CLICK", "SHOOT / SWING THE MELEE WEAPON"],
	["RIGHT CLICK", "AIM DOWN SIGHTS (HOLD, OR TOGGLE IN SETTINGS)"],
	["R", "RELOAD (IN THE SHOP: REROLL)"],
	["Q / WHEEL / 1 / 2", "SWITCH DART GUN AND MELEE (1 GUN, 2 MELEE)"],
	["G", "USE THE GADGET (CHOOSE ONE ON THE LOADOUT PAGE)"],
	["ESC", "PAUSE"],
	["TAB", "SETTINGS"],
	["M", "HOLD TO SHOW THE MAP"],
	["F9", "GRAPHICS QUALITY"],
	["F11", "FULLSCREEN"]
]
const CONTROLS_GAMEPAD = [
	["LEFT STICK", "MOVE"],
	["LEFT STICK CLICK", "SPRINT"],
	["RIGHT STICK", "AIM (WITH AIM ASSIST)"],
	["RT", "SHOOT / SWING THE MELEE WEAPON"],
	["LT", "AIM DOWN SIGHTS (HOLD)"],
	["A", "JUMP"],
	["LB", "DASH"],
	["STICK SIDEWAYS + A", "SIDE DASH (USES THE DASH BAR)"],
	["B", "CROUCH / SLIDE"],
	["X", "RELOAD (IN THE SHOP: REROLL)"],
	["Y / RB", "SWITCH DART GUN AND MELEE"],
	["D-PAD UP", "USE THE GADGET"],
	["START", "PAUSE"],
	["BACK / VIEW", "HOLD TO SHOW THE MAP"],
	["D-PAD + A / B", "MENUS: PICK / BACK"]
]
const CONTROLS_SCREENS = [
	["1 - 4 OR CLICK", "BUY IN THE SHOP (UPGRADES AND MAP: 1 - 3)"],
	["LEFT / RIGHT + ENTER", "PICK A NODE ON THE RUN MAP"],
	["SPACE / ENTER", "LEAVE THE SHOP"]
]


func _draw_controls_rows(rows: Array, x_key: float, x_text: float, y: float, k: float) -> float:
	for row in rows:
		_txt(row[0], x_key, y, int(17 * k), ACCENT)
		_txt(row[1], x_text, y, int(17 * k), TEXT)
		y += 24.0 * k
	return y


func _draw_controls(k: float, cx: float) -> void:
	_txt("CONTROLS", cx, size.y * 0.12, int(56 * k), GOLD, 1)
	var y0 = size.y * 0.255
	_txt("KEYBOARD AND MOUSE", cx - 600.0 * k, y0 - 30.0 * k, int(16 * k), GOLD)
	_draw_controls_rows(CONTROLS_KEYBOARD, cx - 600.0 * k, cx - 410.0 * k, y0, k)
	_txt("GAMEPAD", cx + 40.0 * k, y0 - 30.0 * k, int(16 * k), GOLD)
	var y = _draw_controls_rows(CONTROLS_GAMEPAD, cx + 40.0 * k, cx + 230.0 * k, y0, k)
	_txt("SHOP, UPGRADES AND MAP", cx + 40.0 * k, y + 14.0 * k, int(16 * k), GOLD)
	_draw_controls_rows(CONTROLS_SCREENS, cx + 40.0 * k, cx + 280.0 * k, y + 44.0 * k, k)
	_txt("CLICK OR PRESS ESC TO GO BACK", cx, size.y * 0.94, int(18 * k), GRAY, 1)


# ---------------------------------------------------------------- loadout page (title menu)
# Two lists side by side: the starting perks on the left and the three weapon slots (primary, melee, gadget) on the
# right. Left / Right (D-pad) switch the active list; the weapon slot rows take the next owned weapon when chosen.
func loadout_rect(i: int) -> Rect2:
	var k = size.y / 720.0
	var w = 400.0 * k
	return Rect2(size.x * 0.5 - 440.0 * k, size.y * 0.25 + i * 26.0 * k, w, 24.0 * k)


# the row under a point of the perk list of the Loadout page, -1 for none
func loadout_at(pos: Vector2) -> int:
	if g == null or g.state != "title" or g.title_page != "loadout":
		return -1
	for i in range(g.loadout_options().size()):
		if loadout_rect(i).has_point(pos):
			return i
	return -1


# a weapon slot row (i is an index into WeaponSlots.SLOTS)
func loadout_slot_rect(i: int) -> Rect2:
	var k = size.y / 720.0
	return Rect2(size.x * 0.5 + 40.0 * k, size.y * 0.25 + i * 62.0 * k, 400.0 * k, 54.0 * k)


# the weapon slot row under a point of the Loadout page, -1 for none
func loadout_slot_at(pos: Vector2) -> int:
	if g == null or g.state != "title" or g.title_page != "loadout":
		return -1
	for i in range(WeaponSlots.SLOTS.size()):
		if loadout_slot_rect(i).has_point(pos):
			return i
	return -1


# The small counter in the corner of a weapon slot on the Loadout page, for the row `cur_at` of `wopts` (the rows
# of Main.loadout_weapon_options). The empty row ("NO MELEE", "NO GADGET", an id of "") is not a weapon, so it is
# not counted as owned: with nothing owned it says so, and while it is shown it only says how many are owned.
func loadout_owned_text(wopts: Array, cur_at: int) -> String:
	var owned = 0
	var position_of_current = 0
	for m in range(wopts.size()):
		if str(wopts[m]["id"]) == "":
			continue
		owned += 1
		if m <= cur_at:
			position_of_current = owned
	if owned == 0:
		return "NONE OWNED"
	if str(wopts[cur_at]["id"]) == "":
		return "%d OWNED" % owned
	return "%d OF %d OWNED" % [position_of_current, owned]


func _draw_loadout(k: float, cx: float) -> void:
	_txt("LOADOUT", cx, size.y * 0.12, int(56 * k), GOLD, 1)
	_txt(
		"CHOOSE A STARTING PERK AND ONE WEAPON FOR EACH SLOT",
		cx,
		size.y * 0.185,
		int(18 * k),
		TEXT,
		1
	)
	var opts = g.loadout_options()
	var sel = clampi(g.loadout_sel, 0, opts.size() - 1)
	var perk_active = g.loadout_col == 0
	_txt("STARTING PERK", loadout_rect(0).position.x, size.y * 0.235, int(14 * k), GOLD)
	_txt("WEAPONS", loadout_slot_rect(0).position.x, size.y * 0.235, int(14 * k), GOLD)
	for i in range(opts.size()):
		var r = loadout_rect(i)
		var chosen = opts[i]["id"] == g.meta.start_perk
		if i == sel:
			draw_rect(r, Color(0.176, 0.196, 0.22))
			draw_rect(r, ACCENT if perk_active else GRAY, false, 2.0 * k)
		var base = r.position.y + 17.0 * k
		_txt(
			opts[i]["name"],
			r.position.x + 10.0 * k,
			base,
			int(15 * k),
			TEXT if (i == sel and perk_active) or chosen else GRAY
		)
		if chosen:
			_txt("CHOSEN", r.end.x - 10.0 * k, base, int(14 * k), GOLD, 2)
	if opts.size() == 1:
		_txt(
			"YOU OWN NO STARTING PERKS YET: BUY THEM ON THE UNLOCKS PAGE",
			loadout_rect(0).position.x,
			size.y * 0.25 + 40.0 * k,
			int(12 * k),
			GRAY
		)
	var detail_name = opts[sel]["name"]
	var detail_desc = opts[sel]["desc"]
	for n in range(WeaponSlots.SLOTS.size()):
		var slot = WeaponSlots.SLOTS[n]
		var wopts = g.loadout_weapon_options(slot)
		var cur = g.loadout_weapon_id(slot)
		var cur_at = 0
		for m in range(wopts.size()):
			if wopts[m]["id"] == cur:
				cur_at = m
		var wr = loadout_slot_rect(n)
		var active = not perk_active and n == g.loadout_slot
		draw_rect(wr, Color(0.176, 0.196, 0.22) if active else Color(0.1, 0.11, 0.125))
		draw_rect(wr, ACCENT if active else Color(0.3, 0.32, 0.36), false, 2.0 * k)
		_txt(
			WeaponSlots.SLOT_NAMES[slot],
			wr.position.x + 10.0 * k,
			wr.position.y + 18.0 * k,
			int(12 * k),
			GOLD
		)
		_txt(
			wopts[cur_at]["name"],
			wr.position.x + 10.0 * k,
			wr.position.y + 42.0 * k,
			int(18 * k),
			TEXT if active else GRAY
		)
		_txt(
			loadout_owned_text(wopts, cur_at),
			wr.end.x - 10.0 * k,
			wr.position.y + 18.0 * k,
			int(12 * k),
			GRAY,
			2
		)
		if active:
			detail_name = wopts[cur_at]["name"]
			detail_desc = wopts[cur_at]["desc"]
			if wopts.size() > 1:
				_txt(
					"ENTER: NEXT",
					wr.end.x - 10.0 * k,
					wr.position.y + 42.0 * k,
					int(12 * k),
					ACCENT,
					2
				)
	_txt(detail_name, cx, size.y * 0.84, int(26 * k), TEXT, 1)
	_txt(detail_desc, cx, size.y * 0.84 + 26.0 * k, int(16 * k), TEXT, 1)
	_txt(
		"YOUR LOADOUT IS USED IN EVERY RUN, THE DAILY RUN AND CUSTOM SEEDS TOO",
		cx,
		size.y * 0.9,
		int(14 * k),
		ACCENT,
		1
	)
	_txt(
		"UP / DOWN LOOK   LEFT / RIGHT SWITCH LIST   ENTER, A OR A CLICK CHOOSE   ESC, B OR A CLICK BESIDE THE LISTS BACK",
		cx,
		size.y * 0.955,
		int(14 * k),
		GRAY,
		1
	)


# ---------------------------------------------------------------- unlocks page (title menu)
const UnlocksTable = preload("res://scripts/unlocks.gd")
const UNLOCK_GROUPS = {
	"starting_perk": "STARTING PERKS",
	"shop_item": "SHOP ITEMS",
	"weapon": "WEAPONS",
	"cosmetic": "COSMETICS"
}
const UNLOCK_KIND_TEXT = {
	"starting_perk": "START A RUN WITH THIS PERK",
	"shop_item": "JOINS THE SHOP",
	"weapon": "A WEAPON FOR THE LOADOUT PAGE",
	"cosmetic": "A COSMETIC"
}


# Where each unlock sits: the starting perks fill the left column, everything else the right column under a
# heading per kind. Returns {"rows": Array of Rect2, one per entry of g.UNLOCKS in the same order, "heads": Array of
# {"text", "pos"}}; drawing, the mouse and the keyboard all use it.
func unlocks_layout() -> Dictionary:
	var k = size.y / 720.0
	var rows = []
	var heads = []
	var y = {"left": size.y * 0.25, "right": size.y * 0.25}
	var last_kind = {"left": "", "right": ""}
	# A row is 24 px high, but it gets shorter (down to 16 px) when a column would otherwise run into the detail text
	# under the list: every new weapon adds a row to the right column. tools/unlocks_page_check.gd checks the fit.
	var room = size.y * 0.8 - 26.0 * k - size.y * 0.25 - 2.0 * k
	var fixed = {"left": 0.0, "right": 0.0}  # headings and gaps of a column
	var count = {"left": 0, "right": 0}
	var seen = {"left": "", "right": ""}
	for u in g.UNLOCKS:
		var col = "left" if u["kind"] == "starting_perk" else "right"
		if seen[col] != u["kind"]:
			fixed[col] += (10.0 * k if seen[col] != "" else 0.0) + 30.0 * k
			seen[col] = u["kind"]
		count[col] += 1
	var row_h = 24.0 * k
	for col in count:
		if count[col] > 0:
			row_h = minf(row_h, (room - fixed[col]) / float(count[col]))
	row_h = floorf(maxf(row_h, 16.0 * k))  # whole pixels, so one row ends exactly where the next begins
	for u in g.UNLOCKS:
		var side = "left" if u["kind"] == "starting_perk" else "right"
		var x = size.x * 0.5 - 440.0 * k if side == "left" else size.x * 0.5 + 20.0 * k
		if last_kind[side] != u["kind"]:
			if last_kind[side] != "":
				y[side] += 10.0 * k
			var text = UNLOCK_GROUPS.get(u["kind"], str(u["kind"]).to_upper())
			heads.append({"text": text, "pos": Vector2(x, y[side] + 18.0 * k)})
			y[side] += 30.0 * k
			last_kind[side] = u["kind"]
		rows.append(Rect2(x, y[side], 420.0 * k, row_h))
		y[side] += row_h
	return {"rows": rows, "heads": heads}


# the BUY button under the detail text (it also shows OWNED, COMING SOON or what is missing)
func unlock_buy_rect() -> Rect2:
	var k = size.y / 720.0
	var w = 260.0 * k
	return Rect2((size.x - w) * 0.5, size.y * 0.885, w, 30.0 * k)


# the TRY IT button beside the BUY button: it takes the player and the weapon into the training room
func unlock_try_rect() -> Rect2:
	var k = size.y / 720.0
	var br = unlock_buy_rect()
	return Rect2(br.end.x + 12.0 * k, br.position.y, 170.0 * k, br.size.y)


# the unlock under a point of the Unlocks page, -1 for none
func unlock_at(pos: Vector2) -> int:
	if g == null or g.state != "title" or g.title_page != "unlocks":
		return -1
	var rows = unlocks_layout()["rows"]
	for i in range(rows.size()):
		if rows[i].has_point(pos):
			return i
	return -1


# the entry in the other column that sits closest to entry i (Left / Right on the page), i when there is none
func unlock_other_column(i: int) -> int:
	var rows = unlocks_layout()["rows"]
	if i < 0 or i >= rows.size():
		return i
	var best = i
	var best_d = INF
	for j in range(rows.size()):
		if absf(rows[j].position.x - rows[i].position.x) < 1.0:
			continue
		var d = absf(rows[j].position.y - rows[i].position.y)
		if d < best_d:
			best_d = d
			best = j
	return best


func _draw_unlocks(k: float, cx: float) -> void:
	_txt("UNLOCKS", cx, size.y * 0.12, int(56 * k), GOLD, 1)
	_txt("META COINS %d" % g.meta.balance, cx, size.y * 0.185, int(18 * k), GOLD, 1)
	if g.UNLOCKS.is_empty():
		_txt("NOTHING TO UNLOCK YET", cx, size.y * 0.45, int(24 * k), GRAY, 1)
		_txt("CLICK OR PRESS ESC TO GO BACK", cx, size.y * 0.94, int(18 * k), GRAY, 1)
		return
	var lay = unlocks_layout()
	for h in lay["heads"]:
		_txt(h["text"], h["pos"].x, h["pos"].y, int(16 * k), GOLD)
	for i in range(g.UNLOCKS.size()):
		var u = g.UNLOCKS[i]
		var r = lay["rows"][i]
		var st = UnlocksTable.state_of(u, g.meta.owns(u["id"]), g.meta.balance)
		var on = g.unlock_sel == i  # the mouse updates unlock_sel in input.gd (hover_menu)
		if on:
			draw_rect(r, Color(0.176, 0.196, 0.22))
			draw_rect(r, ACCENT, false, 2.0 * k)
		var base = r.position.y + 17.0 * k
		var name_col = TEXT if (on or st == "owned" or st == "afford") else GRAY
		_txt(u["name"], r.position.x + 10.0 * k, base, int(15 * k), name_col)
		var tag = "%d COINS" % u["cost"]
		var tag_col = GOLD if st == "afford" else GRAY
		if st == "owned":
			tag = "OWNED"
			tag_col = GOLD
		elif st == "soon":
			tag = "SOON"
		_txt(tag, r.position.x + r.size.x - 10.0 * k, base, int(14 * k), tag_col, 2)
	var cur = g.UNLOCKS[clampi(g.unlock_sel, 0, g.UNLOCKS.size() - 1)]
	var cur_st = UnlocksTable.state_of(cur, g.meta.owns(cur["id"]), g.meta.balance)
	var y = size.y * 0.8
	_txt(cur["name"], cx, y, int(26 * k), TEXT, 1)
	_txt(cur["desc"], cx, y + 28.0 * k, int(16 * k), TEXT, 1)
	_txt(UNLOCK_KIND_TEXT.get(cur["kind"], ""), cx, y + 50.0 * k, int(15 * k), GRAY, 1)
	var br = unlock_buy_rect()
	var can_buy = cur_st == "afford"
	draw_rect(br, Color(0.176, 0.196, 0.22) if can_buy else Color(0.13, 0.14, 0.16))
	draw_rect(br, ACCENT if can_buy else Color(0.29, 0.31, 0.33), false, 3.0 * k)
	var label = "BUY  %d COINS" % cur["cost"]
	if cur_st == "owned":
		label = "OWNED"
	elif cur_st == "soon":
		label = "COMING SOON"
	elif cur_st == "locked":
		label = "NEED %d MORE" % (cur["cost"] - g.meta.balance)
	_txt(label, cx, br.position.y + 22.0 * k, int(18 * k), TEXT if can_buy else GRAY, 1)
	if g.can_try(cur):
		var tr = unlock_try_rect()
		draw_rect(tr, Color(0.176, 0.196, 0.22))
		draw_rect(tr, ACCENT, false, 3.0 * k)
		_txt(
			"TRY IT  T / Y",
			tr.position.x + tr.size.x * 0.5,
			tr.position.y + 22.0 * k,
			int(16 * k),
			TEXT,
			1
		)
	if g.unlock_msg != "" and g.time - g.unlock_msg_t0 < 3.0:
		var bought = g.unlock_msg == "BOUGHT"
		_txt(g.unlock_msg, cx, size.y * 0.225, int(18 * k), GOLD if bought else ACCENT, 1)
	_txt(
		"ARROWS OR D-PAD TO LOOK   ENTER, A OR THE BUTTON TO BUY   ESC, B OR A CLICK BESIDE THE LIST TO GO BACK",
		cx,
		size.y * 0.955,
		int(14 * k),
		GRAY,
		1
	)


# placeholder pages for the screens that are still on the roadmap
func _draw_title_page(k: float, cx: float) -> void:
	if g.title_page == "scores":
		_draw_scores_page(k, cx)
		return
	if g.title_page == "scores_confirm":
		_draw_scores_confirm(k, cx)
		return
	if g.title_page == "reset_confirm":
		_draw_confirm(k, cx)  # the two RESET ALL PROGRESS warnings, same page as the pause menu one
		return
	if g.title_page == "challenges":
		_draw_challenges_page(k, cx)
		return
	if g.title_page == "seed":
		_draw_seed_page(k, cx)
		return
	if g.title_page == "controls":
		_draw_controls(k, cx)
		return
	if g.title_page == "unlocks":
		_draw_unlocks(k, cx)
		return
	if g.title_page == "loadout":
		_draw_loadout(k, cx)
		return
	var info = TITLE_PAGES.get(g.title_page, ["", ""])
	_txt(info[0], cx, size.y * 0.24, int(60 * k), GOLD, 1)
	_txt(info[1], cx, size.y * 0.34, int(20 * k), TEXT, 1)
	_txt("COMING SOON", cx, size.y * 0.56, int(32 * k), ACCENT, 1)
	_txt("CLICK OR PRESS ESC TO GO BACK", cx, size.y * 0.78, int(18 * k), GRAY, 1)


# ---------------------------------------------------------------- run map screen (state "map")
const MAP_COLORS = {
	"normal": Color("#7FB069"),
	"elite": Color("#D1495B"),
	"shop": Color("#EDAE49"),
	"event": Color("#00A6A6"),
	"rest": Color("#6C9BD2"),
	"boss": Color("#8E44AD"),
}
const MAP_LETTERS = {
	"normal": "N", "elite": "E", "shop": "S", "event": "?", "rest": "R", "boss": "B"
}
# One line for the highlighted node on the map screen: what choosing it does (README alpha B6). The event node has
# none: it is switched off in the alpha (event weight 0 in `data/map_rules.json`). A boss has two, see map_node_line.
const MAP_LINES = {
	"normal": "A FIGHT. CLEAR IT, THEN PICK AN UPGRADE.",
	"elite": "A HARDER FIGHT. CLEAR IT FOR TWO UPGRADES.",
	"shop": "NO FIGHT. SPEND YOUR CASH ON ITEMS AND PERKS.",
	"rest": "NO FIGHT. REFILL YOUR HEARTS OR TAKE AN EXTRA UPGRADE.",
}
const MAP_BOSS_LINE = "A BOSS GUARDS THIS FLOOR."
const MAP_FINAL_LINE = "THE FINAL BOSS."


# the line that says what a node of type t does; last_floor is true for the node on the final floor
func map_node_line(t: String, last_floor: bool) -> String:
	if t == "boss":
		return MAP_FINAL_LINE if last_floor else MAP_BOSS_LINE
	return str(MAP_LINES.get(t, ""))


# where the key prompt at the bottom of the map screen is drawn (a baseline). Lower than the other screens' prompts so a
# first-run hint line fits between it and the first row of nodes (README early alpha E1.5); tools/hint_screens_check.gd
# uses it too.
func map_prompt_y(_k: float) -> float:
	return size.y * 0.955


# left edge and width of the info panel on the right of the map screen
func map_info_x() -> float:
	return size.x * 0.68


func map_info_width() -> float:
	return size.x * 0.29


# the line of a node, wrapped to the panel (empty for a type with no line)
func map_node_lines(t: String, last_floor: bool, k: float) -> Array:
	var line = map_node_line(t, last_floor)
	if line == "":
		return []
	return _wrap(line, map_info_width(), int(18 * k))


# Where the node of floor f (0-based) and lane i is drawn: floor 1 at the bottom, the final boss at the top,
# lanes spread left to right around the left-middle of the screen (the info panel is on the right).
func map_node_pos(f: int, i: int) -> Vector2:
	var k = size.y / 720.0
	var floors = g.run_map["floors"]
	var top = size.y * 0.2
	var bottom = size.y * 0.84
	var steps = maxi(1, floors.size() - 1)
	var x = size.x * 0.4 + (float(i) - float(floors[f].size() - 1) * 0.5) * 120.0 * k
	var y = bottom - (bottom - top) * float(f) / float(steps)
	return Vector2(x, y)


# which entry of g.map_choices is under the mouse, or -1
func map_choice_at(pos: Vector2) -> int:
	if g == null or g.state != "map" or g.run_map.is_empty():
		return -1
	var k = size.y / 720.0
	for idx in range(g.map_choices.size()):
		if map_node_pos(g.map_floor + 1, int(g.map_choices[idx])).distance_to(pos) <= 28.0 * k:
			return idx
	return -1


func _draw_map_screen(k: float, cx: float) -> void:
	_menu_backdrop(k, 0.55)
	var floors = g.run_map["floors"]
	_txt("CHOOSE YOUR NEXT STOP", cx, size.y * 0.09, int(46 * k), GOLD, 1)
	# the arena the whole run is played in (one style per run); the roundabout has none
	if g.arena.style_label() != "":
		_txt("ARENA: " + g.arena.style_label(), cx, size.y * 0.135, int(18 * k), GRAY, 1)
	var next_f = g.map_floor + 1
	# edges: grey, the path taken in gold, the edges you can take now in white
	for f in range(floors.size() - 1):
		for i in range(floors[f].size()):
			var a = map_node_pos(f, i)
			for j in floors[f][i]["next"]:
				var b = map_node_pos(f + 1, int(j))
				var col = Color(1, 1, 1, 0.16)
				var width = 2.0 * k
				if f < g.map_path.size() - 1 and g.map_path[f] == i and g.map_path[f + 1] == int(j):
					col = GOLD
					width = 5.0 * k
				elif f == g.map_floor and i == g.map_lane and g.map_choices.has(int(j)):
					col = Color(1, 1, 1, 0.8)
					width = 3.0 * k
				draw_line(a, b, col, width, true)
	if g.map_floor < 0:
		for i in g.map_choices:
			draw_line(
				map_node_pos(0, int(i)) + Vector2(0.0, 50.0 * k),
				map_node_pos(0, int(i)),
				Color(1, 1, 1, 0.8),
				3.0 * k,
				true
			)
	var pulse = 0.5 + 0.5 * sin(g.time * 5.0)
	for f in range(floors.size()):
		_txt(
			"%d" % (f + 1),
			map_node_pos(f, 0).x - 130.0 * k - float(floors[f].size() - 1) * 60.0 * k,
			map_node_pos(f, 0).y + 6.0 * k,
			int(16 * k),
			GRAY,
			2
		)
		for i in range(floors[f].size()):
			var p = map_node_pos(f, i)
			var t = str(floors[f][i]["type"])
			var fill = MAP_COLORS.get(t, GRAY)
			var taken = f < g.map_path.size() and g.map_path[f] == i
			var choice = f == next_f and g.map_choices.has(i)
			var picked = choice and g.map_choices[g.map_sel] == i
			var r = 20.0 * k
			if not taken and not choice:
				fill = fill.darkened(0.6)
			if taken:
				draw_circle(p, r + 5.0 * k, GOLD)
			elif picked:
				draw_circle(p, r + (6.0 + 3.0 * pulse) * k, TEXT)
			elif choice:
				draw_circle(p, r + 4.0 * k, Color(1, 1, 1, 0.6))
			else:
				draw_circle(p, r + 2.0 * k, Color(0, 0, 0, 0.6))
			draw_circle(p, r, fill)
			_txt(MAP_LETTERS.get(t, "-"), p.x, p.y + 7.0 * k, int(20 * k), Color.BLACK, 1)
	# the panel on the right: what the highlighted choice is
	var px = map_info_x()
	if g.map_choices.size() > 0:
		var node = floors[next_f][g.map_choices[g.map_sel]]
		var t = str(node["type"])
		_txt("FLOOR %d OF %d" % [next_f + 1, floors.size()], px, size.y * 0.3, int(18 * k), GRAY)
		_txt(
			g.NODE_NAMES.get(t, t.to_upper()),
			px,
			size.y * 0.38,
			int(34 * k),
			MAP_COLORS.get(t, TEXT)
		)
		var ly = size.y * 0.44
		for ln in map_node_lines(t, next_f + 1 == floors.size(), k):
			_txt(ln, px, ly, int(18 * k), TEXT)
			ly += 24.0 * k
		_txt("ROUND %d" % (next_f + 1), px, size.y * 0.57, int(18 * k), TEXT)
	# the cash waits for a shop node (README alpha B1.2): show what the player has to spend
	_txt("CASH  $%d" % g.cash, px, size.y * 0.62, int(24 * k), GOLD)
	_txt("SPEND IT AT A SHOP NODE", px, size.y * 0.67, int(14 * k), GRAY)
	_txt(
		"LEFT / RIGHT OR MOUSE TO CHOOSE   ENTER OR CLICK TO GO   1-3 PICKS DIRECTLY",
		cx,
		map_prompt_y(k),
		int(14 * k),
		GRAY,
		1
	)


# ---------------------------------------------------------------- pause menu
const PAUSE_ITEMS = [
	{"id": "resume", "label": "RESUME"},
	{"id": "settings", "label": "SETTINGS"},
	{"id": "controls", "label": "CONTROLS"},
	{"id": "restart", "label": "RESTART RUN"},
	{"id": "title", "label": "QUIT TO TITLE"}
]


# the pause menu's entries: in the training room (try before buying) BACK TO UNLOCKS takes the place of RESTART RUN
# and QUIT TO TITLE, because nothing there is a run that could be lost
func pause_items() -> Array:
	if g != null and g.practice:
		return [
			{"id": "resume", "label": "RESUME"},
			{"id": "settings", "label": "SETTINGS"},
			{"id": "controls", "label": "CONTROLS"},
			{"id": "leave_practice", "label": "BACK TO UNLOCKS"}
		]
	return PAUSE_ITEMS


func pause_rect(i: int) -> Rect2:
	var k = size.y / 720.0
	var w = 320.0 * k
	var h = 46.0 * k
	return Rect2((size.x - w) * 0.5, size.y * 0.325 + i * (h + 10.0 * k), w, h)


func pause_at(pos: Vector2) -> int:
	if g == null or not g.paused or g.pause_page != "":
		return -1
	for i in range(pause_items().size()):
		if pause_rect(i).has_point(pos):
			return i
	return -1


func _draw_pause_menu(k: float, cx: float) -> void:
	_txt("PAUSED", cx, size.y * 0.26, int(60 * k), TEXT, 1)
	for i in range(pause_items().size()):
		var r = pause_rect(i)
		var on = g.pause_sel == i  # the mouse updates pause_sel in input.gd (hover_menu)
		draw_rect(r, Color(0.176, 0.196, 0.22) if on else Color(0.13, 0.14, 0.16))
		draw_rect(r, ACCENT if on else Color(0.29, 0.31, 0.33), false, 3.0 * k)
		_txt(
			pause_items()[i]["label"],
			r.position.x + r.size.x * 0.5,
			r.position.y + 31.0 * k,
			int(22 * k),
			TEXT if on else GRAY,
			1
		)
	_txt("ESC TO RESUME", cx, size.y * 0.80, int(16 * k), GRAY, 1)


# ---------------------------------------------------------------- arena map, shown while M is held (explore_map.gd)
# Drawn while `main.map_held()` is true (M held in a round); the round keeps running behind it. A top-down view of the
# part of the arena the player has explored: north (-z) is up, east (+x) is right. Ground the
# player has not been near is not drawn, and a supply cache or the extraction point only appears once the player has
# come within sense range of it. Shapes carry the meaning as well as colours: a circle is the start, a bar a gate, a
# diamond a cache (hollow once taken), a square the way out, a triangle you.
const MAP_START = Color("#FF2D95")
const MAP_GATE = Color("#19D3E6")
const MAP_TAKEN = Color(0.62, 0.62, 0.58)
const MAP_FOG = Color(0.05, 0.055, 0.065)
const MAP_LEGEND = [
	["you", "YOU"],
	["start", "START"],
	["gate", "GATE"],
	["cache", "CACHE"],
	["taken", "TAKEN"],
	["exit", "EXIT"]
]


# the square the map is drawn in
func map_rect() -> Rect2:
	var side = minf(size.y * 0.7, size.x * 0.9)
	return Rect2((size.x - side) * 0.5, size.y * 0.17, side, side)


# the screen point of a world point on the map
func map_point(p: Vector3, r: Rect2) -> Vector2:
	var ex = g.explore_sys
	var span = float(ex.n) * ex.cell
	return r.position + Vector2(p.x / span + 0.5, p.z / span + 0.5) * r.size.x


# one map symbol (also used by the legend); `dir` is the way "you" points, in screen space
func _map_symbol(
	kind: String, at: Vector2, k: float, col: Color, dir: Vector2 = Vector2(0, -1)
) -> void:
	var edge = Color(0, 0, 0, 0.8)
	if kind == "start":
		draw_circle(at, 6.5 * k, col)
		draw_arc(at, 6.5 * k, 0.0, TAU, 20, edge, 1.5 * k)
	elif kind == "gate":
		draw_rect(Rect2(at - Vector2(8, 2.5) * k, Vector2(16, 5) * k), col)
	elif kind == "cache":
		_diamond(at, 7.5 * k, col)
	elif kind == "taken":
		var r = 7.0 * k
		var pts = PackedVector2Array(
			[
				at + Vector2(0, -r),
				at + Vector2(r, 0),
				at + Vector2(0, r),
				at + Vector2(-r, 0),
				at + Vector2(0, -r)
			]
		)
		draw_polyline(pts, col, 2.0 * k)
	elif kind == "exit":
		var r = Rect2(at - Vector2(7, 7) * k, Vector2(14, 14) * k)
		draw_rect(r, col)
		draw_rect(r, edge, false, 1.5 * k)
	elif kind == "you":
		var side = Vector2(-dir.y, dir.x)
		var pts = PackedVector2Array(
			[
				at + dir * 10.0 * k,
				at - dir * 6.0 * k + side * 6.5 * k,
				at - dir * 6.0 * k - side * 6.5 * k
			]
		)
		draw_colored_polygon(pts, col)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), edge, 1.5 * k)


func _draw_map_overlay(k: float, cx: float) -> void:
	_txt("MAP", cx, size.y * 0.1, int(56 * k), GOLD, 1)
	var ex = g.explore_sys
	if not ex.enabled() or ex.n <= 0:
		_txt("THIS ARENA HAS NO MAP", cx, size.y * 0.5, int(24 * k), GRAY, 1)
		_txt("RELEASE M OR BACK TO CLOSE", cx, size.y * 0.94, int(18 * k), GRAY, 1)
		return
	var o = g.objective_sys
	var r = map_rect()
	var cs = r.size.x / float(ex.n)
	draw_rect(r, MAP_FOG)
	# the ground that has been seen, one rectangle per run of cells with the same ground
	var rows = ex.layout()["rows"]
	for iz in range(ex.n):
		var row = str(rows[iz])
		var run_from = 0
		var run_ch = ""
		for ix in range(ex.n + 1):
			var ch = ""
			if ix < ex.n and ex.cell_seen(ix, iz):
				ch = row[ix]
			if ch == run_ch:
				continue
			if run_ch != "":
				draw_rect(
					Rect2(
						r.position.x + float(run_from) * cs,
						r.position.y + float(iz) * cs,
						float(ix - run_from) * cs,
						cs + 0.5
					),
					ex.GROUND_COLORS.get(run_ch, Color(1, 0, 1))
				)
			run_ch = ch
			run_from = ix
	draw_rect(r, Color(0.29, 0.31, 0.33), false, 3.0 * k)
	# the start, and the gates in the part that has been seen
	_map_symbol("start", map_point(g.arena.start_position(), r), k, MAP_START)
	for gate in g.arena.gates():
		if not ex.gate_seen(gate):
			continue
		var at = map_point(gate["pos"], r)
		var out = Vector2(gate["outward"].x, gate["outward"].z)
		var along = Vector2(-out.y, out.x)
		var half = float(gate["half_width"]) * cs / ex.cell
		draw_line(at - along * half, at + along * half, MAP_GATE, 5.0 * k)
	# the caches the player has found (taken ones hollow) and the extraction point once found
	for i in range(mini(ex.cache_found.size(), o.caches.size())):
		if not ex.cache_found[i]:
			continue
		var cache: Dictionary = o.caches[i]
		var cp = map_point(cache["pos"], r)
		if cache["taken"]:
			_map_symbol("taken", cp, k, MAP_TAKEN)
		else:
			_map_symbol("cache", cp, k, OBJ_GOLD)
	if ex.goal_found and o.has_goal():
		var gp = map_point(o.goal["pos"], r)
		_map_symbol("exit", gp, k, OBJ_GREEN if o.extracting else Color(OBJ_LOCKED, 0.85))
		_txt(
			"EXIT", gp.x, gp.y - 12.0 * k, int(13 * k), OBJ_GREEN if o.extracting else OBJ_LOCKED, 1
		)
	# you
	var pp = map_point(g.player.position, r)
	pp = Vector2(clampf(pp.x, r.position.x, r.end.x), clampf(pp.y, r.position.y, r.end.y))
	var fwd = Vector2(-sin(g.yaw), -cos(g.yaw))  # the way the player looks, on the map (north is up)
	_map_symbol("you", pp, k, TEXT, fwd)
	_txt(
		(
			"EXPLORED %d%%     CACHES TAKEN %d / %d     %s"
			% [
				int(round(ex.explored_fraction() * 100.0)),
				o.taken,
				o.caches.size(),
				"WAY OUT OPEN" if o.extracting else "WAY OUT LOCKED"
			]
		),
		cx,
		size.y * 0.145,
		int(16 * k),
		GRAY,
		1
	)
	# the legend, in the same shapes and colours
	var lw = minf(size.x * 0.7, 920.0 * k)
	var step = lw / float(MAP_LEGEND.size())
	var ly = r.end.y + 26.0 * k
	var colors = {
		"you": TEXT,
		"start": MAP_START,
		"gate": MAP_GATE,
		"cache": OBJ_GOLD,
		"taken": MAP_TAKEN,
		"exit": OBJ_GREEN
	}
	for i in range(MAP_LEGEND.size()):
		var lx = cx - lw * 0.5 + step * float(i) + 14.0 * k
		_map_symbol(MAP_LEGEND[i][0], Vector2(lx, ly - 5.0 * k), k, colors[MAP_LEGEND[i][0]])
		_txt(MAP_LEGEND[i][1], lx + 18.0 * k, ly, int(15 * k), TEXT)
	_txt("RELEASE M OR BACK TO CLOSE", cx, size.y * 0.94, int(18 * k), GRAY, 1)


# Restart Run and Quit to Title lose the run, so they ask first. NO is the first button and the default.
# "warn" is the red text under the title (wrapped to the width of the screen); "danger" paints the YES button red.
# reset1 and reset2 are the two warnings of RESET ALL PROGRESS, one after the other (input.gd confirm_activate).
const CONFIRM_TEXT = {
	"restart": {"title": "RESTART RUN?", "yes": "YES, RESTART"},
	"title": {"title": "QUIT TO TITLE?", "yes": "YES, QUIT"},
	"reset1":
	{
		"title": "RESET ALL PROGRESS?",
		"yes": "YES, CONTINUE",
		"danger": true,
		"warn":
		[
			"ALL YOUR PROGRESS WILL BE WIPED: COINS, UNLOCKS, LOADOUT, XP, CHALLENGES, HIGH SCORES AND THE SAVED RUN.",
			"THIS CANNOT BE UNDONE AND CANNOT BE RECOVERED."
		]
	},
	"reset2":
	{
		"title": "ARE YOU ABSOLUTELY SURE?",
		"yes": "YES, WIPE EVERYTHING",
		"danger": true,
		"warn": ["THIS IS YOUR LAST CHANCE. EVERYTHING WILL BE GONE FOR GOOD."]
	}
}


func confirm_rect(i: int) -> Rect2:
	var k = size.y / 720.0
	var w = 320.0 * k
	var h = 46.0 * k
	return Rect2((size.x - w) * 0.5, size.y * 0.46 + i * (h + 10.0 * k), w, h)


func confirm_at(pos: Vector2) -> int:
	if g == null:
		return -1
	var on_pause = g.paused and g.pause_page == "confirm"
	var on_title = g.state == "title" and g.title_page == "reset_confirm"  # the RESET ALL PROGRESS warnings
	if not on_pause and not on_title:
		return -1
	for i in range(2):
		if confirm_rect(i).has_point(pos):
			return i
	return -1


func _draw_confirm(k: float, cx: float) -> void:
	var text = CONFIRM_TEXT.get(g.confirm_id, CONFIRM_TEXT["restart"])
	_txt(text["title"], cx, size.y * 0.26, int(60 * k), TEXT, 1)
	var warn = text.get("warn", ["THIS RUN WILL BE LOST - NO SCORE AND NO COINS"])
	var wy = size.y * 0.36
	for line in warn:
		for part in _wrap(str(line), size.x * 0.84, int(20 * k)):
			_txt(part, cx, wy, int(20 * k), RED, 1)
			wy += 26.0 * k
	var danger = text.get("danger", false)
	var labels = ["NO, GO BACK", text["yes"]]
	for i in range(2):
		var r = confirm_rect(i)
		var on = g.confirm_sel == i  # the mouse updates confirm_sel in input.gd (hover_menu)
		if danger and i == 1:  # the YES that wipes everything is red
			draw_rect(r, Color(0.5, 0.08, 0.07) if on else Color(0.36, 0.06, 0.06))
			draw_rect(r, Color(1.0, 0.3, 0.24) if on else RED.darkened(0.35), false, 3.0 * k)
		else:
			draw_rect(r, Color(0.176, 0.196, 0.22) if on else Color(0.13, 0.14, 0.16))
			draw_rect(r, ACCENT if on else Color(0.29, 0.31, 0.33), false, 3.0 * k)
		_txt(
			labels[i],
			r.position.x + r.size.x * 0.5,
			r.position.y + 31.0 * k,
			int(22 * k),
			TEXT if on else GRAY,
			1
		)
	_txt("ESC TO GO BACK", cx, size.y * 0.80, int(16 * k), GRAY, 1)


# ---------------------------------------------------------------- settings panel (pause screen / title with TAB)
const ALL_SETTING_ROWS = [
	{"id": "fov", "label": "FIELD OF VIEW", "min": 60.0, "max": 105.0, "fmt": "%d"},
	{"id": "sens", "label": "MOUSE SENSITIVITY", "min": 0.3, "max": 3.0, "fmt": "%.1fx"},
	{"id": "assist", "label": "AIM ASSIST (STICK)", "min": 0.0, "max": 1.0, "fmt": "pct"},
	{"id": "vol", "label": "VOLUME", "min": 0.0, "max": 1.0, "fmt": "pct"},
	{"id": "tads", "label": "TOGGLE AIM (RMB / LT)", "toggle": true},
	{"id": "outline", "label": "OUTLINES", "toggle": true},
	{"id": "rim", "label": "RIM GLOW (RED FOES, GREEN BYSTANDERS)", "toggle": true},
	{"id": "fx", "label": "SHAKE AND FLASH", "min": 0.0, "max": 1.0, "fmt": "pct"},
	{"id": "quality", "label": "GRAPHICS", "choices": ["HIGH", "MEDIUM", "LOW"]},
	{"id": "fullscreen", "label": "FULLSCREEN", "toggle": true},
	{"id": "sound", "label": "SOUND", "toggle": true},
	{"id": "voices", "label": "VOICES", "toggle": true},
	{"id": "hints", "label": "FIRST-TIME HINTS", "toggle": true},
	# a button, not a setting: opens the two warnings of RESET ALL PROGRESS (input.gd reset_progress_open)
	{"id": "reset_progress", "label": "RESET ALL PROGRESS", "action": true, "danger": true}
]

var _setting_rows = null


# the rows that are shown: the OUTLINES switch only exists while the toon look is on (toon.gd)
func setting_rows() -> Array:
	if _setting_rows == null:
		_setting_rows = []
		for row in ALL_SETTING_ROWS:
			if row["id"] != "outline" or Toon.ENABLED:
				_setting_rows.append(row)
	return _setting_rows


func settings_visible() -> bool:
	return (
		g != null
		and (
			(g.paused and g.pause_page == "settings")
			or (g.state == "title" and g.title_page == "settings")
		)
	)


# the extra space above the red RESET ALL PROGRESS row, so it stands apart from the settings (in units of 720 p)
const DANGER_GAP = 12.0


func panel_rect() -> Rect2:
	var k = size.y / 720.0
	var w = 560.0 * k
	var h = (44.0 + setting_rows().size() * 34.0 + 12.0 + DANGER_GAP) * k
	return Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h)


func row_rect(i: int) -> Rect2:
	var k = size.y / 720.0
	var pr = panel_rect()
	var gap = DANGER_GAP if setting_rows()[i].get("danger", false) else 0.0
	return Rect2(
		pr.position.x + 16.0 * k,
		pr.position.y + (44.0 + gap) * k + i * 34.0 * k,
		pr.size.x - 32.0 * k,
		30.0 * k
	)


func track_rect(i: int) -> Rect2:
	var k = size.y / 720.0
	var r = row_rect(i)
	return Rect2(r.position.x + r.size.x * 0.46, r.position.y + 10.0 * k, r.size.x * 0.38, 10.0 * k)


# the row under a point of the settings panel, -1 for none
func setting_row_at(pos: Vector2) -> int:
	if not settings_visible():
		return -1
	for i in range(setting_rows().size()):
		if row_rect(i).has_point(pos):
			return i
	return -1


func setting_at(pos: Vector2) -> String:
	var i = setting_row_at(pos)
	return "" if i < 0 else str(setting_rows()[i]["id"])


func is_toggle(id: String) -> bool:
	for row in setting_rows():
		if row["id"] == id:
			return row.get("toggle", false) or row.has("choices")
	return false


# true for a row that is a button (RESET ALL PROGRESS), not a switch, a choice or a slider
func is_action(id: String) -> bool:
	for row in setting_rows():
		if row["id"] == id:
			return row.get("action", false)
	return false


func apply_slider(id: String, pos: Vector2) -> void:
	for i in range(setting_rows().size()):
		var row = setting_rows()[i]
		if row["id"] == id and row.has("min"):
			var tr = track_rect(i)
			var t = clampf((pos.x - tr.position.x) / tr.size.x, 0.0, 1.0)
			g.set_setting(id, lerpf(float(row["min"]), float(row["max"]), t))


func _draw_settings(k: float) -> void:
	var pr = panel_rect()
	draw_rect(pr, Color(0.07, 0.075, 0.09, 0.95))
	draw_rect(pr, Color(0.29, 0.31, 0.33), false, 2.0 * k)
	_txt(
		"SETTINGS", pr.position.x + pr.size.x * 0.5, pr.position.y + 30.0 * k, int(20 * k), GOLD, 1
	)
	var sel = clampi(g.setting_sel, 0, setting_rows().size() - 1)  # the mouse moves it too (hover_menu)
	for i in range(setting_rows().size()):
		var row = setting_rows()[i]
		var r = row_rect(i)
		if row.get("danger", false):
			# the red RESET ALL PROGRESS button: red all the time, brighter while it is the picked row
			draw_rect(r, Color(0.5, 0.08, 0.07) if i == sel else Color(0.36, 0.06, 0.06))
			draw_rect(r, Color(1.0, 0.3, 0.24) if i == sel else RED.darkened(0.35), false, 2.0 * k)
			_txt(
				row["label"],
				r.position.x + r.size.x * 0.5,
				r.position.y + 21.0 * k,
				int(14 * k),
				TEXT,
				1
			)
			continue
		if i == sel:
			draw_rect(r, Color(1, 1, 1, 0.06))
			draw_rect(r, ACCENT, false, 2.0 * k)
		var ty = r.position.y + 21.0 * k
		_txt(row["label"], r.position.x + 8.0 * k, ty, int(14 * k), TEXT)
		if row.has("choices"):
			var ch = int(g.get_setting(row["id"]))
			_txt(row["choices"][ch], r.position.x + r.size.x - 10.0 * k, ty, int(14 * k), ACCENT, 2)
		elif row.get("toggle", false):
			var on = bool(g.get_setting(row["id"]))
			_txt(
				"ON" if on else "OFF",
				r.position.x + r.size.x - 10.0 * k,
				ty,
				int(14 * k),
				ACCENT if on else GRAY,
				2
			)
		else:
			var tr = track_rect(i)
			var v = float(g.get_setting(row["id"]))
			var t = clampf(
				(v - float(row["min"])) / (float(row["max"]) - float(row["min"])), 0.0, 1.0
			)
			draw_rect(tr, Color(0.23, 0.16, 0.07))
			draw_rect(Rect2(tr.position, Vector2(tr.size.x * t, tr.size.y)), ACCENT)
			draw_circle(
				Vector2(tr.position.x + tr.size.x * t, tr.position.y + tr.size.y * 0.5),
				8.0 * k,
				TEXT
			)
			var txt = ""
			if row["fmt"] == "pct":
				txt = "%d%%" % int(round(v * 100.0))
			else:
				txt = row["fmt"] % v
			_txt(txt, r.position.x + r.size.x - 10.0 * k, ty, int(14 * k), TEXT, 2)


func _draw_settings_hints(k: float, cx: float) -> void:
	_txt(
		"UP / DOWN: PICK A ROW   LEFT / RIGHT: CHANGE   ENTER: SWITCH ON / OFF",
		cx,
		size.y * 0.89,
		int(14 * k),
		GRAY,
		1
	)
	_txt("ESC OR CLICK OUTSIDE TO GO BACK", cx, size.y * 0.92, int(14 * k), GRAY, 1)
	# a few seconds after RESET ALL PROGRESS: the wipe is done (or part of it failed)
	if g.time - g.progress_wiped_t0 < 6.0:
		var msg = "ALL PROGRESS WIPED"
		if g.progress_wipe_failed > 0:
			msg = "WIPED, BUT %d FILE(S) COULD NOT BE DELETED" % g.progress_wipe_failed
		_txt(msg, cx, panel_rect().position.y - 14.0 * k, int(18 * k), GOLD, 1)


# ---------------------------------------------------------------- main draw
func _draw() -> void:
	if g == null or font == null:
		return
	var k = size.y / 720.0
	var cx = size.x * 0.5
	var state = g.state

	# screen flashes
	if g.flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.08 * g.flash / 0.07 * g.fx_scale))
	if g.red_flash > 0.0:
		draw_rect(
			Rect2(Vector2.ZERO, size), Color(0.9, 0.15, 0.1, 0.4 * g.red_flash / 0.35 * g.fx_scale)
		)

	# hype: warm glow on the screen edges
	if state == "play" and g.hype_t > 0.0:
		var ga = 0.10 + 0.06 * sin(g.time * 8.0)
		draw_rect(Rect2(0, 0, 12.0 * k, size.y), Color(1.0, 0.67, 0.16, ga))
		draw_rect(Rect2(size.x - 12.0 * k, 0, 12.0 * k, size.y), Color(1.0, 0.67, 0.16, ga))

	# floating 3D popups (+points, JOJ!, pickups ...)
	for p in g.popups:
		if g.cam.is_position_behind(p["pos"]):
			continue
		var sp = g.cam.unproject_position(p["pos"])
		var a = clampf(1.0 - p["t"] / 1.3, 0.0, 1.0)
		var col = p["col"]
		col.a = a
		_txt(p["txt"], sp.x, sp.y, int((17 if p["sm"] else 24) * k), col, 1)

	# armour pips over armoured riders
	if state == "play":
		for r in g.riders:
			if r["max_hp"] > 1 and (r["mode"] == "fly" or r["mode"] == "away"):
				var wp = r["pos"] + Vector3(0.0, 2.15, 0.0)
				if g.cam.is_position_behind(wp):
					continue
				var s2 = g.cam.unproject_position(wp)
				var pw = 12.0 * k
				var x0 = s2.x - r["max_hp"] * pw * 0.5
				for i in range(r["max_hp"]):
					draw_rect(
						Rect2(x0 + i * pw + 1.0, s2.y, pw - 2.0, 6.0 * k),
						Color(0.95, 0.71, 0.19) if i < r["hp"] else Color(0.23, 0.18, 0.17)
					)

	if state != "title":  # the title screen has its own corner texts, the run bar would overlap them
		_draw_hud_top(k)

	if state == "play":
		_draw_crosshair(k)
		_draw_threats(k)
		_draw_radar(k)
		_draw_fps(k)
		_draw_objective(k)
		_draw_hud_bottom(k)
		_draw_boss_ui(k)
		if g.practice:
			_draw_practice_banner(k, cx)
		if g.riders.size() == 0 and g.bosses.size() == 0 and g.wait > 0.0 and g.wait_msg != "":
			_txt(g.wait_msg, cx, size.y * 0.30, int(46 * k), TEXT, 1)
			# at the start of a round on a generated arena, the style the seed picked for it
			if g.wait_msg.begins_with("ROUND ") and g.arena.style_label() != "":
				_txt(g.arena.style_label(), cx, size.y * 0.30 + 50.0 * k, int(24 * k), GRAY, 1)
		if g.buffs["shield"] > 0.0:
			draw_arc(
				Vector2(cx, size.y + 230.0 * k),
				360.0 * k,
				PI * 1.2,
				PI * 1.8,
				48,
				Color(0.75, 0.59, 0.94, 0.8),
				4.0 * k
			)

	# centre notes (PERFECT, PEDESTRIAN HIT ...)
	var ny = size.y * 0.38
	for n in g.notes:
		var c = n["col"]
		c.a = clampf(1.6 - n["t"], 0.0, 1.0)
		_txt(n["txt"], cx, ny, int(26 * k), c, 1)
		ny += 36.0 * k

	if g.hit_marker > 0.0:
		var m = 10.0 * k
		var cy = size.y * 0.5
		var hc = Color(1, 1, 1, clampf(g.hit_marker / 0.18, 0.0, 1.0))
		draw_line(Vector2(cx - m, cy - m), Vector2(cx - m * 0.4, cy - m * 0.4), hc, 3.0 * k)
		draw_line(Vector2(cx + m, cy - m), Vector2(cx + m * 0.4, cy - m * 0.4), hc, 3.0 * k)
		draw_line(Vector2(cx - m, cy + m), Vector2(cx - m * 0.4, cy + m * 0.4), hc, 3.0 * k)
		draw_line(Vector2(cx + m, cy + m), Vector2(cx + m * 0.4, cy + m * 0.4), hc, 3.0 * k)

	var blink = int(g.time * 2.0) % 2 == 0
	if state == "title":
		if g.intro_active:
			_draw_intro(k, cx)
		elif g.title_page == "":
			_menu_backdrop(k, 0.28)
			_draw_title_menu(k, cx)
		else:
			_menu_backdrop(k, 0.6)
			if g.title_page != "settings":
				_draw_title_page(k, cx)

	elif state == "over":
		_menu_backdrop(k, 0.5)
		_draw_run_summary(k, cx, blink)
	elif state == "clear":
		_menu_backdrop(k, 0.4)
		var n_hit = g.count_hits()
		_txt("ROUND CLEAR", cx, size.y * 0.2, int(70 * k), GOLD, 1)
		var hit_line = "%d OF %d HIT" % [n_hit, g.PER_ROUND]
		if not g.riders_can_escape():
			hit_line = "ALL %d RIDERS DOWN" % g.PER_ROUND
		_txt(hit_line, cx, size.y * 0.38, int(32 * k), TEXT, 1)
		_txt("SCORE " + str(g.score).pad_zeros(6), cx, size.y * 0.46, int(26 * k), TEXT, 1)
		var acc = 0
		if g.shots_fired > 0:
			acc = int(round(100.0 * g.shots_hit / g.shots_fired))
		_txt(
			"ACCURACY %d%%   BEST COMBO x%d" % [acc, g.best_combo],
			cx,
			size.y * 0.52,
			int(20 * k),
			TEXT,
			1
		)
		if g.score > 0 and g.score >= g.hi and g.ranked_run():
			_txt("NEW HIGH SCORE", cx, size.y * 0.58, int(24 * k), GOLD, 1)
		var elite = g.shop_sys.node_is_elite()
		if elite:  # README alpha B4: the elite node pays a second upgrade pick
			_txt("ELITE CLEARED - EXTRA UPGRADE", cx, size.y * 0.64, int(24 * k), GOLD, 1)
		if g.state_t > 0.8 and blink:
			var prompt = "CLICK TO PICK 2 UPGRADES" if elite else "CLICK TO PICK AN UPGRADE"
			_txt(prompt, cx, size.y * (0.74 if elite else 0.7), int(28 * k), TEXT, 1)
	elif state == "upgrade":
		_draw_upgrade(k)
	elif state == "shop":
		_draw_shop(k)
	elif state == "rest":
		_draw_rest(k)
	elif state == "map":
		_draw_map_screen(k, cx)

	if state != "title":
		_draw_hint(k, cx)

	if g.paused:
		if g.pause_page == "settings":
			_menu_backdrop(k, 0.6)
			_draw_settings(k)
			_draw_settings_hints(k, cx)
		elif g.pause_page == "confirm":
			_menu_backdrop(k, 0.45)
			_draw_confirm(k, cx)
		elif g.pause_page == "controls":
			_menu_backdrop(k, 0.6)
			_draw_controls(k, cx)
		else:
			_menu_backdrop(k, 0.45)
			_draw_pause_menu(k, cx)
	elif g.map_held():
		_dim(0.78)
		_draw_map_overlay(k, cx)
	elif state == "title" and g.title_page == "settings":
		_draw_settings(k)
		_draw_settings_hints(k, cx)


# ---------------------------------------------------------------- pieces
# The first-run hint line (README early alpha E1.2): one line of text with a dark strip behind it, bottom centre, for
# Settings.HINT_SECONDS and fading out at the end. Only drawn: no rect is registered for a click, no key is read, so it
# never blocks input. In a round it sits above the dash bar and the FREE DARTS line. On the upgrade and rest screens it
# sits at 86.5 % of the height, between the cards and the bottom of the window. The shop has its CONTINUE and REROLL buttons
# there, so its line goes at the top, in the gap between the CASH line and the cards. The map has its first row of nodes
# at 84 % of the height, so its line goes in the gap between that row and the key prompt (which sits a little lower for
# it, see map_prompt_y). The pause menu and the other pages are drawn over it. Checked by tools/hint_screens_check.gd.
func hint_y(k: float) -> float:
	if g.state == "play":
		return size.y - 118.0 * k
	if g.state == "shop":
		return size.y * 0.17 + 32.0 * k
	if g.state == "map":
		return size.y * 0.84 + 54.0 * k
	return size.y * 0.865


# the font size of the hint line: 18 at 720p, made smaller when the line would not fit the window width
func hint_fs(k: float) -> int:
	var fs = int(18 * k)
	var max_w = size.x - 48.0 * k
	while fs > 8 and font.get_string_size(g.hint_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		fs -= 1
	return fs


# the dark strip behind the hint line (an empty Rect2 while no hint is showing); also what tools/hint_line_check.gd measures
func hint_rect(k: float) -> Rect2:
	if g.hint_txt == "":
		return Rect2()
	var tw = font.get_string_size(g.hint_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, hint_fs(k)).x
	var w = tw + 28.0 * k
	return Rect2((size.x - w) * 0.5, hint_y(k) - 20.0 * k, w, 32.0 * k)


func _draw_hint(k: float, cx: float) -> void:
	var a = g.settings.hint_alpha()
	if a <= 0.0:
		return
	draw_rect(hint_rect(k), Color(0.04, 0.04, 0.05, 0.72 * a))
	var col = TEXT
	col.a = a
	_txt(g.hint_txt, cx, hint_y(k), hint_fs(k), col, 1)


# the line under the round panel in the training room: where the player is, what is being tried and how to leave
func _draw_practice_banner(k: float, cx: float) -> void:
	_txt("TRYING THE " + str(g.practice_unlock.get("name", "")), cx, 82.0 * k, int(18 * k), GOLD, 1)
	_txt("NOTHING COUNTS HERE   ESC FOR THE MENU", cx, 104.0 * k, int(14 * k), GRAY, 1)


# ---------------------------------------------------------------- in-round HUD (modern FPS layout)
# Corners, like a current shooter: radar top left, round and progress top centre, score and cash top right, health and
# hype bottom left, the big ammo counter with the weapon name bottom right, dash and style bottom centre. Dark
# translucent panels with a thin light edge, flat bars, no full-width strips. The centre of the screen only has the
# crosshair, hit marker and notes. The bottom centre keeps the old positions (DASH label 62 px, FREE DARTS 84 px above
# the bottom at 720p), because the hint line sits above them (`hint_y`, tools/hint_line_check.gd).
const HUD_PANEL = Color(0.04, 0.05, 0.07, 0.55)
const HUD_EDGE = Color(1.0, 1.0, 1.0, 0.14)
const HUD_EMPTY = Color(1.0, 1.0, 1.0, 0.13)  # the empty part of a bar or a segment
const HUD_HEALTH = Color(0.95, 0.3, 0.26)
const HUD_MARGIN = 18.0  # pixels at 720p between the HUD and the side of the window
const HUD_BOTTOM = 22.0  # ... and the bottom of the window (the baseline of the bottom row)


# the width of a text in pixels
func _text_w(s: String, fs: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


# the one panel look of the HUD: dark and translucent with a thin light edge
func _hud_panel(r: Rect2) -> void:
	draw_rect(r, HUD_PANEL)
	draw_rect(r, HUD_EDGE, false, 1.0)


# a key hint in a small box ("Q", "V"), right edge at right_x; returns the left edge
func _key_chip(key: String, right_x: float, base_y: float, fs: int, k: float) -> float:
	var w = _text_w(key, fs) + 10.0 * k
	var r = Rect2(right_x - w, base_y - fs - 2.0 * k, w, fs + 7.0 * k)
	_hud_panel(r)
	_txt(key, r.position.x + w * 0.5, base_y, fs, TEXT, 1)
	return r.position.x


func _draw_hud_top(k: float) -> void:
	var cx = size.x * 0.5
	var rx = size.x - HUD_MARGIN * k

	# round and progress, top centre: one segment per rider, red hit, grey missed, the next one blinks
	var round_label = "ROUND %d/%d  %s" % [g.round_n, g.MAX_ROUNDS, g.THEMES[g.theme_idx]["name"]]
	if g.practice:
		round_label = "TRAINING ROOM"
	if g.daily_mode:
		round_label += "  DAILY"
	elif g.custom_seed_run:
		round_label += "  SEED"
	var fs = int(14 * k)
	var seg_w = 20.0 * k
	var seg_gap = 4.0 * k
	var row_w = g.PER_ROUND * (seg_w + seg_gap) - seg_gap
	var pw = maxf(_text_w(round_label, fs), row_w) + 28.0 * k
	_hud_panel(Rect2(cx - pw * 0.5, 6.0 * k, pw, 42.0 * k))
	_txt(round_label, cx, 26.0 * k, fs, GOLD, 1)
	for i in range(g.PER_ROUND):
		var st = g.hits[i] if i < g.hits.size() else null
		var col = Color(TEXT, 0.55)
		if st == true:
			col = RED
		elif st == false:
			col = GRAY
		elif i < g.next_idx and g.state == "play" and int(g.time * 4.0) % 2 == 0:
			col = GOLD
		draw_rect(Rect2(cx - row_w * 0.5 + i * (seg_w + seg_gap), 33.0 * k, seg_w, 7.0 * k), col)

	# score, high score, cash and combo, top right
	_txt(str(g.score).pad_zeros(6), rx, 38.0 * k, int(32 * k), TEXT, 2)
	_txt("HI " + str(g.hi).pad_zeros(6), rx, 56.0 * k, int(12 * k), GRAY, 2)
	var cash = "$%d" % g.cash
	_txt(cash, rx, 82.0 * k, int(22 * k), GOLD, 2)
	_txt("CASH", rx - _text_w(cash, int(22 * k)) - 8.0 * k, 82.0 * k, int(11 * k), GRAY, 2)
	if g.combo > 1:
		_txt("COMBO x%d" % g.combo, rx, 106.0 * k, int(20 * k), ACCENT, 2)


func _draw_hud_bottom(k: float) -> void:
	_draw_hud_vitals(k)
	_draw_hud_ammo(k)
	_draw_hud_centre(k)


# health (one segment per heart, the last one pulses), the hype meter and the active pickups, bottom left
func _draw_hud_vitals(k: float) -> void:
	var x0 = HUD_MARGIN * k
	var by = size.y - HUD_BOTTOM * k
	var n = g.MAXHEARTS
	var seg_w = 44.0 * k
	var seg_h = 14.0 * k
	var gap = 4.0 * k
	var icon_w = 32.0 * k
	var bars_w = n * (seg_w + gap) - gap

	# hype meter under the health panel
	var on = g.hype_t > 0.0
	var label = "HYPE"
	if on:
		label = "HYPE MODE x2  %.1fs" % g.hype_t
	_txt(label, x0 + icon_w, by - 12.0 * k, int(11 * k), ACCENT if on else GRAY)
	var fcol = ACCENT
	if on and int(g.time * 10.0) % 2 == 1:
		fcol = Color(1.0, 0.82, 0.25)
	var frac = (g.hype_t / 8.0) if on else (g.hype / 100.0)
	draw_rect(Rect2(x0 + icon_w, by - 6.0 * k, bars_w, 6.0 * k), HUD_EMPTY)
	draw_rect(Rect2(x0 + icon_w, by - 6.0 * k, bars_w * clampf(frac, 0.0, 1.0), 6.0 * k), fcol)

	# health
	var panel = Rect2(x0 - 8.0 * k, by - 56.0 * k, icon_w + bars_w + 16.0 * k, 30.0 * k)
	_hud_panel(panel)
	var y = panel.position.y + 8.0 * k
	var hcol = HUD_HEALTH
	if g.hearts == 1:  # the last heart: the whole meter pulses
		hcol.a = 0.7 + 0.3 * sin(g.time * 8.0)
	_heart(x0 + 11.0 * k, y + seg_h * 0.5, 22.0 * k, hcol)
	for i in range(n):
		var col = hcol if i < g.hearts else HUD_EMPTY
		draw_rect(Rect2(x0 + icon_w + i * (seg_w + gap), y, seg_w, seg_h), col)

	# active pickups above the health panel, each with a coloured tick
	var y2 = panel.position.y - 10.0 * k
	var items = [
		["RAPID FIRE", g.buffs["rapid"], Color(1.0, 0.48, 0.1), true],
		["FAT DARTS", g.buffs["big"], Color(0.35, 0.7, 0.42), true],
		["SLOW MO", g.buffs["slow"], Color(0.29, 0.56, 0.84), true],
		["SHIELD", g.buffs["shield"], Color(0.79, 0.66, 0.93), false]
	]
	for it in items:
		if it[1] > 0.0:
			var t = it[0]
			if it[3]:
				t += " %ds" % int(ceil(it[1]))
			draw_rect(Rect2(x0, y2 - 11.0 * k, 3.0 * k, 13.0 * k), it[2])
			_txt(t, x0 + 9.0 * k, y2, int(13 * k), it[2])
			y2 -= 20.0 * k


# the ammo counter, bottom right: the weapon name and its [Q] key chip, the gadget line, a big number with the clip size,
# and the row of dart pips (the next dart blinks while the gun loads)
func _draw_hud_ammo(k: float) -> void:
	var rx = size.x - HUD_MARGIN * k
	var by = size.y - HUD_BOTTOM * k
	var nb = by - 24.0 * k  # the baseline of the big number
	var small = int(13 * k)
	var reloading = g.combat_sys.is_reloading()
	var unlimited = g.buffs["rapid"] > 0.0
	var empty = g.shells <= 0 and not unlimited and g.free_shots <= 0

	# the dart pips, right aligned (dim while the melee weapon is in the hands)
	var pulse = g.combat_sys.reload_pulse()
	var pip_a = 0.4 if g.melee else 1.0
	for i in range(g.MAXSHELLS):
		var sx = rx - 7.0 * k - (g.MAXSHELLS - 1 - i) * 10.0 * k
		var lit = i < g.shells or unlimited
		var body_col = Color(1.0, 0.48, 0.1) if lit else Color(1.0, 1.0, 1.0, 0.16)
		var cap_col = Color(0.11, 0.39, 0.78) if lit else Color(1.0, 1.0, 1.0, 0.1)
		if reloading and i == g.shells:
			body_col = Color(1.0, 1.0, 1.0, 0.16).lerp(Color(1.0, 0.48, 0.1), pulse)
			cap_col = Color(1.0, 1.0, 1.0, 0.1).lerp(Color(0.11, 0.39, 0.78), pulse)
		body_col.a *= pip_a
		cap_col.a *= pip_a
		draw_rect(Rect2(sx, by - 11.0 * k, 7.0 * k, 11.0 * k), body_col)
		draw_rect(Rect2(sx, by - 15.0 * k, 7.0 * k, 5.0 * k), cap_col)

	if g.melee:
		# the melee weapon in the hands: its name big, the gun it switches back to above it
		_txt(WeaponSlots.melee_label(g.melee_weapon), rx, nb, int(30 * k), PINK, 2)
		var gun = WeaponSlots.label(g.primary)
		_key_chip("Q", rx - _text_w(gun, small) - 8.0 * k, nb - 40.0 * k, small, k)
		_txt(gun, rx, nb - 40.0 * k, small, GRAY, 2)
	else:
		var num = "INF" if unlimited else str(g.shells)
		var ncol = TEXT
		if reloading:
			ncol = RELOAD_CYAN
		elif empty:
			ncol = RED
		elif g.shells * 3 <= g.MAXSHELLS:
			ncol = ACCENT
		var nfs = int(52 * k)
		var sub_w = 0.0
		if not unlimited:
			var sub = "/ %d" % g.MAXSHELLS
			_txt(sub, rx, nb, int(20 * k), GRAY, 2)
			sub_w = _text_w(sub, int(20 * k)) + 8.0 * k
		_txt(num, rx - sub_w, nb, nfs, ncol, 2)
		if reloading:
			_txt(
				"RELOAD", rx - sub_w - _text_w(num, nfs) - 14.0 * k, nb, int(14 * k), RELOAD_CYAN, 2
			)
		var wname = WeaponSlots.label(g.primary)
		_txt(wname, rx, nb - 62.0 * k, small, TEXT, 2)
		if g.has_melee():
			_key_chip("Q", rx - _text_w(wname, small) - 8.0 * k, nb - 62.0 * k, small, k)

	# the gadget slot (empty slot: nothing is drawn): its name, the uses left and the key, or the cooldown
	var gtxt = g.gadget_sys.hud_text()
	if gtxt != "":
		_txt(gtxt, rx, nb - 84.0 * k, small, TEXT if g.gadget_sys.ready() else GRAY, 2)

	# the small status line in the corner
	var snd = (
		"[M] MAP   SOUND %s   VOICES %s"
		% ["OFF" if g.sfx.muted else "ON", "OFF" if not g.sfx.voices_on else "ON"]
	)
	_txt(snd, rx, size.y - 6.0 * k, int(11 * k), GRAY, 2)


# dash cooldown and style rank, bottom centre (and the FREE DARTS line above them)
func _draw_hud_centre(k: float) -> void:
	var mx = size.x * 0.5
	var dw = 130.0 * k
	var ready = g.dash_cd <= 0.0
	var fs = int(12 * k)
	var base = size.y - 62.0 * k
	if ready:
		var lw = _text_w("DASH", fs)
		var chip_w = _text_w("V", fs) + 10.0 * k
		var total = lw + 6.0 * k + chip_w
		_txt("DASH", mx - total * 0.5, base, fs, ACCENT)
		_key_chip("V", mx + total * 0.5, base, fs, k)
	else:
		_txt("DASH", mx, base, fs, GRAY, 1)
	var df = 1.0 if ready else clampf(1.0 - g.dash_cd / 0.9, 0.0, 1.0)
	draw_rect(Rect2(mx - dw * 0.5, size.y - 54.0 * k, dw, 6.0 * k), HUD_EMPTY)
	draw_rect(
		Rect2(mx - dw * 0.5, size.y - 54.0 * k, dw * df, 6.0 * k),
		Color(1.0, 0.82, 0.25) if ready else Color(0.78, 0.66, 0.32)
	)

	# style: the letter in a badge, the bar to the next rank and the score multiplier
	var rank = g.shop_sys.style_rank()
	var rcols = [GRAY, TEXT, Color(0.35, 0.7, 0.42), GOLD, ACCENT]
	var badge = Rect2(mx - 65.0 * k, size.y - 44.0 * k, 30.0 * k, 30.0 * k)
	_hud_panel(badge)
	draw_rect(Rect2(badge.position.x, badge.end.y - 3.0 * k, badge.size.x, 3.0 * k), rcols[rank])
	_txt(
		g.shop_sys.style_letter(),
		badge.position.x + badge.size.x * 0.5,
		badge.position.y + 24.0 * k,
		int(24 * k),
		rcols[rank],
		1
	)
	var bx = badge.end.x + 8.0 * k
	var bw = 92.0 * k
	_txt("STYLE", bx, size.y - 30.0 * k, int(11 * k), GRAY)
	if rank > 0:
		_txt(
			"x%.2f" % g.shop_sys.style_mul(),
			bx + bw,
			size.y - 30.0 * k,
			int(11 * k),
			rcols[rank],
			2
		)
	var sf = 1.0 if rank >= 4 else clampf(fmod(g.style, 20.0) / 20.0, 0.0, 1.0)
	draw_rect(Rect2(bx, size.y - 24.0 * k, bw, 5.0 * k), HUD_EMPTY)
	draw_rect(Rect2(bx, size.y - 24.0 * k, bw * sf, 5.0 * k), rcols[rank])
	if g.free_shots > 0:
		_txt("FREE DARTS %d" % g.free_shots, mx, size.y - 84.0 * k, int(13 * k), GOLD, 1)


func _draw_boss_ui(k: float) -> void:
	var cx = size.x * 0.5
	if g.bosses.size() > 0:
		var b = g.bosses[0]
		var mode = b["mode"]
		if mode != "dying":
			var bw = 340.0 * k
			var bx = cx - bw * 0.5
			var by = 82.0 * k
			var title = b["name"]
			if b["kind"] != "runner":
				title += "   PHASE %d" % b["phase"]
			if b.get("final", false):
				title = "FINAL BOSS   " + title
			_txt(title, cx, by - 4.0 * k, int(16 * k), TEXT, 1)
			draw_rect(
				Rect2(bx - 3.0, by + 6.0 * k, bw + 6.0, 16.0 * k), Color(0.05, 0.05, 0.055, 0.8)
			)
			draw_rect(Rect2(bx, by + 9.0 * k, bw, 10.0 * k), Color(0.23, 0.1, 0.09))
			draw_rect(
				Rect2(
					bx, by + 9.0 * k, bw * maxf(0.0, float(b["hp"])) / float(b["max_hp"]), 10.0 * k
				),
				RED
			)
			if b["kind"] != "runner":
				# stagger meter: fill it (weak spots, rubber, deflects) and the boss gets dizzy
				draw_rect(Rect2(bx, by + 24.0 * k, bw, 6.0 * k), Color(0.2, 0.17, 0.08))
				var sf = 1.0 if mode == "stagger" else clampf(b["stagger"] / 100.0, 0.0, 1.0)
				draw_rect(
					Rect2(bx, by + 24.0 * k, bw * sf, 6.0 * k),
					(
						Color(1.0, 0.82, 0.25)
						if mode != "stagger" or int(g.time * 10.0) % 2 == 0
						else Color(1, 1, 1)
					)
				)
				_txt("STAGGER", bx + bw + 8.0 * k, by + 31.0 * k, int(10 * k), GRAY)
			if b["intro"] > 0.0:
				_txt(
					"FINAL BOSS" if b.get("final", false) else "BOSS FIGHT",
					cx,
					size.y * 0.27,
					int(30 * k),
					RED,
					1
				)
				_txt(b["name"], cx, size.y * 0.33, int(36 * k), TEXT, 1)
			if mode == "tele" or mode == "lunge":
				var pulse = 0.12 + 0.12 * absf(sin(g.time * 12.0))
				draw_rect(Rect2(0, 0, 16.0 * k, size.y), Color(1.0, 0.16, 0.12, pulse))
				draw_rect(
					Rect2(size.x - 16.0 * k, 0, 16.0 * k, size.y), Color(1.0, 0.16, 0.12, pulse)
				)
				if int(g.time * 8.0) % 2 == 0:
					var warn = "GET OFF THE RED LANE!  DASH [V]"
					if mode == "tele" and b["pat"] == "slam":
						warn = "GET OUT OF THE CIRCLE!  OR DASH THROUGH [V]"
					elif mode == "tele" and b["pat"] == "volley":
						warn = "PHONES INCOMING!  DODGE OR DEFLECT"
					elif b["combo"] > 0:
						warn = "COMBO!  KEEP MOVING  [V]"
					_txt(warn, cx, size.y * 0.45, int(22 * k), ACCENT, 1)
			elif mode == "stagger":
				var gp = 0.10 + 0.08 * absf(sin(g.time * 8.0))
				draw_rect(Rect2(0, 0, 16.0 * k, size.y), Color(1.0, 0.82, 0.25, gp))
				draw_rect(Rect2(size.x - 16.0 * k, 0, 16.0 * k, size.y), Color(1.0, 0.82, 0.25, gp))
				_txt("DIZZY - HIT IT!  (WEAK SPOT OPEN)", cx, size.y * 0.45, int(22 * k), GOLD, 1)
			# weak spot marker
			if not g.cam.is_position_behind(g.boss_world(b, g.boss_sys.weak_point_y(b))):
				var wp = g.boss_world(b, g.boss_sys.weak_point_y(b))
				var sp = g.cam.unproject_position(wp)
				var dist = maxf(1.0, g.cam.global_position.distance_to(wp))
				var rr = clampf(120.0 * k / dist * (78.0 / g.cam.fov), 7.0 * k, 26.0 * k)
				var pul = 0.6 + 0.4 * sin(g.time * 9.0)
				if g.boss_sys.weak_open(b):
					draw_arc(
						sp,
						rr * (1.0 + 0.15 * pul),
						0.0,
						TAU,
						24,
						Color(1.0, 0.42, 0.17, 0.9),
						2.0 * k
					)
					draw_circle(sp, 2.0 * k, Color(1.0, 0.42, 0.17, 0.9))
				else:  # armoured: a crossed-out grey ring
					draw_arc(sp, rr, 0.0, TAU, 24, Color(0.62, 0.65, 0.7, 0.55), 1.5 * k)
					draw_line(
						sp + Vector2(-rr, -rr) * 0.6,
						sp + Vector2(rr, rr) * 0.6,
						Color(0.62, 0.65, 0.7, 0.55),
						1.5 * k
					)
					draw_line(
						sp + Vector2(-rr, rr) * 0.6,
						sp + Vector2(rr, -rr) * 0.6,
						Color(0.62, 0.65, 0.7, 0.55),
						1.5 * k
					)
	for ph in g.phones:
		if not ph["ret"] and ph["p"] < 0.85 and int(g.time * 8.0) % 2 == 0:
			_txt(
				(
					"INCOMING CALL!  DASH, OR SWING YOUR MELEE AT THE LAST MOMENT"
					if g.has_melee()
					else "INCOMING CALL!  DASH OUT OF THE WAY"
				),
				cx,
				size.y * 0.2,
				int(20 * k),
				ACCENT,
				1
			)
			break


# ---- 360 degree awareness: arrows at the screen edge for anything off screen, and a small radar ----
const THREAT_COL = {
	"rider": Color(1.0, 0.27, 0.2), "boss": Color(1.0, 0.1, 0.12), "phone": Color(1.0, 0.82, 0.15)
}
# the edge arrows: a chevron with a soft glow and a dark outline so it reads on any background; red is danger
const ARROW_SIZE = 17.0  # pixels at 1080p for the weakest arrow
const ARROW_GROW = 17.0  # extra pixels for the strongest
const ARROW_BOSS_SCALE = 1.25  # a boss is the biggest thing that can hit you
const ARROW_MIN_ALPHA = 0.8


# angle of a world point relative to where the camera looks: 0 ahead, + to the right, +-PI behind
func _rel_angle(world_pos: Vector3) -> float:
	var lp = g.cam.global_transform.affine_inverse() * world_pos
	return atan2(lp.x, -lp.z)


func _draw_threats(k: float) -> void:
	arrows = []
	var list = g.threat_list()
	if list.size() == 0:
		return
	# strongest first; on open ground that also weighs distance and approach (threats.gd)
	list = Threats.ranked(list, g.arena.rider_pursuit())
	var c = size * 0.5
	var rx = size.x * 0.5 - 46.0 * k
	var ry = size.y * 0.5 - 96.0 * k
	var half_h = atan(tan(deg_to_rad(g.cam.fov * 0.5)) * size.x / size.y)  # horizontal half field of view
	var drawn = 0
	for t in list:
		var rel = _rel_angle(t["pos"])
		if absf(rel) < half_h * 0.9:
			continue  # on screen: you can see it
		if drawn >= Threats.MAX_ARROWS:
			break
		drawn += 1
		arrows.append({"kind": t["kind"], "dist": t["dist"], "strength": t["strength"]})
		var urg: float = t["strength"]
		var pos = c + Vector2(sin(rel) * rx, -cos(rel) * ry * 0.85)
		var out = (pos - c).normalized()
		var side = Vector2(-out.y, out.x)
		var sz = (ARROW_SIZE + ARROW_GROW * urg) * k
		if t["kind"] == "boss":
			sz *= ARROW_BOSS_SCALE
		var col: Color = THREAT_COL[t["kind"]]
		col.a = lerpf(ARROW_MIN_ALPHA, 1.0, urg)
		# it beats faster the closer and more pressing the threat is; something about to hit you flashes hard
		var beat = 0.5 + 0.5 * sin(g.time * (5.0 + 9.0 * urg))
		var pulse = 1.0 + 0.12 * urg * beat
		if t["urg"] >= 0.9:
			col.a *= 0.6 + 0.4 * (0.5 + 0.5 * sin(g.time * 20.0))
			pulse = 1.0 + 0.2 * beat
		sz *= pulse
		_draw_arrow_shape(pos, out, side, sz, col, k)


# one chevron pointing along out: soft glow, dark outline, the colour, and a light stripe down its middle
func _draw_arrow_shape(
	pos: Vector2, out: Vector2, side: Vector2, sz: float, col: Color, k: float
) -> void:
	var glow = col
	glow.a = col.a * 0.22
	_chevron(pos, out, side, sz * 1.7, glow)
	var shadow = Color(0, 0, 0, 0.75 * col.a)
	_chevron(pos, out, side, sz + 3.5 * k, shadow)
	_chevron(pos, out, side, sz, col)
	var light = Color(1, 1, 1, 0.55 * col.a)
	draw_line(pos - out * sz * 0.35, pos + out * sz * 0.8, light, maxf(1.5 * k, sz * 0.09))


# a notched arrow head centred on pos, drawn as two triangles (a concave polygon can fail to triangulate)
func _chevron(pos: Vector2, out: Vector2, side: Vector2, sz: float, col: Color) -> void:
	var tip = pos + out * sz
	var left = pos - out * sz * 0.55 + side * sz * 0.95
	var right = pos - out * sz * 0.55 - side * sz * 0.95
	var notch = pos - out * sz * 0.15
	draw_colored_polygon(PackedVector2Array([tip, left, notch]), col)
	draw_colored_polygon(PackedVector2Array([tip, notch, right]), col)


# Remembers one frame time and, every FPS_REFRESH seconds, turns the frames counted since into the numbers shown.
func _record_frame(d: float) -> void:
	if _frame_ring.size() != FRAME_SAMPLES:
		_frame_ring.resize(FRAME_SAMPLES)
		_frame_ring.fill(0.0)
	_frame_ring[_frame_i] = d
	_frame_i = (_frame_i + 1) % FRAME_SAMPLES
	_fps_t += d
	_fps_n += 1
	if _fps_t >= FPS_REFRESH:
		_fps_shown = int(round(_fps_n / _fps_t))
		_ms_shown = 1000.0 * _fps_t / _fps_n
		_fps_t = 0.0
		_fps_n = 0


# colour of an FPS value: 0 to 30 red, 30 to 60 yellow, 60 and above green
func fps_color(fps: float) -> Color:
	if fps < 30.0:
		return RED
	return GOLD if fps < 60.0 else FPS_GREEN


# colour of a frame time in milliseconds, the same thresholds (30 FPS is 33.3 ms, 60 FPS is 16.7 ms)
func frame_color(ms: float) -> Color:
	if ms > 1000.0 / 30.0:
		return RED
	return GOLD if ms > 1000.0 / 60.0 else FPS_GREEN


# "62 FPS" in the colour of its range, the average frametime in grey beside it, and a strip of the last second of
# frames (one bar each, taller is slower, coloured like the FPS) with a line at 60 FPS, in the free band between the
# top bar and the radar. A spike that the average hides shows up in the strip.
func _draw_fps(k: float) -> void:
	if _fps_shown <= 0:
		return
	var base = 26.0 * k  # the baseline of the texts and the foot of the strip, above the radar
	_txt("%d FPS" % _fps_shown, 14.0 * k, base, int(12 * k), fps_color(_fps_shown))
	_txt("%.1f MS" % _ms_shown, 64.0 * k, base, int(10 * k), GRAY)
	var h = 12.0 * k
	var bw = 1.4 * k
	var x0 = 112.0 * k
	var full_ms = 50.0  # a bar this slow or slower fills the strip
	draw_rect(
		Rect2(x0 - 2.0 * k, base - h - 1.0 * k, bw * FRAME_SAMPLES + 4.0 * k, h + 2.0 * k),
		Color(0.03, 0.05, 0.08, 0.45)
	)
	for i in range(FRAME_SAMPLES):
		var ms = 1000.0 * _frame_ring[(_frame_i + i) % FRAME_SAMPLES]  # oldest first
		if ms <= 0.0:
			continue
		var bh = clampf(ms / full_ms, 0.05, 1.0) * h
		draw_rect(Rect2(x0 + bw * i, base - bh, bw * 0.8, bh), frame_color(ms))
	var ly = base - h * (1000.0 / 60.0) / full_ms
	draw_line(
		Vector2(x0 - 2.0 * k, ly),
		Vector2(x0 + bw * FRAME_SAMPLES + 2.0 * k, ly),
		Color(1, 1, 1, 0.3),
		1.0
	)


func _draw_radar(k: float) -> void:
	var R = 52.0 * k
	var c = Vector2(HUD_MARGIN * k + R, 34.0 * k + R)  # top left corner, under the FPS counter
	draw_circle(c, R, Color(0.03, 0.05, 0.08, 0.45))
	draw_arc(c, R, 0.0, TAU, 40, Color(1, 1, 1, 0.35), 1.5 * k)
	draw_arc(c, R * 0.5, 0.0, TAU, 28, Color(1, 1, 1, 0.12), 1.0 * k)
	var half_h = atan(tan(deg_to_rad(g.cam.fov * 0.5)) * size.x / size.y)
	for sgn in [-1.0, 1.0]:
		draw_line(
			c, c + Vector2(sin(sgn * half_h), -cos(sgn * half_h)) * R, Color(1, 1, 1, 0.22), 1.0 * k
		)
	var open_ground = g.arena.rider_pursuit()
	for t in g.threat_list():
		var rel = _rel_angle(t["pos"])
		var rr = Threats.radar_fraction(t["dist"], open_ground) * (R - 4.0 * k)
		var dot = c + Vector2(sin(rel), -cos(rel)) * rr
		var col: Color = THREAT_COL[t["kind"]]
		var weight: float = Threats.strength(t, open_ground)  # the roundabout: the urgency, as before
		if open_ground:
			col.a = 0.5 + 0.5 * weight
		draw_circle(dot, (2.4 + 1.8 * weight) * k, col)
	_draw_radar_objectives(c, R, k)
	draw_circle(c, 2.5 * k, Color(1, 1, 1, 0.9))


# the extraction point (a square, green once it is open) and the caches in range (gold diamonds) on the radar
func _draw_radar_objectives(c: Vector2, R: float, k: float) -> void:
	var o = g.objective_sys
	if not o.enabled() or not o.has_goal():
		return
	for cache in o.caches:
		if cache["taken"] or o.dist_to(cache["pos"]) > o.SENSE_RANGE:
			continue
		var rel_c = _rel_angle(cache["pos"])
		var rr_c = Threats.radar_fraction(o.dist_to(cache["pos"]), true) * (R - 4.0 * k)
		_diamond(c + Vector2(sin(rel_c), -cos(rel_c)) * rr_c, 3.6 * k, OBJ_GOLD)
	var gp: Vector3 = o.goal["pos"]
	var rel = _rel_angle(gp)
	var rr = Threats.radar_fraction(o.dist_to(gp), true) * (R - 4.0 * k)
	var col = OBJ_GREEN if o.extracting else Color(OBJ_LOCKED, 0.55)
	var at = c + Vector2(sin(rel), -cos(rel)) * rr
	draw_rect(Rect2(at - Vector2(3.6, 3.6) * k, Vector2(7.2, 7.2) * k), col)


func _diamond(at: Vector2, r: float, col: Color) -> void:
	var pts = PackedVector2Array(
		[at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)]
	)
	draw_colored_polygon(pts, col)
	draw_polyline(
		PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, 0.7), 1.0
	)


# ---------------------------------------------------------------- objectives (objective.gd)
# A marker for something in the world: a diamond with a distance over it when it is on screen, a pointing
# arrow on the edge of the screen when it is off to the side or behind you.
func _world_marker(p: Vector3, col: Color, label: String, k: float, big: bool) -> void:
	var c = size * 0.5
	var r = (11.0 if big else 7.0) * k
	if not g.cam.is_position_behind(p):
		var sp = g.cam.unproject_position(p)
		if Rect2(Vector2(40, 90) * k, size - Vector2(80, 170) * k).has_point(sp):
			_diamond(sp, r, col)
			if label != "":
				_txt(label, sp.x, sp.y - r - 6.0 * k, int(15 * k), col, 1)
			return
	var rel = _rel_angle(p)
	var rx = size.x * 0.5 - 70.0 * k
	var ry = size.y * 0.5 - 130.0 * k
	var pos = c + Vector2(sin(rel) * rx, -cos(rel) * ry * 0.85)
	var out = (pos - c).normalized()
	var side = Vector2(-out.y, out.x)
	var tip = pos + out * r * 1.6
	var pts = PackedVector2Array(
		[tip, pos - out * r * 0.6 + side * r, pos - out * r * 0.6 - side * r]
	)
	draw_colored_polygon(pts, col)
	draw_polyline(
		PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0, 0, 0, 0.75), 1.5 * k
	)
	if label != "":
		_txt(label, pos.x - out.x * r * 2.6, pos.y - out.y * r * 2.6 + 5.0 * k, int(14 * k), col, 1)


func _draw_objective(k: float) -> void:
	var o = g.objective_sys
	if not o.enabled() or not o.has_goal():
		return
	var cx = size.x * 0.5
	var gp: Vector3 = o.goal["pos"]
	var d = int(round(o.dist_to(gp)))
	var y = size.y * 0.115
	if o.extracting:
		var pulse = 0.75 + 0.25 * sin(g.time * 6.0)
		_txt(
			"REACH THE EXTRACTION POINT   %d M" % d, cx, y, int(22 * k), Color(OBJ_GREEN, pulse), 1
		)
	else:
		_txt(
			"EXTRACTION POINT   %d M   (DOWN EVERY RIDER TO OPEN IT)" % d,
			cx,
			y,
			int(14 * k),
			GRAY,
			1
		)
	if o.caches.size() > 0:
		_txt(
			"CACHES %d / %d" % [o.taken, o.caches.size()],
			cx,
			y + 22.0 * k,
			int(14 * k),
			OBJ_GOLD,
			1
		)
	_world_marker(
		gp + Vector3(0, 3.5, 0),
		OBJ_GREEN if o.extracting else Color(OBJ_LOCKED, 0.6),
		"%d m" % d,
		k,
		o.extracting
	)
	for cache in o.caches:
		if not cache["taken"] and o.dist_to(cache["pos"]) <= o.SENSE_RANGE:
			_world_marker(cache["pos"] + Vector3(0, 2.4, 0), OBJ_GOLD, "", k, false)


func _draw_crosshair(k: float) -> void:
	var c = size * 0.5
	if g.melee:
		draw_circle(c, 3.0 * k, Color(1.0, 0.48, 0.72, 0.9))
		return
	var half_fov = deg_to_rad(g.cam.fov * 0.5)
	var gap = tan(deg_to_rad(g.spread_deg)) / tan(half_fov) * size.y * 0.5
	gap += g.player_sys.ex_bonus() * 20.0 * k
	gap = maxf(gap, 3.0 * k)
	# aiming down sights: the gun's own sights do the aiming, so the cross shrinks and fades to nearly a dot
	var ln = 9.0 * k * lerpf(1.0, 0.55, g.ads_t)
	var col = Color(1, 1, 1, lerpf(0.92, 0.55, g.ads_t))
	if g.buffs["big"] > 0.0:
		col = Color(0.55, 0.95, 0.6, col.a + 0.03)
	# out of darts: red; loading shells (the gun cannot fire until it is done, or a dash or melee stops it): a little dimmer
	var empty = g.shells <= 0 and g.buffs["rapid"] <= 0.0 and g.free_shots <= 0
	if empty:
		col = Color(1.0, 0.36, 0.3, 0.95)
	elif g.loading:
		col.a *= 0.7
	var shadow = Color(0, 0, 0, 0.6)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_line(c + d * gap, c + d * (gap + ln), shadow, 4.0 * k)
		draw_line(c + d * gap, c + d * (gap + ln), col, 2.0 * k)
	draw_circle(c, 2.2 * k, shadow)
	draw_circle(c, 1.4 * k, col)
