class_name Ovr
extends RefCounted

## Capability as a single figure — what lets a player compare two operators, or
## two squads, without reading thirty skill bars.
##
## TWO FIGURES, AND THE GAP BETWEEN THEM IS THE POINT.
##
##   OVERALL     what somebody is worth averaged across every kind of work the
##               board offers. One number for "is this person any good".
##   ON THIS JOB what they are worth on ONE kind of work. The same arithmetic
##               against one mission profile instead of all seven.
##
## A specialist and a generalist can hold the same overall rating and be nothing
## alike. Reading the overall alone and sending the highest numbers is exactly
## the mistake this exists to make visible: an engineer who rates 61 overall
## rates 44 on assault work and 78 on sabotage, and the contract says which one
## it is. That is the whole of roadmap2 V1 §2 — the player is rewarded for
## understanding what an operation asks for rather than for sorting a column.
##
## NOTHING HERE IS A SECOND OPINION. `rating()` is the formula and
## MissionResolver's per-operator skill term calls it, so the figure printed
## beside a name in the squad builder is not an estimate of that operator's line
## in the breakdown — it IS that line, before the share it gets paid at. Two
## copies of one formula is one copy too many; the breakdown and the rating
## cannot drift because there is nothing to drift from.
##
## IT IS NOT THE ODDS, AND CANNOT BE TURNED BACK INTO THEM. A rating reads
## SKILLS ONLY — through `get_skill()`, so what somebody is carrying counts, the
## same as it does on their sheet. Rank, temperament, a trait's flat score, kit's
## flat edge, fatigue, morale, bonds, the ground, the client, the leader and
## squad size are all in the squad score and none of them are in here. So a
## rating cannot be subtracted from a difficulty to recover the percentage v0.17
## took off the screen. It answers "can these people do this kind of work",
## which is a different question from "will this contract go well", and the game
## is better for asking both.


## What one operator is worth on one kind of work.
##
## THE FORMULA. The only copy of it — see the class note above.
static func rating(op: OperatorData, role: int, profile: MissionProfile) -> float:
	return (
		Balance.MISSION_SKILL_WEIGHT * profile.skill_match(op)
		+ Balance.ROLE_SKILL_WEIGHT * RoleProfile.score(op, role, profile.mission_type)
	)


## The same, named by mission type, in the role they actually trained for.
##
## Role is not a parameter here on purpose. An operator's role is part of who
## they are rather than a slot the player reassigns per contract — see Squad.add
## — so the rating on a list row is what they would really be worth if sent.
static func on_type(op: OperatorData, mission_type: int) -> int:
	var profile := MissionResolver.profile_for(mission_type)
	if profile == null:
		return 0
	return int(round(rating(op, op.preferred_role, profile)))


## What they are worth across everything the board offers.
##
## The MEAN of their local ratings rather than a formula of its own. Deriving it
## means an overall rating can never say something the seven local ones do not
## already say, and it means the two figures move together when a skill does.
static func overall(op: OperatorData) -> int:
	var total := 0.0
	var count := 0
	for mission_type in GameEnums.MissionType.values():
		var profile := MissionResolver.profile_for(mission_type)
		if profile == null:
			continue
		total += rating(op, op.preferred_role, profile)
		count += 1
	if count == 0:
		return 0
	return int(round(total / float(count)))


## Every kind of work, best first, with what this operator rates on it.
## `[{ "type": MissionType, "rating": int }]` — the roster sheet draws this as a
## column of bars, which is where a player learns what their own people are for.
static func ranked_work(op: OperatorData) -> Array:
	var ranked: Array = []
	for mission_type in GameEnums.MissionType.values():
		ranked.append({"type": mission_type, "rating": on_type(op, mission_type)})
	ranked.sort_custom(func(a, b): return a["rating"] > b["rating"])
	return ranked


