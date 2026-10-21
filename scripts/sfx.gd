extends Node
# Sound: baked WAV samples (see tools/bake_audio.py), positional 3D playback,
# looping engine sounds, and spoken lines played from your own recordings (audio/voice/, see VOICE_LINES.txt there).

const NAMES = [
	"shot",
	"click",
	"pump",
	"shell_tick",
	"shell_drop",
	"land_s",
	"land_m",
	"land_l",
	"thud",
	"whoosh",
	"clear",
	"over",
	"siren",
	"pickup",
	"swing",
	"rubber",
	"boss_intro",
	"boss_hit_minister",
	"boss_hit_wifi",
	"boss_down",
	"boss_down_minister",
	"crash",
	"step",
	"throw",
	"ring",
	"v_yelp",
	"v_gasp",
	"v_cheer",
	"v_groan"
]
const VARIANTS = {
	"hit": 3, "clank2": 2, "boss_hit_mower": 2, "phone_smash": 2, "bird": 3, "v_hey": 4, "car": 2
}
const LOOPS = ["loop_rider", "loop_ambient", "loop_mower", "loop_wifi"]
# Spoken lines. key -> list of lines (the text is only a hint for whoever records them).
# One line   -> audio/voice/<key>.wav
# Many lines -> audio/voice/<key>_0.wav, <key>_1.wav ... (one is picked at random)
# The files that ship are silent placeholders: record over them, keep the file name, done.
const VOICE_LINES = {
	"round_start": ["Naprej!"],
	"round_clear": ["Krog končan!"],
	"round_perfect": ["Popolno!"],
	"game_over": ["Konec igre."],
	"police": ["Policija! Stoj!"],
	"upgrade": ["Nadgradnja!"],
	"shop": ["Trgovina!"],
	"hype": ["Hajp! Dajmo!"],
	"praise": ["Odlično!", "Bravo!"],
	"unstoppable": ["Neustavljiv!"],
	"taunt": ["Ha ha ha!", "Prepočasen si!", "Ujemi me, če me moreš!", "Pa saj ne znaš streljat!"],
	"phone_throw": ["Ej Peter, prevzemi klic!", "Ritter iz Eko Parka zove!"],
	"rider_hit": ["Joj!", "Au, moje kolo!", "Jebiga!", "Kaj pa zdaj?"],
	"civ_hit":
	[
		"Alo, kej ti je?",
		"Pička ti materna!",
		"Jebenti mater!",
		"Si ti normalen?",
		"Kaj delaš, bedak?",
		"Jebemti, glej kam streljaš!",
		"Ti si pa zmešan!"
	],
	"boss_mower": ["Ne dotikaj se mojega travnika!"],
	"boss_wifi": ["Ni signala!"],
	"boss_minister": ["Obljubim vam!"],
	"boss_runner": ["Zdaj si pa ti na vrsti!"],
	"boss_revenge": ["Zdaj si pa ti na vrsti!", "Ti bom že pokazal!", "Pridi sem!"],
	"minister_hit": ["Kaj počnete?", "To je škandal!", "Zahtevam pojasnila!"],
	"minister_out": ["Odstopam!"]
}
const MAX_PLAYERS = 48
const BUS = "SFX"

# Who says what. Every category gets its own bus with its own effects (see _make_voice_bus) so you can tell
# who is talking even when it is hard to hear the words:
#   narr  = the announcer: band-limited "loudspeaker" with a big room echo
#   rider = cyclists: gritty, slightly overdriven shout from a distance
#   civ   = pedestrians: muffled, a little room
#   boss  = bosses: pitched down, distorted, chorus, boomy reverb
const VOICE_CAT = {
	"round_start": "narr",
	"round_clear": "narr",
	"round_perfect": "narr",
	"game_over": "narr",
	"police": "narr",
	"upgrade": "narr",
	"shop": "narr",
	"hype": "narr",
	"praise": "narr",
	"unstoppable": "narr",
	"taunt": "rider",
	"phone_throw": "rider",
	"rider_hit": "rider",
	"boss_runner": "rider",
	"boss_revenge": "rider",
	"civ_hit": "civ",
	"boss_mower": "boss",
	"boss_wifi": "boss",
	"boss_minister": "boss",
	"minister_hit": "boss",
	"minister_out": "boss"
}
const VOICE_GAIN_DB = {"narr": 0.0, "rider": 0.0, "civ": 0.0, "boss": 2.0}  # level of each category relative to the default

