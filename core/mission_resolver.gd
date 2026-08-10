class_name MissionResolver
extends RefCounted

## The core of the game. Scores a squad against a mission, turns that into a
## success percentage, and rolls the outcome.
##
## Deliberately has no node dependencies and no global state: give it a Squad
## and a MissionData and it hands back a MissionReport. That is what lets the
## simulation harness run 5000 missions headlessly in a second, and what stops
## the UI from ever having to know the formula.
##
## THE FORMULA
##   Each operator contributes:
##       0.6 * (how well their skills match what this MISSION TYPE tests)
##     + 0.4 * (how well their skills match the ROLE you assigned them)
##     + rank bonus
##     - personality mismatch cost
##     + trait modifiers
##   Those contributions are averaged, then the squad-level terms are applied:
##     + leader's leadership
##     - squad size deviation from the mission's ideal
##     - missing required roles
##   The result is the squad score. The gap between it and mission.difficulty
##   is fed through a logistic curve to get the success chance, which is clamped
##   so nothing is ever a sure thing.
##
## Every one of those steps appends a Modifier to the report, and the modifiers
## sum exactly to the squad score. If they ever stop summing, the breakdown is
## lying to the player and that is a bug.

static var _profiles: Dictionary = {}


## MissionType -> MissionProfile. Built from code defaults on first use.
static func profiles() -> Dictionary:
	if _profiles.is_empty():
		_profiles = MissionProfile.defaults()
	return _profiles


## Swap in profiles loaded from .tres (v0.2) or tweaked ones for a balance test.
static func set_profiles(new_profiles: Dictionary) -> void:
	_profiles = new_profiles


static func profile_for(mission_type: int) -> MissionProfile:
	return profiles().get(mission_type, null)


