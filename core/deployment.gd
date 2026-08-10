class_name Deployment
extends RefCounted

## A squad currently in the field. Created when the player commits to a contract,
## resolved when its last day ticks over.
##
## The preview report is computed at DEPLOY time and kept, so the odds the player
## agreed to are the odds that get rolled. Anything that happens back at base
## while they are away cannot retroactively change the deal.

var mission: MissionData = null
var squad: Squad = null
var days_remaining: int = 0

## The preview taken when the player committed. Rolled on return.
var report: MissionReport = null


static func create(p_mission: MissionData, p_squad: Squad, p_report: MissionReport) -> Deployment:
	var deployment := Deployment.new()
	deployment.mission = p_mission
	deployment.squad = p_squad
	deployment.report = p_report
	deployment.days_remaining = p_mission.duration_days
	return deployment


func to_dict() -> Dictionary:
	var member_ids: Array = []
	var roles: Array = []
	for op in squad.members():
		member_ids.append(String(op.id))
		roles.append(squad.role_of(op))
	return {
		"mission": mission.to_dict(),
		"member_ids": member_ids,
		"roles": roles,
		"leader_id": String(squad.leader.id) if squad.leader else "",
		"days_remaining": days_remaining,
	}


## Rebuilds against the live roster so deployed operators are the SAME objects
## the roster holds, not copies — otherwise applying the report on return would
## mutate orphans and the roster would never see the casualties.
static func from_dict(data: Dictionary, roster: Array[OperatorData]) -> Deployment:
	var by_id := {}
	for op in roster:
		by_id[String(op.id)] = op

	var squad := Squad.new()
	var member_ids: Array = data.get("member_ids", [])
	var roles: Array = data.get("roles", [])
	for i in member_ids.size():
		var op: OperatorData = by_id.get(member_ids[i], null)
		if op != null:
			squad.add(op, int(roles[i]))

	var leader: OperatorData = by_id.get(data.get("leader_id", ""), null)
	if leader != null:
		squad.set_leader(leader)

	var mission := MissionData.from_dict(data.get("mission", {}))
	var deployment := create(mission, squad, MissionResolver.preview(squad, mission))
	deployment.days_remaining = int(data.get("days_remaining", 0))
	return deployment
