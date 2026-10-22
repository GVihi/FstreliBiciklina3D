extends RefCounted
# Helpers shared by the save files in user:// (settings.cfg, scores.json, meta.json).
# Every one of them carries a "version" number. A file written before versioning has no number and counts as version 0.
# Rules: a file that cannot be read, or that was written by a newer version of the game, is copied to a ".bak" file
# before the game saves over it, so an older build or a damaged file can never destroy a player's data.
# How to change a save format: docs/SAVE_FILES.md


# Copies a save file next to itself as "<name>.<tag>.bak" (for example "scores.json.bad.bak").
# An empty or missing file is not worth a backup. An older backup with the same tag is replaced.
static func backup(path: String, tag: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var bytes = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return
	var f = FileAccess.open(path + "." + tag + ".bak", FileAccess.WRITE)
	if f:
		f.store_buffer(bytes)
		f.close()


# The version stored in a loaded JSON dictionary (0 when it has none).
static func version_of(data: Dictionary) -> int:
	return int(data.get("version", 0))


# Call after reading a file: keeps a copy of a file that a newer game version wrote.
static func backup_if_newer(path: String, found_version: int, current_version: int) -> void:
	if found_version > current_version:
		backup(path, "v%d" % found_version)
