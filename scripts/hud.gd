extends Control
# 2D overlay: HUD, crosshair, floating popups, boss bars, upgrade cards and the title / round screens.
# It only reads state from the main script (g), it never changes it.

var g = null
var font: Font

const GOLD = Color(0.95, 0.71, 0.19)
const RED = Color(0.9, 0.33, 0.24)
const GRAY = Color(0.49, 0.48, 0.44)
const TEXT = Color(0.96, 0.95, 0.92)
const ACCENT = Color(1.0, 0.42, 0.17)
const PINK = Color(1.0, 0.48, 0.72)
const LANE_Z_H = [-5.5, -2.5, 0.5]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = get_theme_default_font()

func _process(_d: float) -> void:
	queue_redraw()

# ---------------------------------------------------------------- helpers
# draw_string() re-shapes the text every call, and we draw every string twice (outline + fill) every frame.
# A TextLine keeps the shaped text, so each distinct string is shaped once and just re-drawn afterwards.
var _lines := {}

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
	var pos = Vector2(px, y - tl.get_line_ascent())          # TextLine draws from the top, draw_string from the baseline
	var rid = get_canvas_item()
	tl.draw_outline(rid, pos, int(fs * 0.14) + 1, Color(0.04, 0.04, 0.06, 0.9))
	tl.draw(rid, pos, col)

func _heart(cx: float, cy: float, sz: float, col: Color) -> void:
	draw_circle(Vector2(cx - sz * 0.25, cy - sz * 0.15), sz * 0.29, col)
	draw_circle(Vector2(cx + sz * 0.25, cy - sz * 0.15), sz * 0.29, col)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - sz * 0.52, cy - sz * 0.02),
		Vector2(cx + sz * 0.52, cy - sz * 0.02),
		Vector2(cx, cy + sz * 0.5)]), col)

func _bike_icon(cx: float, cy: float, k: float, col: Color) -> void:
	var w = 2.0 * k
	draw_arc(Vector2(cx - 8.0 * k, cy + 3.0 * k), 5.0 * k, 0.0, TAU, 14, col, w)
	draw_arc(Vector2(cx + 8.0 * k, cy + 3.0 * k), 5.0 * k, 0.0, TAU, 14, col, w)
	draw_polyline(PackedVector2Array([
		Vector2(cx - 8.0 * k, cy + 3.0 * k), Vector2(cx - 2.0 * k, cy - 5.0 * k),
		Vector2(cx + 6.0 * k, cy - 5.0 * k), Vector2(cx + 8.0 * k, cy + 3.0 * k)]), col, w)

func _dim(a: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.04, 0.05, a))

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
	var n = g.offers.size() if g.state == "upgrade" else g.shop_items.size()
	for i in range(n):
		if card_rect(i, n).has_point(pos):
			return i
	return -1

func _draw_upgrade(k: float) -> void:
	_dim(0.78)
	var cx = size.x * 0.5
	_txt("CHOOSE AN UPGRADE", cx, size.y * 0.13, int(40 * k), GOLD, 1)
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
		for ln2 in _wrap(u["desc"], r.size.x - 36.0 * k, int(15 * k)):
			_txt(ln2, r.position.x + r.size.x * 0.5, dy, int(15 * k), Color(0.79, 0.81, 0.83), 1)
			dy += 24.0 * k
		_txt(g.shop_sys.upgrade_stat(u["id"]), r.position.x + r.size.x * 0.5, r.position.y + r.size.y - 30.0 * k, int(14 * k), ACCENT, 1)
	if int(g.time * 2.0) % 2 == 0:
		_txt("CLICK A CARD OR PRESS 1 2 3", cx, size.y * 0.8, int(20 * k), TEXT, 1)

# ---------------------------------------------------------------- shop
func continue_rect() -> Rect2:
	var k = size.y / 720.0
	return Rect2(size.x * 0.5 - 150.0 * k, size.y * 0.8, 300.0 * k, 48.0 * k)

func reroll_rect() -> Rect2:
	var k = size.y / 720.0
	return Rect2(size.x * 0.5 + 170.0 * k, size.y * 0.8, 250.0 * k, 48.0 * k)

func _draw_shop(k: float) -> void:
	_dim(0.84)
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
			_txt(it["label"], r.position.x + r.size.x - 18.0 * k, r.position.y + 34.0 * k, int(14 * k), PINK if it["perk"] else Color(0.55, 0.78, 0.95), 2)
		var ly = r.position.y + 92.0 * k
		for ln in _wrap(it["name"], r.size.x - 30.0 * k, int(22 * k)):
			_txt(ln, r.position.x + r.size.x * 0.5, ly, int(22 * k), TEXT, 1)
			ly += 28.0 * k
		var dy = r.position.y + 150.0 * k
		for ln2 in _wrap(it["desc"], r.size.x - 36.0 * k, int(15 * k)):
			_txt(ln2, r.position.x + r.size.x * 0.5, dy, int(15 * k), Color(0.79, 0.81, 0.83), 1)
			dy += 22.0 * k
		var ty = r.position.y + 205.0 * k
		for ln3 in _wrap(it["tag"], r.size.x - 36.0 * k, int(13 * k)):
			_txt(ln3, r.position.x + r.size.x * 0.5, ty, int(13 * k), PINK, 1)
			ty += 19.0 * k
		if it["sold"]:
			_txt("SOLD", r.position.x + r.size.x * 0.5, r.position.y + r.size.y - 26.0 * k, int(24 * k), GRAY, 1)
		else:
			_txt("$%d" % it["cost"], r.position.x + r.size.x * 0.5, r.position.y + r.size.y - 26.0 * k, int(26 * k), GOLD if afford else RED, 1)
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
	_txt("REROLL  [R]  $%d" % rc, rr.position.x + rr.size.x * 0.5, rr.position.y + 32.0 * k, int(20 * k), GOLD if rok else RED, 1)
	_txt("CLICK OR PRESS 1-4 TO BUY", cx, size.y * 0.93, int(14 * k), GRAY, 1)

