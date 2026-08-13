extends SceneTree

## Dumps every sentence the game generates, so the prose can be read as prose.
##
##   Godot.exe --headless --path . --script res://tests/sim_prose.gd
##
## Nothing here asserts anything. Grammar is not a thing a boolean can check —
## the only way to find "1 contracts" and "mastered taught by Reyes" is to put a
## few hundred generated lines side by side and read them.

const SEED := 20260810


func _initialize() -> void:
	_briefings()
	_stories()
	_events()
	_incidents()
	_field_events()
	_resumes()
	_item_histories()
	_progression()
	quit()


func _rule(title: String) -> void:
	print("")
	print("=========================== %s ===========================" % title)


func _briefings() -> void:
	_rule("CONTRACT BRIEFINGS")
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in 24:
		var m := MissionFactory.create_for_board(rng, {})
		print("")
		print("  %s  ·  %s  ·  %s  ·  %s" % [
			m.title, m.type_name(), m.region_name(), m.client_name()])
		print("    %s" % m.briefing)


func _stories() -> void:
	_rule("AFTER ACTION")
	for run in 14:
		var campaign := Campaign.new(null, SEED + run)
		campaign.start_new_company(6)
		var state := campaign.state
		state.diamonds = 200000

		var squad := Squad.new()
		var free := state.deployable_operators()
		for i in mini(4, free.size()):
			squad.add(free[i], free[i].preferred_role)
		squad.set_leader(free[0])

		var mission: MissionData = state.board[run % state.board.size()]
		if not campaign.deploy(squad, mission):
			continue

		# GDScript lambdas capture locals by value, so the report has to land in
		# something with an identity.
		var box: Array = []
		campaign.mission_resolved.connect(func(report: MissionReport): box.append(report))
		var guard := 0
		while not state.deployments.is_empty() and guard < 30:
			campaign.end_day()
			guard += 1
		if box.is_empty():
			continue
		var seen: MissionReport = box[0]

		print("")
		print("  --- %s (%s, %s) — %s" % [
			seen.mission.title, seen.mission.type_name(), seen.mission.region_name(),
			"SUCCESS" if seen.success else "FAILED"])
		if not seen.trophy_line.is_empty():
			print("    TROPHY: %s" % seen.trophy_line)
		for line in seen.story:
			print("    %s" % line)
		for line in seen.kill_feed:
			print("    kill | %s" % line)
		for line in seen.kit_notes:
			print("    kit  | %s" % line)
		for line in seen.bond_log:
			print("    bond | %s" % line)
		for op in seen.progression:
			for line in seen.progression[op]:
				print("    prog | %s: %s" % [op.display_label(), line])
		for op in seen.squad.members():
			for other in seen.squad.members():
				if other == op:
					continue
				var reason := Bonds.reason_for(op, other)
				if not reason.is_empty():
					print("    why  | %s & %s: %s" % [
						op.display_label(), other.display_label(), reason])


func _events() -> void:
	_rule("THE WEEK (events)")
	for entry in EventLibrary.catalogue():
		for attempt in 3:
			var campaign := Campaign.new(null, SEED + attempt * 31)
			campaign.start_new_company(6)
			var state := campaign.state
			state.diamonds = 30000
			state.reputation = 55
			state.salvage = 40
			state.deployed_last_week = 2
			state.inventory.append(ItemInstance.create(&"service_carbine", 40.0))
			state.inventory.append(ItemInstance.create(&"plate_carrier", 55.0))
			state.inventory.append(ItemInstance.create(&"night_optics", 30.0))
			for op in state.roster:
				op.morale = 35
			if state.roster.size() >= 2:
				Bonds.link(state.roster[0], state.roster[1], GameEnums.BondType.RIVALRY, 40)
			for id in FactionLibrary.ids():
				state.faction_standing[id] = 12
			# Somebody warm, somebody on the ward, so the events gated on those
			# fire their real line rather than their "nothing to report" fallback.
			state.faction_standing[FactionLibrary.HALBERD] = 65
			state.roster[3].status = GameEnums.OperatorStatus.INJURED
			state.roster[3].days_unavailable = 4
			state.facilities[FacilityLibrary.INFIRMARY] = 2

			var line := EventLibrary.apply(entry, campaign, campaign.rng)
			print("")
			print("  [%s] %s" % [entry["id"], entry["title"]])
			print("    %s" % line)
			break


