extends SceneTree
# Checks the exploration objectives and the rim outline. Run from the project folder:
#   godot --headless --path . --script res://tools/objective_check.gd
#
# Spots (scripts/arena_generated.gd): on 150 generated arenas the extraction point and the supply caches repeat for
# the same seed, stand on ground that can be walked to with room round it, and are spread out (the extraction point
# is far from the start, the caches far from the start, the extraction point and each other).
# Round (scripts/objective.gd): a generated round has caches and a locked extraction point, a cache pays once, taking
# them all pays the bonus, the roundabout has none of it.
# Cache variants (scripts/objective.gd): `pick_variants` repeats for the same seed, never gives more than VARIANT_MAX
# caches a variant, and does roll the vanishing one. A vanishing cache starts its countdown only when the player is
# within VANISH_TRIGGER, keeps counting when the player walks away, is gone at zero (not taken, no pay, no every-cache
# bonus, off the radar and the map) and can still be taken in time.
# A cursed cache pays CURSED_MULT times the cash and score, calls `curse_count` riders out of the gate nearest to it
# one after another (not all at once, and not before CURSE_DELAY), never changes `taken` or the every-cache bonus, and
# sends nobody when the round is not being played; the roll of variants still repeats and does roll the cursed one.
# A locked cache (`assign_keys`) always has a plain cache that holds its key and never turns up without one; with
# no key it does not open (no pay, not taken, a reminder), the cache that holds the key gives it, the locked cache then
# opens, pays LOCKED_MULT times and uses the key up, and keys do not carry into the next round.
# Meta coins (`pick_coins`, `meta.add_cache_coin`): repeatable for the same seed, one in COIN_CHANCE of the caches
# holds a coin (between 10 and 15 % over many rolls, the owner's ask), taking a cache with a coin counts it once for the
# run (a cache without one counts nothing), it is paid with the run (`award_run`) and not before, and a new run starts
# at zero.
# Rim (scripts/rim.gd): riders and bosses get the red rim, pedestrians and cheerleaders the green one, the hit flash
# gives the rim back when it ends and the setting takes it away and back.
# Exits with status 1 and prints the problems.

const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const GeneratedArena = preload("res://scripts/arena_generated.gd")
const Rim = preload("res://scripts/rim.gd")
const Models = preload("res://scripts/models.gd")
const Objective = preload("res://scripts/objective.gd")

const SEEDS = 150
const GOAL_MIN_SHARE = 0.55  # the extraction point is at least this share of the way to the farthest reachable cell
const SEED = 0x2468ACE0

var problems = []


func _initialize() -> void:
	_spots()
	_variants()
	_coin_rolls()
	await _round()
	_rim_models()
	await _rim_in_game()
	if problems.is_empty():
		print(
			(
				"objective_check: spots on %d arenas, a round with caches and an extraction point, and the rim outline hold"
				% SEEDS
			)
		)
		quit(0)
	else:
		print("objective_check: %d problem(s)" % problems.size())
		for p in problems:
			print("  " + p)
		quit(1)


func _fail(text: String) -> void:
	if problems.size() < 40:
		problems.append(text)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r = RandomNumberGenerator.new()
	r.seed = seed_value
	return r


