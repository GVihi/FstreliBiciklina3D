extends RefCounted
# Daily seed: one integer per calendar day, the same for every player.
# The day is taken in UTC, so a player in Ljubljana and a player in Tokyo get the same seed on the same date.
# The seed is a 32-bit FNV-1a hash of the "YYYY-MM-DD" text. It is hand written (not String.hash())
# so the value can never change between Godot versions, which matters once scores are compared online.

const FNV_OFFSET = 2166136261
const FNV_PRIME = 16777619

# "YYYY-MM-DD" for the current UTC day, or for the given unix time.
static func date_string(unix_time: int = -1) -> String:
	var t = unix_time
	if t < 0:
		t = int(Time.get_unix_time_from_system())
	return Time.get_date_string_from_unix_time(t)

# Stable 32-bit seed (0 .. 4294967295) for a "YYYY-MM-DD" string.
static func seed_for(date: String) -> int:
	var h = FNV_OFFSET
	for i in range(date.length()):
		h = ((h ^ date.unicode_at(i)) * FNV_PRIME) & 0xFFFFFFFF
	return h

static func today_seed() -> int:
	return seed_for(date_string())

# Seed for one named part of one round of a daily run, e.g. ("upgrade", run seed, round 3).
# Every part gets its own seed, so what one part draws never changes what another part sees.
static func stream_seed(run_seed: int, round_n: int, part: String) -> int:
	return seed_for("%d:%d:%s" % [run_seed, round_n, part])

# Fisher-Yates shuffle driven by the given generator (Array.shuffle() always uses the global one).
static func shuffle_with(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j = rng.randi() % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

# Short text for screens, e.g. "7F3A91C2".
static func seed_text(s: int) -> String:
	return "%08X" % s
