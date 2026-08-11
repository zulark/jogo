class_name MissionStory
extends RefCounted

## What happened out there, written after the dice have been rolled.
##
## Every line is derived from something that actually occurred — the briefing's
## own opening, the ground, whether a squad member went down, who did the
## shooting, how it ended. Nothing here invents an event the systems did not
## produce, which is the difference between flavour text and a lie: if the feed
## says the medic worked through the night, the report also shows a wounded
## operator and a medic in the squad.

## How the feed opens, by the kind of work it was. One line every time — "The
## squad went in at Angolan Coast" — read as a log entry rather than an account,
## and got the article wrong on top of it. Every opener here takes the place as
## it reads in a sentence: see RegionData.place().
const OPENINGS := {
	GameEnums.MissionType.ASSAULT: [
		"They went in loud, in %s, a little before dawn.",
		"The squad crossed into %s and did not bother hiding it.",
		"It started in %s with a door and a great deal of noise.",
	],
	GameEnums.MissionType.INFILTRATION: [
		"They went into %s quietly, and on foot.",
		"The squad let themselves into %s without anybody logging it.",
		"Nobody in %s was told the company had arrived.",
	],
	GameEnums.MissionType.RESCUE: [
		"The squad went into %s looking for people.",
		"They reached %s on the second night and started asking.",
		"It began in %s, with an address and not much else.",
	],
	GameEnums.MissionType.RECON: [
		"They lay up above %s and watched.",
		"The squad went into %s to look at it, and nothing more.",
		"Two of them sat on %s for as long as the water lasted.",
	],
	GameEnums.MissionType.SABOTAGE: [
		"They went into %s carrying more tools than ammunition.",
		"The squad reached %s with a list of things that had to stop working.",
		"It started in %s, at a fence line nobody was watching.",
	],
	GameEnums.MissionType.ESCORT: [
		"They picked the load up on the near side of %s and started driving.",
		"The squad took the road through %s with the cargo in the middle.",
		"It was a long crossing of %s, and it started well enough.",
	],
	GameEnums.MissionType.ASSASSINATION: [
		"They went into %s for one person.",
		"The squad reached %s two days early and waited.",
		"It began in %s, with a routine somebody had written down.",
	],
}

const OPENING_FALLBACK := ["The squad went to work in %s."]


