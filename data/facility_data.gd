class_name FacilityData
extends Resource

## One area of the base. Level 0 means it does not exist yet.
##
## Every facility follows the same shape — a build cost, an upkeep that scales
## with level, and one effect magnitude per level — so the base screen can render
## all eight without knowing what any of them do, and adding a ninth is content
## rather than code.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

## What the effect magnitude means in words, for the base screen.
@export var effect_caption: String = ""

@export var max_level: int = 3

## Cost to reach each level. Index 0 is the cost of level 1.
@export var upgrade_costs: Array[int] = []

## Charged every week, per level. Index 0 is the upkeep at level 1.
@export var upkeep: Array[int] = []

## Effect magnitude at each level. Index 0 is level 1. Meaning depends on the
## facility — see FacilityLibrary for what each one does with it.
@export var effect: Array[float] = []


func cost_to_upgrade(current_level: int) -> int:
	if current_level >= max_level or current_level >= upgrade_costs.size():
		return 0
	return upgrade_costs[current_level]


func upkeep_at(level: int) -> int:
	if level <= 0 or level > upkeep.size():
		return 0
	return upkeep[level - 1]


func effect_at(level: int) -> float:
	if level <= 0 or level > effect.size():
		return 0.0
	return effect[level - 1]


func is_maxed(level: int) -> bool:
	return level >= max_level


## What the next level buys, in this facility's own units.
##
## Effects are stored as raw magnitudes and every one reads differently — a tier
## number, a flat bonus, a percentage saved. It lives here rather than on the
## screen that draws it because two screens draw it now.
func effect_text(level: int) -> String:
	var value := effect_at(level)
	match id:
		FacilityLibrary.ARMOURY, FacilityLibrary.QUARTERMASTER:
			return "tier %d" % int(value)
		FacilityLibrary.WAREHOUSE:
			return "+%d" % int(value)
		FacilityLibrary.CANTEEN:
			return "+%d/wk" % int(value)
		FacilityLibrary.INTELLIGENCE:
			return "+%.1f" % value
		FacilityLibrary.ACADEMY:
			# The Academy raises a number; the two below lower one. Defaulting
			# everything to a minus sign made it read as a penalty.
			return "+%d%%" % int(round(value * 100.0))
		_:
			return "-%d%%" % int(round(value * 100.0))