## Score the squad and compute the odds WITHOUT rolling. Safe to call every time
## the player changes the squad — this is what feeds the live percentage in the UI.
## `intel_bonus` is whatever the Intelligence Centre is worth — passed in rather
## than read from a global, so the resolver stays a pure function of the squad
## and the contract. Campaign.preview_mission() is the caller that knows it.
static func preview(squad: Squad, mission: MissionData, intel_bonus: float = 0.0) -> MissionReport:
	var report := MissionReport.new()
	report.mission = mission
	report.squad = squad
	report.difficulty = mission.difficulty

	var profile := profile_for(mission.mission_type)
	if profile == null:
		push_error("No MissionProfile registered for type %d" % mission.mission_type)
		return report

	var count := squad.size()
	if count == 0:
		report.success_chance = Balance.MIN_SUCCESS
		return report

	var mission_type: int = mission.mission_type

	# --- Per-operator terms -------------------------------------------------
	# Two passes. First work out what each operator is worth on this job, then
	# sort best-first and pay them out on a decaying weight. The player's best
	# person carries the contract and each additional body helps a little less,
	# which is both how it works in reality and the only arrangement where
	# bringing someone can never lower the odds.
	var scored: Array = []
	for op in squad.members():
		scored.append({"op": op, "raw": _raw_contribution(op, squad.role_of(op), profile)})
	scored.sort_custom(func(a, b): return a["raw"] > b["raw"])

	var denominator: float = profile.contribution_denominator()

	for index in scored.size():
		var op: OperatorData = scored[index]["op"]
		var role: int = squad.role_of(op)
		var share: float = pow(Balance.SQUAD_CONTRIBUTION_DECAY, index) / denominator

		# The name goes on the group heading, not on every line beneath it.
		report.operator_labels[op.id] = "%s  ·  %s  ·  %s" % [
			op.display_label(),
			GameEnums.role_name(role),
			op.demonym(),
		]

		var mission_skill: float = profile.skill_match(op)
		var role_skill: float = RoleProfile.score(op, role, mission_type)
		var base: float = (
			Balance.MISSION_SKILL_WEIGHT * mission_skill
			+ Balance.ROLE_SKILL_WEIGHT * role_skill
		)
		report.add_modifier(
			"Skills for %s work" % profile.display_name.to_lower(),
			base * share,
			GameEnums.ModifierSource.SKILL,
			op.id
		)

		var rank_bonus: float = float(op.rank_step()) * Balance.RANK_BONUS_PER_STEP
		if rank_bonus > 0.0:
			report.add_modifier(
				"Rank: %s" % GameEnums.rank_name(op.rank),
				rank_bonus * share,
				GameEnums.ModifierSource.ROLE_FIT,
				op.id
			)

		var personality: float = profile.personality_cost(op)
		if not is_zero_approx(personality):
			report.add_modifier(
				"Temperament",
				personality * share,
				GameEnums.ModifierSource.PERSONALITY,
				op.id
			)

		for t in op.active_traits(mission_type):
			if is_zero_approx(t.score_modifier):
				continue
			report.add_modifier(
				"Trait: %s" % t.display_name,
				t.score_modifier * share,
				GameEnums.ModifierSource.TRAIT,
				op.id
			)

		# Kit. Skill deltas are already baked into get_skill above; this is the
		# flat edge a good weapon gives on top of what it teaches the hands.
		var kit: float = op.equipment_score()
		if not is_zero_approx(kit):
			var kit_names: PackedStringArray = []
			for item in op.equipment():
				kit_names.append(item.display_name)
			report.add_modifier(
				"Kit: %s" % ", ".join(kit_names),
				kit * share,
				GameEnums.ModifierSource.CONDITION,
				op.id
			)

		# Condition. Fatigue is the rotation pressure: sending the same four
		# people out again is worse than sending a rested rookie eventually.
		var fatigue_cost: float = -Balance.FATIGUE_PENALTY_MAX * (float(op.fatigue) / 100.0)
		if fatigue_cost < -0.05:
			report.add_modifier(
				"Fatigue %d%%" % op.fatigue,
				fatigue_cost * share,
				GameEnums.ModifierSource.CONDITION,
				op.id
			)

		var morale_effect: float = _morale_effect(op.morale)
		if absf(morale_effect) > 0.05:
			report.add_modifier(
				"Morale %d%%" % op.morale,
				morale_effect * share,
				GameEnums.ModifierSource.CONDITION,
				op.id
			)

	# --- Squad-level terms --------------------------------------------------
	if squad.leader != null:
		var leadership: float = float(squad.leader.get_skill(GameEnums.Skill.LEADERSHIP, mission_type))
		report.add_modifier(
			"Led by %s" % squad.leader.display_label(),
			leadership * Balance.LEADER_FACTOR,
			GameEnums.ModifierSource.LEADERSHIP
		)

	_apply_hazard_terms(report, squad, mission)
	_apply_bond_terms(report, squad)
	_apply_region_terms(report, squad, mission)
	_apply_client_terms(report, squad, mission)

	if intel_bonus > 0.0:
		report.add_modifier(
			"Scouted by the Intelligence Centre",
			intel_bonus,
			GameEnums.ModifierSource.COMPOSITION
		)

	# Being short-handed needs no penalty: the fixed denominator above already
	# means fewer people divide into the same number. This only says so out loud,
	# because "you are three short of what this wants" is actionable and a
	# quietly smaller score is not.
	if count < profile.ideal_squad_size:
		report.add_modifier(
			"Short-handed: %d here, %s work wants %d" % [
				count, profile.display_name.to_lower(), profile.ideal_squad_size],
			0.0,
			GameEnums.ModifierSource.SQUAD_SIZE
		)

	var size_cost: float = profile.size_cost(count)
	if not is_zero_approx(size_cost):
		var size_label: String = "Too many for %s work (ideal %d)" % [
			profile.display_name.to_lower(), profile.ideal_squad_size]
		report.add_modifier(size_label, size_cost, GameEnums.ModifierSource.SQUAD_SIZE)

	for role in profile.missing_roles(squad.filled_roles()):
		report.add_modifier(
			"No %s in squad" % GameEnums.role_name(role),
			-profile.missing_role_penalty,
			GameEnums.ModifierSource.COMPOSITION
		)

	# --- Odds ---------------------------------------------------------------
	var total := 0.0
	for m in report.modifiers:
		total += m.value
	report.squad_score = total

	var delta: float = report.squad_score - report.difficulty
	var raw: float = 1.0 / (1.0 + exp(-delta / Balance.SPREAD))
	report.success_chance = clampf(raw, Balance.MIN_SUCCESS, Balance.MAX_SUCCESS)

	return report


## The ground trying to kill people who came unprepared. Unlike the emphasis
## skill, this is a problem money solves: the right kit cancels it outright, so
## a hazardous region is an invoice rather than a wall.
static func _apply_hazard_terms(
	report: MissionReport,
	squad: Squad,
	mission: MissionData
) -> void:
	var region := mission.region()
	if region == null or region.hazard == GameEnums.Hazard.NONE:
		return

	var uncovered: Array = []
	for op in squad.members():
		var covered := false
		for item in op.equipment():
			if item.counters(region.hazard):
				covered = true
				break
		if not covered:
			uncovered.append(op)

	if uncovered.is_empty():
		report.add_modifier(
			"%s handled: everyone is equipped for it" % GameEnums.hazard_name(region.hazard),
			0.0,
			GameEnums.ModifierSource.CONDITION
		)
		return

	report.add_modifier(
		"%s: %d of %d without the right kit" % [
			GameEnums.hazard_name(region.hazard), uncovered.size(), squad.size()],
		-float(uncovered.size()) * Balance.HAZARD_SCORE,
		GameEnums.ModifierSource.CONDITION
	)


