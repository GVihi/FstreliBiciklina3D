extends SceneTree
# Checks that a weapon is only an entry of data/weapons.json (README, Technical Refactor, "Make weapon additions
# easier"; data/README.md, "Adding a weapon"):
#   - the shipped file: every weapon has an `info` (slot, HUD name, Loadout name), the slot tables of
#     scripts/weapon_slots.gd are exactly what the file says, every weapon has all the numbers its slot needs, every
#     sound it names exists in scripts/sfx.gd, every model key it names has a builder in Models.build_viewmodel
#     (and a weapon without one is shown with the default's model), a gadget has a use limit or a cooldown, and every
#     weapon unlock that is not `planned` points at a weapon that exists,
#   - a made-up file with a new primary weapon, melee weapon and gadget (each one only a few lines): they land in the
#     right slots, missing numbers take the slot's base values, a typo is logged and ignored, a weapon with a broken
#     `info` or an unknown slot is left out, and the two weapons the game cannot start without are put back when the
#     file lacks them,
#   - those made-up weapons work in a game with no code change: they can be equipped, give their own numbers, and a
#     primary weapon without a model is shown with the default's model and makes the baked shot.
# The made-up file is user://weapon_registry_check.json and never touches the real data. The loader logs every
# mistake it finds with push_error, so the output of this check holds ERROR lines for the broken entries on purpose.
# Not checked: how a weapon looks, sounds or feels, and the numbers (they are first guesses).
# Run from the project folder:
#   godot --headless --path . --script res://tools/weapon_registry_check.gd
# or with: python tools/run_checks.py weapon_registry
# Exits with status 1 and prints the problems when a check fails.

const WeaponSlots = preload("res://scripts/weapon_slots.gd")
const Weapons = preload("res://scripts/weapons.gd")
const Sfx = preload("res://scripts/sfx.gd")
const TEST_FILE = "user://weapon_registry_check.json"
const SEED_A = 0x1234ABCD

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_check_shipped_file()
	_check_made_up_file()
	_check_made_up_weapons_in_game()
	_remove_test_file()
	_finish()


# ---- the file that ships with the game


func _check_shipped_file() -> void:
	var all = Weapons.load_all()
	var stats = all["stats"]
	var info = all["info"]
	for id in Weapons.FALLBACK:
		if not info.has(id):
			_fail("%s, a weapon every run needs, is not in data/weapons.json" % id)
	if stats.keys() != info.keys():
		_fail("the numbers and the info of data/weapons.json do not list the same weapons")
	if WeaponSlots.WEAPON_INFO != info:
		_fail("WeaponSlots.WEAPON_INFO is not what data/weapons.json says")
	for slot in Weapons.SLOTS:
		if WeaponSlots.table_of(slot) != Weapons.hud_names(info, slot):
			_fail("the %s table of weapon_slots.gd is not what data/weapons.json says" % slot)
	for id in info:
		var slot = str(info[id]["slot"])
		for key in Weapons.required_numbers(slot):
			if not stats[id].has(key):
				_fail("%s (%s slot) has no number %s" % [id, slot, key])
		if str(info[id]["name"]) == "" or str(info[id]["hud"]) == "":
			_fail("%s has no name or HUD name" % id)
		if slot == "primary":
			var sound = str(info[id]["sound"])
			if not Sfx.NAMES.has(sound) and not Sfx.CLIPS.has(sound):
				_fail("%s names the sound %s, which scripts/sfx.gd does not have" % [id, sound])
			var model = str(info[id]["model"])
			if main.guns.has(id) != (model != ""):
				_fail("%s: the model key '%s' and the gun models built do not agree" % [id, model])
			if model != "" and main.Models.build_viewmodel(model).is_empty():
				_fail(
					(
						"%s names the model %s, which Models.build_viewmodel does not build"
						% [id, model]
					)
				)
		if (
			slot == "gadget"
			and float(stats[id]["uses"]) <= 0.0
			and float(stats[id]["cooldown"]) <= 0.0
		):
			_fail("the gadget %s has neither a use limit nor a cooldown" % id)
	for u in main.UNLOCKS:
		if str(u.get("kind", "")) == "weapon" and not bool(u.get("planned", false)):
			if not info.has(str(u["target"])):
				_fail(
					(
						"the unlock %s is for %s, which is not in data/weapons.json"
						% [u["id"], u["target"]]
					)
				)
	if not WeaponSlots.PRIMARY_WEAPONS.has(WeaponSlots.PRIMARY_DEFAULT):
		_fail("the default primary weapon is not in the primary table")
	if not WeaponSlots.MELEE_WEAPONS.has(WeaponSlots.MELEE_DEFAULT):
		_fail("the default melee weapon is not in the melee table")


