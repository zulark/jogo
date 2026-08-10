class_name MedalLibrary
extends RefCounted

## What the company hands out, and what it takes to earn it.
##
## Medals are checked after every contract against the operator's whole record,
## so each one is a milestone the player watched happen rather than a reward
## dispensed by a table. They are permanent, they show on the cemetery entry, and
## a couple of them are worth real morale — which is the point: an award is only
## meaningful if the roster reacts to it.

const MEDALS := [
	{
		"id": &"first_blood",
		"name": "First Contact",
		"note": "Their first confirmed kill.",
		"morale": 3,
	},
	{
		"id": &"marksman_cross",
		"name": "Marksman's Cross",
		"note": "Twenty-five confirmed kills.",
		"morale": 8,
	},
	{
		"id": &"iron_tally",
		"name": "Iron Tally",
		"note": "A hundred confirmed kills.",
		"morale": 14,
	},
	{
		"id": &"guardian",
		"name": "Guardian",
		"note": "Pulled five squadmates out alive.",
		"morale": 10,
	},
	{
		"id": &"veteran_service",
		"name": "Long Service",
		"note": "Twenty-five contracts completed for the company.",
		"morale": 10,
	},
	{
		"id": &"survivor",
		"name": "Survivor's Mark",
		"note": "Came home from a contract nobody expected them to.",
		"morale": 12,
	},
	{
		"id": &"assassin",
		"name": "The Quiet Professional",
		"note": "Killed a named target.",
		"morale": 10,
	},
	{
		"id": &"instructor_laurel",
		"name": "Instructor's Laurel",
		"note": "Trained five operators.",
		"morale": 8,
	},
]

static var _cache: Dictionary = {}


static func all() -> Dictionary:
	if _cache.is_empty():
		for entry in MEDALS:
			_cache[entry["id"]] = entry
	return _cache


static func get_medal(id: StringName) -> Dictionary:
	return all().get(id, {})


static func display_name(id: String) -> String:
	return str(get_medal(StringName(id)).get("name", id))


static func note(id: String) -> String:
	return str(get_medal(StringName(id)).get("note", ""))


## Everything this operator has just become eligible for. Awards them, applies
## the morale, and returns the lines for the after-action feed.
##
## `desperate_survival` is passed by the caller because it is a property of the
## contract, not of the operator — surviving a 12% job is the whole medal.
static func award_earned(
	op: OperatorData,
	desperate_survival: bool,
	killed_named_target: bool
) -> Array[String]:
	var earned: Array[String] = []

	var qualifies := {
		&"first_blood": op.confirmed_kills >= 1,
		&"marksman_cross": op.confirmed_kills >= 25,
		&"iron_tally": op.confirmed_kills >= 100,
		&"guardian": op.saves >= 5,
		&"veteran_service": op.missions_completed >= 25,
		&"survivor": desperate_survival,
		&"assassin": killed_named_target,
		&"instructor_laurel": op.trainees.size() >= 5,
	}

	for id in qualifies:
		if not qualifies[id]:
			continue
		if op.medals.has(String(id)):
			continue
		op.medals.append(String(id))
		var medal := get_medal(id)
		op.morale = mini(100, op.morale + int(medal.get("morale", 0)))
		earned.append("Awarded the %s — %s" % [medal["name"], medal["note"]])

	return earned
