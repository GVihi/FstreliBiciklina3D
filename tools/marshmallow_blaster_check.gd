extends SceneTree
# Checks the Marshmallow Blaster (README Milestone C, New Weapons, "Marshmallow Blaster: Implement weapon"):
#   - it has numbers in data/weapons.json (a clip of 2, several pellets, a short range), a place in the primary
#     slot, its own HUD and Loadout names and the shotgun sound, and it has to be bought (weapon_marshmallow_blaster),
#   - the first-person model is the shotgun of assets/models/shotgun_x3_low_poly turned so the barrel points to -Z,
#     about 0.9 m long, centred, with the shell that floats beside the gun left out (when the model is imported),
#   - one pull uses one shell and sends every pellet on its own ray inside the spread cone, none of them further than
#     the range, and a rider in front of the gun is hit,
#   - the dart gun and the pistol still send one dart, and the darts of a pellet weapon are marshmallows,
#   - it reloads shell by shell, a reload can be stopped with the shells already in staying in, and it survives a
#     saved run,
#   - the sound clip is the first shot of the mp3 and the other weapons still use the baked shot.
# It uses its own run file (user://marshmallow_blaster_check.json) and never touches the real user://run.json.
# Not checked: how the gun looks and feels in the hand, the sound itself (it needs ears), the numbers (they are first
# guesses), and the falloff, knockback and upgrade tiers (they are separate roadmap items).
# Run from the project folder:
#   godot --headless --path . --script res://tools/marshmallow_blaster_check.gd
# or with: python tools/run_checks.py marshmallow_blaster
# Exits with status 1 and prints the problems when a check fails.

const WeaponSlots = preload("res://scripts/weapon_slots.gd")
const Weapons = preload("res://scripts/weapons.gd")
const RunSave = preload("res://scripts/run_save.gd")
const Models = preload("res://scripts/models.gd")
const BLASTER = "marshmallow_blaster"
const UNLOCK_ID = "weapon_marshmallow_blaster"
const TEST_PATH = "user://marshmallow_blaster_check.json"
const SEED_A = 0x1234ABCD

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	RunSave.test_path = TEST_PATH
	_check_table()
	_check_unlock()
	_check_equip()
	_check_model()
	_check_spread()
	_check_fire()
	_check_other_weapons()
	_check_reload()
	_check_sound()
	_check_run_save()
	_remove_test_file()
	RunSave.test_path = ""
	_finish()


func _check_table() -> void:
	var tuning = Weapons.load_table()
	if not tuning.has(BLASTER):
		_fail("data/weapons.json has no %s" % BLASTER)
		return
	if not WeaponSlots.is_primary_weapon(BLASTER):
		_fail("the blaster cannot be in the primary slot")
	if WeaponSlots.label(BLASTER) != "BLASTER":
		_fail("the HUD calls the blaster %s" % WeaponSlots.label(BLASTER))
	if WeaponSlots.display_name(WeaponSlots.PRIMARY, BLASTER) != "MARSHMALLOW BLASTER":
		_fail("the Loadout page calls it %s" % WeaponSlots.display_name("primary", BLASTER))
	if WeaponSlots.display_desc(WeaponSlots.PRIMARY, BLASTER) == "":
		_fail("the blaster has no Loadout text")
	if WeaponSlots.PRIMARY_DEFAULT == BLASTER:
		_fail("the blaster is the starting weapon: it has to be bought first")
	var b = tuning[BLASTER]
	var p = tuning["dart_pistol"]
	var d = tuning["dart_gun"]
	if int(b["start_clip"]) != 2:
		_fail("the blaster clip is %d, the roadmap says 2" % int(b["start_clip"]))
	if int(b["pellets"]) < 2:
		_fail("the blaster sends %d pellet(s) a shot" % int(b["pellets"]))
	if float(b["range"]) >= float(p["range"]) or float(b["range"]) > 25.0:
		_fail("the blaster range is %s: a short-range weapon is the point" % str(b["range"]))
	if float(b["spread_hip"]) <= float(p["spread_hip"]):
		_fail("the blaster cone is not wider than the pistol's")
	if int(b["semi_auto"]) != 1:
		_fail("the blaster is not semi-automatic")
	if int(b["max_clip"]) <= int(b["start_clip"]) or int(b["clip_step"]) < 1:
		_fail("the blaster clip cannot grow with upgrades")
	if float(b["pump_min"]) >= float(b["pump_start"]) or float(b["pump_step"]) <= 0.0:
		_fail("the blaster fire rate cannot grow with upgrades")
	if int(b["damage"]) < 1:
		_fail("a blaster pellet does no damage")
	for key in d:
		if not b.has(key):
			_fail("the blaster has no %s" % key)
	if d.has("pellets") or p.has("pellets"):
		_fail("the dart gun or the pistol has a pellets value: they send one dart")
	if WeaponSlots.shot_sound(BLASTER) != "shotgun":
		_fail("the blaster makes the sound %s" % WeaponSlots.shot_sound(BLASTER))
	for other in ["dart_gun", "dart_pistol", "nope", "", 5, null]:
		if WeaponSlots.shot_sound(other) != "shot":
			_fail("%s does not make the baked shot" % str(other))


