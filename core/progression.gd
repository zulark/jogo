class_name Progression
extends RefCounted

## How operators change. Every function here takes an operator, mutates it, and
## returns a list of plain-English lines describing what happened.
##
## The change log is not decoration. A management game where your people quietly
## improve behind the scenes gives the player nothing to feel; the after-action
## screen has to be able to say "Combat 41 → 46" and "Promoted to Corporal" or
## the entire progression layer is invisible.
##
## No node dependencies and no global state, so the campaign harness exercises
## all of it headlessly.


# --- Rank --------------------------------------------------------------------

## Highest rank this operator's XP entitles them to, respecting the field cap.
static func rank_for_xp(xp: int, track: int) -> int:
	var ceiling: int = (
		GameEnums.Rank.COLONEL if track == GameEnums.CareerTrack.INSTRUCTOR
		else GameEnums.FIELD_RANK_CAP
	)
	var rank: int = GameEnums.Rank.PRIVATE
	for candidate in range(Balance.RANK_XP.size()):
		if candidate > ceiling:
			break
		if xp >= int(Balance.RANK_XP[candidate]):
			rank = candidate
	return rank


static func xp_for_next_rank(op: OperatorData) -> int:
	var next: int = op.rank_step() + 1
	var ceiling: int = (
		GameEnums.Rank.COLONEL if op.career_track == GameEnums.CareerTrack.INSTRUCTOR
		else GameEnums.FIELD_RANK_CAP
	)
	if next > ceiling or next >= Balance.RANK_XP.size():
		return 0
	return int(Balance.RANK_XP[next])


## 0.0-1.0 toward the next rank, or 1.0 when there is nothing left to reach.
static func rank_progress(op: OperatorData) -> float:
	var target := xp_for_next_rank(op)
	if target <= 0:
		return 1.0
	var floor_xp: int = int(Balance.RANK_XP[op.rank_step()])
	var span: int = target - floor_xp
	if span <= 0:
		return 1.0
	return clampf(float(op.xp - floor_xp) / float(span), 0.0, 1.0)


## True when a field career has hit its ceiling and the instructor fork opens.
static func can_become_instructor(op: OperatorData) -> bool:
	return (
		op.career_track == GameEnums.CareerTrack.FIELD
		and op.rank == GameEnums.FIELD_RANK_CAP
		and op.status != GameEnums.OperatorStatus.DEAD
	)


static func promote_if_earned(op: OperatorData) -> Array[String]:
	var log: Array[String] = []
	var earned := rank_for_xp(op.xp, op.career_track)
	while op.rank_step() < earned:
		op.rank = op.rank_step() + 1
		log.append("Promoted to %s" % GameEnums.rank_name(op.rank))
	return log


# --- Skills ------------------------------------------------------------------

## Adds progress to one skill, converting a filled bar into a star. Returns a
## line describing what changed, or "" if nothing did. `ceiling` is how far
## ordinary practice can carry them.
##
## `gain` is a FLOAT and anything under a whole point is BANKED on the operator
## rather than discarded. It used to be rounded to an int at the call site, and
## the effect was far worse than a rounding error. Field gain is
## SKILL_GAIN_BASE * weight * headroom, so 0.5 was the real ceiling and it
## arrived long before SKILL_FIELD_CEILING ever did: a primary skill at weight
## 0.55 froze at 82, a 0.3-weight skill at 67, and anything a contract only
## brushed — a 0.2 weight — stopped dead at 50 and never moved again for the rest
## of that operator's career. All of it was invisible, because a gain that
## rounds to nothing prints nothing, so a plateau the arithmetic imposed read as
## one the operator had earned.
##
## Banking the remainder is deliberately not a random tick. Doing the same work
## twice makes somebody a point better for it, every time, for a reason the
## player can point at.
##
## `reason` must be a NOUN PHRASE naming where the practice came from —
## "infiltration work", "training under Reyes" — never a clause. Both lines below
## put it after a dash, and the first version of this fed it to "mastered %s",
## which shipped "Medical reached 1 star — mastered taught by Reyes".
static func add_skill_progress(
	op: OperatorData,
	skill: int,
	gain: float,
	ceiling: int,
	reason: String
) -> String:
	if gain <= 0.0:
		return ""

	var before: int = op.skill_progress(skill)
	var stars: int = op.stars_in(skill)

	# A filled bar becomes a star and starts again — but only while there is a
	# star left to earn. Five is the end of the road.
	if before >= 100:
		if stars >= Balance.MAX_SKILL_STARS:
			return ""
		op.skill_stars[skill] = stars + 1
		op.skills[skill] = 0
		op.skill_fraction[skill] = 0.0
		return "%s mastered to %s — %s" % [
			GameEnums.skill_name(skill), TextUtil.spelled(stars + 1, "star"), reason]

	# Already at what this kind of practice can teach. Say nothing and bank
	# nothing — otherwise the remainder grows all campaign and pays out the
	# instant a better ceiling (a class, an Academy) raises the bar.
	if before >= ceiling:
		return ""

	var banked: float = float(op.skill_fraction.get(skill, 0.0)) + gain
	var whole: int = int(floor(banked))
	op.skill_fraction[skill] = banked - float(whole)
	if whole <= 0:
		return ""

	var after: int = mini(before + whole, ceiling)
	if after <= before:
		return ""
	op.skills[skill] = after
	return "%s %d to %d — %s" % [GameEnums.skill_name(skill), before, after, reason]


