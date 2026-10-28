extends RefCounted
# The one test of README alpha B9: "can this drop, upgrade card, shop item or perk change the next round for what the
# player holds now?". An entry says what it needs with an optional `needs` object (in data/items.json,
# data/perks.json, on a duo, and in DROP_NEEDS of content.gd for the drops); an entry without it always passes.
# Every place that decides what is dropped, offered or sold asks `ok` and nowhere else, so a new rule is added here
# once. The rules read the player's state (`g` is main.gd), not only the weapon: a pistol with three EXTENDED CLIP
# levels holds 4 darts and passes `clip_min` 3, the dart gun holds 6 from the start.
#
#   "clip_min": N     the clip the player holds (`MAXSHELLS`) is at least N darts. Ammo that goes through
#                     `add_shells` stops at the clip, so with a clip of 1 or 2 it can do (almost) nothing
#   "hurt": true      hearts are below the maximum (a heart, PATCH UP)
#   "shop_ahead": true  a shop node is still ahead of the player on the run map: cash only pays there
#   "boss_ahead": true  a boss node is still ahead on the run map: weak spots exist only on bosses
#
# "Ahead" is read from the run map (`main.node_type_ahead`): nodes on later floors that the current node leads to.
# A run without a map (the roundabout) has a shop after every round and bosses in its rounds, so both pass there.
# Format and rules for the data files: data/README.md.

const KEYS = ["clip_min", "hurt", "shop_ahead", "boss_ahead"]


# true when every need of the entry holds (an empty `needs` holds)
static func ok(needs: Dictionary, g) -> bool:
	for key in needs:
		if key == "clip_min":
			if g.MAXSHELLS < int(needs[key]):
				return false
		elif key == "hurt":
			if g.hearts >= g.MAXHEARTS:
				return false
		elif key == "shop_ahead":
			if not g.node_type_ahead("shop"):
				return false
		elif key == "boss_ahead":
			if not g.node_type_ahead("boss"):
				return false
	return true


# Validates the `needs` of a data entry (`who` is the entry's id, for the message). Returns {} when there is none; a
# key that is unknown, or has a value of the wrong kind, is logged and left out, like the other tables do.
static func clean(raw, who: String) -> Dictionary:
	var out = {}
	if raw == null:
		return out
	if typeof(raw) != TYPE_DICTIONARY:
		push_error('needs: %s has "needs" that is not an object: %s' % [who, str(raw)])
		return out
	for key in raw:
		if not KEYS.has(key):
			push_error('needs: %s has unknown need "%s" (known: %s)' % [who, str(key), str(KEYS)])
		elif key == "clip_min":
			var v = raw[key]
			if (typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT) or int(v) < 1:
				push_error('needs: %s "clip_min" must be a whole number of at least 1' % who)
			else:
				out[key] = int(v)
		elif raw[key] != true:
			push_error(
				'needs: %s "%s" must be true (leave it out to not need it)' % [who, str(key)]
			)
		else:
			out[key] = true
	return out
