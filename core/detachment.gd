class_name Detachment
extends RefCounted

## One operator away on standing work. The counterpart to Deployment, and
## deliberately much thinner: there is no squad, no briefing and no dice worth
## showing — it resolves itself and reports a number.

var job: SideJobData = null
var operator: OperatorData = null
var days_remaining: int = 0


static func create(p_job: SideJobData, p_operator: OperatorData) -> Detachment:
	var detachment := Detachment.new()
	detachment.job = p_job
	detachment.operator = p_operator
	detachment.days_remaining = p_job.duration_days
	return detachment


## Auto-resolution. Pay scales with how suited the person sent was, floored so
## that even a poor fit earns something — the point is utility for the bench,
## not another way to lose money.
func resolve(rng: RandomNumberGenerator) -> Dictionary:
	var suitability := job.suitability(operator)
	var margin: float = (suitability - job.expectation) / 50.0
	var quality: float = clampf(0.55 + margin * 0.45, Balance.SIDE_JOB_MIN_RATIO, 1.35)

	var pay := int(round(float(job.base_pay) * quality))
	var xp := int(round(float(Balance.SIDE_JOB_XP) * clampf(quality, 0.5, 1.2)))

	operator.xp += xp
	operator.fatigue = clampi(
		operator.fatigue + job.duration_days * Balance.SIDE_JOB_FATIGUE_PER_DAY, 0, 100)

	# Dull work is not risk-free work, but it is close. A badly matched operator
	# is the one who gets hurt.
	var mishap := false
	var mishap_odds: float = clampf(
		Balance.SIDE_JOB_MISHAP_BASE - margin * 0.06, 0.0, 0.25)
	if rng.randf() < mishap_odds:
		mishap = true
		operator.status = GameEnums.OperatorStatus.INJURED
		operator.days_unavailable = rng.randi_range(2, 5)
		operator.morale = maxi(0, operator.morale - 5)

	var log: Array[String] = Progression.promote_if_earned(operator)

	return {
		"pay": pay,
		"xp": xp,
		"mishap": mishap,
		"promotions": log,
	}


func to_dict() -> Dictionary:
	return {
		"job": job.to_dict(),
		"operator_id": String(operator.id),
		"days_remaining": days_remaining,
	}


static func from_dict(data: Dictionary, roster: Array[OperatorData]) -> Detachment:
	var operator: OperatorData = null
	for op in roster:
		if String(op.id) == data.get("operator_id", ""):
			operator = op
			break
	if operator == null:
		return null

	var detachment := create(SideJobData.from_dict(data.get("job", {})), operator)
	detachment.days_remaining = int(data.get("days_remaining", 0))
	return detachment
