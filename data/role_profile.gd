class_name RoleProfile
extends RefCounted

## What each squad role is actually good for. Used to score "is this operator
## a sensible fit for the slot you put them in", independent of the mission.
##
## Kept in code rather than .tres because roles are structural: adding one means
## adding an enum value and touching the squad UI anyway.

## Role -> { Skill: weight }. Weights per role sum to 1.0.
const WEIGHTS := {
	GameEnums.Role.ASSAULT: {
		GameEnums.Skill.COMBAT: 0.65,
		GameEnums.Skill.ENDURANCE: 0.25,
		GameEnums.Skill.LEADERSHIP: 0.10,
	},
	GameEnums.Role.MARKSMAN: {
		GameEnums.Skill.COMBAT: 0.70,
		GameEnums.Skill.STEALTH: 0.20,
		GameEnums.Skill.ENDURANCE: 0.10,
	},
	GameEnums.Role.MEDIC: {
		GameEnums.Skill.MEDICAL: 0.70,
		GameEnums.Skill.ENDURANCE: 0.20,
		GameEnums.Skill.COMBAT: 0.10,
	},
	GameEnums.Role.SCOUT: {
		GameEnums.Skill.STEALTH: 0.65,
		GameEnums.Skill.ENDURANCE: 0.20,
		GameEnums.Skill.TECH: 0.15,
	},
	GameEnums.Role.ENGINEER: {
		GameEnums.Skill.TECH: 0.70,
		GameEnums.Skill.STEALTH: 0.15,
		GameEnums.Skill.COMBAT: 0.15,
	},
}


## 0-100. How well this operator's skills serve the role they were assigned.
static func score(op: OperatorData, role: int, mission_type: int) -> float:
	var weights: Dictionary = WEIGHTS.get(role, {})
	var total := 0.0
	for skill in weights:
		total += float(op.get_skill(skill, mission_type)) * float(weights[skill])
	return total


## The single skill that matters most for a role — used by UI to show
## "Marksman: Combat 78" without dumping the whole weight table.
static func key_skill(role: int) -> int:
	var weights: Dictionary = WEIGHTS.get(role, {})
	var best := -1
	var best_weight := -1.0
	for skill in weights:
		if float(weights[skill]) > best_weight:
			best_weight = float(weights[skill])
			best = skill
	return best
