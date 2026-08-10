class_name Deployment
extends RefCounted

## A squad currently in the field. Created when the player commits to a contract,
## resolved when its last day ticks over.
##
## The preview report is computed at DEPLOY time and kept, so the odds the player
## agreed to are the odds that get rolled. Anything that happens back at base
## while they are away cannot retroactively change the deal.
##
## The one thing that CAN change it is the player themselves, over the radio —
## see FieldEventLibrary. Those decisions go through the helpers below rather
## than editing the report, because the score has to keep coming from the
## modifier list: a percentage that moved without a line to explain it is the
## one thing this game's odds screen promises never to do.

var mission: MissionData = null
var squad: Squad = null
var days_remaining: int = 0

## The preview taken when the player committed. Rolled on return.
var report: MissionReport = null

## Field event ids already raised on this contract, so the squad never radios in
## with the same situation twice.
var fired_events: Array = []

## Score lines added in the field, kept alongside the report because a save
## rebuilds the report from scratch — see from_dict.
var field_modifiers: Array = []

## Kit the squad picked up out there and is carrying home. Added to storage when
## they land, not before: an item that exists in the warehouse while the people
## holding it are still in a valley is a lie the inventory screen would tell.
var carried_out: Array = []


static func create(p_mission: MissionData, p_squad: Squad, p_report: MissionReport) -> Deployment:
	var deployment := Deployment.new()
	deployment.mission = p_mission
	deployment.squad = p_squad
	deployment.report = p_report
	deployment.days_remaining = p_mission.duration_days
	return deployment


# --- Decisions taken in the field --------------------------------------------

## One line in the breakdown, added while the squad is out.
##
## The odds are not nudged: the line goes on the list and the score is re-derived
## from the list, so the sum invariant that makes the whole odds screen readable
## survives a mid-contract decision.
func apply_modifier(label: String, value: float) -> void:
	report.add_modifier(label, value, GameEnums.ModifierSource.FIELD)
	field_modifiers.append({"label": label, "value": value})
	MissionResolver.recompute(report)


## The job got harder while they were in it. Mission and report move together —
## the mission carries it into the save, the report carries it into the odds.
func raise_difficulty(amount: float) -> void:
	mission.difficulty += amount
	report.difficulty = mission.difficulty
	MissionResolver.recompute(report)


## More dangerous, without being harder. The two are independent everywhere else
## in this game and a field decision is no different: pushing through a storm
## does not make the objective harder to take, it makes the night more likely to
## cost somebody.
func raise_risk(amount: float) -> void:
	mission.risk = clampf(mission.risk + amount, 0.0, 100.0)


## Another day out there. Both counters move: days_remaining is when they land,
## duration_days is what the contract cost them in fatigue when they do.
func extend(days: int) -> void:
	days_remaining += days
	mission.duration_days += days


## Send somebody to the extraction point. They are out of it from here — and it
## costs precisely what they were contributing, taken straight off the
## breakdown rather than estimated.
func pull_out(op: OperatorData) -> float:
	if report.withdrawn.has(op):
		return 0.0
	var worth: float = report.contribution_of(op)
	report.withdrawn.append(op)
	apply_modifier("%s pulled out" % op.display_label(), -worth)
	return worth


## What the squad decided, for the after-action feed.
func note(line: String) -> void:
	report.field_lines.append(line)


func to_dict() -> Dictionary:
	var member_ids: Array = []
	var roles: Array = []
	for op in squad.members():
		member_ids.append(String(op.id))
		roles.append(squad.role_of(op))

	var withdrawn_ids: Array = []
	for op in report.withdrawn:
		withdrawn_ids.append(String(op.id))

	var carried: Array = []
	for id in carried_out:
		carried.append(String(id))

	return {
		"mission": mission.to_dict(),
		"member_ids": member_ids,
		"roles": roles,
		"leader_id": String(squad.leader.id) if squad.leader else "",
		"days_remaining": days_remaining,
		"fired_events": fired_events.duplicate(),
		"field_modifiers": field_modifiers.duplicate(true),
		"field_lines": report.field_lines.duplicate(),
		"withdrawn_ids": withdrawn_ids,
		"carried_out": carried,
	}


## Rebuilds against the live roster so deployed operators are the SAME objects
## the roster holds, not copies — otherwise applying the report on return would
## mutate orphans and the roster would never see the casualties.
##
## The report is re-previewed rather than serialised, so everything that changed
## it after the preview has to be replayed on top: the intel the contract was
## cased with, and every decision taken in the field since.
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
	var intel: float = mission.intel_bonus if mission.scouted else 0.0
	var deployment := create(mission, squad, MissionResolver.preview(squad, mission, intel))
	deployment.days_remaining = int(data.get("days_remaining", 0))

	for id in data.get("fired_events", []):
		deployment.fired_events.append(StringName(str(id)))
	for id in data.get("carried_out", []):
		deployment.carried_out.append(StringName(str(id)))

	var withdrawn_ids: Array = data.get("withdrawn_ids", [])
	for op_id in withdrawn_ids:
		var op: OperatorData = by_id.get(str(op_id), null)
		if op != null:
			deployment.report.withdrawn.append(op)

	# Replayed straight onto the list rather than through apply_modifier, so a
	# reloaded contract carries the exact lines the player was quoted rather than
	# whatever those decisions would be worth against today's squad.
	for entry in data.get("field_modifiers", []):
		var label: String = str(entry.get("label", ""))
		var value: float = float(entry.get("value", 0.0))
		deployment.report.add_modifier(label, value, GameEnums.ModifierSource.FIELD)
		deployment.field_modifiers.append({"label": label, "value": value})
	MissionResolver.recompute(deployment.report)

	for line in data.get("field_lines", []):
		deployment.report.field_lines.append(str(line))

	return deployment