# ------------------------------------------------------------------ spots
func _spots() -> void:
	var rules = ArenaGenScript.load_rules()
	var short_caches = 0
	for k in range(SEEDS):
		var run_seed = 0x51000000 + k * 7919
		var layout = ArenaGenScript.generate(run_seed, rules)
		var a = GeneratedArena.new(layout, rules)
		var tag = "seed %08X" % run_seed
		var goal = a.goal_spot(_rng(run_seed))
		var again = a.goal_spot(_rng(run_seed))
		if goal != again:
			_fail("%s: the extraction point is not repeatable" % tag)
		var n = int(layout["cells"])
		var cell = float(layout["cell"])
		var dist = a.walk_distances()
		var gi = _cell_index(a, goal)
		if gi < 0 or dist[gi] < 0:
			_fail("%s: the extraction point cannot be walked to" % tag)
			continue
		if ArenaGenScript.nav_clearance(layout, gi % n, gi / n) < GeneratedArena.GOAL_CLEAR:
			_fail("%s: the extraction point has no room round it" % tag)
		var far = 0
		for d in dist:
			far = maxi(far, d)
		if float(dist[gi]) < float(far) * GOAL_MIN_SHARE:
			_fail("%s: the extraction point is only %d of %d steps away" % [tag, dist[gi], far])
		var caches = a.cache_spots(4, goal, _rng(run_seed + 1))
		if caches != a.cache_spots(4, goal, _rng(run_seed + 1)):
			_fail("%s: the caches are not repeatable" % tag)
		if caches.size() < 4:
			short_caches += 1
		var seen = [a.start_position(), goal]
		for c in caches:
			var ci = _cell_index(a, c)
			if ci < 0 or dist[ci] < 0:
				_fail("%s: a cache cannot be walked to" % tag)
				continue
			if float(dist[ci]) * cell < GeneratedArena.CACHE_MIN_WALK:
				_fail(
					(
						"%s: a cache is only %.0f m of walking from the start"
						% [tag, float(dist[ci]) * cell]
					)
				)
			if ArenaGenScript.nav_clearance(layout, ci % n, ci / n) < GeneratedArena.CACHE_CLEAR:
				_fail("%s: a cache has no room round it" % tag)
			for o in seen:
				if Vector2(c.x - o.x, c.z - o.z).length() < GeneratedArena.CACHE_APART - 0.01:
					_fail(
						(
							"%s: a cache is under %d m from another spot"
							% [tag, GeneratedArena.CACHE_APART]
						)
					)
			seen.append(c)
	if short_caches > SEEDS / 20:
		_fail("%d of %d arenas have fewer than 4 cache spots" % [short_caches, SEEDS])


func _variants() -> void:
	var seen_vanishing = 0
	var seen_cursed = 0
	var seen_locked = 0
	var rounds_with_none = 0
	for s in range(SEEDS):
		var v1 = Objective.pick_variants(4, _rng(SEED + s))
		if v1 != Objective.pick_variants(4, _rng(SEED + s)):
			_fail("seed %d: the cache variants are not repeatable" % s)
		if v1.size() != 4:
			_fail("seed %d: %d variants for 4 caches" % [s, v1.size()])
		var n = 0
		for v in v1:
			if v == Objective.VARIANT_PLAIN:
				continue
			n += 1
			if not Objective.VARIANTS.has(v):
				_fail("seed %d: unknown cache variant %s" % [s, v])
			if v == Objective.VARIANT_VANISHING:
				seen_vanishing += 1
			if v == Objective.VARIANT_CURSED:
				seen_cursed += 1
			if v == Objective.VARIANT_LOCKED:
				seen_locked += 1
		if n > Objective.VARIANT_MAX:
			_fail(
				(
					"seed %d: %d caches have a variant, the most allowed is %d"
					% [s, n, Objective.VARIANT_MAX]
				)
			)
		if n == 0:
			rounds_with_none += 1
	if seen_vanishing == 0:
		_fail("no vanishing cache was rolled on %d seeds" % SEEDS)
	if seen_cursed == 0:
		_fail("no cursed cache was rolled on %d seeds" % SEEDS)
	if seen_locked == 0:
		_fail("no locked cache was rolled on %d seeds" % SEEDS)
	_keys()
	if rounds_with_none == 0:
		_fail(
			"every one of %d seeds rolled a variant: 'some of the caches' became 'always'" % SEEDS
		)


func _coin_rolls() -> void:
	var hits = 0
	var total = 0
	for s in range(5000):
		var r1 = Objective.pick_coins(4, _rng(SEED + s))
		if r1 != Objective.pick_coins(4, _rng(SEED + s)):
			_fail("seed %d: the cache coins are not repeatable" % s)
		if r1.size() != 4:
			_fail("seed %d: %d coin flags for 4 caches" % [s, r1.size()])
		hits += r1.count(true)
		total += r1.size()
	var share = float(hits) / float(total)
	if share < 0.10 or share > 0.15:
		_fail(
			(
				"%.1f %% of the caches hold a meta coin, the owner asked for 10 to 15 %%"
				% (share * 100.0)
			)
		)


