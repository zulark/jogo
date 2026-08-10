class_name PersonalityPref
extends Resource

## "This kind of job wants a certain kind of person."
## Attached to a MissionProfile; distance from `ideal` costs score.

@export var axis: GameEnums.PersonalityAxis = GameEnums.PersonalityAxis.AGGRESSION

## The value this mission type rewards, 0-100.
@export_range(0, 100) var ideal: int = 50

## How much the mission cares. 0 = ignore the axis, 1 = full weight.
@export_range(0.0, 1.0, 0.05) var weight: float = 0.5


static func create(p_axis: int, p_ideal: int, p_weight: float) -> PersonalityPref:
	var pref := PersonalityPref.new()
	pref.axis = p_axis
	pref.ideal = p_ideal
	pref.weight = p_weight
	return pref