# ---------------------------------------------------------------- run summary (game over)
func _draw_run_summary(k: float, cx: float, blink: bool) -> void:
	_txt("RUN OVER", cx, size.y * 0.15, int(66 * k), RED, 1)
	if g.OVER_MSG.has(g.over_reason):
		_txt(g.OVER_MSG[g.over_reason], cx, size.y * 0.22, int(20 * k), RED, 1)
	var acc = 0
	if g.shots_fired > 0:
		acc = int(round(100.0 * g.shots_hit / g.shots_fired))
	var rcols = [GRAY, TEXT, Color(0.35, 0.7, 0.42), GOLD, ACCENT]
	var letters = ["D", "C", "B", "A", "S"]
	var lx = cx - 190.0 * k
	var rx = cx + 190.0 * k
	var y0 = size.y * 0.29
	var step = 32.0 * k
	var rows = [
		["SCORE", str(g.score).pad_zeros(6), TEXT],
		["KILLS", str(g.kills), TEXT],
		["ACCURACY", "%d%%" % acc, TEXT],
		["BEST STYLE RANK", letters[g.best_rank], rcols[g.best_rank]],
		["ROUND REACHED", str(g.round_n), TEXT],
		["BEST COMBO", "x%d" % g.best_combo, TEXT]
	]
	for i in range(rows.size()):
		var y = y0 + i * step
		draw_rect(Rect2(lx, y + 8.0 * k, rx - lx, 1.0 * k), Color(1, 1, 1, 0.1))
		_txt(rows[i][0], lx, y, int(20 * k), GRAY)
		_txt(rows[i][1], rx, y, int(24 * k), rows[i][2], 2)
	var uy = y0 + rows.size() * step + 14.0 * k
	if g.score > 0 and g.score >= g.hi:
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
				var tw = _line(g.name_buf, int(22 * k), -1.0, HORIZONTAL_ALIGNMENT_LEFT).get_line_width()
				draw_rect(Rect2(cx + tw * 0.5 + 4.0 * k, uy + 14.0 * k, 3.0 * k, 24.0 * k), TEXT)
		else:
			_txt("SAVED AS  " + g.player_name, cx, uy + 30.0 * k, int(20 * k), TEXT, 1)
		uy += 72.0 * k
	_txt("NEWLY UNLOCKED", cx, uy, int(16 * k), GRAY, 1)
	if g.new_unlocks.is_empty():
		_txt("NOTHING THIS RUN", cx, uy + 26.0 * k, int(18 * k), GRAY, 1)
	else:
		for i in range(g.new_unlocks.size()):
			_txt(str(g.new_unlocks[i]).to_upper(), cx, uy + 26.0 * k + i * 24.0 * k, int(18 * k), GOLD, 1)
	if g.state_t > 0.8 and blink and not g.name_entry:
		_txt("CLICK TO CONTINUE", cx, size.y * 0.93, int(24 * k), TEXT, 1)

# ---------------------------------------------------------------- title screen menu
const TITLE_ITEMS = [
	{"id": "play", "label": "PLAY"},
	{"id": "loadout", "label": "LOADOUT", "soon": true},
	{"id": "unlocks", "label": "UNLOCKS", "soon": true},
	{"id": "scores", "label": "HIGH SCORES"},
	{"id": "settings", "label": "SETTINGS"},
	{"id": "quit", "label": "QUIT"}
]
const TITLE_PAGES = {
	"loadout": ["LOADOUT", "PICK YOUR STARTING WEAPON AND PERK BEFORE A RUN."],
	"unlocks": ["UNLOCKS", "SPEND WHAT YOU EARN ON PERMANENT UNLOCKS BETWEEN RUNS."]
}

func title_rect(i: int) -> Rect2:
	var k = size.y / 720.0
	var w = 320.0 * k
	var h = 46.0 * k
	return Rect2((size.x - w) * 0.5, size.y * 0.38 + i * (h + 10.0 * k), w, h)

func title_at(pos: Vector2) -> int:
	if g == null or g.state != "title" or g.title_page != "":
		return -1
	for i in range(TITLE_ITEMS.size()):
		if title_rect(i).has_point(pos):
			return i
	return -1