# Takes a cache with a coin and one without on a round that is already set up: `o` is the main's objective_sys.
func _coins(m, o) -> void:
	o.setup_round()
	m.meta.begin_run()
	if m.meta.cache_coins != 0:
		_fail("coins: %d cache coins at the start of a run" % m.meta.cache_coins)
	for c in o.caches:
		c["variant"] = Objective.VARIANT_PLAIN
		c["key"] = false
		c["coin"] = false
	o.caches[0]["coin"] = true
	var balance0 = m.meta.balance
	m.player.position = o.caches[1]["pos"]
	o.update(0.05)
	if m.meta.cache_coins != 0:
		_fail("coins: a cache with no coin counted one")
	m.player.position = o.caches[0]["pos"]
	o.update(0.05)
	o.update(0.05)
	if m.meta.cache_coins != 1:
		_fail("coins: %d cache coins after taking one coin cache" % m.meta.cache_coins)
	if m.meta.balance != balance0:
		_fail("coins: the coin was paid before the run ended")
	var cleared = maxi(0, m.round_n - 1 - m.screens_passed()) + (1 if m.run_won else 0)
	var n = m.meta.award_run()
	var want = (
		m.meta.reward_for_score(m.score)
		+ m.meta.reward_for_rounds(cleared)
		+ m.challenges.coins
		+ 1
	)
	if n != want or m.meta.balance != balance0 + n:
		_fail(
			(
				"coins: award_run paid %d, wanted %d with the cache coin; balance %d to %d"
				% [n, want, balance0, m.meta.balance]
			)
		)
	m.meta.begin_run()
	if m.meta.cache_coins != 0:
		_fail("coins: a new run did not start at zero")


# Plays the vanishing cache on a round that is already set up: `o` is the main's objective_sys.
func _vanishing(m, o) -> void:
	o.setup_round()
	if o.caches.size() < 3:
		_fail("vanishing: only %d caches after a second setup" % o.caches.size())
		return
	for other in o.caches:  # the other caches are plain: the pay of the rest is counted below
		other["variant"] = Objective.VARIANT_PLAIN
		other["key"] = false
	var c = o.caches[0]
	c["variant"] = Objective.VARIANT_VANISHING  # force it: what the seed rolls is not the point here
	var p: Vector3 = c["pos"]
	var far = p + Vector3(Objective.VANISH_TRIGGER + 5.0, 0.0, 0.0)
	var near = p + Vector3(Objective.VANISH_TRIGGER - 2.0, 0.0, 0.0)
	# too far: no countdown
	m.player.position = far
	o.update(1.0)
	if c["left"] >= 0.0:
		_fail("vanishing: the countdown started with the player %.0f m away" % o.dist_to(p))
	if Objective.countdown_label(c) != "":
		_fail("vanishing: a label before the countdown started")
	# within range: it starts, and shows the seconds
	m.player.position = near
	o.update(0.5)
	if absf(c["left"] - (Objective.VANISH_TIME - 0.5)) > 0.01:
		_fail(
			(
				"vanishing: after 0.5 s %.2f s were left, wanted %.2f"
				% [c["left"], Objective.VANISH_TIME - 0.5]
			)
		)
	if Objective.countdown_label(c) == "":
		_fail("vanishing: no countdown label while it runs")
	# walking away does not stop it
	m.player.position = far
	o.update(1.0)
	if absf(c["left"] - (Objective.VANISH_TIME - 1.5)) > 0.01:
		_fail("vanishing: walking away changed the countdown (%.2f s left)" % c["left"])
	# it runs out: gone, not taken, nothing paid, off the radar, markers and map
	var cash0 = m.cash
	var score0 = m.score
	o.update(Objective.VANISH_TIME)
	if not c["gone"] or c["taken"] or o.taken != 0:
		_fail(
			(
				"vanishing: at zero gone %s, taken %s, taken count %d"
				% [c["gone"], c["taken"], o.taken]
			)
		)
	if Objective.is_open(c):
		_fail("vanishing: a vanished cache still counts as open")
	if not c["node"].is_queued_for_deletion():
		_fail("vanishing: the crate and the light column were not removed")
	m.player.position = p
	o.update(0.05)
	if m.score != score0 or m.cash != cash0 or o.taken != 0:
		_fail("vanishing: a vanished cache paid out")
	# the others still pay, but taking all that are left does not pay the every-cache bonus
	var paid0 = m.cash
	for i in range(1, o.caches.size()):
		m.player.position = o.caches[i]["pos"]
		o.update(0.05)
	if o.taken != o.caches.size() - 1:
		_fail("vanishing: %d of %d other caches taken" % [o.taken, o.caches.size() - 1])
	if m.cash - paid0 >= o.taken * o.CACHE_CASH + o.ALL_CACHES_CASH:
		_fail("vanishing: the every-cache bonus was paid with a cache gone")
	# a second round: taken in time, it pays like any other cache
	o.setup_round()
	for other in o.caches:
		other["variant"] = Objective.VARIANT_PLAIN
		other["key"] = false
	var c2 = o.caches[0]
	c2["variant"] = Objective.VARIANT_VANISHING
	var p2: Vector3 = c2["pos"]
	m.player.position = p2 + Vector3(Objective.VANISH_TRIGGER - 2.0, 0.0, 0.0)
	o.update(Objective.VANISH_TIME - 1.0)
	if c2["gone"] or c2["left"] <= 0.0:
		_fail("vanishing: gone before its time (%.2f s left)" % c2["left"])
	var score1 = m.score
	m.player.position = p2
	o.update(0.05)
	if not c2["taken"] or m.score <= score1:
		_fail("vanishing: a cache taken in time did not pay")


