extends SceneTree
# Checks buying on the Unlocks page (README Milestone I: "Unlock and buy upgrades and starting perks with meta
# currency", and "Save unlocks and purchases in the versioned save files"):
#   - Meta.buy spends the price once, marks the unlock owned and saves; it refuses an unlock that is owned, planned
#     or too dear and then changes nothing,
#   - what is owned survives a reload of meta.json, an old file without "owned" loads with nothing owned, a damaged
#     "owned" field is ignored, and an id the table no longer has stays owned,
#   - Enter / A and the BUY button buy the highlighted unlock and set the message; a second press does not charge again,
#   - total_earned is not lowered by spending.
# It keeps the real meta.json (and its backups) first and puts them back at the end.
# Run from the project folder:
#   godot --headless --path . --script res://tools/unlocks_buy_check.gd
# or with tools\run_unlocks_buy_check.bat on Windows.
# Exits with status 1 and prints the problems when a check fails.

var problems = []
var main
var kept = {}


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_keep_user_files()
	_check_buy()
	_check_save_and_load()
	_check_input()
	_restore_user_files()
	_finish()


func _finish() -> void:
	if problems.is_empty():
		print("unlocks_buy_check: buying spends once, refuses the rest and is saved")
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("unlocks_buy_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


func _paths() -> Array:
	var meta_path = main.meta.PATH
	return [meta_path, meta_path + ".bad.bak", meta_path + ".v2.bak"]


func _keep_user_files() -> void:
	for path in _paths():
		if FileAccess.file_exists(path):
			kept[path] = FileAccess.get_file_as_bytes(path)


func _restore_user_files() -> void:
	for path in _paths():
		if kept.has(path):
			var f = FileAccess.open(path, FileAccess.WRITE)
			if f:
				f.store_buffer(kept[path])
				f.close()
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.meta.load_meta()


# the first unlock that can be bought, the first planned one
func _first(planned: bool) -> int:
	for i in range(main.UNLOCKS.size()):
		if main.UNLOCKS[i]["planned"] == planned:
			return i
	return -1


func _fresh(balance: int) -> void:
	main.meta.balance = balance
	main.meta.total_earned = balance
	main.meta.owned = {}


func _check_buy() -> void:
	var i = _first(false)
	var j = _first(true)
	if i < 0 or j < 0:
		_fail("the table has no unlock that can be bought or none that is planned")
		return
	var u = main.UNLOCKS[i]
	var cost = int(u["cost"])
	# too dear: nothing changes
	_fresh(cost - 1)
	if main.meta.buy(u) != "locked" or main.meta.balance != cost - 1 or main.meta.owns(u["id"]):
		_fail("buying with %d coins for %d did not refuse cleanly" % [cost - 1, cost])
	# exactly enough: the price is spent once and the unlock is owned
	_fresh(cost)
	if main.meta.buy(u) != "bought" or main.meta.balance != 0 or not main.meta.owns(u["id"]):
		_fail("buying with exactly enough coins failed (balance %d)" % main.meta.balance)
	if main.meta.total_earned != cost:
		_fail("spending changed total_earned to %d" % main.meta.total_earned)
	# again: owned, no second charge
	main.meta.balance = cost * 3
	if main.meta.buy(u) != "owned" or main.meta.balance != cost * 3:
		_fail("buying an owned unlock was not refused or charged again")
	# planned: refused even with plenty of coins
	var p = main.UNLOCKS[j]
	main.meta.balance = 100000
	if main.meta.buy(p) != "soon" or main.meta.balance != 100000 or main.meta.owns(p["id"]):
		_fail("a planned unlock could be bought")


func _check_save_and_load() -> void:
	var i = _first(false)
	var u = main.UNLOCKS[i]
	_fresh(int(u["cost"]) + 7)
	main.meta.buy(u)
	main.meta.balance = 0
	main.meta.owned = {}
	main.meta.load_meta()
	if main.meta.balance != 7 or not main.meta.owns(u["id"]):
		_fail(
			(
				"after a reload the balance is %d and owned is %s"
				% [main.meta.balance, str(main.meta.owned)]
			)
		)
	# a file written before "owned" existed
	_write('{"version": 1, "balance": 40, "total_earned": 90}')
	main.meta.load_meta()
	if main.meta.balance != 40 or not main.meta.owned.is_empty():
		_fail("an old meta.json did not load as 40 coins and nothing owned")
	# a damaged field, and an id the table does not have
	_write('{"version": 1, "balance": 5, "total_earned": 5, "owned": "perk_steady"}')
	main.meta.load_meta()
	if main.meta.balance != 5 or not main.meta.owned.is_empty():
		_fail("a text 'owned' field was not ignored")
	_write(
		'{"version": 1, "balance": 5, "total_earned": 5, "owned": ["gone_id", 3, "", null, "perk_steady"]}'
	)
	main.meta.load_meta()
	if (
		not main.meta.owns("gone_id")
		or not main.meta.owns("perk_steady")
		or main.meta.owned.size() != 2
	):
		_fail("loading kept the wrong ids: %s" % str(main.meta.owned))
	# saving writes the ids back sorted, with the rest of the file
	main.meta.save_meta()
	var data = JSON.parse_string(FileAccess.get_file_as_string(main.meta.PATH))
	if (
		typeof(data) != TYPE_DICTIONARY
		or data.get("owned") != ["gone_id", "perk_steady"]
		or int(data.get("balance", -1)) != 5
		or int(data.get("version", -1)) != 1
	):
		_fail("meta.json after a save is %s" % str(data))


func _write(text: String) -> void:
	var f = FileAccess.open(main.meta.PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# Enter / A and the BUY button, through the input script
func _check_input() -> void:
	var inp = main.input_sys
	var i = _first(false)
	var u = main.UNLOCKS[i]
	var cost = int(u["cost"])
	_fresh(cost + 3)
	main.go_to_title()
	inp.title_activate(_title_entry("unlocks"))
	main.unlock_sel = i
	main.hud.size = Vector2(1280.0, 720.0)
	inp.menu_confirm()  # Enter
	if main.unlock_msg != "BOUGHT" or main.meta.balance != 3 or not main.meta.owns(u["id"]):
		_fail("Enter did not buy: message '%s', balance %d" % [main.unlock_msg, main.meta.balance])
	if main.title_page != "unlocks":
		_fail("buying left the page ('%s')" % main.title_page)
	inp.title_activate(main.title_sel)  # A
	if main.unlock_msg != "YOU ALREADY OWN THIS" or main.meta.balance != 3:
		_fail("a second press: message '%s', balance %d" % [main.unlock_msg, main.meta.balance])
	# a planned one says so
	main.unlock_sel = _first(true)
	main.meta.balance = 100000
	inp.unlock_buy()
	if main.unlock_msg != "NOT IN THE GAME YET" or main.meta.balance != 100000:
		_fail("a planned unlock: message '%s', balance %d" % [main.unlock_msg, main.meta.balance])
	# the BUY button is a place on the page that the mouse can hit
	if not main.hud.unlock_buy_rect().has_point(main.hud.unlock_buy_rect().get_center()):
		_fail("the BUY button has no area")
	# the keys do nothing off the page
	main.go_to_title()
	var owned = main.meta.owned.duplicate()
	main.meta.balance = 100000
	inp.unlock_buy()
	if main.meta.owned != owned or main.meta.balance != 100000:
		_fail("unlock_buy worked on the title menu")


func _title_entry(id: String) -> int:
	for i in range(main.hud.TITLE_ITEMS.size()):
		if main.hud.TITLE_ITEMS[i]["id"] == id:
			return i
	return -1