## What a whole squad is worth on this job.
##
## Weighted exactly the way MissionResolver.preview() pays its people: best
## first, each further body on a decaying share, over a denominator fixed to the
## size the job is designed around. So this figure is the sum of the skill lines
## in the breakdown, and turning up short reads as a lower rating rather than
## needing a penalty bolted on beside it.
##
## NOT ON ANY SCREEN, and that is a decision rather than an omission. It is a
## weighted SUM over a fixed denominator, so an over-strength squad rates past
## 100 — true, and unreadable next to bars that stop there. The briefing shows
## the per-skill averages instead, and SQUAD SCORE already answers the question
## an aggregate would. What this is for is the harness check that the per-
## operator ratings on screen really are the resolver's own arithmetic: if this
## ever stops equalling the breakdown's skill lines, every rating in the game is
## quoting a formula the simulation does not use.
static func squad_rating(squad: Squad, profile: MissionProfile) -> float:
	if squad == null:
		return 0.0
	var scored: Array = []
	for op in squad.members():
		scored.append(rating(op, squad.role_of(op), profile))
	scored.sort_custom(func(a, b): return a > b)

	var denominator: float = profile.contribution_denominator()
	var total := 0.0
	for index in scored.size():
		total += float(scored[index]) * pow(Balance.SQUAD_CONTRIBUTION_DECAY, index) / denominator
	return total


# --- What a job asks for -----------------------------------------------------

## How much of the heaviest weight a skill has to carry before it counts as
## something the job is PRIMARILY about.
##
## Derived from the profile rather than listed by hand, so a profile that gets
## retuned can never end up labelled in a way its own weights contradict. On the
## built-in seven it reads assassination as combat and stealth primary with tech
## behind them, and rescue as three things tested about equally — which is what
## those two jobs are.
const PRIMARY_SHARE := 0.5


## What this kind of work tests, heaviest first.
## `[{ "skill": Skill, "weight": float, "primary": bool }]`.
static func emphasis(profile: MissionProfile) -> Array:
	var ranked: Array = []
	var top := 0.0
	for skill in profile.skill_weights:
		var weight := float(profile.skill_weights[skill])
		if weight <= 0.0:
			continue
		top = maxf(top, weight)
		ranked.append({"skill": skill, "weight": weight})
	ranked.sort_custom(func(a, b): return a["weight"] > b["weight"])

	for entry in ranked:
		entry["primary"] = float(entry["weight"]) >= top * PRIMARY_SHARE
	return ranked


## What a group of people brings in one skill, as a plain average.
##
## Deliberately NOT the decayed weighting `squad_rating()` uses, and this is the
## figure that reaches the screen. A rating answers "what is this squad worth on
## this job", where an extra body can only help; this answers "where is this
## squad thin", where an extra weak body genuinely does thin them out — which is
## the question a bar per skill is being asked. The resolver's own region term
## measures a squad the same way, so it is not a shape invented for a readout.
static func group_average(members: Array, skill: int, mission_type: int = -1) -> int:
	if members.is_empty():
		return 0
	var total := 0.0
	for op in members:
		total += float(op.get_skill(skill, mission_type))
	return int(round(total / float(members.size())))


## How many people the job is built around, and what bringing more costs.
##
## One sentence pair, in one place, because the contract panel and the briefing
## both state it and two hand-built versions of the same fact drift. Read off
## `ideal_squad_size`, `size_tolerance` and `oversize_penalty` — nothing here is
## a judgement about a profile, it is the profile read out loud.
##
## The second sentence is the whole of roadmap2 §2's "Penalty: Large squad",
## stated before the player assembles a squad rather than discovered by watching
## a score fall. `oversize_penalty` runs from 2 on assault work, where numbers
## barely matter, to 12 on an assassination, where a crowd is the failure.
const OVERSIZE_SEVERE := 7.0
const OVERSIZE_MODERATE := 3.5


## Kept short deliberately. This lands on the briefing panel, where it has one
## line and a second one costs height the panel does not have — see the layout
## note in ui/mission_briefing.gd.
static func _oversize_note(profile: MissionProfile) -> String:
	if profile.oversize_penalty >= OVERSIZE_SEVERE:
		return "Past that, a crowd gets people killed."
	if profile.oversize_penalty >= OVERSIZE_MODERATE:
		return "Past that, extra bodies get in the way."
	return "Past that, extra bodies cost very little."


static func size_note(profile: MissionProfile) -> String:
	var low: int = maxi(1, profile.ideal_squad_size - profile.size_tolerance)
	var high: int = profile.ideal_squad_size + profile.size_tolerance
	var wants: String = "Wants %s" % TextUtil.count(
		profile.ideal_squad_size, "person", "people")
	if high > low:
		wants += ", and anything from %d to %d costs nothing" % [low, high]
	return "%s. %s" % [wants, _oversize_note(profile)]