# Plays the cursed cache on a round that is already set up: `o` is the main's objective_sys.
func _cursed(m, o) -> void:
	o.setup_round()
	var plain = o.caches[0]
	var cursed = o.caches[1]
	plain["variant"] = Objective.VARIANT_PLAIN
	cursed["variant"] = Objective.VARIANT_CURSED
	m.round_n = 2
	var cash0 = m.cash
	var score0 = m.score
	m.player.position = plain["pos"]
	o.update(0.05)
	var plain_cash = m.cash - cash0
	var plain_score = m.score - score0
	if o.curse_pending() != 0:
		_fail("cursed: a plain cache called riders")
	var riders0 = m.riders.size()
	cash0 = m.cash
	score0 = m.score
	m.player.position = cursed["pos"]
	o.update(0.05)
	if not cursed["taken"] or o.taken != 2:
		_fail("cursed: the cache was not taken (taken %d)" % o.taken)
	if m.cash - cash0 < Objective.CURSED_MULT * Objective.CACHE_CASH:
		_fail("cursed: paid %d cash, plain paid %d" % [m.cash - cash0, plain_cash])
	if (
		m.score - score0 < Objective.CURSED_MULT * Objective.CACHE_SCORE
		or m.score - score0 <= plain_score
	):
		_fail("cursed: paid %d score, plain paid %d" % [m.score - score0, plain_score])
	var want = Objective.curse_count(m.round_n)
	if o.curse_pending() != want:
		_fail("cursed: %d riders lined up, wanted %d" % [o.curse_pending(), want])
	if m.riders.size() != riders0:
		_fail("cursed: a rider came out before CURSE_DELAY")
	# they come one after another, not all at once
	m.player.position = o.goal["pos"]
	o.update(Objective.CURSE_DELAY)
	var came = m.riders.size() - riders0
	if came != 1 or o.curse_pending() != want - 1:
		_fail(
			"cursed: %d riders after the delay, wanted 1 (%d pending)" % [came, o.curse_pending()]
		)
	for i in range(want):
		o.update(Objective.CURSE_GAP)
	if o.curse_pending() != 0 or m.riders.size() - riders0 != want:
		_fail(
			(
				"cursed: %d riders came, %d pending, wanted %d and 0"
				% [m.riders.size() - riders0, o.curse_pending(), want]
			)
		)
	if Objective.curse_count(Objective.CURSE_BIG_ROUND) <= Objective.curse_count(1):
		_fail("cursed: a late round does not call more riders")
	# nothing is sent when the round is not being played
	o.setup_round()
	o.caches[0]["variant"] = Objective.VARIANT_CURSED
	m.player.position = o.caches[0]["pos"]
	o.update(0.05)
	var n = m.riders.size()
	m.state = "clear"
	o.update(Objective.CURSE_DELAY + 1.0)
	m.state = "play"
	if m.riders.size() != n or o.curse_pending() != 0:
		_fail("cursed: riders came out of a round that was over")