static func write(report: MissionReport, rng: RandomNumberGenerator) -> Array[String]:
	var lines: Array[String] = []
	var mission := report.mission
	var region := mission.region()

	# 1. Arrival, taken from the contract itself so the feed opens on the brief.
	var openings: Array = OPENINGS.get(mission.mission_type, OPENING_FALLBACK)
	lines.append(openings[rng.randi() % openings.size()] % mission.region_place())

	# 2. The ground, if it had anything to say.
	if region != null and region.hazard != GameEnums.Hazard.NONE:
		lines.append(_hazard_line(region.hazard, report))

	# 2b. What the company told them to do while they were out there. These are
	# the player's own decisions, so they go in ahead of the shooting — the feed
	# should read as the consequence of a call somebody made, not as a log.
	lines.append_array(report.field_lines)

	# 3. Contact, sized by how much shooting actually happened. A contract the
	# company called off is described by the withdrawal instead — nobody wants a
	# blow-by-blow of a fight that was broken off on purpose — but what it cost
	# on the way out, below, still gets said.
	var dead: Array = report.casualties()
	var hurt: Array = report.wounded()

	# Who carried it. Named because a feed with names in it is one the player
	# remembers — but held back until the casualty list is known, because "X did
	# most of it." immediately followed by "X did not come back." reads as two
	# unrelated reports of the same person.
	var top: OperatorData = null

	if report.withdrew:
		lines.append("They broke contact and came out with the job unfinished.")
	else:
		var total_kills := 0
		for op in report.kills:
			total_kills += int(report.kills[op])

		if total_kills == 0:
			lines.append("Nobody fired a shot.")
		elif total_kills <= 2:
			lines.append("There was a brief exchange, and %s went down on the other side." % (
				TextUtil.spelled(total_kills, "man", "men")))
		elif total_kills <= 8:
			lines.append("It turned into a proper fight, and %s of theirs did not get up." % (
				TextUtil.number(total_kills)))
		else:
			lines.append("It became a battle. %s of theirs did not walk away." % (
				TextUtil.number_capitalised(total_kills)))

		for op in report.kills:
			if top == null or int(report.kills[op]) > int(report.kills[top]):
				top = op
		if top != null and int(report.kills[top]) >= 2 and not dead.has(top):
			lines.append("%s did most of it." % top.display_label())

	# 5. Casualties, in the order that matters. The best shot, if they were also
	# the one who did not come home, is said once and in one breath — it is the
	# single most affecting sentence the feed can produce and splitting it in two
	# throws it away.
	if not dead.is_empty():
		if top != null and dead.has(top) and int(report.kills.get(top, 0)) >= 2 \
				and dead.size() == 1:
			lines.append("%s did most of the fighting, and did not come back." % (
				top.display_label()))
		else:
			var names: Array = []
			for op in dead:
				names.append(op.display_label())
			lines.append("%s did not come back." % TextUtil.join_names(names))

	if not hurt.is_empty():
		if hurt.size() == 1:
			lines.append("%s came back needing the infirmary." % hurt[0].display_label())
		else:
			lines.append("%s of them came back needing the infirmary." % (
				TextUtil.number_capitalised(hurt.size())))

	# 6. A save, if a medic was there to make one.
	for op in report.saves:
		var rescued: OperatorData = report.saves[op]
		lines.append("%s got %s off the ground and kept them breathing all the way out." % [
			op.display_label(), rescued.display_label()])

	# 7. The trophy is deliberately NOT repeated here. AfterAction already prints
	# it as the headline of this column, under a ☠, and appending it to the feed
	# as well meant the player read the same sentence twice on the same card.
	# The kill is the headline; the lines below are still the account of it.

	# 8. How it closed. A withdrawal already has its ending — the company chose
	# it — so it does not get one of the failure lines, which are all about being
	# beaten.
	if report.withdrew:
		lines.append("%s was told the contract would not be completed." % (
			mission.client_name()))
	elif report.success:
		var wins := [
			"The client got what they paid for.",
			"Contract closed. The client did not ask for details.",
			"Done, and the invoice went out the same evening.",
			"It held together, and the job was signed off on the ground.",
			"Everything the contract asked for, and nothing it did not.",
			"The client had what they wanted before anybody had finished writing it up.",
		]
		lines.append(wins[rng.randi() % wins.size()])
	else:
		var losses := [
			"They came out with the job unfinished.",
			"It went wrong early and never came back.",
			"The client will hear about this from someone else first.",
			"Whatever the contract wanted, it is still there.",
			"They got out. That is the most that can be said for it.",
			"The job was beyond them on the day, and everybody knew it by the end.",
		]
		lines.append(losses[rng.randi() % losses.size()])

	return lines


static func _hazard_line(hazard: int, report: MissionReport) -> String:
	# Only complain about the ground for people who were not equipped for it.
	var uncovered := 0
	var region := report.mission.region()
	for op in report.squad.members():
		var covered := false
		for item in op.equipment():
			if item.counters(region.hazard):
				covered = true
				break
		if not covered:
			uncovered += 1

	if uncovered == 0:
		match hazard:
			GameEnums.Hazard.INFECTION:
				return "Wet heat the whole way, but everyone had been dosed for it."
			GameEnums.Hazard.HEAT:
				return "Brutal heat. They had water and shade and it was fine."
			GameEnums.Hazard.COLD:
				return "Well below freezing, and the kit held."
			_:
				return "Thin air on the approach. The bottles did their job."

	match hazard:
		GameEnums.Hazard.INFECTION:
			return "Wet heat, standing water, and %s of them without antiseptics." % (
				TextUtil.number(uncovered))
		GameEnums.Hazard.HEAT:
			return "The heat did more damage than anyone shooting at them."
		GameEnums.Hazard.COLD:
			return "%s of them spent the night without cold weather kit." % (
				TextUtil.number_capitalised(uncovered))
		_:
			return "The approach was above four thousand metres, and %s of them were gasping." % (
				TextUtil.number(uncovered))