## Operators improve at what the contract tested AND at what their own role
## demanded, with diminishing returns. Every line says why, because
## "Stealth 42 to 45" means nothing without "scouted the approach".
static func grow_skills(
	op: OperatorData,
	profile: MissionProfile,
	success: bool,
	role: int = -1
) -> Array[String]:
	var log: Array[String] = []
	if profile == null:
		return log

	var ratio: float = 1.0 if success else Balance.SKILL_GAIN_FAILURE_RATIO
	var job: String = profile.display_name.to_lower()

	var weights := {}
	for skill in profile.skill_weights:
		weights[skill] = float(profile.skill_weights[skill])

	# What their own role asked of them, on top of what the contract tested.
	var role_weights: Dictionary = RoleProfile.WEIGHTS.get(role, {}) if role >= 0 else {}
	for skill in role_weights:
		weights[skill] = float(weights.get(skill, 0.0)) \
			+ float(role_weights[skill]) * Balance.ROLE_SKILL_GROWTH

	for skill in weights:
		var weight: float = float(weights[skill])
		var before: int = op.skill_progress(skill)
		var headroom: float = 1.0 - float(before) / 100.0
		# Not rounded. add_skill_progress banks whatever is under a point, which
		# is the only reason a lightly-tested skill ever moves at all.
		var gain: float = Balance.SKILL_GAIN_BASE * weight * headroom * ratio

		# "working as scout on infiltration work" was missing its article, and on
		# an assault contract the role and the job are the same word — "working as
		# assault on assault work". Naming the role only when it adds something
		# fixes both.
		var reason: String = "%s work" % job
		if role_weights.has(skill) and GameEnums.role_name(role).to_lower() != job:
			reason = "%s work, as the squad's %s" % [
				job, GameEnums.role_person_name(role)]

		var line := add_skill_progress(
			op, skill, gain, Balance.SKILL_FIELD_CEILING, reason)
		if not line.is_empty():
			log.append(line)

	return log


# --- Traits ------------------------------------------------------------------

## What the contract left behind. Trauma always marks; triumph and disaster only
## sometimes do.
## `scar_relief` is the Psychologist's effect: it lowers the odds a negative
## trait forms. It never removes one that already exists.
static func award_trait(
	op: OperatorData,
	report: MissionReport,
	fate: int,
	rng: RandomNumberGenerator,
	scar_relief: float = 0.0
) -> Array[String]:
	var log: Array[String] = []
	if op.traits.size() >= Balance.MAX_TRAITS:
		return log

	var mission_type: int = report.mission.mission_type
	var softening: float = 1.0 - clampf(scar_relief, 0.0, 0.9)

	if fate == GameEnums.Fate.TRAUMATIZED:
		if rng.randf() < Balance.TRAIT_CHANCE_ON_TRAUMA * softening:
			return _attach(op, TraitLibrary.fear_of(mission_type), log)

	if report.success:
		var margin: float = report.roll_value * 100.0
		var was_comfortable: bool = (report.chance_percent() - margin) >= Balance.TRIUMPH_MARGIN
		if was_comfortable and rng.randf() < Balance.TRAIT_CHANCE_ON_TRIUMPH:
			return _attach(op, TraitLibrary.random_trait(
				rng, GameEnums.TraitPolarity.POSITIVE), log)
		return log

	# Came home from a failure. Unhurt is not the same as unaffected.
	if fate == GameEnums.Fate.UNHARMED \
			and rng.randf() < Balance.TRAIT_CHANCE_ON_DISASTER * softening:
		return _attach(op, TraitLibrary.random_trait(
			rng, GameEnums.TraitPolarity.NEGATIVE), log)

	return log