func _check_unlock() -> void:
	var found = {}
	for u in main.UNLOCKS:
		if u["id"] == UNLOCK_ID:
			found = u
	if found.is_empty():
		_fail("data/unlocks.json has no %s" % UNLOCK_ID)
		return
	if found["kind"] != "weapon" or found["target"] != BLASTER or found["planned"]:
		_fail("the unlock entry is %s" % str(found))
	if int(found["tier"]) != 3 or int(found["cost"]) != 250:
		_fail(
			(
				"the blaster is tier %d at %d coins, the roadmap says tier 3 (250)"
				% [int(found["tier"]), int(found["cost"])]
			)
		)
	main.meta.owned.erase(UNLOCK_ID)
	if main.weapon_owned(BLASTER):
		_fail("the blaster is owned before it was bought")
	main.meta.weapon_choice = {}
	if main.loadout_weapon_options("primary").has(BLASTER):
		_fail("the Loadout page lists a blaster that was not bought")
	main.meta.owned[UNLOCK_ID] = true
	if not main.weapon_owned(BLASTER):
		_fail("the blaster is not owned after buying %s" % UNLOCK_ID)
	var ids = []
	for o in main.loadout_weapon_options("primary"):
		ids.append(o["id"] if typeof(o) == TYPE_DICTIONARY else o)
	if not ids.has(BLASTER):
		_fail("the Loadout page does not list the bought blaster: %s" % str(ids))
	main.meta.owned.erase(UNLOCK_ID)


func _check_equip() -> void:
	main.start_game(false, SEED_A)
	if not main.equip_primary(BLASTER):
		_fail("equip_primary refused the blaster")
		return
	var w = main.primary_stats()
	if main.primary != BLASTER or w != main.WEAPONS[BLASTER]:
		_fail("primary_stats is not the blaster table entry")
	if main.MAXSHELLS != 2 or main.shells != 2:
		_fail("the blaster magazine is %d/%d" % [main.shells, main.MAXSHELLS])
	if not is_equal_approx(main.pump_base, float(w["pump_start"])):
		_fail("the blaster pump time is %s" % str(main.pump_base))
	main.reset_run()
	if main.primary == BLASTER:
		_fail("reset_run left the blaster in the slot")