func _draw_title_menu(k: float, cx: float) -> void:
	_txt("FSTRELI", cx, size.y * 0.17, int(76 * k), ACCENT, 1)
	_txt("BICIKLINA 3D", cx, size.y * 0.28, int(76 * k), ACCENT, 1)
	var hov = title_at(get_viewport().get_mouse_position())
	for i in range(TITLE_ITEMS.size()):
		var item = TITLE_ITEMS[i]
		var r = title_rect(i)
		var on = hov == i or (hov < 0 and g.title_sel == i)
		draw_rect(r, Color(0.176, 0.196, 0.22) if on else Color(0.13, 0.14, 0.16))
		draw_rect(r, ACCENT if on else Color(0.29, 0.31, 0.33), false, 3.0 * k)
		var base = r.position.y + 31.0 * k
		_txt(item["label"], r.position.x + r.size.x * 0.5, base, int(22 * k), TEXT if on else GRAY, 1)
		if item.get("soon", false):
			_txt("SOON", r.position.x + r.size.x - 12.0 * k, base - 2.0 * k, int(12 * k), GRAY, 2)
	if g.hi > 0:
		_txt("HIGH SCORE " + str(g.hi).pad_zeros(6), cx, size.y * 0.885, int(20 * k), GOLD, 1)
	_txt("WASD MOVE   SHIFT RUN   SPACE DASH   MOUSE AIM   CLICK SHOOT   R RELOAD   Q MELEE", cx, size.y * 0.93, int(14 * k), GRAY, 1)
	_txt("GAMEPAD: STICKS MOVE + AIM   RT SHOOT   LT AIM   A DASH   X RELOAD   Y SWITCH   START PAUSE", cx, size.y * 0.965, int(14 * k), GRAY, 1)

func _draw_scores_page(k: float, cx: float) -> void:
	_txt("HIGH SCORES", cx, size.y * 0.14, int(56 * k), GOLD, 1)
	var y0 = size.y * 0.27
	var c_rank = cx - 300.0 * k
	var c_name = cx - 262.0 * k
	var c_score = cx + 20.0 * k
	var c_round = cx + 110.0 * k
	var c_kills = cx + 195.0 * k
	var c_date = cx + 300.0 * k
	_txt("#", c_rank, y0, int(14 * k), GRAY)
	_txt("NAME", c_name, y0, int(14 * k), GRAY)
	_txt("SCORE", c_score, y0, int(14 * k), GRAY, 2)
	_txt("ROUND", c_round, y0, int(14 * k), GRAY, 2)
	_txt("KILLS", c_kills, y0, int(14 * k), GRAY, 2)
	_txt("DATE", c_date, y0, int(14 * k), GRAY, 2)
	var list = g.scores.entries
	if list.is_empty():
		_txt("NO SCORES YET - FINISH A RUN TO GET ON THE LIST", cx, size.y * 0.5, int(22 * k), GRAY, 1)
	for i in range(list.size()):
		var e = list[i]
		var y = y0 + (i + 1) * 34.0 * k
		var mine = i == g.last_rank
		if mine:
			draw_rect(Rect2(c_rank - 12.0 * k, y - 24.0 * k, (c_date - c_rank) + 24.0 * k, 32.0 * k), Color(0.95, 0.71, 0.19, 0.14))
		var col = GOLD if mine else TEXT
		_txt(str(i + 1), c_rank, y, int(20 * k), col)
		var nm = str(e.get("name", ""))
		_txt(nm if nm != "" else "-", c_name, y, int(20 * k), col)
		_txt(str(e["score"]).pad_zeros(6), c_score, y, int(22 * k), col, 2)
		_txt(str(e["round"]), c_round, y, int(20 * k), col, 2)
		_txt(str(e["kills"]), c_kills, y, int(20 * k), col, 2)
		_txt(str(e["date"]), c_date, y, int(16 * k), GRAY, 2)
	_txt("CLICK OR PRESS ESC TO GO BACK", cx, size.y * 0.94, int(18 * k), GRAY, 1)

# placeholder pages for the screens that are still on the roadmap
func _draw_title_page(k: float, cx: float) -> void:
	if g.title_page == "scores":
		_draw_scores_page(k, cx)
		return
	var info = TITLE_PAGES.get(g.title_page, ["", ""])
	_txt(info[0], cx, size.y * 0.24, int(60 * k), GOLD, 1)
	_txt(info[1], cx, size.y * 0.34, int(20 * k), TEXT, 1)
	_txt("COMING SOON", cx, size.y * 0.56, int(32 * k), ACCENT, 1)
	_txt("CLICK OR PRESS ESC TO GO BACK", cx, size.y * 0.78, int(18 * k), GRAY, 1)

# ---------------------------------------------------------------- pause menu
const PAUSE_ITEMS = [
	{"id": "resume", "label": "RESUME"},
	{"id": "settings", "label": "SETTINGS"},
	{"id": "restart", "label": "RESTART RUN"},
	{"id": "title", "label": "QUIT TO TITLE"}
]

func pause_rect(i: int) -> Rect2:
	var k = size.y / 720.0
	var w = 320.0 * k
	var h = 46.0 * k
	return Rect2((size.x - w) * 0.5, size.y * 0.36 + i * (h + 10.0 * k), w, h)

func pause_at(pos: Vector2) -> int:
	if g == null or not g.paused or g.pause_page != "":
		return -1
	for i in range(PAUSE_ITEMS.size()):
		if pause_rect(i).has_point(pos):
			return i
	return -1