var muted = false
var voices_on = true
var streams = {}
var voice_players = {}  # one player per voice category, so a boss line and the narrator can overlap
var voice_clips = {}
var voice_fx_on = true
var amb: AudioStreamPlayer
var amb_target = 0.0
var amb_level = 0.0
var clock = 0.0


# The samples are baked DRY (tools/bake_audio.py). One shared reverb on its own bus gives them a room,
# and it works properly with 3D positioning (a reverb baked into the file moves with the sound).
func _setup_bus() -> void:
	if AudioServer.get_bus_index(BUS) >= 0:
		return
	AudioServer.add_bus()
	var idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, BUS)
	AudioServer.set_bus_send(idx, "Master")
	var rv = AudioEffectReverb.new()
	rv.room_size = 0.35
	rv.damping = 0.65
	rv.spread = 1.0
	rv.hipass = 0.15
	rv.predelay_msec = 20.0
	rv.predelay_feedback = 0.2
	rv.dry = 1.0
	rv.wet = 0.13
	AudioServer.add_bus_effect(idx, rv)


func _make_voice_bus(cat: String, fx: Array) -> void:
	var name = "VOICE_" + cat.to_upper()
	if AudioServer.get_bus_index(name) < 0:
		AudioServer.add_bus()
		var idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, BUS)
		for e in fx:
			AudioServer.add_bus_effect(idx, e)
	var pl = AudioStreamPlayer.new()
	pl.bus = name
	add_child(pl)
	voice_players[cat] = pl


func _fx_hp(hz: float) -> AudioEffect:
	var e = AudioEffectHighPassFilter.new()
	e.cutoff_hz = hz
	return e


func _fx_lp(hz: float) -> AudioEffect:
	var e = AudioEffectLowPassFilter.new()
	e.cutoff_hz = hz
	return e


func _fx_reverb(room: float, damp: float, wet: float, pre_ms: float) -> AudioEffect:
	var e = AudioEffectReverb.new()
	e.room_size = room
	e.damping = damp
	e.wet = wet
	e.dry = 1.0
	e.predelay_msec = pre_ms
	e.predelay_feedback = 0.3
	return e


func _fx_drive(mode: int, drive: float, pre: float, post: float) -> AudioEffect:
	var e = AudioEffectDistortion.new()
	e.mode = mode
	e.drive = drive
	e.pre_gain = pre
	e.post_gain = post
	return e


func _setup_voice_buses() -> void:
	# narrator: loudspeaker
	_make_voice_bus("narr", [_fx_hp(220.0), _fx_lp(6500.0), _fx_reverb(0.6, 0.5, 0.28, 40.0)])
	# riders: gritty shout
	_make_voice_bus(
		"rider",
		[
			_fx_hp(300.0),
			_fx_drive(AudioEffectDistortion.MODE_OVERDRIVE, 0.12, 0.0, -1.0),
			_fx_reverb(0.25, 0.6, 0.08, 10.0)
		]
	)
	# pedestrians: muffled
	_make_voice_bus("civ", [_fx_hp(120.0), _fx_lp(4200.0), _fx_reverb(0.25, 0.7, 0.10, 10.0)])
	# bosses: low, dirty and boomy
	var ps = AudioEffectPitchShift.new()
	ps.pitch_scale = 0.84
	ps.fft_size = AudioEffectPitchShift.FFT_SIZE_2048
	var ch = AudioEffectChorus.new()
	ch.voice_count = 2
	ch.wet = 0.3
	_make_voice_bus(
		"boss",
		[
			ps,
			_fx_drive(AudioEffectDistortion.MODE_ATAN, 0.18, 0.0, -2.0),
			ch,
			_fx_reverb(0.8, 0.45, 0.3, 30.0)
		]
	)


# F7: switch the voice effects off and on to compare
func toggle_voice_fx() -> bool:
	voice_fx_on = not voice_fx_on
	for cat in voice_players.keys():
		var idx = AudioServer.get_bus_index("VOICE_" + String(cat).to_upper())
		for i in range(AudioServer.get_bus_effect_count(idx)):
			AudioServer.set_bus_effect_enabled(idx, i, voice_fx_on)
	return voice_fx_on


func _ready() -> void:
	_setup_bus()
	_setup_voice_buses()
	_load_voices()
	for n in NAMES:
		_load(n)
	for n in VARIANTS.keys():
		for i in range(VARIANTS[n]):
			_load("%s_%d" % [n, i])
	for n in LOOPS:
		var s = load("res://audio/%s.wav" % n)
		if s != null:
			var d = s.duplicate()
			d.loop_mode = AudioStreamWAV.LOOP_FORWARD
			d.loop_begin = 0
			d.loop_end = int(d.data.size() / 2)  # 16-bit mono -> 2 bytes per frame
			streams[n] = d
	amb = AudioStreamPlayer.new()
	amb.stream = streams.get("loop_ambient", null)
	amb.volume_db = -80.0
	add_child(amb)
	if amb.stream != null:
		amb.play()