# the blaster has its own first-person model, shown while it is in the slot
func _check_model() -> void:
	main.start_game(false, SEED_A)
	main.state = "play"
	main.paused = false
	main.melee = false
	main.equip_primary(BLASTER)
	main.player_sys.update_gun(0.016)
	if not main.guns.has(BLASTER):
		_fail("the blaster has no model")
		return
	var g = main.guns[BLASTER]
	for key in ["root", "pump", "muzzle", "light", "flash", "ammo", "ads_y", "pump_z"]:
		if not g.has(key):
			_fail("the blaster model has no %s" % key)
	if main.gun_id != BLASTER or main.gun != g:
		_fail("the blaster model is not the one shown (gun_id %s)" % main.gun_id)
	if g["root"] == main.guns["dart_gun"]["root"] or g["root"] == main.guns["dart_pistol"]["root"]:
		_fail("the blaster shares a model with another weapon")
	if (
		not g["root"].visible
		or main.guns["dart_gun"]["root"].visible
		or main.guns["dart_pistol"]["root"].visible
	):
		_fail("with the blaster in the slot its model is not the only one shown")
	var muzzle: Vector3 = g["muzzle"].position
	if muzzle.z > -0.6 or muzzle.z < -0.9 or absf(muzzle.x) > 0.01:
		_fail("the blaster muzzle is at %s" % str(muzzle))
	main.equip_primary("dart_pistol")
	main.player_sys.update_gun(0.016)
	if g["root"].visible:
		_fail("the blaster model stays visible after the pistol is equipped")

	# the plain model (used when the shotgun is not imported) is a whole viewmodel too
	var plain = Models._build_blaster_plain()
	for key in ["root", "pump", "muzzle", "light", "flash", "ammo", "ads_y", "pump_z"]:
		if not plain.has(key):
			_fail("the plain blaster model has no %s" % key)
	plain["root"].free()

	# the shotgun model: the barrel points to -Z, about 0.92 m long, centred, the floating shell left out
	if not ResourceLoader.exists(Models.BLASTER_MODEL_PATH):
		print(
			"marshmallow_blaster_check: the shotgun is not imported here, the model size was not checked"
		)
		return
	var node: Node3D = g["root"]
	if not node.find_children(Models.BLASTER_SPARE_SHELL, "Node3D", true, false).is_empty():
		_fail("the shell that floats beside the gun is still in the model")
	for kept in ["Cercle_011", "Cercle_012", "Cercle_013", "Cercle_014", "Cercle_015"]:
		if node.find_children(kept, "Node3D", true, false).is_empty():
			_fail("the shell %s of the drum is missing from the model" % kept)
	var box = _mesh_bounds(node, g["muzzle"])
	if box.size == Vector3.ZERO:
		_fail("the blaster model has no meshes")
		return
	if box.size.z < 0.85 or box.size.z > 1.0:
		_fail("the blaster model is %.3f m long, expected about 0.92" % box.size.z)
	if box.size.x > 0.3 or box.size.y > 0.4:
		_fail("the blaster model is %.3f m wide and %.3f m high" % [box.size.x, box.size.y])
	var tip = box.position.z
	if absf(tip - muzzle.z) > 0.03:
		_fail("the barrel ends at z %.3f but the muzzle is at z %.3f" % [tip, muzzle.z])
	var middle = box.position.x + box.size.x * 0.5
	if absf(middle) > 0.03:
		_fail("the blaster model is %.3f m off to the side" % middle)
	var top = box.position.y + box.size.y
	if absf(top - (-float(g["ads_y"]) + 0.0)) > 0.06:
		_fail(
			(
				"the top of the gun is %.3f above the root, the sights are set for %.3f"
				% [top, -float(g["ads_y"])]
			)
		)


# the bounds of every mesh under `node`, in the space of `node`, except the muzzle flash (it hangs on the muzzle and
# sticks out far in front of the gun)
func _mesh_bounds(node: Node3D, skip: Node3D) -> AABB:
	var total = AABB()
	var first = true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		if skip.is_ancestor_of(mi):
			continue
		var chain = Transform3D.IDENTITY
		var cur: Node = mi
		while cur != node and cur != null:
			chain = (cur as Node3D).transform * chain
			cur = cur.get_parent()
		var bb: AABB = chain * (mi as MeshInstance3D).get_aabb()
		if first:
			total = bb
			first = false
		else:
			total = total.merge(bb)
	return total