static func _attach(op: OperatorData, t: TraitData, log: Array[String]) -> Array[String]:
	if t == null or op.has_trait(t.id):
		return log
	op.traits.append(t)
	var verb: String = "Picked up" if t.polarity == GameEnums.TraitPolarity.POSITIVE else "Left with"
	log.append("%s: %s" % [verb, t.display_name])
	return log


# --- The whole after-mission pass --------------------------------------------

## Applied to one operator when their squad comes home. Returns the change log.
static func apply_mission_result(
	op: OperatorData,
	report: MissionReport,
	rng: RandomNumberGenerator,
	scar_relief: float = 0.0
) -> Array[String]:
	var log: Array[String] = []
	var fate: int = report.fates.get(op, GameEnums.Fate.UNHARMED)

	if fate == GameEnums.Fate.KILLED:
		return log

	op.xp += int(report.xp_gained.get(op, 0))

	var profile := MissionResolver.profile_for(report.mission.mission_type)
	log.append_array(grow_skills(op, profile, report.success, report.squad.role_of(op)))
	log.append_array(award_trait(op, report, fate, rng, scar_relief))
	log.append_array(promote_if_earned(op))
	return log


# --- Training ----------------------------------------------------------------

## Can this pairing teach anything? A mentor must outrank the trainee clearly,
## and instructors can teach anyone.
## Nobody teaches upward. An instructor is exempt from the *gap* requirement —
## teaching is their whole job — but not from outranking the trainee, because a
## Lieutenant instructing a Warrant Officer they are junior to is nonsense the
## screen should never offer.
static func can_train(mentor: OperatorData, trainee: OperatorData) -> bool:
	if mentor == trainee:
		return false
	if not mentor.is_deployable() or not trainee.is_deployable():
		return false
	if mentor.rank_step() <= trainee.rank_step():
		return false
	if mentor.career_track == GameEnums.CareerTrack.INSTRUCTOR:
		return true
	return mentor.rank_step() - trainee.rank_step() >= Balance.TRAINING_MIN_RANK_GAP


## The trainee closes part of the gap on every skill the mentor is better at,
## and may inherit one of the mentor's traits — including a bad one. A hard
## veteran teaches their flinches along with their marksmanship.
## `academy` is the Academy's effect: it raises how much of the gap a single
## session closes.
static func apply_training(
	mentor: OperatorData,
	trainee: OperatorData,
	rng: RandomNumberGenerator,
	academy: float = 0.0
) -> Dictionary:
	var trainee_log: Array[String] = []
	var mentor_log: Array[String] = []
	var transfer: float = Balance.TRAINING_TRANSFER * (1.0 + academy)

	for skill in GameEnums.Skill.values():
		var mentor_value: int = mentor.get_skill(skill)
		var before: int = trainee.skill_progress(skill)
		if mentor_value <= before:
			continue

		var gain: float = float(mentor_value - before) * transfer
		var ceiling: int = mini(mentor_value, Balance.TRAINING_SKILL_CEILING)
		var line := add_skill_progress(
			trainee, skill, gain, ceiling,
			"training under %s" % mentor.display_label())
		if not line.is_empty():
			trainee_log.append(line)

	if rng.randf() < Balance.TRAINING_TRAIT_CHANCE and not mentor.traits.is_empty():
		var inherited: TraitData = mentor.traits[rng.randi() % mentor.traits.size()]
		if trainee.traits.size() < Balance.MAX_TRAITS and not trainee.has_trait(inherited.id):
			trainee.traits.append(inherited)
			trainee_log.append("Learned from %s: %s" % [
				mentor.display_label(), inherited.display_name])

	trainee_log.append_array(promote_if_earned(trainee))

	# Teaching is how an instructor's own career advances.
	mentor.xp += Balance.XP_PER_TRAINING
	mentor_log.append_array(promote_if_earned(mentor))

	trainee.trained_by = mentor.display_label()
	if not mentor.trainees.has(trainee.display_label()):
		mentor.trainees.append(trainee.display_label())

	return {"trainee": trainee_log, "mentor": mentor_log}