func _draw_pause_menu(k: float, cx: float) -> void:
	_txt("PAUSED", cx, size.y * 0.26, int(60 * k), TEXT, 1)
	var hov = pause_at(get_viewport().get_mouse_position())
	for i in range(PAUSE_ITEMS.size()):
		var r = pause_rect(i)
		var on = hov == i or (hov < 0 and g.pause_sel == i)
		draw_rect(r, Color(0.176, 0.196, 0.22) if on else Color(0.13, 0.14, 0.16))
		draw_rect(r, ACCENT if on else Color(0.29, 0.31, 0.33), false, 3.0 * k)
		_txt(PAUSE_ITEMS[i]["label"], r.position.x + r.size.x * 0.5, r.position.y + 31.0 * k, int(22 * k), TEXT if on else GRAY, 1)
	_txt("ESC TO RESUME", cx, size.y * 0.80, int(16 * k), GRAY, 1)

# ---------------------------------------------------------------- settings panel (pause screen / title with TAB)
const SETTING_ROWS = [
	{"id": "fov", "label": "FIELD OF VIEW", "min": 60.0, "max": 105.0, "fmt": "%d"},
	{"id": "sens", "label": "MOUSE SENSITIVITY", "min": 0.3, "max": 3.0, "fmt": "%.1fx"},
	{"id": "assist", "label": "AIM ASSIST (STICK)", "min": 0.0, "max": 1.0, "fmt": "pct"},
	{"id": "vol", "label": "VOLUME", "min": 0.0, "max": 1.0, "fmt": "pct"},
	{"id": "tads", "label": "TOGGLE AIM (RMB / LT)", "toggle": true},
	{"id": "outline", "label": "OUTLINES", "toggle": true},
	{"id": "quality", "label": "GRAPHICS", "choices": ["HIGH", "MEDIUM", "LOW"]},
	{"id": "fullscreen", "label": "FULLSCREEN", "toggle": true},
	{"id": "sound", "label": "SOUND", "toggle": true},
	{"id": "voices", "label": "VOICES", "toggle": true}
]

func settings_visible() -> bool:
	return g != null and ((g.paused and g.pause_page == "settings") or (g.state == "title" and g.title_page == "settings"))

func panel_rect() -> Rect2:
	var k = size.y / 720.0
	var w = 560.0 * k
	var h = (44.0 + SETTING_ROWS.size() * 34.0 + 12.0) * k
	return Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h)

func row_rect(i: int) -> Rect2:
	var k = size.y / 720.0
	var pr = panel_rect()
	return Rect2(pr.position.x + 16.0 * k, pr.position.y + 44.0 * k + i * 34.0 * k, pr.size.x - 32.0 * k, 30.0 * k)

func track_rect(i: int) -> Rect2:
	var k = size.y / 720.0
	var r = row_rect(i)
	return Rect2(r.position.x + r.size.x * 0.46, r.position.y + 10.0 * k, r.size.x * 0.38, 10.0 * k)

func setting_at(pos: Vector2) -> String:
	if not settings_visible():
		return ""
	for i in range(SETTING_ROWS.size()):
		if row_rect(i).has_point(pos):
			return SETTING_ROWS[i]["id"]
	return ""

func is_toggle(id: String) -> bool:
	for row in SETTING_ROWS:
		if row["id"] == id:
			return row.get("toggle", false) or row.has("choices")
	return false

func apply_slider(id: String, pos: Vector2) -> void:
	for i in range(SETTING_ROWS.size()):
		var row = SETTING_ROWS[i]
		if row["id"] == id:
			var tr = track_rect(i)
			var t = clampf((pos.x - tr.position.x) / tr.size.x, 0.0, 1.0)
			g.set_setting(id, lerpf(float(row["min"]), float(row["max"]), t))

func _draw_settings(k: float) -> void:
	var pr = panel_rect()
	draw_rect(pr, Color(0.07, 0.075, 0.09, 0.95))
	draw_rect(pr, Color(0.29, 0.31, 0.33), false, 2.0 * k)
	_txt("SETTINGS", pr.position.x + pr.size.x * 0.5, pr.position.y + 30.0 * k, int(20 * k), GOLD, 1)
	var mp = get_viewport().get_mouse_position()
	for i in range(SETTING_ROWS.size()):
		var row = SETTING_ROWS[i]
		var r = row_rect(i)
		if r.has_point(mp):
			draw_rect(r, Color(1, 1, 1, 0.06))
		var ty = r.position.y + 21.0 * k
		_txt(row["label"], r.position.x + 8.0 * k, ty, int(14 * k), TEXT)
		if row.has("choices"):
			var ch = int(g.get_setting(row["id"]))
			_txt(row["choices"][ch], r.position.x + r.size.x - 10.0 * k, ty, int(14 * k), ACCENT, 2)
		elif row.get("toggle", false):
			var on = bool(g.get_setting(row["id"]))
			_txt("ON" if on else "OFF", r.position.x + r.size.x - 10.0 * k, ty, int(14 * k), ACCENT if on else GRAY, 2)
		else:
			var tr = track_rect(i)
			var v = float(g.get_setting(row["id"]))
			var t = clampf((v - float(row["min"])) / (float(row["max"]) - float(row["min"])), 0.0, 1.0)
			draw_rect(tr, Color(0.23, 0.16, 0.07))
			draw_rect(Rect2(tr.position, Vector2(tr.size.x * t, tr.size.y)), ACCENT)
			draw_circle(Vector2(tr.position.x + tr.size.x * t, tr.position.y + tr.size.y * 0.5), 8.0 * k, TEXT)
			var txt = ""
			if row["fmt"] == "pct":
				txt = "%d%%" % int(round(v * 100.0))
			else:
				txt = row["fmt"] % v
			_txt(txt, r.position.x + r.size.x - 10.0 * k, ty, int(14 * k), TEXT, 2)