func _load(n: String) -> void:
	var path = "res://audio/%s.wav" % n
	if ResourceLoader.exists(path):
		streams[n] = load(path)


func _pick(n: String):
	if VARIANTS.has(n):
		return streams.get("%s_%d" % [n, randi() % int(VARIANTS[n])], null)
	return streams.get(n, null)


func _process(delta: float) -> void:
	clock += delta
	var tgt = 0.0 if muted else amb_target
	amb_level = move_toward(amb_level, tgt, delta * 0.08)
	amb.volume_db = -80.0 if amb_level <= 0.0005 else linear_to_db(amb_level)


# ------------------------------------------------------------------ one-shots
func play(n: String, vol_db: float = -20.0) -> void:
	if muted or get_child_count() > MAX_PLAYERS:
		return
	var s = _pick(n)
	if s == null:
		return
	var p = AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = vol_db
	p.bus = BUS
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func play3d(n: String, pos: Vector3, vol_db: float = 0.0) -> void:
	if muted or get_child_count() > MAX_PLAYERS:
		return
	var s = _pick(n)
	if s == null:
		return
	var p = AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = vol_db
	p.unit_size = 12.0
	p.bus = BUS
	add_child(p)
	p.position = pos
	p.finished.connect(p.queue_free)
	p.play()


# ------------------------------------------------------------------ loops (engines, wind)
func make_loop(n: String, parent: Node3D, offset: Vector3 = Vector3.ZERO) -> AudioStreamPlayer3D:
	var s = streams.get(n, null)
	if s == null:
		return null
	var p = AudioStreamPlayer3D.new()
	p.stream = s
	p.unit_size = 12.0
	p.volume_db = -80.0
	p.bus = BUS
	parent.add_child(p)
	p.position = offset
	p.play()
	return p


func set_loop(p, vol: float, pitch: float) -> void:
	if p == null or not is_instance_valid(p):
		return
	p.volume_db = -80.0 if (muted or vol <= 0.0001) else linear_to_db(vol)
	# glide towards the target pitch: setting it straight every frame makes the loop warble
	p.pitch_scale = lerpf(p.pitch_scale, clampf(pitch, 0.1, 6.0), 0.12)


func stop_loop(p) -> void:
	if p == null or not is_instance_valid(p):
		return
	p.volume_db = -80.0
	p.stop()
	p.queue_free()


func set_ambient(on: bool) -> void:
	amb_target = 0.035 if on else 0.0


# ------------------------------------------------------------------ spoken lines (your recordings)
func _load_voices() -> void:
	for k in VOICE_LINES.keys():
		var n = VOICE_LINES[k].size()
		var list = []
		for i in range(n):
			var path = (
				"res://audio/voice/%s.wav" % k if n == 1 else "res://audio/voice/%s_%d.wav" % [k, i]
			)
			if ResourceLoader.exists(path):
				list.append(load(path))
		voice_clips[k] = list


# One line at a time per category (a new narrator line cuts the previous narrator line, but not a boss line).
func say(key: String, vol_db: float = 6.0) -> void:
	if muted or not voices_on or not voice_clips.has(key):
		return
	var list = voice_clips[key]
	if list.size() == 0:
		return
	var cat = VOICE_CAT.get(key, "narr")
	var pl: AudioStreamPlayer = voice_players[cat]
	pl.stream = list[randi() % list.size()]
	pl.volume_db = vol_db + float(VOICE_GAIN_DB[cat])
	pl.play()


func stop_voices() -> void:
	for cat in voice_players.keys():
		voice_players[cat].stop()


func set_master(v: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))


func toggle_mute() -> void:
	muted = not muted
	if muted:
		stop_voices()


func toggle_voices() -> void:
	voices_on = not voices_on
	if not voices_on:
		stop_voices()


# ------------------------------------------------------------------ the web game's named sounds
func v_yelp(pos: Vector3) -> void:
	if voices_on:
		play3d("v_yelp", pos)


func v_hey(pos: Vector3) -> void:
	if voices_on:
		play3d("v_hey", pos)


func v_gasp(pos: Vector3) -> void:
	if voices_on:
		play3d("v_gasp", pos)


func v_cheer() -> void:
	if voices_on:
		play("v_cheer")


func v_groan() -> void:
	if voices_on:
		play("v_groan")