# `assign_keys` on rolled variants and on made-up ones: every locked cache that is left has its own plain key holder.
func _keys() -> void:
	for s in range(SEEDS):
		var v = Objective.pick_variants(4, _rng(SEED + s))
		var holds = Objective.assign_keys(v)
		var locked = v.count(Objective.VARIANT_LOCKED)
		if holds.count(true) != locked:
			_fail("seed %d: %d locked caches but %d keys" % [s, locked, holds.count(true)])
		for i in range(v.size()):
			if holds[i] and v[i] != Objective.VARIANT_PLAIN:
				_fail("seed %d: cache %d holds a key but is not plain (%s)" % [s, i, v[i]])
	# nothing plain to hold a key: the first locked cache turns plain and then holds the key of the next one
	var all_locked = [Objective.VARIANT_LOCKED, Objective.VARIANT_LOCKED, Objective.VARIANT_LOCKED]
	var h2 = Objective.assign_keys(all_locked)
	if h2.count(true) != all_locked.count(Objective.VARIANT_LOCKED):
		_fail("assign_keys: %s with keys %s, every locked cache needs a key" % [all_locked, h2])
	var mixed = [Objective.VARIANT_LOCKED, Objective.VARIANT_VANISHING, Objective.VARIANT_PLAIN]
	var h3 = Objective.assign_keys(mixed)
	if mixed[0] != Objective.VARIANT_LOCKED or h3 != [false, false, true]:
		_fail("assign_keys: a vanishing cache was chosen to hold a key, or the pair was lost")


# Plays the locked cache on a round that is already set up: `o` is the main's objective_sys.
func _locked(m, o) -> void:
	o.setup_round()
	var lock = o.caches[0]
	var holder = o.caches[1]
	for c in o.caches:
		c["variant"] = Objective.VARIANT_PLAIN
		c["key"] = false
	lock["variant"] = Objective.VARIANT_LOCKED
	holder["key"] = true
	if o.keys != 0:
		_fail("locked: %d keys at the start of a round" % o.keys)
	if o.lock_label(lock) != "LOCKED":
		_fail("locked: label '%s' before a key, wanted LOCKED" % o.lock_label(lock))
	var cash0 = m.cash
	var score0 = m.score
	m.player.position = lock["pos"]
	o.update(0.05)
	if lock["taken"] or o.taken != 0 or m.cash != cash0 or m.score != score0:
		_fail("locked: a cache without a key paid or was taken")
	if lock["warn"] <= 0.0:
		_fail("locked: no reminder at a locked cache")
	# the key
	m.player.position = holder["pos"]
	o.update(0.05)
	if o.keys != 1 or not holder["taken"]:
		_fail("locked: the key cache gave %d keys" % o.keys)
	if o.lock_label(lock) != "OPEN":
		_fail("locked: label '%s' with a key, wanted OPEN" % o.lock_label(lock))
	# the key opens it
	cash0 = m.cash
	score0 = m.score
	m.player.position = lock["pos"]
	o.update(0.05)
	if not lock["taken"] or o.keys != 0:
		_fail("locked: taken %s, %d keys left after opening" % [lock["taken"], o.keys])
	if m.cash - cash0 < Objective.LOCKED_MULT * Objective.CACHE_CASH:
		_fail("locked: paid %d cash" % (m.cash - cash0))
	if m.score - score0 < Objective.LOCKED_MULT * Objective.CACHE_SCORE:
		_fail("locked: paid %d score" % (m.score - score0))
	# a key left over does not carry into the next round
	o.keys = 1
	o.setup_round()
	if o.keys != 0:
		_fail("locked: a key carried into the next round")
	for c in o.caches:
		if c["variant"] == Objective.VARIANT_LOCKED and not o.caches.any(func(k): return k["key"]):
			_fail("locked: a locked cache in the round has no key holder")


