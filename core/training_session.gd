class_name TrainingSession
extends RefCounted

## A mentor and a trainee, both off the board for the duration.
##
## Structurally a Deployment for the academy: it occupies days, it occupies
## people, and it resolves when its last day ticks over. Costing the company two
## operators at once is what makes training a decision rather than free upside.

var mentor: OperatorData = null
var trainee: OperatorData = null
var days_remaining: int = 0
var total_days: int = 0


static func create(
	p_mentor: OperatorData,
	p_trainee: OperatorData,
	days: int = Balance.TRAINING_DAYS
) -> TrainingSession:
	var session := TrainingSession.new()
	session.mentor = p_mentor
	session.trainee = p_trainee
	session.days_remaining = days
	session.total_days = days
	return session


func to_dict() -> Dictionary:
	return {
		"mentor_id": String(mentor.id),
		"trainee_id": String(trainee.id),
		"days_remaining": days_remaining,
		"total_days": total_days,
	}


## Binds against the live roster, so the people who come back out of a save are
## the same objects the roster holds rather than copies nothing else can see.
static func from_dict(data: Dictionary, roster: Array[OperatorData]) -> TrainingSession:
	var by_id := {}
	for op in roster:
		by_id[String(op.id)] = op

	var mentor: OperatorData = by_id.get(data.get("mentor_id", ""), null)
	var trainee: OperatorData = by_id.get(data.get("trainee_id", ""), null)
	if mentor == null or trainee == null:
		return null

	var session := create(mentor, trainee, int(data.get("total_days", Balance.TRAINING_DAYS)))
	session.days_remaining = int(data.get("days_remaining", 0))
	return session