## The ground itself. Each region tests one skill, and a squad is measured
## against the middle of the range rather than a flat bonus — so bad terrain for
## these people genuinely costs, instead of good terrain being free upside.
static func _apply_region_terms(
	report: MissionReport,
	squad: Squad,
	mission: MissionData
) -> void:
	var region := mission.region()
	if region == null:
		return

	var members: Array = squad.members()
	if members.is_empty():
		return

	var total := 0.0
	for op in members:
		total += float(op.get_skill(region.emphasis_skill, mission.mission_type))
	var average: float = total / float(members.size())

	var value: float = (average - 50.0) * Balance.REGION_EMPHASIS_FACTOR
	if absf(value) < 0.05:
		return

	report.add_modifier(
		"%s: %s" % [region.display_name, region.emphasis_note],
		value,
		GameEnums.ModifierSource.COMPOSITION
	)


## What the client wants, scored openly. A cartel job and a mining job reward
## completely different squads, which is the point of having clients at all.
static func _apply_client_terms(
	report: MissionReport,
	squad: Squad,
	mission: MissionData
) -> void:
	var client := mission.client()
	if client == null:
		return

	var members: Array = squad.members()
	var count: int = members.size()
	if count == 0:
		return

	match client.preference:
		FactionData.Preference.DISCREET:
			var excess: int = count - Balance.CLIENT_DISCREET_IDEAL
			if excess > 0:
				report.add_modifier(
					"%s wants nobody noticed" % client.display_name,
					-float(excess) * Balance.CLIENT_DISCREET_PENALTY,
					GameEnums.ModifierSource.COMPOSITION
				)

		FactionData.Preference.OVERWHELMING:
			var over: int = count - Balance.CLIENT_OVERWHELMING_IDEAL
			var force: float = float(over) * Balance.CLIENT_OVERWHELMING_BONUS
			# A line reading "+0.0" is noise; say nothing when there is nothing
			# to say.
			if absf(force) > 0.05:
				report.add_modifier(
					"%s wants a show of force" % client.display_name,
					force,
					GameEnums.ModifierSource.COMPOSITION
				)

		FactionData.Preference.PROFESSIONALS:
			var ranks := 0
			for op in members:
				ranks += op.rank_step()
			var average_rank: float = float(ranks) / float(count)
			var audit: float = (
				average_rank - Balance.CLIENT_EXPECTED_RANK) * Balance.CLIENT_RANK_FACTOR
			if absf(audit) > 0.05:
				report.add_modifier(
					"%s is auditing your ranks" % client.display_name,
					audit,
					GameEnums.ModifierSource.COMPOSITION
				)

		_:
			# NONE has nothing to say, and CLEAN_HANDS is judged after the fact —
			# it costs standing when someone dies, not score before they go.
			pass


## What one operator is worth on this job, all in. Used only to rank the squad
## best-first before weights are handed out — the same components are emitted
## individually in preview() so the breakdown still explains itself.
static func _raw_contribution(op: OperatorData, role: int, profile: MissionProfile) -> float:
	var mission_type: int = profile.mission_type

	var total: float = (
		Balance.MISSION_SKILL_WEIGHT * profile.skill_match(op)
		+ Balance.ROLE_SKILL_WEIGHT * RoleProfile.score(op, role, mission_type)
	)
	total += float(op.rank_step()) * Balance.RANK_BONUS_PER_STEP
	total += profile.personality_cost(op)

	for t in op.active_traits(mission_type):
		total += t.score_modifier

	total += op.equipment_score()
	total -= Balance.FATIGUE_PENALTY_MAX * (float(op.fatigue) / 100.0)
	total += _morale_effect(op.morale)
	return total


## Morale reads as a swing either side of neutral rather than a straight penalty,
## so a happy squad is genuinely worth building and not merely "not broken".
static func _morale_effect(morale: int) -> float:
	if morale >= Balance.MORALE_NEUTRAL:
		var above: float = float(morale - Balance.MORALE_NEUTRAL)
		var span: float = float(100 - Balance.MORALE_NEUTRAL)
		return Balance.MORALE_BONUS_MAX * (above / maxf(span, 1.0))
	var below: float = float(Balance.MORALE_NEUTRAL - morale)
	return -Balance.MORALE_PENALTY_MAX * (below / maxf(float(Balance.MORALE_NEUTRAL), 1.0))


