class_name RegionLog
extends RefCounted

## What the company has done in each place, and the only thing allowed to write
## it — the rule `Bonds` holds over `op.bonds` and `ItemHistory` holds over an
## item's record, for the same reason. One writer is what stops a count on the
## map disagreeing with the count in the panel beside it.
##
## THE MAP IS WHY THIS EXISTS. A board of markers on an empty grid says where
## the work is and nothing about where the company has BEEN, so every region
## read exactly the same on day 200 as on day 1. A place the company has buried
## somebody in should not look like a place it has never heard of, and until now
## there was nowhere for that fact to live.
##
## Every field counts something that actually happened and is written at the
## moment it happens, which is the standard the events, the incidents and the
## item histories are all held to. Nothing here is inferred. A region with no
## entry has never been worked, and the map says nothing about it rather than
## saying zero — an absence and a nil are different facts.

const EMPTY := {
	"contracts": 0,
	"won": 0,
	"lost": 0,
	"dead": 0,
	"hurt": 0,
	"last_day": 0,
}


## The record for one place, always fully populated so callers never branch on a
## missing key. JSON hands integers back as floats, which is why every field is
## read through int() rather than taken as it comes.
static func entry(state: GameState, region_id: StringName) -> Dictionary:
	var found: Dictionary = state.region_log.get(region_id, {})
	var record := EMPTY.duplicate()
	for key in record:
		if found.has(key):
			record[key] = int(found[key])
	return record


static func has_history(state: GameState, region_id: StringName) -> bool:
	return int(entry(state, region_id)["contracts"]) > 0


## Called once per contract, as it resolves.
##
## A contract the company called off still counts as having been there: people
## went, the ground was walked, and somebody may not have come back. Recording
## only the ones that ran to the end would make the map quietly forget the worst
## days the company had.
static func record_contract(state: GameState, report: MissionReport) -> void:
	if report.mission == null or report.mission.region_id == &"":
		return

	var record := entry(state, report.mission.region_id)
	record["contracts"] += 1
	if report.success:
		record["won"] += 1
	else:
		record["lost"] += 1
	record["dead"] += report.casualties().size()
	record["hurt"] += report.wounded().size()
	record["last_day"] = state.day
	state.region_log[report.mission.region_id] = record


## How heavily the company has worked somewhere, 0 to 3. The map draws this, so
## it is deliberately coarse: the eye is being asked "have we been here a lot",
## not "how many exactly".
static func weight(state: GameState, region_id: StringName) -> int:
	var contracts: int = int(entry(state, region_id)["contracts"])
	if contracts >= 6:
		return 3
	if contracts >= 3:
		return 2
	if contracts >= 1:
		return 1
	return 0


## The company's record in one place, as sentences.
##
## Returns "" when there is nothing to say. Callers must treat that as "show
## nothing" rather than printing an empty section — a heading over a blank is
## how a UI implies data it does not have.
static func summary(state: GameState, region_id: StringName) -> String:
	var record := entry(state, region_id)
	var contracts: int = int(record["contracts"])
	if contracts <= 0:
		return ""

	var parts: Array = []

	# The tally, said as one clause rather than two counts. "Three contracts
	# here, all of which came off" beats "3 contracts. Won 3. Lost 0" for the
	# same reason the biography stopped listing fields in v0.16.
	var won: int = int(record["won"])
	var lost: int = int(record["lost"])
	var here: String = TextUtil.spelled_capitalised(contracts, "contract")
	if lost == 0:
		parts.append("%s here, and all of them came off" % here)
	elif won == 0:
		parts.append("%s here, and none of them came off" % here)
	else:
		parts.append("%s here: %s came off, %s did not" % [
			here, TextUtil.number(won), TextUtil.number(lost)])

	var dead: int = int(record["dead"])
	var hurt: int = int(record["hurt"])
	if dead > 0:
		parts.append("%s buried" % TextUtil.spelled_capitalised(dead, "operator"))
	elif hurt > 0:
		parts.append("%s came home hurt" % TextUtil.spelled_capitalised(hurt, "operator"))
	else:
		parts.append("Nobody has been lost here")

	parts.append("Last worked on day %d" % int(record["last_day"]))
	return TextUtil.sentences(parts)
