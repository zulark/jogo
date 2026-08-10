class_name TraitData
extends Resource

## A single positive or negative quirk attached to an operator.
## Authored as .tres files under res://content/traits/ so new traits are content,
## not code.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var polarity: GameEnums.TraitPolarity = GameEnums.TraitPolarity.NEUTRAL

## Flat points added to this operator's contribution to the squad score.
## Negative for drawbacks. Typical range: -12 to +12.
@export var score_modifier: float = 0.0

## Percentage points added to this operator's chance of being harmed.
## A coward is not worse at the job, just likelier to get hurt.
@export var danger_modifier: float = 0.0

## Permanent deltas applied on top of the operator's base skills.
## Keys are GameEnums.Skill, values are integers.
@export var skill_modifiers: Dictionary = {}

## Leave empty for a trait that always applies. Otherwise the trait only fires
## on these GameEnums.MissionType values — this is how "fears infiltration" works.
@export var applies_to_mission_types: Array[int] = []


func applies_to(mission_type: int) -> bool:
	if applies_to_mission_types.is_empty():
		return true
	return mission_type in applies_to_mission_types


func skill_delta(skill: int) -> int:
	return int(skill_modifiers.get(skill, 0))
