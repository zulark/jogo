class_name MissionReport
extends RefCounted

## Everything the resolver worked out about a deployment.
##
## Produced twice in a mission's life:
##   1. As a PREVIEW while the player is still arranging the squad — odds and
##      breakdown only, nothing rolled.
##   2. As a RESULT after the mission runs — same breakdown, plus the dice.
##
## The breakdown is the point. A bare "62%" tells the player nothing; a list
## saying WHY it is 62% is what makes squad building a decision instead of a
## guess.

var mission: MissionData = null
var squad: Squad = null

## Every line that went into the score, in the order it was applied.
var modifiers: Array[Modifier] = []

## Operator id -> "Name (Role)". Per-operator modifier labels are kept short
## ("Skills", "Rank: Corporal") and the name is printed once as a group heading,
## so the breakdown does not repeat the same name on every line.
var operator_labels: Dictionary = {}

var squad_score: float = 0.0
var difficulty: float = 0.0
var success_chance: float = 0.0

## What casing this contract turned out to be worth, as the preview priced it.
## Kept separately from the modifier line it also produces because intel buys two
## different things — score on the odds, and threat off every operator's harm
## roll — and roll() has to spend the second one against the exact figure the
## player was quoted at the door rather than whatever the mission says later.
var intel_applied: float = 0.0

## --- Filled in only after roll() ---
var rolled: bool = false
var success: bool = false
var roll_value: float = 0.0
var reward_paid: int = 0

## OperatorData -> GameEnums.Fate
var fates: Dictionary = {}

## OperatorData -> days unavailable (0 for unharmed and dead)
var recovery_days: Dictionary = {}

## OperatorData -> xp gained
var xp_gained: Dictionary = {}

## OperatorData -> Array[String] of what changed about them: skill gains, traits
## picked up, promotions. Filled by Progression when the squad comes home.
var progression: Dictionary = {}

## OperatorData -> morale delta from this contract.
var morale_change: Dictionary = {}

## OperatorData -> confirmed kills on this contract.
var kills: Dictionary = {}

## What happened out there, in order. Written from the briefing and the dice so
## it never contradicts either.
var story: Array[String] = []

## The decisions the player took over the radio while the squad was out, in the
## order they were taken. MissionStory folds them into the feed, so the report
## reads as one account rather than as a debrief with a separate log beside it.
var field_lines: Array[String] = []

## Operators pulled out of the contract early. They take no further part: no
## harm roll, no kills, and the score they were contributing is subtracted in
## the breakdown rather than quietly removed.
var withdrawn: Array = []

## Set when the player called the whole thing off. A failure, but not the same
## failure as being beaten — nobody was still standing there when it ended.
var withdrew: bool = false

## OperatorData -> squadmates they pulled out.
var saves: Dictionary = {}

## Item ids brought back.
var loot: Array[StringName] = []

## Parts recovered off the contract, spendable at a bench.
var salvage_gained: int = 0

## Plans for something the shops do not sell, if this one turned any up.
var blueprint_found: StringName = &""

## What the contract did to the kit that went on it — only the lines worth
## reading, which means wear that crossed into unserviceable and anything signed
## back in off somebody who did not come home.
var kit_notes: Array[String] = []

## Set when a named target went down. The headline of the whole contract.
var trophy_line: String = ""

## One line per kill, in the order they happened, for the feed.
var kill_feed: Array[String] = []

## Friendships, rivalries and romances that formed or deepened out there.
var bond_log: Array[String] = []

## How the company's standing moved because of this contract.
var reputation_change: int = 0

## And how the client who commissioned it feels about you now.
var client_standing_change: int = 0


func add_modifier(label: String, value: float, source: int, op_id: StringName = &"") -> void:
	modifiers.append(Modifier.create(label, value, source, op_id))


## Everything this operator is currently worth to the squad score, read straight
## off the breakdown rather than recalculated. Pulling somebody out of a contract
## costs exactly this, and taking the number from the list is what stops the
## breakdown and the score from disagreeing.
func contribution_of(op: OperatorData) -> float:
	var total := 0.0
	for m in modifiers:
		if m.operator_id == op.id:
			total += m.value
	return total


func modifiers_by_source(source: int) -> Array[Modifier]:
	var result: Array[Modifier] = []
	for m in modifiers:
		if m.source == source:
			result.append(m)
	return result


func casualties() -> Array:
	var dead: Array = []
	for op in fates:
		if fates[op] == GameEnums.Fate.KILLED:
			dead.append(op)
	return dead


func wounded() -> Array:
	var hurt: Array = []
	for op in fates:
		var fate: int = fates[op]
		if fate == GameEnums.Fate.WOUNDED or fate == GameEnums.Fate.TRAUMATIZED:
			hurt.append(op)
	return hurt


func chance_percent() -> int:
	return int(round(success_chance * 100.0))


## Human-readable dump. Used by the simulation harness and handy for debugging
## a squad the player thinks should have won.
func to_text() -> String:
	var lines: PackedStringArray = []
	lines.append("=== %s (%s) ===" % [mission.title, mission.type_name()])
	lines.append("Squad: %s, leader %s" % [
		TextUtil.count(squad.size(), "operator"),
		squad.leader.display_label() if squad.leader else "none",
	])
	lines.append("")
	var current_owner: StringName = &"￿"
	for m in modifiers:
		if m.operator_id != current_owner:
			current_owner = m.operator_id
			lines.append("  " + str(operator_labels.get(current_owner, "SQUAD")))
		lines.append("    " + m.to_line())
	lines.append("")
	lines.append("  %-46s %6.1f" % ["SQUAD SCORE", squad_score])
	lines.append("  %-46s %6.1f" % ["MISSION DIFFICULTY", difficulty])
	lines.append("  %-46s %5d%%" % ["SUCCESS CHANCE", chance_percent()])

	if rolled:
		lines.append("")
		lines.append("  ROLL %.1f -> %s" % [roll_value * 100.0, "SUCCESS" if success else "FAILURE"])
		lines.append("  Payout: %d diamonds" % reward_paid)
		for op in fates:
			var fate_name: String = GameEnums.Fate.keys()[fates[op]]
			var days: int = int(recovery_days.get(op, 0))
			var suffix: String = (" (%s)" % TextUtil.count(days, "day")) if days > 0 else ""
			lines.append("    %-28s %s%s" % [op.display_label(), fate_name, suffix])
	return "\n".join(lines)
