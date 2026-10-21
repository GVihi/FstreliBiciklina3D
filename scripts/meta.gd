extends RefCounted
# Meta currency: earned when a run ends and kept between runs in user://meta.json.
# It is deliberately separate from run cash (g.cash): run cash is earned and spent inside one run and is
# gone when the run ends, while the meta balance only ever goes up from finished runs. It will be the
# currency for permanent unlocks, cosmetics and Heat rewards (roadmap, Milestone B).

const PATH = "user://meta.json"
const SCORE_PER_COIN = 100  # tuning knob: 100 points of score = 1 meta coin

var g = null
var balance = 0  # coins available to spend
var total_earned = 0  # coins earned over all runs, for stats
var awarded = false  # a run pays out once, however many end paths it passes through


func _init(game) -> void:
	g = game
	load_meta()


func load_meta() -> void:
	balance = 0
	total_earned = 0
	if not FileAccess.file_exists(PATH):
		return
	var f = FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		balance = maxi(0, int(data.get("balance", 0)))
		total_earned = maxi(balance, int(data.get("total_earned", 0)))


func save_meta() -> void:
	var f = FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"balance": balance, "total_earned": total_earned}))
		f.close()


# called when a new run starts
func begin_run() -> void:
	awarded = false
	g.meta_earned = 0


func reward_for_score(score: int) -> int:
	return floori(float(maxi(0, score)) / float(SCORE_PER_COIN))


# Pays out the run that just ended (once). Returns the coins earned and leaves them in g.meta_earned for the summary screen.
func award_run() -> int:
	if awarded:
		return 0
	awarded = true
	var n = reward_for_score(g.score)
	g.meta_earned = n
	if n > 0:
		balance += n
		total_earned += n
		save_meta()
	return n