# ---------------------------------------------------------------- main draw
func _draw() -> void:
	if g == null or font == null:
		return
	var k = size.y / 720.0
	var cx = size.x * 0.5
	var state = g.state

	# screen flashes
	if g.flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.08 * g.flash / 0.07))
	if g.red_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.9, 0.15, 0.1, 0.4 * g.red_flash / 0.35))

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
				var wp = g.tw3(r["x"], 2.15, LANE_Z_H[r["ln"]])
				if g.cam.is_position_behind(wp):
					continue
				var s2 = g.cam.unproject_position(wp)
				var pw = 12.0 * k
				var x0 = s2.x - r["max_hp"] * pw * 0.5
				for i in range(r["max_hp"]):
					draw_rect(Rect2(x0 + i * pw + 1.0, s2.y, pw - 2.0, 6.0 * k),
						Color(0.95, 0.71, 0.19) if i < r["hp"] else Color(0.23, 0.18, 0.17))

	_draw_top_bar(k)

	if state == "play":
		_draw_crosshair(k)
		_draw_threats(k)
		_draw_radar(k)
		_draw_bottom(k)
		_draw_boss_ui(k)
		if g.riders.size() == 0 and g.bosses.size() == 0 and g.wait > 0.0 and g.wait_msg != "":
			_txt(g.wait_msg, cx, size.y * 0.30, int(46 * k), TEXT, 1)
		if g.buffs["shield"] > 0.0:
			draw_arc(Vector2(cx, size.y + 230.0 * k), 360.0 * k, PI * 1.2, PI * 1.8, 48, Color(0.75, 0.59, 0.94, 0.8), 4.0 * k)

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
		if g.title_page == "":
			_dim(0.45)
			_draw_title_menu(k, cx)
		else:
			_dim(0.86)
			if g.title_page != "settings":
				_draw_title_page(k, cx)

	elif state == "over":
		_dim(0.6)
		_draw_run_summary(k, cx, blink)
	elif state == "clear":
		_dim(0.52)
		var n_hit = g.count_hits()
		_txt("ROUND CLEAR", cx, size.y * 0.2, int(70 * k), GOLD, 1)
		_txt("%d OF %d HIT" % [n_hit, g.PER_ROUND], cx, size.y * 0.38, int(32 * k), TEXT, 1)
		_txt("SCORE " + str(g.score).pad_zeros(6), cx, size.y * 0.46, int(26 * k), TEXT, 1)
		var acc = 0
		if g.shots_fired > 0:
			acc = int(round(100.0 * g.shots_hit / g.shots_fired))
		_txt("ACCURACY %d%%   BEST COMBO x%d" % [acc, g.best_combo], cx, size.y * 0.52, int(20 * k), TEXT, 1)
		if g.score > 0 and g.score >= g.hi:
			_txt("NEW HIGH SCORE", cx, size.y * 0.58, int(24 * k), GOLD, 1)
		if g.state_t > 0.8 and blink:
			_txt("CLICK TO PICK AN UPGRADE", cx, size.y * 0.7, int(28 * k), TEXT, 1)
	elif state == "upgrade":
		_draw_upgrade(k)
	elif state == "shop":
		_draw_shop(k)

	if g.paused:
		if g.pause_page == "settings":
			_dim(0.86)
			_draw_settings(k)
			_txt("ESC OR CLICK OUTSIDE TO GO BACK", cx, size.y * 0.92, int(14 * k), GRAY, 1)
		else:
			_dim(0.6)
			_draw_pause_menu(k, cx)
	elif state == "title" and g.title_page == "settings":
		_draw_settings(k)
		_txt("ESC OR CLICK OUTSIDE TO GO BACK", cx, size.y * 0.92, int(14 * k), GRAY, 1)