# ---- a file with made-up weapons

const MADE_UP = {
	"test_gun":
	{
		"info": {"slot": "primary", "hud": "TEST", "name": "TEST GUN"},
		"damage": 3,
		"range": 12,
		"pellets": 5,
		"typo_key": 1
	},
	"test_stick":
	{
		"info": {"slot": "melee", "hud": "STICK", "name": "TEST STICK", "desc": "A STICK"},
		"damage": 5
	},
	"test_gadget": {"info": {"slot": "gadget", "hud": "GIZMO", "name": "TEST GADGET"}, "uses": 3},
	"bad_slot": {"info": {"slot": "head", "hud": "X", "name": "X"}},
	"no_info": {"damage": 1},
	"no_hud": {"info": {"slot": "primary", "name": "NO HUD NAME"}},
	"not_an_object": 5
}


func _check_made_up_file() -> void:
	var f = FileAccess.open(TEST_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(MADE_UP, "", false))  # false: keep the order of the entries
	f.close()
	var all = Weapons.load_all(TEST_FILE)
	var stats = all["stats"]
	var info = all["info"]
	for id in ["bad_slot", "no_info", "no_hud", "not_an_object"]:
		if stats.has(id) or info.has(id):
			_fail("the broken entry %s was not left out" % id)
	for id in ["test_gun", "test_stick", "test_gadget"]:
		if not stats.has(id) or not info.has(id):
			_fail("the made-up weapon %s was not loaded" % id)
	# the file does not list the dart pistol or the worm: they are put back
	for id in Weapons.FALLBACK:
		if not stats.has(id) or not info.has(id):
			_fail("%s was not put back when the file lacked it" % id)
	if stats.is_empty() or info.is_empty():
		return
	var gun = stats.get("test_gun", {})
	if typeof(gun.get("damage")) != TYPE_INT or int(gun.get("damage", 0)) != 3:
		_fail("test_gun.damage is %s, not the whole number 3" % str(gun.get("damage")))
	if typeof(gun.get("range")) != TYPE_FLOAT or float(gun.get("range", 0.0)) != 12.0:
		_fail("test_gun.range is %s, not the float 12" % str(gun.get("range")))
	if int(gun.get("pellets", 0)) != 5:
		_fail("test_gun.pellets (an optional number) was not kept")
	if gun.has("typo_key"):
		_fail("test_gun.typo_key, a key nothing reads, was not ignored")
	var pistol = Weapons.FALLBACK["dart_pistol"]
	if int(gun.get("start_clip", -1)) != int(pistol["start_clip"]):
		_fail("test_gun.start_clip, left out of the file, did not take the pistol's value")
	if gun.keys().size() != pistol.keys().size() + 1:
		_fail(
			(
				"test_gun has the numbers of the primary slot plus its pellets, not %d"
				% gun.keys().size()
			)
		)
	var stick = stats.get("test_stick", {})
	if int(stick.get("damage", 0)) != 5 or float(stick.get("cooldown", 0.0)) != 0.3:
		_fail("test_stick should have damage 5 and the worm's cooldown 0.3, it has %s" % str(stick))
	var gadget = stats.get("test_gadget", {})
	if (
		gadget.keys().size() != 2
		or int(gadget.get("uses", 0)) != 3
		or float(gadget.get("cooldown", 1.0)) != 0.0
	):
		_fail("test_gadget should have uses 3 and cooldown 0, it has %s" % str(gadget))
	var i = info.get("test_gun", {})
	if str(i.get("sound")) != "shot" or str(i.get("model")) != "" or str(i.get("desc")) != "":
		_fail("test_gun's sound, model and text should default to shot and nothing: %s" % str(i))
	if Weapons.hud_names(info, "primary").get("test_gun") != "TEST":
		_fail("test_gun is not in the primary table with its HUD name")
	if Weapons.hud_names(info, "melee").get("test_stick") != "STICK":
		_fail("test_stick is not in the melee table with its HUD name")
	if Weapons.hud_names(info, "gadget").get("test_gadget") != "GIZMO":
		_fail("test_gadget is not in the gadget table with its HUD name")
	if Weapons.hud_names(info, "primary").has("test_stick"):
		_fail("test_stick, a melee weapon, is in the primary table")
	if info.keys().slice(0, 3) != ["test_gun", "test_stick", "test_gadget"]:
		_fail("the weapons are not in the order of the file: %s" % str(info.keys()))
	# a file that is not there or not an object still gives the two weapons every run needs
	for bad_path in ["user://weapon_registry_check_missing.json", "res://data/README.md"]:
		var fallback = Weapons.load_all(bad_path)
		if (
			fallback["stats"].keys() != Weapons.FALLBACK.keys()
			or fallback["info"].keys() != Weapons.FALLBACK.keys()
		):
			_fail(
				(
					"%s did not give the built-in weapons: %s"
					% [bad_path, str(fallback["info"].keys())]
				)
			)


