class_name Bonds
extends RefCounted

## Who gets on with whom.
##
## Bonds live on the operators themselves rather than in a central registry, so
## MissionResolver can read them straight off a Squad without being handed extra
## state. The cost is that every link exists twice, once on each side — so
## nothing outside this file may touch `op.bonds` directly. Write through `link`
## and both halves stay in step.
##
## The doc asks for rivalry, friendship and a deliberately rare romance. What
## makes them worth having is that they are consequences: they form from who
## survived what together, and then they change who you can afford to send.


static func get_bond(a: OperatorData, b: OperatorData) -> Dictionary:
	return a.bonds.get(b.id, {})


static func has_bond(a: OperatorData, b: OperatorData) -> bool:
	return a.bonds.has(b.id)


static func bond_type(a: OperatorData, b: OperatorData) -> int:
	var bond := get_bond(a, b)
	return int(bond.get("type", -1))


static func strength(a: OperatorData, b: OperatorData) -> int:
	var bond := get_bond(a, b)
	return int(bond.get("strength", 0))


## Creates or deepens a link, on both sides. Changing the type resets strength —
## a friendship that curdles into rivalry starts over.
static func link(
	a: OperatorData,
	b: OperatorData,
	type: int,
	gain: int,
	reason: String = ""
) -> void:
	if a == b:
		return
	_write(a, b, type, gain, reason)
	_write(b, a, type, gain, reason)


static func _write(
	from: OperatorData,
	to: OperatorData,
	type: int,
	gain: int,
	reason: String
) -> void:
	var existing: Dictionary = from.bonds.get(to.id, {})
	var current_type: int = int(existing.get("type", type))
	var current_strength: int = int(existing.get("strength", 0))
	var current_reason: String = str(existing.get("reason", ""))

	if current_type != type:
		current_strength = 0
		current_type = type
		current_reason = ""

	# The first cause sticks. "They fell out over Salt the Wells" is a story;
	# overwriting it every contract turns it back into a number.
	if current_reason.is_empty() and not reason.is_empty():
		current_reason = reason

	from.bonds[to.id] = {
		"type": current_type,
		"strength": mini(current_strength + gain, Balance.BOND_STRENGTH_MAX),
		"reason": current_reason,
	}


static func reason_for(a: OperatorData, b: OperatorData) -> String:
	return str(get_bond(a, b).get("reason", ""))


static func remove(a: OperatorData, b: OperatorData) -> void:
	a.bonds.erase(b.id)
	b.bonds.erase(a.id)


## One-sided: strips this operator out of everyone else's book while leaving
## their own intact. Used on death — the living must stop being scored for a
## friendship with a corpse, but the headstone should still say who they were
## close to.
static func detach(op: OperatorData, others: Array) -> void:
	for other in others:
		if other != op:
			other.bonds.erase(op.id)


## Everyone this operator has a link with, resolved against a roster.
## Returns [{ "other": OperatorData, "type": int, "strength": int }].
static func list_for(op: OperatorData, roster: Array) -> Array:
	var found: Array = []
	for other in roster:
		if other == op or not op.bonds.has(other.id):
			continue
		var bond: Dictionary = op.bonds[other.id]
		found.append({
			"other": other,
			"type": int(bond.get("type", 0)),
			"strength": int(bond.get("strength", 0)),
		})
	found.sort_custom(func(x, y): return x["strength"] > y["strength"])
	return found


## Which way a pair is likely to go, from temperament. Sociable people make
## friends; two aggressive ones grate. Nothing here is certain — the roll in
## evolve_after_mission decides.
static func _likely_type(a: OperatorData, b: OperatorData, rng: RandomNumberGenerator) -> int:
	var sociability: float = float(
		a.get_personality(GameEnums.PersonalityAxis.SOCIABILITY)
		+ b.get_personality(GameEnums.PersonalityAxis.SOCIABILITY)
	) / 2.0
	var aggression: float = float(
		a.get_personality(GameEnums.PersonalityAxis.AGGRESSION)
		+ b.get_personality(GameEnums.PersonalityAxis.AGGRESSION)
	) / 2.0

	if rng.randf() < Balance.BOND_ROMANCE_SHARE:
		return GameEnums.BondType.ROMANCE

	# Sociability pulls toward friendship, aggression toward friction.
	var friendly_odds: float = clampf(
		Balance.BOND_FRIENDLY_BASE + (sociability - aggression) / 200.0, 0.25, 0.95)
	if rng.randf() < friendly_odds:
		return GameEnums.BondType.FRIENDSHIP
	return GameEnums.BondType.RIVALRY


