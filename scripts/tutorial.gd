extends RefCounted
# The short tutorial (README Milestone E, Onboarding). It runs in the training room (`g.practice`, see
# `start_training` in main.gd) and walks the player through the basics one step at a time: look, walk, shoot, reload,
# bring down a rider, dash, jump and swing the melee weapon (the starting pistol holds one dart, so shooting leads
# straight into the reload step). A step is done when the player has done the thing (this
# file watches the game state each frame, it adds no hook to the input code), and the prompt on screen moves on to
# the next one. The door stays shut until the rider step, so nothing rides at a player who is still finding the mouse.
# The first visit to the TRAINING ROOM starts it; after it is finished or skipped (`g.tutorial_done`, saved in
# settings.cfg) the room opens as a plain room, and the pause menu has TUTORIAL to run it again.
# Nothing here is random or scored: the room's rules (no damage, nothing saved) are the practice round's.

# {id, text}: the text is one line under TEXT_MAX_CHARS and names the keyboard and the gamepad control
const STEPS = [
	{"id": "look", "text": "LOOK AROUND: MOUSE OR RIGHT STICK"},
	{"id": "walk", "text": "WALK TO THE WALL: WASD OR LEFT STICK"},
	{"id": "shoot", "text": "SHOOT THE FAR WALL: CLICK OR RT"},
	{"id": "reload", "text": "ONE DART IN THE CLIP: RELOAD WITH R OR X"},
	{"id": "rider", "text": "A RIDER IS COMING: SHOOT IT DOWN"},
	{"id": "dash", "text": "DASH: V OR LB (A NEAR MISS IS A PERFECT DODGE)"},
	{"id": "jump", "text": "JUMP: SPACE OR A"},
	{"id": "melee", "text": "SWITCH TO MELEE (Q OR Y) AND SWING (CLICK OR RT)"}
]
const DONE_TEXT = "TUTORIAL DONE: THE ROOM IS YOURS"
const TEXT_MAX_CHARS = 52  # the prompt is drawn in one line at the smallest window
const LOOK_RAD = 1.2  # radians of turning (yaw and pitch added up) that count as looking around
const WALK_M = 5.0  # metres walked
const JUMP_GUARD_M = 3.0  # a move of more than this in one frame is a teleport (a new round), not walking
const DONE_SECONDS = 4.0  # how long DONE_TEXT stays on screen
const RIDER_WAIT = 0.5  # seconds between the rider step starting and the rider coming out of the door

var g = null
var active = false
var done_t = 0.0  # seconds left of DONE_TEXT
var _plan: Array = []  # the steps of this run (a melee step is left out when the loadout has no melee weapon)
var _idx = 0
var _look = 0.0
var _walked = 0.0
var _last_yaw = 0.0
var _last_pitch = 0.0
var _last_pos = Vector3.ZERO
var _shots0 = 0
var _kills0 = 0


func _init(game) -> void:
	g = game


# Starts the tutorial from its first step. Only while the player is in the training room.
func start() -> void:
	if not g.practice:
		return
	_plan = []
	for s in STEPS:
		if s["id"] == "melee" and not g.has_melee():
			continue
		_plan.append(s)
	_idx = 0
	active = true
	done_t = 0.0
	_enter()


# Leaves the tutorial without marking it done (the player left the room).
func stop() -> void:
	active = false
	done_t = 0.0


# Ends the tutorial for good: `completed` shows DONE_TEXT, a skip does not. Either way the first-visit start is used up
# and saved, and the door opens if the tutorial was still holding it shut.
func finish(completed: bool) -> void:
	var was_holding = holding()
	active = false
	done_t = DONE_SECONDS if completed else 0.0
	g.tutorial_done = true
	g.settings.save_settings()
	if was_holding or completed:
		_release()


# true while the door must stay shut: the tutorial is on and has not reached the rider step
func holding() -> bool:
	return active and _idx < _rider_index()


func step_id() -> String:
	return str(_plan[_idx]["id"]) if active and _idx < _plan.size() else ""


func step_number() -> int:
	return _idx + 1


func step_total() -> int:
	return _plan.size()


# what the prompt says now: the step's text, DONE_TEXT for a few seconds after the last step, "" otherwise
func text() -> String:
	if active and _idx < _plan.size():
		return str(_plan[_idx]["text"])
	return DONE_TEXT if done_t > 0.0 else ""


func update(dt: float) -> void:
	if not active:
		if done_t > 0.0:
			done_t -= dt
		return
	if not g.practice:
		stop()
		return
	if g.state != "play" or g.paused:
		return
	var done = false
	match step_id():
		"look":
			_look += absf(g.yaw - _last_yaw) + absf(g.pitch - _last_pitch)
			done = _look >= LOOK_RAD
		"walk":
			var d = g.player.position - _last_pos
			d.y = 0.0
			if d.length() < JUMP_GUARD_M:
				_walked += d.length()
			done = _walked >= WALK_M
		"shoot":
			done = not g.melee and g.shots_fired > _shots0
		"reload":
			done = g.loading
		"rider":
			done = g.kills > _kills0
		"dash":
			done = g.dash_t > 0.0
		"jump":
			done = g.player_sys.is_airborne()
		"melee":
			done = g.melee and g.swing_t > 0.0
	_last_yaw = g.yaw
	_last_pitch = g.pitch
	_last_pos = g.player.position
	if done:
		_advance()


func _advance() -> void:
	_idx += 1
	g.sfx.play("click")
	if _idx >= _plan.size():
		finish(true)
	else:
		_enter()


# sets up the watching for the step that is now current
func _enter() -> void:
	_look = 0.0
	_walked = 0.0
	_last_yaw = g.yaw
	_last_pitch = g.pitch
	_last_pos = g.player.position
	_shots0 = g.shots_fired
	_kills0 = g.kills
	if step_id() == "reload" and (g.melee or g.shells >= g.MAXSHELLS):
		_advance()  # nothing to reload (an infinite magazine, or the melee weapon in hand): leave the step out
		return
	if step_id() == "rider":
		_release()


func _rider_index() -> int:
	for i in range(_plan.size()):
		if _plan[i]["id"] == "rider":
			return i
	return _plan.size()


# lets the next rider out of the door soon (the round's wait timer only runs down while the door is not held shut)
func _release() -> void:
	if g.riders.size() == 0 and g.bosses.size() == 0 and g.wait <= 0.0:
		g.wait = RIDER_WAIT