# ---------------------------------------------------------------- pieces
func _draw_top_bar(k: float) -> void:
	var bar_h = 58.0 * k
	draw_rect(Rect2(0, 0, size.x, bar_h), Color(0.05, 0.05, 0.055, 0.72))
	draw_rect(Rect2(0, bar_h - 2.0, size.x, 2.0), Color(0.29, 0.26, 0.22))
	var fs = int(13 * k)

	# ammo
	_txt("DARTS", 14.0 * k, 17.0 * k, fs, GOLD)
	for i in range(g.MAXSHELLS):
		var sx = (14.0 + i * 10.0) * k
		var on = i < g.shells or g.buffs["rapid"] > 0.0
		draw_rect(Rect2(sx, 29.0 * k, 7.0 * k, 15.0 * k), Color(1.0, 0.48, 0.1) if on else Color(0.21, 0.19, 0.16))
		draw_rect(Rect2(sx, 25.0 * k, 7.0 * k, 5.0 * k), Color(0.11, 0.39, 0.78) if on else Color(0.29, 0.26, 0.22))

	# lives
	_txt("LIVES", 160.0 * k, 17.0 * k, fs, GOLD)
	for i in range(g.MAXHEARTS):
		_heart((172.0 + i * 26.0) * k, 36.0 * k, 16.0 * k, RED if i < g.hearts else Color(0.23, 0.18, 0.17))

	# round + progress
	_txt("ROUND %d  %s" % [g.round_n, g.THEMES[g.theme_idx]["name"]], 300.0 * k, 17.0 * k, fs, GOLD)
	for i in range(g.PER_ROUND):
		var st = g.hits[i] if i < g.hits.size() else null
		var col = TEXT
		if st == true:
			col = RED
		elif st == false:
			col = GRAY
		elif i < g.next_idx and g.state == "play" and int(g.time * 4.0) % 2 == 0:
			col = GOLD
		_bike_icon((312.0 + i * 31.0) * k, 36.0 * k, k, col)

	# cash
	_txt("CASH", 650.0 * k, 17.0 * k, fs, GOLD)
	_txt("$%d" % g.cash, 650.0 * k, 44.0 * k, int(24 * k), TEXT)

	# score
	_txt("HI " + str(g.hi).pad_zeros(6), size.x - 12.0 * k, 17.0 * k, fs, GRAY, 2)
	_txt(str(g.score).pad_zeros(6), size.x - 12.0 * k, 44.0 * k, int(26 * k), TEXT, 2)
	if g.combo > 1:
		_txt("x%d" % g.combo, size.x - 150.0 * k, 44.0 * k, int(20 * k), ACCENT, 2)

