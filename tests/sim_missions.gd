extends SceneTree

## Headless balance harness for v0.1. No UI, no scenes — this is how we tune the
## resolver before a single button exists.
##
## Run it with:
##   godot --headless --path . --script res://tests/sim_missions.gd
##
## It does four things:
##   1. Prints one full mission breakdown, so we can read what the player's
##      tooltip will say and check the lines sum to the score.
##   2. Checks the two composition rules the design doc calls out by name:
##      infiltration should punish a big squad, rescue should punish no medic.
##   3. Runs Monte Carlo over every difficulty grade to see real success and
##      death rates, not just the advertised percentage.
##   4. Sanity-checks the economy: does a week of missions cover a week of salary.

## Sample many contracts per grade, not one: difficulty and risk are rolled
## independently, so a single sampled mission tells us nothing about the grade.
const MISSIONS_PER_GRADE := 40
const RUNS_PER_MISSION := 200
const SEED := 20260809


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	print("")
	print("################ SQUAD MANAGER — v0.1 RESOLVER SIM ################")

	var roster := _build_reference_roster(rng)

	_section_breakdown(roster, rng)
	_section_composition_rules(roster, rng)
	_section_monte_carlo(roster, rng)
	_section_economy(roster, rng)

	print("")
	quit()


# --- Setup -------------------------------------------------------------------

## Six hand-tiered operators, one per role plus a spare, so every comparison
## below uses the same people and only the variable under test changes.
func _build_reference_roster(rng: RandomNumberGenerator) -> Array[OperatorData]:
	var E := GameEnums
	var F := OperatorFactory
	var roster: Array[OperatorData] = [
		F.create(rng, E.Role.ASSAULT, F.Tier.VETERAN),
		F.create(rng, E.Role.SCOUT, F.Tier.VETERAN),
		F.create(rng, E.Role.MEDIC, F.Tier.REGULAR),
		F.create(rng, E.Role.ENGINEER, F.Tier.REGULAR),
		F.create(rng, E.Role.MARKSMAN, F.Tier.REGULAR),
		F.create(rng, E.Role.ASSAULT, F.Tier.ROOKIE),
	]
	print("")
	print("--- REFERENCE ROSTER ---")
	for op in roster:
		var trait_names: PackedStringArray = []
		for t in op.traits:
			trait_names.append(t.display_name)
		print("  %-26s %-10s %-16s %-12s %4d  %s" % [
			op.display_label(),
			GameEnums.role_name(op.preferred_role),
			GameEnums.rank_name(op.rank),
			op.demonym(),
			op.salary,
			", ".join(trait_names),
		])
	return roster


func _squad(ops: Array, roles: Array, leader_index: int = 0) -> Squad:
	var s := Squad.new()
	for i in ops.size():
		s.add(ops[i], roles[i])
	s.set_leader(ops[leader_index])
	return s


# --- 1. Breakdown ------------------------------------------------------------

func _section_breakdown(roster: Array[OperatorData], rng: RandomNumberGenerator) -> void:
	var E := GameEnums
	print("")
	print("--- 1. FULL BREAKDOWN (this is what the player's tooltip shows) ---")

	var mission := MissionFactory.create(rng, E.MissionType.RESCUE, MissionFactory.Grade.STANDARD)
	var squad := _squad(
		[roster[0], roster[2], roster[4], roster[1]],
		[E.Role.ASSAULT, E.Role.MEDIC, E.Role.MARKSMAN, E.Role.SCOUT]
	)

	var report := MissionResolver.preview(squad, mission)
	print(report.to_text())

	# The breakdown is only trustworthy if the lines add up to the score.
	var total := 0.0
	for m in report.modifiers:
		total += m.value
	var drift: float = absf(total - report.squad_score)
	print("")
	print("  [check] modifiers sum to squad score, drift %.6f  %s" % [
		drift, "OK" if drift < 0.001 else "FAIL",
	])


# --- 2. Composition rules from the design doc --------------------------------

