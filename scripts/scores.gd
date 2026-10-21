extends RefCounted
# Local leaderboard: the best MAX_ENTRIES runs, best first, saved to user://scores.json.
# Every entry is {"name", "score", "round", "kills", "date"}. A run is recorded once, when it ends.

const MAX_ENTRIES = 10
const PATH = "user://scores.json"

var g = null
var entries = []


func _init(game) -> void:
	g = game
	load_scores()


func load_scores() -> void:
	entries = []
	if not FileAccess.file_exists(PATH):
		return
	var f = FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Array:
		for e in data:
			if e is Dictionary and e.has("score"):
				entries.append(
					{
						"name": str(e.get("name", "")),
						"score": int(e["score"]),
						"round": int(e.get("round", 1)),
						"kills": int(e.get("kills", 0)),
						"time": int(e.get("time", 0)),
						"date": str(e.get("date", ""))
					}
				)
	entries.sort_custom(func(a, b): return a["score"] > b["score"])
	if entries.size() > MAX_ENTRIES:
		entries.resize(MAX_ENTRIES)


func save_scores() -> void:
	var f = FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(entries))
		f.close()


# Records the run that just ended. Sets g.last_rank to its place (0 = first), or -1 when it did not make the list.
func submit_run() -> int:
	g.last_rank = -1
	if g.daily_mode:  # kept out of the normal Top 10; the daily scoreboard is a separate roadmap item
		return -1
	if g.score <= 0:
		return -1
	# an equal score ranks below the older one
	var idx = entries.size()
	for i in range(entries.size()):
		if g.score > entries[i]["score"]:
			idx = i
			break
	if idx >= MAX_ENTRIES:
		return -1
	entries.insert(
		idx,
		{
			"name": g.player_name,
			"score": g.score,
			"round": g.round_n,
			"kills": g.kills,
			"time": int(g.play_time + g.shop_time),
			"date": Time.get_date_string_from_system()
		}
	)
	if entries.size() > MAX_ENTRIES:
		entries.resize(MAX_ENTRIES)
	save_scores()
	g.last_rank = idx
	g.name_entry = true
	g.name_buf = g.player_name
	return idx


func set_name(idx: int, nm: String) -> void:
	if idx >= 0 and idx < entries.size():
		entries[idx]["name"] = nm
		save_scores()