## Who works well together, and who cannot be in the same truck. Squad-level, so
## these land in the pinned block next to composition — they are things the
## player fixes by changing the squad, not by changing an operator.
##
## Divided by the number of PAIRS, not summed. A squad has n(n-1)/2 pairs, so
## summing would make bonds scale quadratically with squad size and drown out
## every other term.
static func _apply_bond_terms(report: MissionReport, squad: Squad) -> void:
	var members: Array = squad.members()
	if members.size() < 2:
		return

	var pair_count: float = float(members.size() * (members.size() - 1)) / 2.0
	var share: float = 1.0 / pair_count

	for i in members.size():
		for j in range(i + 1, members.size()):
			var a: OperatorData = members[i]
			var b: OperatorData = members[j]
			if not Bonds.has_bond(a, b):
				continue

			var type: int = Bonds.bond_type(a, b)
			var scale: float = float(Bonds.strength(a, b)) / 100.0
			var value := 0.0
			var label := ""

			match type:
				GameEnums.BondType.FRIENDSHIP:
					value = Balance.BOND_FRIENDSHIP_BONUS * scale
					label = "%s and %s have each other's backs" % [
						a.display_label(), b.display_label()]
				GameEnums.BondType.ROMANCE:
					value = Balance.BOND_ROMANCE_BONUS * scale
					label = "%s and %s are inseparable" % [
						a.display_label(), b.display_label()]
				_:
					value = -Balance.BOND_RIVALRY_PENALTY * scale
					label = "Bad blood between %s and %s" % [
						a.display_label(), b.display_label()]

			if absf(value * share) > 0.05:
				report.add_modifier(label, value * share, GameEnums.ModifierSource.BOND)


## Roll the dice on an existing preview. Mutates and returns the same report.
static func roll(report: MissionReport, rng: RandomNumberGenerator) -> MissionReport:
	if report.mission == null or report.squad == null:
		return report

	report.rolled = true
	report.roll_value = rng.randf()
	report.success = report.roll_value < report.success_chance

	report.reward_paid = (
		report.mission.reward_diamonds if report.success
		else int(round(float(report.mission.reward_diamonds) * Balance.FAILURE_REWARD_RATIO))
	)

	# A failed mission is where people die. Success still costs blood sometimes.
	var danger: float = report.mission.risk
	if not report.success:
		danger *= Balance.FAILURE_DANGER_MULT

	# How much of the harm band is fatal, for THIS contract. A dangerous job that
	# went wrong kills; a milk run that went wrong mostly does not.
	var death_share: float = (
		Balance.DEATH_SHARE
		+ report.mission.risk * Balance.DEATH_SHARE_PER_RISK
		+ (Balance.DEATH_SHARE_ON_FAILURE if not report.success else 0.0)
	)

	var has_medic: bool = report.squad.has_role(GameEnums.Role.MEDIC)
	var mission_type: int = report.mission.mission_type
	var xp_base: float = float(
		Balance.XP_ON_SUCCESS if report.success else Balance.XP_ON_FAILURE
	)
	var xp_award := int(round(
		xp_base * (1.0 + report.mission.difficulty * Balance.XP_DIFFICULTY_FACTOR)
	))

	for op in report.squad.members():
		var threat := danger

		var survival: float = (
			float(op.get_skill(GameEnums.Skill.ENDURANCE, mission_type)) * Balance.SURVIVAL_ENDURANCE_WEIGHT
			+ float(op.get_skill(GameEnums.Skill.COMBAT, mission_type)) * Balance.SURVIVAL_COMBAT_WEIGHT
		)
		threat -= survival * Balance.ENDURANCE_MITIGATION

		for t in op.active_traits(mission_type):
			threat += t.danger_modifier

		# Armour is the main thing standing between an operator and the cemetery.
		threat += op.equipment_danger()

		# And the ground itself, for anyone who came without the kit for it.
		var region := report.mission.region()
		if region != null and region.hazard != GameEnums.Hazard.NONE:
			var covered := false
			for item in op.equipment():
				if item.counters(region.hazard):
					covered = true
					break
			if not covered:
				threat += Balance.HAZARD_HARM

		# Tired people get hurt. This is the other half of rotation pressure:
		# running a squad into the ground does not just lower the odds, it
		# raises the body count.
		threat += Balance.FATIGUE_HARM_MAX * (float(op.fatigue) / 100.0)

		if has_medic:
			threat *= (1.0 - Balance.MEDIC_HARM_REDUCTION)

		threat = clampf(threat, 0.0, 95.0)

		var harm_roll: float = rng.randf() * 100.0
		var fate: int = GameEnums.Fate.UNHARMED
		var days := 0

		if harm_roll < threat and threat > 0.0:
			# Reuse the same roll to pick severity: the deeper into the threat
			# band you land, the worse it went. One roll, no double jeopardy.
			var band: float = harm_roll / threat
			if band < death_share:
				fate = GameEnums.Fate.KILLED
			elif band < death_share + Balance.WOUND_SHARE:
				fate = GameEnums.Fate.WOUNDED
				days = rng.randi_range(Balance.WOUND_DAYS_MIN, Balance.WOUND_DAYS_MAX)
			else:
				fate = GameEnums.Fate.TRAUMATIZED
				days = rng.randi_range(Balance.TRAUMA_DAYS_MIN, Balance.TRAUMA_DAYS_MAX)

		report.fates[op] = fate
		report.recovery_days[op] = days
		report.xp_gained[op] = 0 if fate == GameEnums.Fate.KILLED else xp_award
		_roll_kills(report, op, fate, rng)

	return report


