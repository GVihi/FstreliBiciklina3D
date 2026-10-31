extends RefCounted
# Weapon slots (README Milestone C). The player carries one weapon per slot. This file holds the slots: which
# weapons may sit in each, which one a run starts with, and what the HUD calls them.
# main.gd keeps the weapon that is in a slot in `primary`, `melee_weapon` and `gadget` (ids of data/weapons.json) and every
# script that needs its numbers asks `g.primary_stats()`, `g.melee_stats()` or `g.gadget_stats()`, so a new weapon is
# not a change in every script that fires, reloads, swings or upgrades. The weapons themselves are not listed here:
# every weapon is an entry of data/weapons.json, whose `info` says which slot it sits in (scripts/weapons.gd reads it),
# and the tables below are built from that file. (`melee` in main.gd is not the slot: it is true while the melee
# weapon is the one in the player's hands.)

const Weapons = preload("res://scripts/weapons.gd")

# what data/weapons.json says about every weapon: {id: {slot, hud, name, desc, sound, model}}, in the order of the file
static var WEAPON_INFO = Weapons.load_info()

const PRIMARY = "primary"
const PRIMARY_DEFAULT = "dart_pistol"  # what every run starts with (the Dart Nerf Pistol, README alpha C1)
# what a saved run without a `primary` field was playing: such a file is older than the weapon slots, and until then
# every run played with the dart gun, so CONTINUE gives that run its dart gun back (docs/SAVE_FILES.md)
const PRIMARY_BEFORE_SLOTS = "dart_gun"
# every weapon that can be in the primary slot, with the name the HUD shows (`slot` "primary" in data/weapons.json)
# (static vars, not consts, so a check can add a made-up weapon to a slot and take it out again)
static var PRIMARY_WEAPONS = Weapons.hud_names(WEAPON_INFO, "primary")


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


# the sound a primary weapon makes when it fires (`sound` in data/weapons.json, a name known to scripts/sfx.gd); a
# weapon that names none, or that is not known, makes the baked "shot"
static func shot_sound(id) -> String:
	if typeof(id) == TYPE_STRING and WEAPON_INFO.has(id) and str(WEAPON_INFO[id]["sound"]) != "":
		return str(WEAPON_INFO[id]["sound"])
	return "shot"


# the key of the first-person model of a weapon (`model` in data/weapons.json, see Models.build_viewmodel); "" for a
# weapon that has none of its own, which is shown with the model of the slot's default weapon
static func model_of(id) -> String:
	if typeof(id) == TYPE_STRING and WEAPON_INFO.has(id):
		return str(WEAPON_INFO[id]["model"])
	return ""


# ---- melee slot

const MELEE = "melee"
const MELEE_DEFAULT = "melee"  # the gummy worm, what every run starts with
# every weapon that can be in the melee slot, with the name the HUD shows (`slot` "melee" in data/weapons.json)
static var MELEE_WEAPONS = Weapons.hud_names(WEAPON_INFO, "melee")


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
const NO_GADGET = ""  # an empty slot: what every run starts with
# every gadget that can be in the gadget slot, with the name the HUD shows (`slot` "gadget" in data/weapons.json).
# Empty until the first gadget (the stink bomb of Milestone C) is built.
static var GADGET_WEAPONS = Weapons.hud_names(WEAPON_INFO, "gadget")


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