# the pellets of one pull go in different directions, all inside the cone
func _check_spread() -> void:
	main.start_game(false, SEED_A)
	main.equip_primary(BLASTER)
	var cone = 7.0
	main.spread_deg = cone
	var fwd = -main.cam.global_transform.basis.z
	var widest = 0.0
	var seen = {}
	for i in range(200):
		var dir = main.combat_sys.ray_dir_with_spread()
		var angle = rad_to_deg(fwd.angle_to(dir))
		widest = maxf(widest, angle)
		seen[str(dir.snapped(Vector3.ONE * 0.001))] = true
		if angle > cone + 0.01:
			_fail("a pellet left the %.1f degree cone: %.2f degrees" % [cone, angle])
			return
	if widest < cone * 0.7 or seen.size() < 150:
		_fail(
			(
				"the pellets barely scatter: widest %.2f degrees, %d different directions of 200"
				% [widest, seen.size()]
			)
		)


func _ready_to_fire() -> void:
	main.start_game(false, SEED_A)
	main.equip_primary(BLASTER)
	main.shells = main.MAXSHELLS  # a round start fills the magazine; this check never starts a round
	main.state = "play"
	main.paused = false
	main.melee = false
	main.loading = false
	main.pump_t = 0.0
	for d in main.darts:
		main.combat_sys.release_dart(d["node"])
	main.darts.clear()


func _check_fire() -> void:
	_ready_to_fire()
	var w = main.primary_stats()
	var pellets = int(w["pellets"])
	var range_m = float(w["range"])
	main.spread_deg = float(w["spread_hip"])
	var before = main.shells
	var fired_before = main.shots_fired
	main.combat_sys.fire()
	if main.shells != before - 1:
		_fail("one pull left %d shells, expected %d" % [main.shells, before - 1])
	if main.shots_fired != fired_before + 1:
		_fail("one pull counts as %d shots" % (main.shots_fired - fired_before))
	if main.darts.size() != pellets:
		_fail("one pull sent %d projectiles, expected %d" % [main.darts.size(), pellets])
	var org = main.cam.global_position
	var ends = {}
	for d in main.darts:
		ends[str(d["b"].snapped(Vector3.ONE * 0.01))] = true
		if org.distance_to(d["b"]) > range_m + 0.05:
			_fail("a pellet flew %.1f m, the range is %.1f" % [org.distance_to(d["b"]), range_m])
		if not d["node"].has_meta("pellet"):
			_fail("a pellet is not a marshmallow")
	if ends.size() < 2:
		_fail("all pellets landed on the same spot")
	if not is_equal_approx(main.pump_t, float(w["pump_start"])):
		_fail("the pump time after a shot is %s" % str(main.pump_t))
	var count = main.darts.size()
	main.combat_sys.fire()  # still pumping: nothing happens
	if main.darts.size() != count or main.shells != before - 1:
		_fail("the blaster fired again before its pump time was over")

	# a rider straight ahead, aimed at with no spread, is hit
	_ready_to_fire()
	main.spread_deg = 0.0
	var r = main.rider_sys.spawn_rider(1, 1)
	var fwd = -main.cam.global_transform.basis.z
	var pos = org + fwd * 6.0
	pos.y = 0.0
	r["pos"] = pos
	r["mode"] = "fly"
	r["hidden"] = false
	r["hp"] = 1
	var kills = main.kills
	main.combat_sys.fire()
	if r["mode"] != "hit" or main.kills != kills + 1:
		_fail(
			(
				"a blaster shot straight at a rider 6 m away did not remove it (mode %s)"
				% str(r["mode"])
			)
		)
	if main.darts.size() != pellets:
		_fail("a hit stopped the other pellets: %d of %d flew" % [main.darts.size(), pellets])
	main.riders.erase(r)
	main.free_rider(r)

	# a rider past the range is not hit
	_ready_to_fire()
	main.spread_deg = 0.0
	var far = main.rider_sys.spawn_rider(1, 1)
	var far_pos = org + fwd * (range_m + 8.0)
	far_pos.y = 0.0
	far["pos"] = far_pos
	far["mode"] = "fly"
	far["hidden"] = false
	far["hp"] = 1
	main.combat_sys.fire()
	if far["mode"] == "hit":
		_fail("a rider %.0f m away was hit, past the %.0f m range" % [range_m + 8.0, range_m])
	main.riders.erase(far)
	main.free_rider(far)