func _cell_index(a, p: Vector3) -> int:
	var n = int(a.layout["cells"])
	var cell = float(a.layout["cell"])
	var cx = int(floor(p.x / cell + float(n) / 2.0))
	var cz = int(floor(p.z / cell + float(n) / 2.0))
	if cx < 0 or cz < 0 or cx >= n or cz >= n:
		return -1
	return cz * n + cx


# ------------------------------------------------------------------ the round
func _make_main(generated: bool):
	var m = load("res://main.tscn").instantiate()
	m.generated_arena = generated
	root.add_child(m)
	for i in range(3):
		await process_frame
	return m


func _drop(m) -> void:
	root.remove_child(m)
	m.free()


func _round() -> void:
	var m = await _make_main(false)
	if (
		m.objective_sys.enabled()
		or m.objective_sys.has_goal()
		or not m.objective_sys.caches.is_empty()
	):
		_fail("roundabout: has objectives")
	_drop(m)

	m = await _make_main(true)
	m.start_game(false, SEED)
	for i in range(3):
		await process_frame
	if m.state != "map":
		_fail("a new run did not open the map (state %s)" % m.state)
	else:
		m.pick_node(0)
	var o = m.objective_sys
	if m.state != "play":
		_fail("picking a node did not start the round (state %s)" % m.state)
		_drop(m)
		return
	if not o.enabled() or not o.has_goal():
		_fail("generated round: no extraction point")
		_drop(m)
		return
	if o.extracting:
		_fail("generated round: the extraction point is open before any rider is down")
	if o.caches.size() < 3:
		_fail("generated round: only %d caches" % o.caches.size())
	var first_goal: Vector3 = o.goal["pos"]
	# a cache pays once
	var cash0 = m.cash
	var score0 = m.score
	m.player.position = o.caches[0]["pos"]
	o.update(0.05)
	if o.taken != 1 or m.score <= score0 or m.cash <= cash0:
		_fail(
			(
				"a cache paid nothing (taken %d, score %d to %d, cash %d to %d)"
				% [o.taken, score0, m.score, cash0, m.cash]
			)
		)
	var score1 = m.score
	o.update(0.05)
	if m.score != score1 or o.taken != 1:
		_fail("a cache paid twice")
	# the rest pay the bonus
	for i in range(1, o.caches.size()):
		m.player.position = o.caches[i]["pos"]
		o.update(0.05)
	if o.taken != o.caches.size():
		_fail("not every cache could be taken (%d of %d)" % [o.taken, o.caches.size()])
	if m.score - score1 < o.ALL_CACHES_SCORE:
		_fail("taking every cache did not pay the %d bonus" % o.ALL_CACHES_SCORE)
	# walking onto the locked extraction point does nothing
	m.player.position = first_goal
	o.update(0.05)
	if m.state != "play":
		_fail("the locked extraction point ended the round (state %s)" % m.state)
	# the next round gets a fresh set, the old nodes are gone
	var old_nodes = []
	for c in o.caches:
		old_nodes.append(c["node"])
	m.clear_pickups()
	if o.has_goal() or not o.caches.is_empty():
		_fail("clear_pickups left objectives behind")
	_vanishing(m, o)
	_cursed(m, o)
	_locked(m, o)
	_coins(m, o)
	_drop(m)


