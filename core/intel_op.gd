class_name IntelOp
extends RefCounted

## A team sent to case a contract before the squad goes in.
##
## There are two ways to know what you are walking into. `Campaign.scout()` is
## the desk answer: the Intelligence Centre buys a look, instantly arranged and
## only as good as the facility. This is the other one — people on the ground,
## tied up for days, coming back with something the desk could not get.
##
## The trade is deliberate. Intel costs no money and a great deal of time, and
## the people who are best at it (scouts, engineers) are often the people the
## squad wanted. Casing a hard job properly means going in short-handed or going
## in late, and the board keeps expiring either way.

var mission: MissionData = null
var operators: Array[OperatorData] = []
var days_remaining: int = 0


static func create(
	p_mission: MissionData,
	p_operators: Array[OperatorData],
	p_days: int
) -> IntelOp:
	var op := IntelOp.new()
	op.mission = p_mission
	op.operators = p_operators.duplicate()
	op.days_remaining = maxi(1, p_days)
	return op


## How good this team is at casing a place, 0–100.
##
## Stealth leads and tech follows, because the work is getting close without
## being seen and then reading what you find. A second operator adds a fraction
## of a share rather than averaging in — two mediocre scouts should not out-read
## one excellent one, but they should beat them working alone.
static func rating_of(members: Array) -> float:
	if members.is_empty():
		return 0.0

	var best := 0.0
	var total := 0.0
	for op: OperatorData in members:
		var value: float = (
			float(op.get_skill(GameEnums.Skill.STEALTH)) * Balance.INTEL_STEALTH_WEIGHT
			+ float(op.get_skill(GameEnums.Skill.TECH))
				* (1.0 - Balance.INTEL_STEALTH_WEIGHT))
		best = maxf(best, value)
		total += value

	var partners: float = total - best
	return clampf(best + partners * Balance.INTEL_PARTNER_BONUS, 0.0, 100.0)


func team_rating() -> float:
	return rating_of(operators)


## Days this team needs. Sharp people work faster, and so does a good facility.
static func days_for(members: Array, facility_level: int) -> int:
	var days: int = Balance.INTEL_BASE_DAYS - maxi(0, facility_level)
	if rating_of(members) >= 70.0:
		days -= 1
	if members.size() >= 2:
		days -= 1
	return maxi(1, days)


## What the team brings home, and what it cost them.
##
## Returns the log the after-action and the day feed read from; the caller is
## responsible for putting the operators back on the roster.
func resolve(state: GameState, rng: RandomNumberGenerator) -> Dictionary:
	var rating := team_rating()
	var bonus: float = Balance.INTEL_TEAM_MAX_BONUS * (rating / 100.0)

	# The facility is analysis, not legwork: it multiplies what the team brings
	# back rather than replacing it, so an Intelligence Centre stays worth
	# building and stays worthless on its own.
	bonus += state.facility_effect(FacilityLibrary.INTELLIGENCE) * Balance.SCOUT_BONUS_FACTOR
	bonus = minf(bonus, Balance.INTEL_BONUS_CEILING)

	# Getting noticed is the risk. A sharp team on a quiet job almost never is;
	# a poor team on a dangerous one regularly is, and the ground goes alert.
	var mishap_odds: float = clampf(
		Balance.INTEL_MISHAP_BASE
			+ mission.risk / 600.0
			- rating / 400.0,
		0.0, 0.35)
	var noticed: bool = rng.randf() < mishap_odds

	var lines: Array[String] = []
	var names: Array = []
	for op in operators:
		names.append(op.display_label())

	if noticed:
		# Still scouted — they saw the place. It is just alert now, and the
		# intel is worth less because half of what they learned has changed.
		bonus *= 0.5
		mission.difficulty += Balance.INTEL_MISHAP_DIFFICULTY
		lines.append("%s were spotted casing %s. The ground is alert." % [
			TextUtil.join_names(names), mission.region_name()])
	else:
		lines.append("%s cased %s without being seen." % [
			TextUtil.join_names(names), mission.title])

	mission.scouted = true
	mission.intel_bonus = maxf(mission.intel_bonus, bonus)

	for op in operators:
		op.xp += Balance.INTEL_XP
		op.fatigue = clampi(
			op.fatigue + days_spent() * Balance.INTEL_FATIGUE_PER_DAY, 0, 100)
		if noticed:
			op.morale = maxi(0, op.morale - 6)
		for line in Progression.promote_if_earned(op):
			lines.append(line)

	lines.append("%s is worth %+.1f to any squad sent in." % [mission.title, bonus])

	return {
		"mission": mission,
		"bonus": bonus,
		"noticed": noticed,
		"lines": lines,
	}


## Fatigue is charged for the whole job, so a longer case costs more rest.
func days_spent() -> int:
	return maxi(1, IntelOp.days_for(operators, 0))


func to_dict() -> Dictionary:
	var ids: Array = []
	for op in operators:
		ids.append(String(op.id))
	return {
		"mission_id": String(mission.id),
		"operator_ids": ids,
		"days_remaining": days_remaining,
	}


## Re-links to the live board rather than rebuilding a mission of its own.
##
## An IntelOp mutates the contract it finishes — scouted, intel_bonus, and the
## difficulty if the team is spotted. Deserialising a private copy would apply
## all of that to an object no squad can ever be sent against. Returns null if
## the contract expired while the team was out, which is a real outcome and not
## an error: the operators are freed and the work is wasted.
static func from_dict(data: Dictionary, roster: Array, board: Array) -> IntelOp:
	var wanted_id := String(data.get("mission_id", ""))
	var found: MissionData = null
	for mission: MissionData in board:
		if String(mission.id) == wanted_id:
			found = mission
			break
	if found == null:
		return null

	var op := IntelOp.new()
	op.mission = found
	op.days_remaining = int(data.get("days_remaining", 1))

	var wanted: Array = data.get("operator_ids", [])
	for member in roster:
		if wanted.has(String(member.id)):
			op.operators.append(member)
	return op
