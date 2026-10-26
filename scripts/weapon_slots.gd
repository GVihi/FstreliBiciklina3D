extends RefCounted
# Weapon slots (README Milestone C). The player carries one weapon per slot. This file holds the slots: which
# weapons may sit in each, which one a run starts with, and what the HUD calls them.
# main.gd keeps the weapon that is in a slot in `primary`, `melee_weapon` and `gadget` (ids of data/weapons.json) and every
# script that needs its numbers asks `g.primary_stats()` or `g.melee_stats()`, so a new weapon is a new entry here
# and in the tuning table, not a change in every script that fires, reloads, swings or upgrades. (`melee` in
# main.gd is not the slot: it is true while the melee weapon is the one in the player's hands.)

const PRIMARY = "primary"
const PRIMARY_DEFAULT = "dart_gun"  # what every run starts with
# every weapon that can be in the primary slot, with the name the HUD shows. The Milestone C weapons join here.
# (static vars, not consts, so a check can add a made-up weapon to a slot and take it out again)
static var PRIMARY_WEAPONS = {"dart_gun": "DARTS", "dart_pistol": "PISTOL"}


# true when `id` is a weapon that can be in the primary slot
static func is_primary_weapon(id) -> bool:
	return typeof(id) == TYPE_STRING and PRIMARY_WEAPONS.has(id)


# `id` itself when it can be in the primary slot, otherwise the default (a saved run from an older version, a
# hand-edited file or a weapon that was taken out of the game)
static func primary_or_default(id) -> String:
	return str(id) if is_primary_weapon(id) else PRIMARY_DEFAULT


# the name the HUD shows for a primary weapon (the default's name for an unknown id)
static func label(id) -> String:
	return PRIMARY_WEAPONS[primary_or_default(id)]


# ---- melee slot

const MELEE = "melee"
const MELEE_DEFAULT = "melee"  # the gummy worm, what every run starts with
# every weapon that can be in the melee slot, with the name the HUD shows
static var MELEE_WEAPONS = {"melee": "MELEE"}


# true when `id` is a weapon that can be in the melee slot
static func is_melee_weapon(id) -> bool:
	return typeof(id) == TYPE_STRING and MELEE_WEAPONS.has(id)


# `id` itself when it can be in the melee slot, otherwise the default
static func melee_or_default(id) -> String:
	return str(id) if is_melee_weapon(id) else MELEE_DEFAULT


# the name the HUD shows for a melee weapon (the default's name for an unknown id)
static func melee_label(id) -> String:
	return MELEE_WEAPONS[melee_or_default(id)]


# ---- gadget slot

const GADGET = "gadget"
const NO_GADGET = ""  # an empty slot: what every run starts with, because no gadget exists yet
# every gadget that can be in the gadget slot, with the name the HUD shows. Empty until the Milestone C weapons
# that are gadgets (for example the stink bomb) are built; they join here and in data/weapons.json.
static var GADGET_WEAPONS = {}


# true when `id` is a gadget that can be in the gadget slot (the empty slot is not a gadget)
static func is_gadget(id) -> bool:
	return typeof(id) == TYPE_STRING and GADGET_WEAPONS.has(id)


# `id` itself when it can be in the gadget slot, otherwise an empty slot
static func gadget_or_none(id) -> String:
	return str(id) if is_gadget(id) else NO_GADGET


# the name the HUD shows for a gadget ("" for an empty slot)
static func gadget_label(id) -> String:
	return GADGET_WEAPONS[id] if is_gadget(id) else ""


# ---- all slots together (the Loadout page lists them in this order)

const SLOTS = ["primary", "melee", "gadget"]
const SLOT_NAMES = {"primary": "PRIMARY", "melee": "MELEE", "gadget": "GADGET"}
# the name and text the Loadout page shows for a weapon; a weapon without an entry uses its HUD name and no text
static var WEAPON_INFO = {
	"dart_gun": {"name": "DART GUN", "desc": "THE PUMP-ACTION DART GUN EVERY RUN STARTS WITH"},
	"dart_pistol":
	{
		"name": "DART NERF PISTOL",
		"desc": "ONE DART PER PULL: SMALL CLIP, QUICK HANDS, UPGRADES MAKE IT GOOD"
	},
	"melee":
	{"name": "GUMMY WORM", "desc": "THE GIANT GUMMY WORM: SWING IT AT RIDERS AND INCOMING PHONES"}
}


# the table of the weapons that can be in a slot (id -> HUD name); {} for an unknown slot
static func table_of(slot: String) -> Dictionary:
	match slot:
		PRIMARY:
			return PRIMARY_WEAPONS
		MELEE:
			return MELEE_WEAPONS
		GADGET:
			return GADGET_WEAPONS
	return {}


# the weapon a slot holds when the player has chosen nothing (an empty string for the gadget slot)
static func default_of(slot: String) -> String:
	match slot:
		PRIMARY:
			return PRIMARY_DEFAULT
		MELEE:
			return MELEE_DEFAULT
	return NO_GADGET


# the name the Loadout page shows for a weapon id ("" = an empty gadget slot)
static func display_name(slot: String, id: String) -> String:
	if id == "":
		return "NO GADGET" if slot == GADGET else ""
	if WEAPON_INFO.has(id):
		return str(WEAPON_INFO[id]["name"])
	return str(table_of(slot).get(id, id))


# the text the Loadout page shows under a weapon id
static func display_desc(slot: String, id: String) -> String:
	if id == "":
		return "NO GADGET: THE SLOT STAYS EMPTY" if slot == GADGET else ""
	return str(WEAPON_INFO[id]["desc"]) if WEAPON_INFO.has(id) else ""