func _section_composition_rules(roster: Array[OperatorData], rng: RandomNumberGenerator) -> void:
	var E := GameEnums
	print("")
	print("--- 2. COMPOSITION RULES ---")

	# "Infiltration punishes a large squad" (design doc, section 2).
	var infil := MissionFactory.create(rng, E.MissionType.INFILTRATION, MissionFactory.Grade.STANDARD)
	infil.difficulty = 60.0

	var small := _squad(
		[roster[1], roster[3], roster[4]],
		[E.Role.SCOUT, E.Role.ENGINEER, E.Role.MARKSMAN],
		0
	)
	var large := _squad(
		[roster[1], roster[3], roster[4], roster[0], roster[2], roster[5]],
		[E.Role.SCOUT, E.Role.ENGINEER, E.Role.MARKSMAN, E.Role.ASSAULT, E.Role.MEDIC, E.Role.ASSAULT],
		0
	)
	var small_report := MissionResolver.preview(small, infil)
	var large_report := MissionResolver.preview(large, infil)
	print("  Infiltration, squad of 3 : score %5.1f -> %3d%%" % [
		small_report.squad_score, small_report.chance_percent()])
	print("  Infiltration, squad of 6 : score %5.1f -> %3d%%" % [
		large_report.squad_score, large_report.chance_percent()])
	print("  [check] bigger squad is worse on infiltration: %s" % [
		"OK" if large_report.success_chance < small_report.success_chance else "FAIL"])

	# "Rescue requires a medic role" (design doc, section 2).
	var rescue := MissionFactory.create(rng, E.MissionType.RESCUE, MissionFactory.Grade.STANDARD)
	rescue.difficulty = 60.0

	var with_medic := _squad(
		[roster[0], roster[2], roster[4], roster[1]],
		[E.Role.ASSAULT, E.Role.MEDIC, E.Role.MARKSMAN, E.Role.SCOUT]
	)
	var no_medic := _squad(
		[roster[0], roster[5], roster[4], roster[1]],
		[E.Role.ASSAULT, E.Role.ASSAULT, E.Role.MARKSMAN, E.Role.SCOUT]
	)
	var wm := MissionResolver.preview(with_medic, rescue)
	var nm := MissionResolver.preview(no_medic, rescue)
	print("  Rescue, with medic       : score %5.1f -> %3d%%" % [wm.squad_score, wm.chance_percent()])
	print("  Rescue, no medic         : score %5.1f -> %3d%%" % [nm.squad_score, nm.chance_percent()])
	print("  [check] medic matters on rescue: %s" % [
		"OK" if nm.success_chance < wm.success_chance else "FAIL"])

	# A trait that only fires on one mission type should be invisible elsewhere.
	var claustrophobe := OperatorFactory.create(rng, E.Role.SCOUT, OperatorFactory.Tier.REGULAR)
	claustrophobe.traits = [TraitLibrary.get_trait(&"claustrophobic")] as Array[TraitData]
	var solo_infil := _squad([claustrophobe], [E.Role.SCOUT])
	var assault_job := MissionFactory.create(rng, E.MissionType.ASSAULT, MissionFactory.Grade.STANDARD)
	assault_job.difficulty = 60.0
	var a := MissionResolver.preview(solo_infil, infil)
	var b := MissionResolver.preview(solo_infil, assault_job)
	var fires_on_infil := false
	for m in a.modifiers:
		if m.source == E.ModifierSource.TRAIT:
			fires_on_infil = true
	var fires_on_assault := false
	for m in b.modifiers:
		if m.source == E.ModifierSource.TRAIT:
			fires_on_assault = true
	print("  [check] conditional trait fires on infiltration only: %s" % [
		"OK" if fires_on_infil and not fires_on_assault else "FAIL"])

	_check_condition_rules(rng)


# --- 2c. Fatigue, morale and bonds -------------------------------------------

