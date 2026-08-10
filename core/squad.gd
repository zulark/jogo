class_name Squad
extends RefCounted

## A deployment: which operators are going, what slot each one fills, and who
## is in charge. Built by the squad-builder UI, consumed by MissionResolver.

## OperatorData -> GameEnums.Role
var assignments: Dictionary = {}

var leader: OperatorData = null

var squad_name: String = "Squad"


## An operator's role is part of who they are, not a slot the player assigns per
## contract. Passing a role is still allowed for tests and for the odd case where
## someone is filling in, but the default is simply what they trained as.
func add(op: OperatorData, role: int = -1) -> void:
	assignments[op] = op.preferred_role if role < 0 else role
	if leader == null:
		leader = op


func remove(op: OperatorData) -> void:
	assignments.erase(op)
	if leader == op:
		leader = null if assignments.is_empty() else assignments.keys()[0]


func set_leader(op: OperatorData) -> bool:
	if not assignments.has(op):
		return false
	leader = op
	return true


func members() -> Array:
	return assignments.keys()


func size() -> int:
	return assignments.size()


func role_of(op: OperatorData) -> int:
	return int(assignments.get(op, -1))


func filled_roles() -> Array[int]:
	var roles: Array[int] = []
	for op in assignments:
		var role: int = assignments[op]
		if not role in roles:
			roles.append(role)
	return roles


func has_role(role: int) -> bool:
	return role in filled_roles()


## Why a squad cannot be deployed. Empty array means it is good to go.
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if assignments.is_empty():
		errors.append("Squad is empty.")
	if leader == null:
		errors.append("No leader assigned.")
	elif not assignments.has(leader):
		errors.append("Leader is not a member of the squad.")
	for op in assignments:
		if not op.is_deployable():
			errors.append("%s is not available." % op.display_label())
		elif op.is_exhausted():
			errors.append("%s is spent and cannot be deployed." % op.display_label())
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()


func duplicate_squad() -> Squad:
	var copy := Squad.new()
	copy.squad_name = squad_name
	copy.assignments = assignments.duplicate()
	copy.leader = leader
	return copy
