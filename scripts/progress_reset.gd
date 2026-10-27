extends RefCounted
# RESET ALL PROGRESS (bottom row of the settings panel): finds and deletes the files that hold a player's progress.
# Progress is the meta file (coins, unlocks, loadout, challenge counts, XP), the leaderboard, the saved run and the
# old high score file, together with every backup copy the game made of them (".bad.bak", ".v<N>.bak", ".reset.bak",
# ".replaced.bak"). The backups go too: a wipe that leaves a copy behind is not a wipe, and the player was told that it
# cannot be recovered. settings.cfg (the options and the leaderboard name) is not progress and is kept.
# What the rest of the game does after the files are gone is in main.gd `reset_all_progress`; the texts of the two
# warnings are in hud.gd CONFIRM_TEXT; the flow is in input.gd. Format notes: docs/SAVE_FILES.md

const DIR = "user://"
const FILES = ["meta.json", "scores.json", "run.json", "hi.dat"]


# true for a progress file or a backup copy of one, by its name in the save folder
static func is_progress_file(file_name: String) -> bool:
	for f in FILES:
		if file_name == f:
			return true
		if file_name.begins_with(f + ".") and file_name.ends_with(".bak"):
			return true
	return false


# the names of the progress files in the save folder now
static func find_files() -> Array:
	var found = []
	var dir = DirAccess.open(DIR)
	if dir == null:
		return found
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and is_progress_file(file_name):
			found.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found


# deletes every progress file; returns the names of the ones that could not be deleted (empty when all are gone)
static func delete_files() -> Array:
	var failed = []
	for file_name in find_files():
		var err = DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + file_name))
		if err != OK:
			failed.append(file_name)
	return failed