func _incidents() -> void:
	_rule("INCIDENTS")
	for entry in IncidentLibrary.catalogue():
		var campaign := Campaign.new(null, SEED + 5)
		campaign.start_new_company(6)
		var state := campaign.state
		state.diamonds = -3000 if entry["id"] == &"creditor" else 30000
		state.reputation = 55
		state.deployed_last_week = 2
		for op in state.roster:
			op.morale = 35
		if state.roster.size() >= 2:
			Bonds.link(state.roster[0], state.roster[1], GameEnums.BondType.RIVALRY, 40)
		state.roster[2].status = GameEnums.OperatorStatus.INJURED
		state.roster[2].days_unavailable = 2
		state.roster[4].fatigue = 82
		for id in FactionLibrary.ids():
			state.faction_standing[id] = 45
		var worn := ItemInstance.create(&"night_optics", 34.0)
		state.inventory.append(worn)

		# Somebody in the ground, so the letter home has a name on it.
		var lost := OperatorFactory.create(campaign.rng, -1, OperatorFactory.Tier.VETERAN)
		lost.status = GameEnums.OperatorStatus.DEAD
		lost.died_on_mission = "Salt the Wells"
		lost.died_on_day = 40
		state.cemetery.append(lost)

		if not (entry["requires"] as Callable).call(state):
			print("")
			print("  [%s] (conditions not met)" % entry["id"])
			continue

		var built: Dictionary = (entry["build"] as Callable).call(campaign, campaign.rng)
		print("")
		print("  [%s] %s" % [entry["id"], built["title"]])
		print("    %s" % built["line"])
		for option in built["options"]:
			print("      > %s" % option["label"])
			print("        %s" % option["detail"])
			print("        -> %s" % (option["apply"] as Callable).call())


func _field_events() -> void:
	_rule("FROM THE FIELD")
	for entry in FieldEventLibrary.catalogue():
		var campaign := Campaign.new(null, SEED + 11)
		campaign.start_new_company(6)
		var state := campaign.state
		state.diamonds = 30000

		var squad := Squad.new()
		var free := state.deployable_operators()
		for i in mini(4, free.size()):
			squad.add(free[i], free[i].preferred_role)
		squad.set_leader(free[0])
		if squad.members().size() >= 3:
			Bonds.link(squad.members()[1], squad.members()[2], GameEnums.BondType.RIVALRY, 40)
			squad.members()[1].fatigue = 70

		var mission := MissionFactory.create_for_board(campaign.rng, {})
		# Any real place will do here — the prose rules care that a region NAME
		# lands in the sentence, not which one. Named ids rot: this one outlived
		# the region it pointed at and the situations were being written against
		# "the region" for months.
		mission.region_id = RegionLibrary.ids()[0]
		mission.risk = 60.0
		mission.duration_days = 6
		if entry["id"] == &"people_in_the_way":
			mission = MissionFactory.create(campaign.rng, GameEnums.MissionType.ASSAULT)
			mission.client_id = FactionLibrary.ids()[0]
		if entry["id"] == &"the_target_is_moving":
			mission = MissionFactory.create(
				campaign.rng, GameEnums.MissionType.ASSASSINATION)
			mission.client_id = FactionLibrary.ids()[0]
		if entry["id"] == &"patrol_on_the_route":
			mission = MissionFactory.create(campaign.rng, GameEnums.MissionType.INFILTRATION)
			mission.client_id = FactionLibrary.ids()[0]
		state.board.append(mission)
		if not campaign.deploy(squad, mission):
			print("")
			print("  [%s] (could not deploy)" % entry["id"])
			continue
		var deployment: Deployment = state.deployments[state.deployments.size() - 1]
		# Halfway through, so the events gated on how much of the contract is left
		# get a chance to fire.
		deployment.days_remaining = maxi(1, mission.duration_days / 2)

		if not (entry["requires"] as Callable).call(deployment, state):
			print("")
			print("  [%s] (conditions not met)" % entry["id"])
			continue

		var built: Dictionary = (entry["build"] as Callable).call(
			campaign, deployment, campaign.rng)
		print("")
		print("  [%s] %s" % [entry["id"], built["title"]])
		print("    %s" % built["line"])
		for option in built["options"]:
			print("      > %s" % option["label"])
			print("        %s" % option["detail"])
		# Apply the first option only, so the note lines show up.
		print("        -> %s" % (built["options"][0]["apply"] as Callable).call())
		for note in deployment.report.field_lines:
			print("        note | %s" % note)