## Who they went through to get the job done.
##
## Kills are flavour with teeth: they feed the after-action feed, an operator's
## lifetime record, and the reputation of the people who rack them up. The count
## follows combat skill and how loud the contract was, so a marksman on an
## assault comes back with a tally and a scout on a recon mostly does not.
const _ENEMY_KINDS := [
	"a sentry", "a machine-gun team", "a runner", "a technical crew",
	"a squad leader", "a spotter", "a driver", "a radio operator",
	"a patrol pair", "a guard on the wire",
]

## How a kill reads depends on what they were carrying. A marksman rifle does
## not produce the same sentence as a suppressed pistol, and the feed is much
## better for saying so.
const _METHODS := {
	&"marksman_rifle": ["single shot", "a shot through cover", "one round, no follow-up"],
	&"battle_rifle": ["a short burst", "sustained fire", "two bursts"],
	&"service_carbine": ["a controlled pair", "close-range fire", "a burst"],
	&"suppressed_pistol": ["suppressed, close", "two rounds, quietly", "no noise at all"],
	&"prototype_smg": ["a very fast burst", "nine rounds in under a second"],
	&"breaching_kit": ["a shaped charge", "the wall came down on them"],
}

const _METHODS_DEFAULT := ["close quarters", "a struggle", "a rifle butt", "the knife"]

## How much of a firefight each mission type actually is.
const _CONTACT_WEIGHT := {
	GameEnums.MissionType.ASSAULT: 1.0,
	GameEnums.MissionType.ESCORT: 0.75,
	GameEnums.MissionType.RESCUE: 0.65,
	GameEnums.MissionType.SABOTAGE: 0.4,
	GameEnums.MissionType.INFILTRATION: 0.3,
	GameEnums.MissionType.RECON: 0.15,
}


static func _roll_kills(
	report: MissionReport,
	op: OperatorData,
	fate: int,
	rng: RandomNumberGenerator
) -> void:
	var contact: float = float(_CONTACT_WEIGHT.get(report.mission.mission_type, 0.5))
	var combat: float = float(op.get_skill(GameEnums.Skill.COMBAT)) / 100.0

	# Someone who died still took people with them; someone who never made
	# contact did not.
	var expected: float = contact * (0.5 + combat * 2.5) * (report.mission.risk / 55.0)
	if fate == GameEnums.Fate.KILLED:
		expected *= 0.6

	var count: int = int(floor(expected))
	if rng.randf() < expected - float(count):
		count += 1
	if count <= 0:
		return

	report.kills[op] = count
	op.confirmed_kills += count

	# One line per kill: who, what, how, and how far away. A tally is a number;
	# this is a story the player can retell.
	var methods: Array = _METHODS.get(op.weapon_id, _METHODS_DEFAULT)
	var long_range: bool = op.weapon_id == &"marksman_rifle"

	for i in count:
		var kind: String = _ENEMY_KINDS[rng.randi() % _ENEMY_KINDS.size()]
		var how: String = methods[rng.randi() % methods.size()]
		var distance: int = (
			rng.randi_range(180, 900) if long_range else rng.randi_range(4, 120))
		report.kill_feed.append("%s  ·  %s  ·  %s  ·  %dm" % [
			op.display_label(), kind, how, distance])


## Preview and roll in one call.
static func resolve(
	squad: Squad,
	mission: MissionData,
	rng: RandomNumberGenerator
) -> MissionReport:
	return roll(preview(squad, mission), rng)