# ---- the made-up weapons in a running game


func _check_made_up_weapons_in_game() -> void:
	var all = Weapons.load_all(TEST_FILE)
	var ids = ["test_gun", "test_stick", "test_gadget"]
	for id in ids:
		if not all["stats"].has(id):
			return  # already reported above
		main.WEAPONS[id] = all["stats"][id]
		WeaponSlots.WEAPON_INFO[id] = all["info"][id]
	WeaponSlots.PRIMARY_WEAPONS["test_gun"] = "TEST"
	WeaponSlots.MELEE_WEAPONS["test_stick"] = "STICK"
	WeaponSlots.GADGET_WEAPONS["test_gadget"] = "GIZMO"
	main.start_game(false, SEED_A)
	if not main.equip_primary("test_gun"):
		_fail("the made-up primary weapon cannot be equipped")
	elif (
		int(main.primary_stats()["damage"]) != 3
		or main.MAXSHELLS != int(main.primary_stats()["start_clip"])
	):
		_fail("the made-up primary weapon does not give its own numbers")
	main.sync_gun_model()
	if main.gun_id != WeaponSlots.PRIMARY_DEFAULT:
		_fail("a weapon without a model is shown with %s, not the default's" % str(main.gun_id))
	if WeaponSlots.shot_sound("test_gun") != "shot":
		_fail("a weapon that names no sound does not make the baked shot")
	if (
		WeaponSlots.label("test_gun") != "TEST"
		or WeaponSlots.display_name("primary", "test_gun") != "TEST GUN"
	):
		_fail("the made-up primary weapon does not show its HUD name and Loadout name")
	main.melee_weapon = "test_stick"
	if int(main.melee_stats()["damage"]) != 5 or WeaponSlots.melee_label("test_stick") != "STICK":
		_fail("the made-up melee weapon does not give its numbers and name")
	if WeaponSlots.display_desc("melee", "test_stick") != "A STICK":
		_fail("the made-up melee weapon does not show its text on the Loadout page")
	if not main.equip_gadget("test_gadget") or int(main.gadget_stats().get("uses", 0)) != 3:
		_fail("the made-up gadget cannot be equipped or gives no numbers")
	if main.equip_gadget("nope"):
		_fail("a gadget that does not exist was equipped")
	main.equip_gadget("")
	main.melee_weapon = WeaponSlots.MELEE_DEFAULT
	main.equip_primary(WeaponSlots.PRIMARY_DEFAULT)
	for id in ids:
		main.WEAPONS.erase(id)
		WeaponSlots.WEAPON_INFO.erase(id)
		WeaponSlots.PRIMARY_WEAPONS.erase(id)
		WeaponSlots.MELEE_WEAPONS.erase(id)
		WeaponSlots.GADGET_WEAPONS.erase(id)


func _remove_test_file() -> void:
	if FileAccess.file_exists(TEST_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_FILE))


func _finish() -> void:
	if problems.is_empty():
		print("weapon_registry_check: a weapon is only an entry of data/weapons.json")
		quit(0)
	else:
		for line in problems.slice(0, 15):
			printerr("weapon_registry_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