func _resumes() -> void:
	_rule("RESUMES")
	var campaign := Campaign.new(null, SEED + 21)
	campaign.start_new_company(6)
	for op in campaign.state.roster:
		print("")
		print("  %s" % op.resume())
	for op in campaign.state.recruits:
		print("")
		print("  %s" % op.resume())

	# And a decorated veteran, so the long form gets read too.
	var vet := campaign.state.roster[0]
	vet.missions_completed = 27
	vet.missions_failed = 1
	vet.prior_service = 12
	vet.confirmed_kills = 41
	vet.saves = 3
	vet.trained_by = campaign.state.roster[1].display_label()
	vet.trainees = ["A", "B"]
	print("")
	print("  %s" % vet.resume())

	var rookie := campaign.state.roster[2]
	rookie.missions_completed = 1
	rookie.missions_failed = 1
	rookie.prior_service = 1
	rookie.confirmed_kills = 1
	rookie.saves = 1
	rookie.trainees = ["A"]
	print("")
	print("  %s" % rookie.resume())

	# The reported case, built exactly: a Nigerian sergeant second class with
	# eleven contracts elsewhere, nothing here yet, combat 85, no-nonsense.
	var reported := OperatorFactory.create(campaign.rng, GameEnums.Role.ASSAULT)
	reported.operator_name = "Zainab Abubakar"
	reported.callsign = "Husk"
	reported.nationality = &"nigeria"
	reported.rank = GameEnums.Rank.SERGEANT_SECOND
	reported.prior_service = 11
	reported.missions_completed = 0
	reported.missions_failed = 0
	reported.confirmed_kills = 0
	reported.saves = 0
	reported.traits = []
	reported.trained_by = ""
	reported.trainees = []
	reported.age = 34
	for skill in GameEnums.Skill.values():
		reported.skills[skill] = 40
	reported.skills[GameEnums.Skill.COMBAT] = 85
	reported.personality[GameEnums.PersonalityAxis.DISCIPLINE] = 82
	reported.personality[GameEnums.PersonalityAxis.AGGRESSION] = 55
	reported.personality[GameEnums.PersonalityAxis.BRAVERY] = 55
	reported.personality[GameEnums.PersonalityAxis.SOCIABILITY] = 45
	print("")
	print("  [reported case] %s" % reported.resume())

	# An instructor and somebody the years have caught up with, so the two
	# permanent status facts get read.
	var teacher := OperatorFactory.create(campaign.rng, -1, OperatorFactory.Tier.ELITE)
	teacher.career_track = GameEnums.CareerTrack.INSTRUCTOR
	teacher.rank = GameEnums.Rank.CAPTAIN
	teacher.missions_completed = 14
	teacher.missions_failed = 2
	teacher.prior_service = 9
	teacher.trainees = ["A", "B", "C"]
	print("")
	print("  [instructor]    %s" % teacher.resume())

	var old_hand := OperatorFactory.create(campaign.rng, -1, OperatorFactory.Tier.VETERAN)
	old_hand.age = 47
	old_hand.missions_completed = 6
	old_hand.missions_failed = 0
	old_hand.prior_service = 0
	print("")
	print("  [ageing]        %s" % old_hand.resume())


## A singular, a grammatical plural and a mass noun, each taken through a whole
## life. The class of the noun decides the article, the verb and the pronoun in
## every line, so all three have to be read side by side.
const _ITEM_CLASSES := [&"battle_rifle", &"shaped_charges", &"altitude_kit"]


