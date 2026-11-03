extends RefCounted
# Rebindable keyboard controls (README Milestone E, "Key rebinding").
#
# The controls of a round are a short table of actions (ACTIONS). Each action has up to two keys: the first one, and an
# alternative that may be empty. The player changes them on the REBIND KEYS page (settings panel), and they are saved
# under [keys] in settings.cfg (docs/SAVE_FILES.md). Everything else on the keyboard stays where it is: Esc, Tab,
# Enter, the arrow keys, F7, F9, F10, F11, Delete, Backspace and T belong to the menus (RESERVED), and Alt, Meta and
# Caps Lock cannot be used (NOT_BINDABLE). The mouse and the gamepad are not rebindable.
#
# A key is stored as the physical key that was pressed (the place on the keyboard, not the letter on it), the same way
# the movement keys always were, so a French keyboard keeps its WASD place; the page shows the letter the player sees.
# A key event matches when its physical key is the bound one. An event that carries no physical key (the checks make
# such events) is matched by its key code.
#
# No key belongs to two actions. Binding a key that another action has swaps it (or takes it away from that action if
# the spot it leaves is empty), and an action always keeps at least one key. A damaged or hand-edited [keys] section
# can only put keys back to their defaults, it never stops the game from starting.
#
# Keys 1 to 4 and Space also work on the shop, map and upgrade screens whatever the bindings say (they are menu keys
# there), and Space always leaves the shop.

const SECTION = "keys"
const SLOTS = 2  # keys per action: the key and the alternative

# id (the name in settings.cfg), label (the REBIND KEYS page), keys (the defaults: key, then the alternative if any)
const ACTIONS = [
	{"id": "forward", "label": "MOVE FORWARD", "keys": [KEY_W]},
	{"id": "left", "label": "MOVE LEFT", "keys": [KEY_A]},
	{"id": "back", "label": "MOVE BACK", "keys": [KEY_S]},
	{"id": "right", "label": "MOVE RIGHT", "keys": [KEY_D]},
	{"id": "sprint", "label": "SPRINT", "keys": [KEY_SHIFT]},
	{"id": "crouch", "label": "CROUCH / SLIDE", "keys": [KEY_CTRL, KEY_C]},
	{"id": "jump", "label": "JUMP", "keys": [KEY_SPACE]},
	{"id": "dash", "label": "DASH", "keys": [KEY_V]},
	{"id": "reload", "label": "RELOAD (SHOP: REROLL)", "keys": [KEY_R]},
	{"id": "switch", "label": "SWITCH DART GUN AND MELEE", "keys": [KEY_Q]},
	{"id": "gun", "label": "DART GUN", "keys": [KEY_1, KEY_KP_1]},
	{"id": "melee", "label": "MELEE WEAPON", "keys": [KEY_2, KEY_KP_2]},
	{"id": "gadget", "label": "USE THE GADGET", "keys": [KEY_G]},
	{"id": "map", "label": "HOLD TO SHOW THE MAP", "keys": [KEY_M]},
]

# used by the menus: cannot be given to an action
const RESERVED = [
	KEY_ESCAPE,
	KEY_TAB,
	KEY_ENTER,
	KEY_KP_ENTER,
	KEY_LEFT,
	KEY_RIGHT,
	KEY_UP,
	KEY_DOWN,
	KEY_F7,
	KEY_F9,
	KEY_F10,
	KEY_F11,
	KEY_DELETE,
	KEY_BACKSPACE,
	KEY_T,
]
# modifiers that make no sense as a game key (Shift and Ctrl are fine: they are the defaults of sprint and crouch)
const NOT_BINDABLE = [KEY_ALT, KEY_META, KEY_CAPSLOCK]

static var _bind: Dictionary = _defaults()


static func _defaults() -> Dictionary:
	var out = {}
	for a in ACTIONS:
		var ks: Array = a["keys"]
		out[a["id"]] = [int(ks[0]), int(ks[1]) if ks.size() > 1 else 0]
	return out


static func reset_defaults() -> void:
	_bind = _defaults()


static func action_ids() -> Array:
	var out = []
	for a in ACTIONS:
		out.append(a["id"])
	return out


static func action_label(id: String) -> String:
	for a in ACTIONS:
		if a["id"] == id:
			return str(a["label"])
	return id


# the two keys of an action (0 = none), as a copy
static func keys_of(id: String) -> Array:
	if not _bind.has(id):
		return [0, 0]
	return (_bind[id] as Array).duplicate()


static func default_keys_of(id: String) -> Array:
	return _defaults().get(id, [0, 0])


# true when every action is on its defaults
static func is_default() -> bool:
	return _bind == _defaults()


# ---------------------------------------------------------------- reading the keyboard
# the key a key event stands for: its physical key, or its key code when it carries no physical key
static func event_code(event: InputEventKey) -> int:
	var pc = int(event.physical_keycode)
	return pc if pc != 0 else int(event.keycode)


# a key event (pressed or not: the caller decides) that is one of the keys of this action
static func matches(event: InputEvent, id: String) -> bool:
	if not (event is InputEventKey) or not _bind.has(id):
		return false
	var code = event_code(event)
	return code != 0 and (_bind[id][0] == code or _bind[id][1] == code)


# one of the keys of this action is held down now
static func pressed(id: String) -> bool:
	if not _bind.has(id):
		return false
	for code in _bind[id]:
		if code == 0:
			continue
		if Input.is_physical_key_pressed(code as Key):
			return true
		if (code == KEY_SHIFT or code == KEY_CTRL) and Input.is_key_pressed(code as Key):
			return true
	return false