# ------------------------------------------------------------------ the rim
func _rim_models() -> void:
	var kit = Models.kit_of(1)
	var pro = Models.build_rider("pro", kit)
	Rim.apply(pro["root"], Rim.FOE)
	if Rim.count(pro["root"]) < 5:
		_fail("a rider got a rim on only %d meshes" % Rim.count(pro["root"]))
	var pal = {
		"shirt": Color.html("#d65a4a"),
		"pants": Color.html("#2d3a52"),
		"hair": Color.html("#2b1d12"),
		"skin": Color.html("#f0c8a0"),
		"bag": Color.html("#c49a5a")
	}
	var civ = Models.build_civ("walker", pal)
	Rim.apply(civ["root"], Rim.FRIEND)
	var cheer = Models.build_cheer(0)
	Rim.apply(cheer["root"], Rim.FRIEND)
	if Rim.count(civ["root"]) < 3 or Rim.count(cheer["root"]) < 3:
		_fail("a pedestrian or cheerleader has too few rim meshes")
	var foe = Rim.material_for(Rim.FOE)
	var friend = Rim.material_for(Rim.FRIEND)
	if (
		foe == friend
		or foe.get_shader_parameter("rim_color") == friend.get_shader_parameter("rim_color")
	):
		_fail("foes and bystanders share a rim colour")
	var c: Color = foe.get_shader_parameter("rim_color")
	var f: Color = friend.get_shader_parameter("rim_color")
	if not (c.r > c.g and c.r > c.b):
		_fail("the foe rim is not red")
	if not (f.g > f.r and f.g > f.b):
		_fail("the bystander rim is not green")
	if _any_overlay(pro["root"], foe) == 0 or _any_overlay(civ["root"], friend) == 0:
		_fail("models have the rim in their meta but not on the overlay")
	Rim.apply(pro["root"], Rim.FOE, false)
	if Rim.count(pro["root"]) != 0 or _any_overlay(pro["root"], foe) != 0:
		_fail("taking the rim off left some behind")
	pro["root"].free()
	civ["root"].free()
	cheer["root"].free()


func _any_overlay(node: Node, mat: Material) -> int:
	var n = 0
	if node is MeshInstance3D and node.material_overlay == mat:
		n += 1
	for ch in node.get_children():
		n += _any_overlay(ch, mat)
	return n


func _rim_in_game() -> void:
	var m = await _make_main(true)
	m.start_game(false, SEED)
	for i in range(3):
		await process_frame
	m.pick_node(0)
	m.rider_sys.spawn_wave()
	for i in range(2):
		await process_frame
	if m.riders.is_empty():
		_fail("no rider was spawned to look at")
		_drop(m)
		return
	var rider_root: Node = m.riders[0]["model"]["root"]
	var foe = Rim.material_for(Rim.FOE)
	var rimmed = Rim.count(rider_root)
	if rimmed == 0 or _any_overlay(rider_root, foe) != rimmed:
		_fail(
			(
				"a spawned rider has no rim (%d meshes, %d on overlay)"
				% [rimmed, _any_overlay(rider_root, foe)]
			)
		)
	# the cheerleaders were built with the green rim
	var green = Rim.material_for(Rim.FRIEND)
	var cheer_rimmed = 0
	for c in m.cheerleaders:
		cheer_rimmed += _any_overlay(c["root"], green)
	if cheer_rimmed == 0:
		_fail("cheerleaders have no rim")
	# the hit flash covers the rim and gives it back
	m.set_flash(rider_root, true)
	if _any_overlay(rider_root, m.flash_mat) == 0 or _any_overlay(rider_root, foe) != 0:
		_fail("the hit flash did not replace the rim")
	m.set_flash(rider_root, false)
	if _any_overlay(rider_root, foe) != rimmed:
		_fail(
			(
				"the rim did not come back after the hit flash (%d of %d)"
				% [_any_overlay(rider_root, foe), rimmed]
			)
		)
	# the setting
	m.set_setting("rim", false)
	if _any_overlay(rider_root, foe) != 0 or m.rim_outline:
		_fail("the RIM GLOW setting did not take the rim off")
	m.set_setting("rim", true)
	if _any_overlay(rider_root, foe) != rimmed:
		_fail("the RIM GLOW setting did not put the rim back")
	# a new rider with the setting off gets none
	m.set_setting("rim", false)
	m.rider_sys.spawn_wave()
	var newest: Node = m.riders[m.riders.size() - 1]["model"]["root"]
	if Rim.count(newest) != 0:
		_fail("a rider spawned with the setting off has a rim")
	m.set_setting("rim", true)
	_drop(m)