func _draw_bottom(k: float) -> void:
	# hype bar + active pickups, bottom left
	var bx = 14.0 * k
	var by = size.y - 30.0 * k
	var bw = 190.0 * k
	var on = g.hype_t > 0.0
	var label = "HYPE"
	if on:
		label = "HYPE MODE x2  %.1fs" % g.hype_t
	_txt(label, bx, by - 8.0 * k, int(13 * k), ACCENT if on else GOLD)
	draw_rect(Rect2(bx - 2.0, by - 2.0, bw + 4.0, 14.0 * k), Color(0.05, 0.05, 0.055, 0.8))
	draw_rect(Rect2(bx, by, bw, 10.0 * k), Color(0.23, 0.16, 0.07))
	var fcol = Color(1.0, 0.42, 0.17)
	if on and int(g.time * 10.0) % 2 == 1:
		fcol = Color(1.0, 0.82, 0.25)
	var frac = (g.hype_t / 8.0) if on else (g.hype / 100.0)
	draw_rect(Rect2(bx, by, bw * clampf(frac, 0.0, 1.0), 10.0 * k), fcol)
	var y2 = by - 34.0 * k
	var items = [["RAPID FIRE", g.buffs["rapid"], Color(1.0, 0.48, 0.1), true], ["FAT DARTS", g.buffs["big"], Color(0.35, 0.7, 0.42), true],
		["SLOW MO", g.buffs["slow"], Color(0.29, 0.56, 0.84), true], ["SHIELD", g.buffs["shield"], Color(0.79, 0.66, 0.93), false]]
	for it in items:
		if it[1] > 0.0:
			var t = it[0]
			if it[3]:
				t += " %ds" % int(ceil(it[1]))
			_txt(t, bx, y2, int(13 * k), it[2])
			y2 -= 18.0 * k
	# weapon + sound status, bottom right
	var wcol = PINK if g.melee else TEXT
	_txt(("MELEE" if g.melee else "DARTS") + "  [Q] SWITCH", size.x - 12.0 * k, size.y - 14.0 * k, int(13 * k), wcol, 2)
	var snd = "SOUND %s   VOICES %s" % ["OFF" if g.sfx.muted else "ON", "OFF" if not g.sfx.voices_on else "ON"]
	_txt("[M] / [V]  " + snd, size.x - 12.0 * k, size.y - 34.0 * k, int(11 * k), GRAY, 2)

	# dash cooldown + style rank, bottom centre
	var mx = size.x * 0.5
	var dw = 130.0 * k
	var ready = g.dash_cd <= 0.0
	_txt("DASH [SPACE]" if ready else "DASH", mx, size.y - 62.0 * k, int(12 * k), ACCENT if ready else GRAY, 1)
	draw_rect(Rect2(mx - dw * 0.5 - 2.0, size.y - 56.0 * k, dw + 4.0, 10.0 * k), Color(0.05, 0.05, 0.055, 0.8))
	var df = 1.0 if ready else clampf(1.0 - g.dash_cd / 0.9, 0.0, 1.0)
	draw_rect(Rect2(mx - dw * 0.5, size.y - 54.0 * k, dw * df, 6.0 * k), Color(1.0, 0.82, 0.25) if ready else Color(0.5, 0.42, 0.2))
	var rank = g.shop_sys.style_rank()
	var rcols = [GRAY, TEXT, Color(0.35, 0.7, 0.42), GOLD, ACCENT]
	_txt("STYLE", mx - 40.0 * k, size.y - 18.0 * k, int(12 * k), GRAY, 2)
	_txt(g.shop_sys.style_letter(), mx - 28.0 * k, size.y - 12.0 * k, int(34 * k), rcols[rank])
	draw_rect(Rect2(mx + 6.0 * k, size.y - 24.0 * k, dw * 0.6, 8.0 * k), Color(0.05, 0.05, 0.055, 0.8))
	draw_rect(Rect2(mx + 7.0 * k, size.y - 23.0 * k, (dw * 0.6 - 2.0) * clampf(fmod(g.style, 20.0) / 20.0 if rank < 4 else 1.0, 0.0, 1.0), 6.0 * k), rcols[rank])
	if rank > 0:
		_txt("x%.2f SCORE" % g.shop_sys.style_mul(), mx + 6.0 * k, size.y - 30.0 * k, int(11 * k), rcols[rank])
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
			_txt(title, cx, by - 4.0 * k, int(16 * k), TEXT, 1)
			draw_rect(Rect2(bx - 3.0, by + 6.0 * k, bw + 6.0, 16.0 * k), Color(0.05, 0.05, 0.055, 0.8))
			draw_rect(Rect2(bx, by + 9.0 * k, bw, 10.0 * k), Color(0.23, 0.1, 0.09))
			draw_rect(Rect2(bx, by + 9.0 * k, bw * maxf(0.0, float(b["hp"])) / float(b["max_hp"]), 10.0 * k), RED)
			if b["kind"] != "runner":
				# stagger meter: fill it (weak spots, rubber, deflects) and the boss gets dizzy
				draw_rect(Rect2(bx, by + 24.0 * k, bw, 6.0 * k), Color(0.2, 0.17, 0.08))
				var sf = 1.0 if mode == "stagger" else clampf(b["stagger"] / 100.0, 0.0, 1.0)
				draw_rect(Rect2(bx, by + 24.0 * k, bw * sf, 6.0 * k), Color(1.0, 0.82, 0.25) if mode != "stagger" or int(g.time * 10.0) % 2 == 0 else Color(1, 1, 1))
				_txt("STAGGER", bx + bw + 8.0 * k, by + 31.0 * k, int(10 * k), GRAY)
			if b["intro"] > 0.0:
				_txt("BOSS FIGHT", cx, size.y * 0.27, int(30 * k), RED, 1)
				_txt(b["name"], cx, size.y * 0.33, int(36 * k), TEXT, 1)
			if mode == "tele" or mode == "lunge":
				var pulse = 0.12 + 0.12 * absf(sin(g.time * 12.0))
				draw_rect(Rect2(0, 0, 16.0 * k, size.y), Color(1.0, 0.16, 0.12, pulse))
				draw_rect(Rect2(size.x - 16.0 * k, 0, 16.0 * k, size.y), Color(1.0, 0.16, 0.12, pulse))
				if int(g.time * 8.0) % 2 == 0:
					var warn = "GET OFF THE RED LANE!  DASH [SPACE]"
					if mode == "tele" and b["pat"] == "slam":
						warn = "GET OUT OF THE CIRCLE!  OR DASH THROUGH [SPACE]"
					elif mode == "tele" and b["pat"] == "volley":
						warn = "PHONES INCOMING!  DODGE OR DEFLECT"
					elif b["combo"] > 0:
						warn = "COMBO!  KEEP MOVING  [SPACE]"
					_txt(warn, cx, size.y * 0.45, int(22 * k), ACCENT, 1)
			elif mode == "stagger":
				var gp = 0.10 + 0.08 * absf(sin(g.time * 8.0))
				draw_rect(Rect2(0, 0, 16.0 * k, size.y), Color(1.0, 0.82, 0.25, gp))
				draw_rect(Rect2(size.x - 16.0 * k, 0, 16.0 * k, size.y), Color(1.0, 0.82, 0.25, gp))
				_txt("DIZZY - HIT IT!  (WEAK SPOT OPEN)", cx, size.y * 0.45, int(22 * k), GOLD, 1)
			# weak spot marker
			if not g.cam.is_position_behind(g.tw3(b["x"], g.boss_sys.weak_point_y(b), b["z"])):
				var wp = g.tw3(b["x"], g.boss_sys.weak_point_y(b), b["z"])
				var sp = g.cam.unproject_position(wp)
				var dist = maxf(1.0, g.cam.global_position.distance_to(wp))
				var rr = clampf(120.0 * k / dist * (78.0 / g.cam.fov), 7.0 * k, 26.0 * k)
				var pul = 0.6 + 0.4 * sin(g.time * 9.0)
				if g.boss_sys.weak_open(b):
					draw_arc(sp, rr * (1.0 + 0.15 * pul), 0.0, TAU, 24, Color(1.0, 0.42, 0.17, 0.9), 2.0 * k)
					draw_circle(sp, 2.0 * k, Color(1.0, 0.42, 0.17, 0.9))
				else:                                                  # armoured: a crossed-out grey ring
					draw_arc(sp, rr, 0.0, TAU, 24, Color(0.62, 0.65, 0.7, 0.55), 1.5 * k)
					draw_line(sp + Vector2(-rr, -rr) * 0.6, sp + Vector2(rr, rr) * 0.6, Color(0.62, 0.65, 0.7, 0.55), 1.5 * k)
					draw_line(sp + Vector2(-rr, rr) * 0.6, sp + Vector2(rr, -rr) * 0.6, Color(0.62, 0.65, 0.7, 0.55), 1.5 * k)
	for ph in g.phones:
		if not ph["ret"] and ph["p"] < 0.85 and int(g.time * 8.0) % 2 == 0:
			_txt("INCOMING CALL!  DASH, OR SWING YOUR MELEE AT THE LAST MOMENT", cx, size.y * 0.2, int(20 * k), ACCENT, 1)
			break