func _check_condition_rules(rng: RandomNumberGenerator) -> void:
	var E := GameEnums
	print("")
	print("  Condition:")

	# One squad, cloned three ways. Only the condition differs.
	var base_ops: Array[OperatorData] = []
	for i in 4:
		base_ops.append(OperatorFactory.create(
			rng, GameEnums.Role.ASSAULT, OperatorFactory.Tier.REGULAR))

	var job := MissionFactory.create(rng, E.MissionType.ASSAULT, MissionFactory.Grade.STANDARD)
	job.difficulty = 60.0
	job.risk = 60.0

	var rested := _clone_squad(base_ops, 0, 70)
	var spent := _clone_squad(base_ops, 95, 70)
	var rested_report := MissionResolver.preview(rested, job)
	var spent_report := MissionResolver.preview(spent, job)
	print("    Rested squad   : score %5.1f -> %3d%%" % [
		rested_report.squad_score, rested_report.chance_percent()])
	print("    Exhausted squad: score %5.1f -> %3d%%" % [
		spent_report.squad_score, spent_report.chance_percent()])
	print("    [check] fatigue costs the odds: %s" % [
		"OK" if spent_report.squad_score < rested_report.squad_score else "FAIL"])

	var happy := _clone_squad(base_ops, 0, 95)
	var broken := _clone_squad(base_ops, 0, 10)
	var happy_report := MissionResolver.preview(happy, job)
	var broken_report := MissionResolver.preview(broken, job)
	print("    [check] morale swings both ways around neutral: %s" % [
		"OK" if broken_report.squad_score < rested_report.squad_score
			and happy_report.squad_score > rested_report.squad_score else "FAIL"])

	# Bonds, isolated: same people, same condition, only the links differ.
	var friends := _clone_squad(base_ops, 0, 70)
	_link_all(friends, E.BondType.FRIENDSHIP)
	var enemies := _clone_squad(base_ops, 0, 70)
	_link_all(enemies, E.BondType.RIVALRY)
	var friends_report := MissionResolver.preview(friends, job)
	var enemies_report := MissionResolver.preview(enemies, job)
	print("    Squad of friends: score %5.1f -> %3d%%" % [
		friends_report.squad_score, friends_report.chance_percent()])
	print("    Squad of rivals : score %5.1f -> %3d%%" % [
		enemies_report.squad_score, enemies_report.chance_percent()])
	print("    [check] friends beat rivals: %s" % [
		"OK" if enemies_report.squad_score < friends_report.squad_score else "FAIL"])

	# Fatigue must also cost blood, not just odds — that is the half of the
	# rotation pressure the player feels rather than reads.
	var rested_harm := _harm_rate(rested_report, rng, 3000)
	var spent_harm := _harm_rate(spent_report, rng, 3000)
	print("    Casualty rate per operator: rested %.1f%%, exhausted %.1f%%" % [
		rested_harm, spent_harm])
	print("    [check] exhausted operators get hurt more: %s" % [
		"OK" if spent_harm > rested_harm else "FAIL"])


func _clone_squad(base_ops: Array[OperatorData], fatigue: int, morale: int) -> Squad:
	var squad := Squad.new()
	for op in base_ops:
		var copy: OperatorData = op.duplicate()
		copy.bonds = {}
		copy.fatigue = fatigue
		copy.morale = morale
		squad.add(copy, GameEnums.Role.ASSAULT)
	squad.set_leader(squad.members()[0])
	return squad


func _link_all(squad: Squad, type: int) -> void:
	var members: Array = squad.members()
	for i in members.size():
		for j in range(i + 1, members.size()):
			Bonds.link(members[i], members[j], type, Balance.BOND_STRENGTH_MAX)


## Percentage of deployments that end in a wound, trauma or death.
func _harm_rate(report: MissionReport, rng: RandomNumberGenerator, runs: int) -> float:
	var harmed := 0
	var total := 0
	for i in runs:
		MissionResolver.roll(report, rng)
		for op in report.fates:
			total += 1
			if report.fates[op] != GameEnums.Fate.UNHARMED:
				harmed += 1
	return 100.0 * float(harmed) / float(maxi(1, total))


# --- 2b. Language rules ------------------------------------------------------

func _check_language_rules(rng: RandomNumberGenerator) -> void:
	var E := GameEnums
	print("")
	print("  Languages:")