# the dart gun and the pistol still send one dart per pull, and it is a dart
func _check_other_weapons() -> void:
	for id in ["dart_pistol", "dart_gun"]:
		_ready_to_fire()
		main.equip_primary(id)
		main.shells = main.MAXSHELLS
		main.spread_deg = 1.0
		main.combat_sys.fire()
		if main.darts.size() != 1:
			_fail("%s sent %d projectiles" % [id, main.darts.size()])
		elif main.darts[0]["node"].has_meta("pellet"):
			_fail("%s sent a marshmallow" % id)


# the reload puts one shell in at a time and can be stopped
func _check_reload() -> void:
	_ready_to_fire()
	var step = main.combat_sys.reload_step()
	if not is_equal_approx(step, float(main.primary_stats()["reload_step"])):
		_fail("the blaster reload step is %s" % str(step))
	main.shells = 0
	main.combat_sys.start_load()
	if not main.loading:
		_fail("the blaster did not start a reload")
	main.combat_sys.load_one_shell()
	if main.shells != 1 or not main.loading:
		_fail(
			"after one shell the blaster holds %d and loading is %s" % [main.shells, main.loading]
		)
	main.combat_sys.interrupt_load()
	if main.loading or main.shells != 1:
		_fail("stopping the reload left %d shells and loading %s" % [main.shells, main.loading])
	main.combat_sys.start_load()
	main.combat_sys.load_one_shell()
	if main.shells != main.MAXSHELLS or main.loading:
		_fail(
			"the blaster has %d/%d shells, loading %s" % [main.shells, main.MAXSHELLS, main.loading]
		)


# the shotgun sound is the first shot of the mp3, the other weapons keep the baked shot
func _check_sound() -> void:
	var sfx = main.sfx
	if not sfx.CLIPS.has("shotgun"):
		_fail("sfx.gd has no clip for the shotgun")
		return
	var clip = sfx.CLIPS["shotgun"]
	if float(clip["start"]) < 0.0 or float(clip["start"]) + float(clip["length"]) > 1.35:
		_fail("the shotgun clip runs into the second shot of the file: %s" % str(clip))
	if not ResourceLoader.exists(str(clip["path"])):
		print(
			"marshmallow_blaster_check: the shot mp3 is not imported here, the sound was not checked"
		)
	elif not sfx.streams.has("shotgun"):
		_fail("the shot mp3 is imported but sfx.gd did not load it")
	elif sfx.streams["shotgun"].get_length() < float(clip["start"]) + float(clip["length"]):
		_fail("the shot mp3 is shorter than its clip")
	var players = sfx.get_child_count()
	sfx.play("shotgun")
	if sfx.streams.has("shotgun") and sfx.get_child_count() != players + 1 and not sfx.muted:
		_fail("playing the shotgun sound started no player")
	if not sfx.streams.has("shot"):
		_fail("the baked shot is gone")


func _check_run_save() -> void:
	main.start_game(false, SEED_A)
	main.equip_primary(BLASTER)
	var saved = RunSave.capture(main)
	if saved.get("primary", "") != BLASTER:
		_fail("the saved run holds primary %s" % str(saved.get("primary", "<missing>")))
	if int(saved.get("max_shells", 0)) != 2:
		_fail("the saved run holds a clip of %s" % str(saved.get("max_shells", "<missing>")))
	var cleaned = RunSave.clean(saved)
	if cleaned.get("primary", "") != BLASTER:
		_fail("a cleaned saved run holds primary %s" % str(cleaned.get("primary", "<missing>")))
	main.reset_run()
	RunSave.apply(main, cleaned)
	if main.primary != BLASTER or main.MAXSHELLS != 2:
		_fail(
			(
				"after loading the saved run the slot holds %s with a clip of %d"
				% [main.primary, main.MAXSHELLS]
			)
		)


func _remove_test_file() -> void:
	for path in [TEST_PATH, TEST_PATH + ".bak", TEST_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish() -> void:
	if problems.is_empty():
		print(
			"marshmallow_blaster_check: the Marshmallow Blaster is in the game and plays through the primary slot"
		)
		quit(0)
	else:
		for line in problems.slice(0, 15):
			printerr("marshmallow_blaster_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