func _item_histories() -> void:
	_rule("ITEM SERVICE RECORDS")
	var campaign := Campaign.new(null, SEED + 41)
	campaign.start_new_company(6)
	var state := campaign.state
	var mission := MissionFactory.create_for_board(campaign.rng, {})
	var second := MissionFactory.create_for_board(campaign.rng, {})

	var carrier: OperatorData = state.roster[0]
	var heir: OperatorData = state.roster[1]
	var estate: Array[ItemInstance] = []

	for item_id in _ITEM_CLASSES:
		var instance := ItemInstance.create(item_id)
		ItemHistory.record_purchase(instance, 3)
		ItemHistory.record_issue(instance, carrier, 5)
		ItemHistory.record_kills(instance, carrier, 4, 9, mission)
		instance.contracts = 6
		ItemHistory.record_broken(instance, 14, mission)
		instance.wear(85.0)
		instance.repair()
		ItemHistory.record_rebuild(instance, 17)
		var named := ItemHistory.record_loss(instance, carrier, 22, second)
		ItemHistory.record_issue(instance, heir, 24)
		estate.append(instance)

		print("")
		print("  --- %s" % instance.display_name())
		if not named.is_empty():
			print("      debrief | %s" % named)
		for line in ItemHistory.lines(instance):
			print("      %s" % line)

	# What the cemetery says about what they left behind, one item and several.
	print("")
	print("  --- headstone, %s" % carrier.display_label())
	print("      one   | %s" % ItemHistory.memorial_line(carrier, [estate[0]]))
	print("      many  | %s" % ItemHistory.memorial_line(carrier, estate))

	# And the ordinary case, which is most of them: bought last week, never used.
	var fresh := ItemInstance.create(&"night_optics")
	ItemHistory.record_purchase(fresh, 2)
	print("")
	print("  --- %s (nothing has happened to it)" % fresh.display_name())
	for line in ItemHistory.lines(fresh):
		print("      %s" % line)

	# Recovered off a contract rather than bought, so the other origin gets read.
	var salvaged := ItemInstance.create(&"plate_carrier", 51.0)
	ItemHistory.record_found(salvaged, 8, mission)
	print("")
	print("  --- %s" % salvaged.display_name())
	for line in ItemHistory.lines(salvaged):
		print("      %s" % line)


func _progression() -> void:
	_rule("PROGRESSION LINES")
	var campaign := Campaign.new(null, SEED + 33)
	campaign.start_new_company(4)
	var rng := campaign.rng

	var mentor: OperatorData = campaign.state.roster[0]
	var trainee: OperatorData = campaign.state.roster[1]
	mentor.rank = GameEnums.Rank.WARRANT_OFFICER
	for skill in GameEnums.Skill.values():
		mentor.skills[skill] = 95
		trainee.skills[skill] = 20
	var result := Progression.apply_training(mentor, trainee, rng)
	for line in result["trainee"]:
		print("    train | %s" % line)

	# A skill on the cusp of a star, taught and worked, so both mastery lines show.
	for skill in GameEnums.Skill.values():
		trainee.skills[skill] = 100
	var starred := Progression.apply_training(mentor, trainee, rng)
	for line in starred["trainee"]:
		print("    star  | %s" % line)

	var profile := MissionResolver.profile_for(GameEnums.MissionType.INFILTRATION)
	var worker: OperatorData = campaign.state.roster[2]
	for line in Progression.grow_skills(worker, profile, true, GameEnums.Role.SCOUT):
		print("    grow  | %s" % line)
	for skill in GameEnums.Skill.values():
		worker.skills[skill] = 100
	for line in Progression.grow_skills(worker, profile, true, GameEnums.Role.SCOUT):
		print("    grow* | %s" % line)

	_rule("MEDALS AND TRAITS")
	# Through award_earned rather than formatted here, so the dump reads exactly
	# what the after-action screen would print.
	var decorated := OperatorFactory.create(campaign.rng, -1, OperatorFactory.Tier.ELITE)
	decorated.confirmed_kills = 100
	decorated.saves = 5
	decorated.missions_completed = 25
	decorated.trainees = ["A", "B", "C", "D", "E"]
	for line in MedalLibrary.award_earned(decorated, true, true):
		print("    medal | %s" % line)
	for t in TraitLibrary.all().values():
		print("    trait | %s — %s" % [t.display_name, t.description])