## Called when a squad comes home. Survivors who went through something together
## get closer; a failure sours a pairing that was already rocky.
## Returns lines describing anything new, for the after-action screen.
static func evolve_after_mission(
	report: MissionReport,
	rng: RandomNumberGenerator
) -> Array[String]:
	var log: Array[String] = []
	var survivors: Array = []
	for op in report.squad.members():
		if report.fates.get(op, GameEnums.Fate.UNHARMED) != GameEnums.Fate.KILLED:
			survivors.append(op)

	for i in survivors.size():
		for j in range(i + 1, survivors.size()):
			var a: OperatorData = survivors[i]
			var b: OperatorData = survivors[j]
			if rng.randf() >= Balance.BOND_FORM_CHANCE:
				continue

			var existing_type: int = bond_type(a, b)
			var type: int = existing_type
			if existing_type < 0:
				type = _likely_type(a, b, rng)
				# A contract that went badly is where blame gets assigned.
				if not report.success and type == GameEnums.BondType.FRIENDSHIP \
						and rng.randf() < Balance.BOND_BLAME_ON_FAILURE:
					type = GameEnums.BondType.RIVALRY

			var before: int = strength(a, b)
			link(a, b, type, Balance.BOND_STRENGTH_GAIN,
				_reason_for_new_bond(type, report, rng))

			if existing_type < 0:
				log.append("%s and %s: %s" % [
					a.display_label(), b.display_label(), _phrase(type)])
			elif before < Balance.BOND_STRENGTH_MAX:
				log.append("%s and %s grew closer" % [a.display_label(), b.display_label()]
					if type != GameEnums.BondType.RIVALRY
					else "%s and %s fell out further" % [a.display_label(), b.display_label()])

	return log


## Why these two ended up like this. Drawn from the contract they shared, so the
## roster reads as a history rather than a table of relationship values.
##
## A contract title is the name of a JOB, not of a place — "Nobody Was There",
## "Deliver or Die" — so every template here has to frame it as one. "Got each
## other out of Nobody Was There" reads as a location and falls apart; "on
## Nobody Was There" and "how Nobody Was There went" both hold. The region is
## available for the templates that genuinely want somewhere.
##
## GRAMMAR (see .docs/prose_style_guide.md): every line is a COMPLETE SENTENCE
## carrying its own subject — "They", "One of them", "Neither of them" — capital
## first letter, closing stop. The relationships screen prints this on its own
## under the two portraits with no lead-in of its own, so subjectless fragments
## ("Blamed each other for how X went.") read as a note somebody forgot to
## finish, and a bare noun phrase ("A disagreement about an order given on X.")
## reads as a caption for a picture that is not there.
## Named placeholders rather than "%s": these pools mix two substitutions —
## `{title}` is the name of the job, `{place}` is where it happened — and a
## positional template makes the two impossible to tell apart at the point where
## somebody is writing a new line. A template may use either, both or neither.
const BOND_REASONS := {
	GameEnums.BondType.ROMANCE: [
		"Something started on the way back from {title}.",
		"Nobody will say what happened after {title}.",
		"Whatever this is, it started somewhere in {place}.",
		"They came off {title} standing closer than they went in.",
	],
	GameEnums.BondType.FRIENDSHIP: [
		"They got each other out alive on {title}.",
		"They shared a very long night on {title}.",
		"One of them carried the other out on {title}.",
		"They went through {title} together and came back agreeing about it.",
		"Neither of them talks about {title} to anybody else.",
		"They were the last two moving on {title}.",
	],
	GameEnums.BondType.RIVALRY: [
		"They blamed each other for how {title} went.",
		"They argued over the take from {title} and never settled it.",
		"One of them broke contact first on {title}. Both remember it differently.",
		"They fell out over an order given on {title}.",
		"One of them was somewhere else when it mattered on {title}.",
		"They have not agreed on a single detail of {title} since.",
	],
}


static func _reason_for_new_bond(
	type: int,
	report: MissionReport,
	rng: RandomNumberGenerator
) -> String:
	var pool: Array = BOND_REASONS.get(type, BOND_REASONS[GameEnums.BondType.RIVALRY])
	return str(pool[rng.randi() % pool.size()]).format({
		"title": report.mission.title,
		"place": report.mission.region_place(),
	})


static func _phrase(type: int) -> String:
	match type:
		GameEnums.BondType.FRIENDSHIP:
			return "became friends"
		GameEnums.BondType.ROMANCE:
			return "fell for each other"
		_:
			return "cannot stand each other"


## Plain-English label for the roster sheet.
static func describe(type: int, bond_strength: int) -> String:
	var depth: String = "Close" if bond_strength >= 70 else ("Growing" if bond_strength >= 35 else "New")
	match type:
		GameEnums.BondType.FRIENDSHIP:
			return "%s friendship" % depth
		GameEnums.BondType.ROMANCE:
			return "%s romance" % depth
		_:
			return "%s rivalry" % depth


static func color_for(type: int) -> Color:
	match type:
		GameEnums.BondType.FRIENDSHIP:
			return UiStyle.MINT
		GameEnums.BondType.ROMANCE:
			return UiStyle.STEEL
		_:
			return UiStyle.RUST
