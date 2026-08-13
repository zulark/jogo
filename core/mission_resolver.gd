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
##       their RATING on this job — 0.6 * (how well their skills match what this
##       MISSION TYPE tests) + 0.4 * (how well they suit their ROLE), which is
##       `Ovr.rating()` and is the same figure the squad builder prints beside
##       their name
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

		# The rating, and the same one every screen prints beside their name — see
		# Ovr. Named on the line rather than only summed into it, because a
		# player who read "Rated 71 for sabotage work" on the row and then found
		# an unlabelled +23.4 here has been given two numbers and no way to know
		# they are the same one. The gap between them is the share above, which
		# the short-handed line further down explains.
		var base: float = Ovr.rating(op, role, profile)
		report.add_modifier(
			"Rated %d for %s work" % [int(round(base)), profile.display_name.to_lower()],
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
				# Named with its state, because a rifle at 40% is a different
				# line on this breakdown than the same rifle new, and the whole
				# promise of the odds screen is that the list explains the number.
				kit_names.append("%s (%s)" % [item.display_name(), item.condition_word().to_lower()])
			report.add_modifier(
				"Kit: %s" % ", ".join(kit_names),
				kit * share,
				GameEnums.ModifierSource.CONDITION,
				op.id
			)

		# Broken kit is worth saying out loud even where it scores nothing. Its
		# skill bonuses have already fallen out of get_skill above and its
		# drawbacks have not, so the operator is quietly worse for carrying it —
		# and a cost with no line to explain it is the one thing this screen
		# promises never to do.
		for item in op.equipment():
			if item.is_serviceable():
				continue
			report.add_modifier(
				"%s is carrying an unserviceable %s" % [op.display_label(), item.display_name()],
				0.0,
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

	# Kept on the report as well as spent on the breakdown, because casing a
	# contract buys two separate things and roll() needs the second one. The
	# score line below is the odds; report.intel_applied is the safety.
	report.intel_applied = maxf(intel_bonus, 0.0)

	if intel_bonus > 0.0:
		report.add_modifier(
			"Scouted: the ground is known",
			intel_bonus,
			GameEnums.ModifierSource.COMPOSITION
		)
		# Said out loud and scored at nothing, because it is not score — it comes
		# off the harm roll in roll(), and a benefit the player paid a week of
		# somebody's time for cannot be one they have to infer from the casualty
		# list afterwards.
		report.add_modifier(
			"Everyone goes in knowing where the patrols are (-%.0f%% harm)" % (
				intel_bonus * Balance.INTEL_HARM_FACTOR),
			0.0,
			GameEnums.ModifierSource.CONDITION
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

	recompute(report)
	return report


## Re-sum the breakdown and re-derive the odds from it.
##
## Called at the end of every preview, and again whenever something changes a
## report that has already been previewed — a decision taken over the radio
## while the squad is out. The score is never edited directly anywhere: a change
## adds a line and the total is taken from the list, which is the only
## arrangement where the breakdown cannot drift away from the percentage.
static func recompute(report: MissionReport) -> void:
	var total := 0.0
	for m in report.modifiers:
		total += m.value
	report.squad_score = total
	report.success_chance = chance_for(report.squad_score, report.difficulty)


## The curve, in one place. Also called with hypothetical numbers by anything
## that has to quote the player a price before they pay it — a field decision
## saying "58% → 64%" is reading this rather than approximating it.
static func chance_for(score: float, difficulty: float) -> float:
	var raw: float = 1.0 / (1.0 + exp(-(score - difficulty) / Balance.SPREAD))
	return clampf(raw, Balance.MIN_SUCCESS, Balance.MAX_SUCCESS)


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
			# Capped going up, uncapped going down: turning up short still
			# disappoints them by however short you were, but past a couple of
			# spare bodies they have seen the point and stacking more is no
			# longer an argument. Uncapped, this was the only term in the game
			# that paid for bodies without limit — eight operators on an assault
			# contract cost -4 to squad size and earned +12 here — so a client
			# who liked numbers turned composition into "bring everyone".
			var over: int = mini(
				count - Balance.CLIENT_OVERWHELMING_IDEAL,
				Balance.CLIENT_OVERWHELMING_MAX_OVER)
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

	var total: float = Ovr.rating(op, role, profile)
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
##
## `withdrawal` is the player having called the contract off over the radio.
## There is nothing to roll — the job is not done — but getting out is not free
## either, so the harm pass still runs at a fraction of the contract's danger.
static func roll(
	report: MissionReport,
	rng: RandomNumberGenerator,
	withdrawal: bool = false
) -> MissionReport:
	if report.mission == null or report.squad == null:
		return report

	report.rolled = true
	if withdrawal:
		report.withdrew = true
		report.roll_value = 1.0
		report.success = false
	else:
		report.roll_value = rng.randf()
		report.success = report.roll_value < report.success_chance

	report.reward_paid = (
		report.mission.reward_diamonds if report.success
		else int(round(float(report.mission.reward_diamonds) * Balance.FAILURE_REWARD_RATIO))
	)

	# How badly the day went, as a multiplier rather than a flat danger. It is
	# applied to what is LEFT of the contract's danger after each operator's own
	# skill, kit and intel have come off it — see FAILURE_DANGER_MULT for why the
	# order is the whole point.
	var outcome_mult := 1.0
	if withdrawal:
		outcome_mult = Balance.WITHDRAWAL_DANGER_MULT
	elif not report.success:
		outcome_mult = Balance.FAILURE_DANGER_MULT

	# How much of the harm band is fatal, for THIS contract. A dangerous job that
	# went wrong kills; a milk run that went wrong mostly does not. Breaking
	# contact deliberately does not carry the failure share: the squad was
	# leaving, not losing.
	var has_medic: bool = report.squad.has_role(GameEnums.Role.MEDIC)
	var death_share: float = (
		Balance.DEATH_SHARE
		+ report.mission.risk * Balance.DEATH_SHARE_PER_RISK
		+ (Balance.DEATH_SHARE_ON_FAILURE if not report.success and not withdrawal else 0.0)
	)
	if has_medic:
		death_share *= (1.0 - Balance.MEDIC_DEATH_SHARE_RELIEF)
	death_share = minf(death_share, Balance.DEATH_SHARE_MAX)

	# What the squad knew going in, priced when the case finished. Comes off
	# everyone's exposure, so a cased contract is a safer contract and not merely
	# a likelier one — and the fee, the XP and the parts are all untouched,
	# because none of this went anywhere near mission.difficulty.
	var intel_relief: float = report.intel_applied * Balance.INTEL_HARM_FACTOR
	var mission_type: int = report.mission.mission_type
	var xp_base: float = float(
		Balance.XP_ON_SUCCESS if report.success else Balance.XP_ON_FAILURE
	)
	var xp_award := int(round(
		xp_base * (1.0 + report.mission.difficulty * Balance.XP_DIFFICULTY_FACTOR)
	))

	for op in report.squad.members():
		# Anyone pulled out earlier sat the rest of it out at the extraction
		# point. No harm roll and no kills — and the score they were worth was
		# taken off the breakdown when the call was made, so this is not free.
		if report.withdrawn.has(op):
			report.fates[op] = GameEnums.Fate.UNHARMED
			report.recovery_days[op] = 0
			report.xp_gained[op] = int(round(float(xp_award) * Balance.WITHDRAWN_XP_RATIO))
			continue

		# EXPOSURE: how much of this contract's danger reaches this operator,
		# before the day's outcome is known. Everything the player can do
		# something about lands here — who they sent, what they gave them, how
		# rested they are, and whether anybody looked at the place first.
		var exposure: float = report.mission.risk

		var survival: float = (
			float(op.get_skill(GameEnums.Skill.ENDURANCE, mission_type)) * Balance.SURVIVAL_ENDURANCE_WEIGHT
			+ float(op.get_skill(GameEnums.Skill.COMBAT, mission_type)) * Balance.SURVIVAL_COMBAT_WEIGHT
		)
		exposure -= survival * Balance.ENDURANCE_MITIGATION
		exposure -= intel_relief

		for t in op.active_traits(mission_type):
			exposure += t.danger_modifier

		# Armour is the main thing standing between an operator and the cemetery.
		exposure += op.equipment_danger()

		# And the ground itself, for anyone who came without the kit for it.
		var region := report.mission.region()
		if region != null and region.hazard != GameEnums.Hazard.NONE:
			var covered := false
			for item in op.equipment():
				if item.counters(region.hazard):
					covered = true
					break
			if not covered:
				exposure += Balance.HAZARD_HARM

		# Tired people get hurt. This is the other half of rotation pressure:
		# running a squad into the ground does not just lower the odds, it
		# raises the body count.
		exposure += Balance.FATIGUE_HARM_MAX * (float(op.fatigue) / 100.0)

		# Only now does the day's outcome multiply it. An operator who was
		# prepared for this contract is prepared for it going wrong, which is the
		# whole reason preparing for it is a decision.
		var threat: float = maxf(exposure, 0.0) * outcome_mult

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
## One entry is one person. A "patrol pair" or a "machine-gun team" counted as a
## single confirmed kill made the feed contradict its own tally — five lines
## under a heading that said nine — so every kind here is one body. "A patrol
## element" was exactly that mistake and is gone.
##
## GRAMMAR (see .docs/prose_style_guide.md): a singular INDEFINITE noun phrase
## carrying its own article, lower case, no closing stop, no comma. Indefinite
## because the feed lists strangers: "the last man standing" claimed a fact about
## the whole engagement that nothing here computes, and printed twice in the same
## feed the moment an operator got two kills.
const _ENEMY_KINDS := [
	"a sentry", "a machine gunner", "a runner", "a gunner on a technical",
	"a squad leader", "a spotter", "a driver", "a radio operator",
	"a man on the wire", "a lookout on the roof", "an officer",
	"a courier", "a man at the gate", "a rifleman in the treeline",
	"a radioman calling for fire", "a forward observer",
	"a designated marksman", "a mortar crewman",
	"a man left holding the position", "a point man", "a straggler",
	"a heavy weapons operator", "a combat medic", "an entrenched shooter",
]

## How a kill reads depends on what they were carrying. A marksman rifle does
## not produce the same sentence as a suppressed pistol, and the feed is much
## better for saying so.
##
## Each entry carries its own range band, in metres. Reading "the knife · 102m"
## in the feed is the kind of detail that stops a player believing any of it, and
## a distance rolled off the weapon alone could never have been right — the same
## rifle kills at 400 metres and at arm's length, and the sentence is what says
## which one happened.
##
## GRAMMAR (see .docs/prose_style_guide.md): `[phrase, min_metres, max_metres]`,
## where the phrase is an INDEFINITE noun phrase naming the means of the kill —
## a countable head takes "a"/"an", a mass or plural head takes no determiner at
## all, and nothing here ever takes "the". No finite verb, no comma, no stop.
## "Suppressive fire that found a mark" and "a burst that actually worked" hung a
## clause off the noun and read as half a sentence dropped into a table cell.
const _METHODS := {
	&"marksman_rifle": [
		["a single shot", 180, 900],
		["a shot through cover", 150, 600],
		["a single round with no follow-up", 220, 850],
		["a clean headshot", 200, 1000],
		["a high-angle shot", 300, 900],
	],
	&"battle_rifle": [
		["a short burst", 40, 220],
		["sustained fire", 60, 300],
		["two bursts", 30, 180],
		["a strike from the rifle butt", 1, 3],
		["a stray round from suppressive fire", 50, 250],
		["a heavy-calibre round through light armour", 20, 200],
	],
	&"service_carbine": [
		["a controlled pair", 15, 90],
		["rapid close-range fire", 4, 30],
		["a tight burst", 20, 120],
		["a double tap to centre mass", 10, 50],
		["a snap shot on the move", 5, 25],
	],
	&"suppressed_pistol": [
		["a suppressed shot at close range", 2, 12],
		["two quiet rounds", 3, 15],
		["a silent takedown", 1, 8],
		["a shot from the shadows", 4, 15],
		["a suppressed headshot", 5, 20],
	],
	&"prototype_smg": [
		["a very fast burst", 5, 45],
		["nine rounds in under a second", 4, 30],
		["an unmanageable spray at close range", 10, 50],
		["a continuous stream of fire", 5, 25],
	],
	&"breaching_kit": [
		["a shaped-charge blast", 5, 25],
		["spalling from a collapsed wall", 2, 15],
		["concussive force from a breach", 1, 8],
		["fragmentation from a doorframe", 3, 12],
	],
	&"shop_smg": [
		["a rare clean burst", 5, 40],
		["three rounds before a malfunction", 3, 20],
		["erratic full-auto fire", 4, 25],
		["a burst cut short by a jam", 2, 15],
	],
	&"shaped_charges": [
		["a charge placed on a doorframe", 4, 20],
		["shockwave from a close detonation", 2, 12],
		["overpressure from a blast", 3, 15],
		["directed shrapnel", 5, 30],
	],
}

## Standard issue is a sidearm and whatever is to hand, so nobody shot anybody
## from four hundred metres and nobody swung a rifle they were never given — "a
## lethal strike with a rifle buttstock" contradicted the very line above it.
## Every one of these is arm's length by definition, and the band says so.
const _METHODS_DEFAULT := [
	["close-quarters combat", 1, 6],
	["a hand-to-hand struggle", 1, 3],
	["a chokehold", 1, 2],
	["a knife thrust", 1, 2],
	["a sidearm fired at contact range", 2, 10],
	["blunt force trauma", 1, 2],
	["a desperate point-blank struggle", 1, 3],
]

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
	# A squad that broke contact was leaving, not fighting through. Whatever
	# shooting there was happened on the way out.
	if report.withdrew:
		expected *= 0.4

	var count: int = int(floor(expected))
	if rng.randf() < expected - float(count):
		count += 1
	if count <= 0:
		return

	report.kills[op] = count
	op.confirmed_kills += count

	# One line per kill: who, what, how, and how far away. A tally is a number;
	# this is a story the player can retell. The range comes off the method, not
	# off the weapon, because "the knife · 102m" is a lie the player can see.
	var methods: Array = _METHODS.get(op.weapon_item_id(), _METHODS_DEFAULT)

	for i in count:
		var kind: String = _ENEMY_KINDS[rng.randi() % _ENEMY_KINDS.size()]
		var method: Array = methods[rng.randi() % methods.size()]
		var distance: int = rng.randi_range(int(method[1]), int(method[2]))
		report.kill_feed.append("%s  ·  %s  ·  %s  ·  %dm" % [
			op.display_label(), kind, str(method[0]), distance])


## Preview and roll in one call.
static func resolve(
	squad: Squad,
	mission: MissionData,
	rng: RandomNumberGenerator
) -> MissionReport:
	return roll(preview(squad, mission), rng)