# ---- 360 degree awareness: arrows at the screen edge for anything off screen, and a small radar ----
const THREAT_COL = {"rider": Color(1.0, 0.92, 0.75), "boss": Color(1.0, 0.25, 0.2), "phone": Color(1.0, 0.82, 0.2)}

# angle of a world point relative to where the camera looks: 0 ahead, + to the right, +-PI behind
func _rel_angle(world_pos: Vector3) -> float:
	var lp = g.cam.global_transform.affine_inverse() * world_pos
	return atan2(lp.x, -lp.z)

func _draw_threats(k: float) -> void:
	var list = g.threat_list()
	if list.size() == 0:
		return
	list.sort_custom(func(a, b): return a["urg"] > b["urg"])
	var c = size * 0.5
	var rx = size.x * 0.5 - 30.0 * k
	var ry = size.y * 0.5 - 80.0 * k
	var half_h = atan(tan(deg_to_rad(g.cam.fov * 0.5)) * size.x / size.y)     # horizontal half field of view
	var drawn = 0
	for t in list:
		var rel = _rel_angle(t["pos"])
		if absf(rel) < half_h * 0.9:
			continue                                  # on screen: you can see it
		if drawn >= 8:
			break
		drawn += 1
		var urg: float = t["urg"]
		var pos = c + Vector2(sin(rel) * rx, -cos(rel) * ry * 0.85)
		var out = (pos - c).normalized()
		var side = Vector2(-out.y, out.x)
		var sz = (9.0 + 11.0 * urg) * k
		var col: Color = THREAT_COL[t["kind"]]
		col.a = 0.55 + 0.4 * urg
		if urg >= 0.9:
			col.a *= 0.65 + 0.35 * sin(g.time * 18.0)
		var tip = pos + out * sz
		var b1 = pos - out * sz * 0.4 + side * sz * 0.8
		var b2 = pos - out * sz * 0.4 - side * sz * 0.8
		draw_colored_polygon(PackedVector2Array([tip + out * 2.0 * k, b1 - side * 2.0 * k, b2 + side * 2.0 * k]), Color(0, 0, 0, 0.55 * col.a))
		draw_colored_polygon(PackedVector2Array([tip, b1, b2]), col)

func _draw_radar(k: float) -> void:
	var R = 46.0 * k
	var c = Vector2(66.0 * k, 68.0 * k + R + 6.0 * k)
	draw_circle(c, R, Color(0.03, 0.05, 0.08, 0.45))
	draw_arc(c, R, 0.0, TAU, 40, Color(1, 1, 1, 0.35), 1.5 * k)
	draw_arc(c, R * 0.5, 0.0, TAU, 28, Color(1, 1, 1, 0.12), 1.0 * k)
	var half_h = atan(tan(deg_to_rad(g.cam.fov * 0.5)) * size.x / size.y)
	for sgn in [-1.0, 1.0]:
		draw_line(c, c + Vector2(sin(sgn * half_h), -cos(sgn * half_h)) * R, Color(1, 1, 1, 0.22), 1.0 * k)
	var me = g.player.position
	for t in g.threat_list():
		var d: Vector3 = t["pos"] - me
		var dist = Vector2(d.x, d.z).length()
		var rel = _rel_angle(t["pos"])
		var rr = minf(dist / 26.0, 1.0) * (R - 4.0 * k)
		var dot = c + Vector2(sin(rel), -cos(rel)) * rr
		var col: Color = THREAT_COL[t["kind"]]
		draw_circle(dot, (2.4 + 1.8 * t["urg"]) * k, col)
	draw_circle(c, 2.5 * k, Color(1, 1, 1, 0.9))

func _draw_crosshair(k: float) -> void:
	var c = size * 0.5
	if g.melee:
		draw_circle(c, 3.0 * k, Color(1.0, 0.48, 0.72, 0.9))
		return
	var half_fov = deg_to_rad(g.cam.fov * 0.5)
	var gap = tan(deg_to_rad(g.spread_deg)) / tan(half_fov) * size.y * 0.5
	gap += g.player_sys.ex_bonus() * 20.0 * k
	gap = maxf(gap, 3.0 * k)
	var ln = 9.0 * k
	var col = Color(1, 1, 1, 0.92)
	if g.buffs["big"] > 0.0:
		col = Color(0.55, 0.95, 0.6, 0.95)
	var shadow = Color(0, 0, 0, 0.6)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_line(c + d * gap, c + d * (gap + ln), shadow, 4.0 * k)
		draw_line(c + d * gap, c + d * (gap + ln), col, 2.0 * k)
	draw_circle(c, 2.2 * k, shadow)
	draw_circle(c, 1.4 * k, col)