# ---------------------------------------------------------------- text
# the name of a key as the player sees it on the keyboard ("-" for none)
static func key_label(code: int) -> String:
	if code == 0:
		return "-"
	var shown = DisplayServer.keyboard_get_keycode_from_physical(code as Key)
	var text = OS.get_keycode_string(shown if int(shown) != 0 else (code as Key))
	return text.to_upper() if text != "" else "KEY %d" % code


# the first key of an action, as text
static func key_text(id: String) -> String:
	return key_label(int(keys_of(id)[0]))


# both keys of an action, as text ("CTRL / C"), without the empty one
static func keys_text(id: String) -> String:
	var parts = []
	for code in keys_of(id):
		if int(code) != 0:
			parts.append(key_label(int(code)))
	return " / ".join(parts)


# the four movement keys in the order W A S D: joined when each is one character ("WASD"), else with spaces
static func move_text() -> String:
	var parts = []
	var joined = true
	for id in ["forward", "left", "back", "right"]:
		var t = key_text(id)
		parts.append(t)
		if t.length() != 1:
			joined = false
	return "".join(parts) if joined else " ".join(parts)


# ---------------------------------------------------------------- changing the bindings
# "" when this key can be given to an action, otherwise the reason (shown on the page)
static func why_not(code: int) -> String:
	if code <= 0 or code >= (1 << 24):
		return "THAT KEY CANNOT BE USED"
	if RESERVED.has(code):
		return "THAT KEY IS USED BY THE MENUS"
	if NOT_BINDABLE.has(code):
		return "THAT KEY CANNOT BE USED"
	return ""


# who has this key: {"id", "slot"}, or {} when nobody does
static func owner_of(code: int) -> Dictionary:
	for a in ACTIONS:
		var ks: Array = _bind[a["id"]]
		for s in range(SLOTS):
			if code != 0 and int(ks[s]) == code:
				return {"id": a["id"], "slot": s}
	return {}


static func _count(id: String) -> int:
	var n = 0
	for code in _bind[id]:
		if int(code) != 0:
			n += 1
	return n


# the first spot is never empty while the second is used
static func _tidy(id: String) -> void:
	var ks: Array = _bind[id]
	if int(ks[0]) == 0 and int(ks[1]) != 0:
		_bind[id] = [ks[1], 0]


# Gives `code` to spot `slot` (0 or 1) of action `id`. Returns {"ok": bool, "msg": String}: msg is the reason when it
# failed, and "SWAPPED WITH ..." or "TAKEN FROM ..." when another action had the key.
static func assign(id: String, slot: int, code: int) -> Dictionary:
	if not _bind.has(id) or slot < 0 or slot >= SLOTS:
		return {"ok": false, "msg": "NO SUCH CONTROL"}
	var reason = why_not(code)
	if reason != "":
		return {"ok": false, "msg": reason}
	var current = int(_bind[id][slot])
	if current == code:
		return {"ok": true, "msg": ""}
	var note = ""
	var other = owner_of(code)
	if not other.is_empty():
		var other_id = str(other["id"])
		var other_label = action_label(other_id)
		if other_id == id and current == 0:
			return {"ok": true, "msg": ""}  # the action already has this key, in its other spot
		if current == 0 and _count(other_id) <= 1:
			return {"ok": false, "msg": "%s NEEDS AT LEAST ONE KEY" % other_label}
		(_bind[other_id] as Array)[int(other["slot"])] = current
		note = ("SWAPPED WITH " if current != 0 else "TAKEN FROM ") + other_label
		if other_id != id:
			_tidy(other_id)
	(_bind[id] as Array)[slot] = code
	_tidy(id)
	return {"ok": true, "msg": note}


# Takes the key out of spot `slot`. An action keeps at least one key, so the last one cannot be cleared. Returns true
# when something was cleared.
static func clear(id: String, slot: int) -> bool:
	if not _bind.has(id) or slot < 0 or slot >= SLOTS:
		return false
	if int(_bind[id][slot]) == 0 or _count(id) <= 1:
		return false
	(_bind[id] as Array)[slot] = 0
	_tidy(id)
	return true


# ---------------------------------------------------------------- settings.cfg
static func _valid_code(code: int) -> bool:
	return why_not(code) == ""


# The bindings a [keys] section describes. Anything that is not a pair of whole numbers, a key that cannot be used, an
# action with no key, or a key that two actions claim: that action (or, for a clash, every action) is on its defaults.
static func parse(cf: ConfigFile) -> Dictionary:
	var table = _defaults()
	for a in ACTIONS:
		var id = str(a["id"])
		var v = cf.get_value(SECTION, id, null)
		if typeof(v) != TYPE_ARRAY or (v as Array).size() != SLOTS:
			continue
		var pair = []
		var ok = true
		for c in v:
			if typeof(c) != TYPE_INT or (int(c) != 0 and not _valid_code(int(c))):
				ok = false
				break
			pair.append(int(c))
		if not ok or (pair[0] == 0 and pair[1] == 0) or pair[0] == pair[1]:
			continue
		if pair[0] == 0:
			pair = [pair[1], 0]
		table[id] = pair
	var seen = {}
	for id in table:
		for c in table[id]:
			if int(c) == 0:
				continue
			if seen.has(int(c)):
				return _defaults()
			seen[int(c)] = true
	return table


static func load_from(cf: ConfigFile) -> void:
	_bind = parse(cf)


static func save_to(cf: ConfigFile) -> void:
	for a in ACTIONS:
		var ks: Array = _bind[a["id"]]
		cf.set_value(SECTION, a["id"], [int(ks[0]), int(ks[1])])