func _section_monte_carlo(roster: Array[OperatorData], rng: RandomNumberGenerator) -> void:
	var E := GameEnums
	var total_runs: int = MISSIONS_PER_GRADE * RUNS_PER_MISSION
	print("")
	print("--- 3. MONTE CARLO (%d contracts x %d runs per grade, 4-operator squad) ---" % [
		MISSIONS_PER_GRADE, RUNS_PER_MISSION])
	print("  %-11s %6s %6s %8s %8s %9s %9s %9s" % [
		"GRADE", "DIFF", "RISK", "PREDICT", "ACTUAL", "DEATH/OP", "HURT/OP", "AVG PAY"])

	var squad := _squad(
		[roster[0], roster[2], roster[4], roster[1]],
		[E.Role.ASSAULT, E.Role.MEDIC, E.Role.MARKSMAN, E.Role.SCOUT]
	)

	var worst_drift := 0.0

	for grade in MissionFactory.Grade.values():
		var wins := 0
		var deaths := 0
		var wounds := 0
		var payout := 0
		var deployments := 0
		var sum_difficulty := 0.0
		var sum_risk := 0.0
		var sum_predicted := 0.0

		for m in MISSIONS_PER_GRADE:
			var mission := MissionFactory.create(rng, E.MissionType.ASSAULT, grade)
			var report := MissionResolver.preview(squad, mission)
			sum_difficulty += mission.difficulty
			sum_risk += mission.risk
			sum_predicted += report.success_chance

			for i in RUNS_PER_MISSION:
				MissionResolver.roll(report, rng)
				if report.success:
					wins += 1
				payout += report.reward_paid
				for op in report.fates:
					deployments += 1
					match report.fates[op]:
						E.Fate.KILLED:
							deaths += 1
						E.Fate.WOUNDED, E.Fate.TRAUMATIZED:
							wounds += 1

		var predicted: float = 100.0 * sum_predicted / float(MISSIONS_PER_GRADE)
		var actual: float = 100.0 * float(wins) / float(total_runs)
		worst_drift = maxf(worst_drift, absf(predicted - actual))

		print("  %-11s %6.1f %6.1f %7.1f%% %7.1f%% %8.2f%% %8.2f%% %9d" % [
			MissionFactory.Grade.keys()[grade],
			sum_difficulty / float(MISSIONS_PER_GRADE),
			sum_risk / float(MISSIONS_PER_GRADE),
			predicted,
			actual,
			100.0 * float(deaths) / float(deployments),
			100.0 * float(wounds) / float(deployments),
			payout / total_runs,
		])

	print("")
	print("  [check] predicted vs actual, worst drift %.2f pp  %s" % [
		worst_drift, "OK" if worst_drift < 1.5 else "FAIL"])
	print("  PREDICT is what the UI promises, ACTUAL is what the dice deliver.")
	print("  DEATH/OP is the chance any ONE operator does not come home; with a")
	print("  4-operator squad, the chance of losing SOMEBODY is roughly 4x that.")


# --- 4. Economy sanity check -------------------------------------------------

func _section_economy(roster: Array[OperatorData], rng: RandomNumberGenerator) -> void:
	var E := GameEnums
	print("")
	print("--- 4. ECONOMY SANITY CHECK ---")

	var weekly_salary := 0
	for op in roster:
		weekly_salary += op.salary
	print("  Roster of %d, weekly salary bill: %d diamonds" % [roster.size(), weekly_salary])

	var squad := _squad(
		[roster[0], roster[2], roster[4], roster[1]],
		[E.Role.ASSAULT, E.Role.MEDIC, E.Role.MARKSMAN, E.Role.SCOUT]
	)

	for grade in MissionFactory.Grade.values():
		var sum_ev := 0.0
		var sum_per_week := 0.0
		for m in MISSIONS_PER_GRADE:
			var mission := MissionFactory.create(rng, E.MissionType.ASSAULT, grade)
			var report := MissionResolver.preview(squad, mission)
			sum_ev += (
				report.success_chance * float(mission.reward_diamonds)
				+ (1.0 - report.success_chance) * float(mission.reward_diamonds) * Balance.FAILURE_REWARD_RATIO
			)
			# How many of these one squad could run in a week, ignoring recovery.
			sum_per_week += float(Balance.DAYS_PER_WEEK) / float(maxi(1, mission.duration_days))

		var expected: float = sum_ev / float(MISSIONS_PER_GRADE)
		var per_week: float = sum_per_week / float(MISSIONS_PER_GRADE)
		var weekly: float = expected * per_week
		print("  %-11s EV %6.0f, ~%.1f jobs/week = %7.0f vs salary %d  [%s]" % [
			MissionFactory.Grade.keys()[grade],
			expected,
			per_week,
			weekly,
			weekly_salary,
			"profit" if weekly > float(weekly_salary) else "LOSS",
		])

	print("")
	print("  CAVEAT: this is an optimistic ceiling. It ignores wound downtime, the")
	print("  fixed costs from design doc section 4 (ammo, food, medicine) and all")
	print("  facility upkeep, none of which exist yet. The check only becomes")
	print("  meaningful in v0.5 — until then, treat 'profit' as expected.")
