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

static func write(report: MissionReport, rng: RandomNumberGenerator) -> Array[String]:
	var lines: Array[String] = []
	var mission := report.mission
	var region := mission.region()

	# 1. Arrival, taken from the contract itself so the feed opens on the brief.
	var place: String = mission.region_name()
	lines.append("The squad went in at %s." % place)

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
	if report.withdrew:
		lines.append("They broke contact and came out with the job unfinished.")
	else:
		var total_kills := 0
		for op in report.kills:
			total_kills += int(report.kills[op])

		if total_kills == 0:
			lines.append("Nobody fired a shot.")
		elif total_kills <= 2:
			lines.append("There was a brief exchange, and %s went down on their side." % (
				TextUtil.spelled(total_kills, "man", "men")))
		elif total_kills <= 8:
			lines.append("It turned into a proper fight, with %s accounted for." % (
				TextUtil.spelled(total_kills, "of theirs", "of theirs")))
		else:
			lines.append("It became a battle. %s of theirs did not walk away." % (
				TextUtil.number_capitalised(total_kills)))

		# 4. Who carried it. The best shot gets named, because a feed with names
		# in it is one the player remembers.
		var top: OperatorData = null
		for op in report.kills:
			if top == null or int(report.kills[op]) > int(report.kills[top]):
				top = op
		if top != null and int(report.kills[top]) >= 2:
			lines.append("%s did most of it." % top.display_label())

	# 5. Casualties, in the order that matters.
	var dead: Array = report.casualties()
	var hurt: Array = report.wounded()
	if not dead.is_empty():
		var names: Array = []
		for op in dead:
			names.append(op.display_label())
		lines.append("%s did not come back." % TextUtil.join_names(names))
	if not hurt.is_empty():
		lines.append("%s came back needing the infirmary." % (
			TextUtil.number_capitalised(hurt.size())))

	# 6. A save, if a medic was there to make one.
	for op in report.saves:
		var rescued: OperatorData = report.saves[op]
		lines.append("%s got %s off the ground and kept them there." % [
			op.display_label(), rescued.display_label()])

	# 7. The trophy overrides the ending — it IS the ending.
	if not report.trophy_line.is_empty():
		lines.append(report.trophy_line)

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
		]
		lines.append(wins[rng.randi() % wins.size()])
	else:
		var losses := [
			"They pulled out with the job unfinished.",
			"It went wrong early and never came back.",
			"The client will hear about this from someone else first.",
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
