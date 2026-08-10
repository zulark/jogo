class_name GameState
extends RefCounted

## Everything a save file contains. Pure data plus queries — it never advances
## time or resolves anything, which is Campaign's job. Keeping the split means
## the save format is decided by one small class instead of leaking into every
## system that touches the roster.

const STARTING_DIAMONDS := 9000
const BOARD_SIZE := 6
const RECRUIT_POOL_SIZE := 4

## Day 1 is the first day of week 1. The player ends days when they choose;
## every seventh day close charges payroll.
var day: int = 1
var diamonds: int = STARTING_DIAMONDS

var roster: Array[OperatorData] = []
var cemetery: Array[OperatorData] = []
var board: Array[MissionData] = []
var recruits: Array[OperatorData] = []
var deployments: Array[Deployment] = []
var training: Array[TrainingSession] = []

## Standing work: what is on offer, and who is away doing it.
var side_jobs: Array[SideJobData] = []
var detachments: Array[Detachment] = []

## Teams away casing contracts. The bench's other job.
var intel_ops: Array[IntelOp] = []

## FactionLibrary id -> weekly payment. A client on this list is paying to keep
## the company on call, and may call.
var retainers: Dictionary = {}

## FacilityLibrary id -> level. Absent or 0 means not built.
var facilities: Dictionary = {}

## Item ids the company owns, one entry per copy. Equipped items stay in here —
## the operator holds a reference, the company still owns the thing.
var inventory: Array[StringName] = []

## 0-100. What clients think the company is worth. Gates the blackmarket and
## nudges what contracts pay.
var reputation: int = Balance.REPUTATION_START

## FactionLibrary id -> 0-100 standing with that client specifically. Separate
## from `reputation`, which is the company's general name in the trade: you can
## be famous and still be the last people the Cartel would call.
var faction_standing: Dictionary = {}

## Deployed headcount for the current week, reset each week close. Ammunition is
## billed on work actually done, not on who happens to be out on payday.
var deployed_this_week: int = 0

## Signing bonus is a multiple of weekly salary, so good people cost to land as
## well as to keep.
const HIRE_COST_WEEKS := 3


func week() -> int:
	return (day - 1) / Balance.DAYS_PER_WEEK + 1


func day_of_week() -> int:
	return (day - 1) % Balance.DAYS_PER_WEEK + 1


func is_week_end() -> bool:
	return day_of_week() == Balance.DAYS_PER_WEEK


## Everyone on the payroll, including the wounded. You pay people to heal.
func weekly_payroll() -> int:
	var total := 0
	for op in roster:
		if op.status != GameEnums.OperatorStatus.DEAD:
			total += op.salary
	return total


func available_operators() -> Array[OperatorData]:
	var free: Array[OperatorData] = []
	for op in roster:
		if op.is_deployable():
			free.append(op)
	return free


func hire_cost(op: OperatorData) -> int:
	return op.salary * HIRE_COST_WEEKS


# --- Headcounts, for the budget sheet ----------------------------------------

func living_roster_size() -> int:
	var count := 0
	for op in roster:
		if op.status != GameEnums.OperatorStatus.DEAD:
			count += 1
	return count


func deployed_headcount() -> int:
	return deployed_this_week


func injured_headcount() -> int:
	var count := 0
	for op in roster:
		if op.status == GameEnums.OperatorStatus.INJURED:
			count += 1
	return count


# --- Facilities --------------------------------------------------------------

func standing_with(faction_id: StringName) -> int:
	return int(faction_standing.get(faction_id, 0))


func adjust_standing(faction_id: StringName, delta: int) -> void:
	if faction_id == &"":
		return
	faction_standing[faction_id] = clampi(standing_with(faction_id) + delta, 0, 100)


func facility_level(id: StringName) -> int:
	return int(facilities.get(id, 0))


func built_facility_count() -> int:
	var count := 0
	for id in facilities:
		if int(facilities[id]) > 0:
			count += 1
	return count


## Magnitude of a facility's effect at its current level. 0.0 when not built, so
## callers can multiply without branching.
func facility_effect(id: StringName) -> float:
	var facility := FacilityLibrary.get_facility(id)
	if facility == null:
		return 0.0
	return facility.effect_at(facility_level(id))


# --- Inventory ---------------------------------------------------------------

func storage_capacity() -> int:
	return FacilityLibrary.BASE_STORAGE + int(facility_effect(FacilityLibrary.WAREHOUSE))


func storage_used() -> int:
	return inventory.size()


func has_storage_room() -> bool:
	return storage_used() < storage_capacity()


## Copies of an item the company owns that nobody is carrying.
func unequipped_count(item_id: StringName) -> int:
	var owned := 0
	for id in inventory:
		if id == item_id:
			owned += 1
	for op in roster:
		if op.weapon_id == item_id or op.gear_id == item_id:
			owned -= 1
	return maxi(0, owned)


## Items of a given slot that are free to hand to someone.
func available_items(slot: int) -> Array[ItemData]:
	var seen := {}
	var free: Array[ItemData] = []
	for id in inventory:
		if seen.has(id):
			continue
		seen[id] = true
		var item := ItemLibrary.get_item(id)
		if item != null and item.slot == slot and unequipped_count(id) > 0:
			free.append(item)
	return free


func find_operator(id: StringName) -> OperatorData:
	for op in roster:
		if op.id == id:
			return op
	return null


func is_deployed(op: OperatorData) -> bool:
	for deployment in deployments:
		if deployment.squad.members().has(op):
			return true
	return false


func is_training(op: OperatorData) -> bool:
	for session in training:
		if session.mentor == op or session.trainee == op:
			return true
	return false


func is_detached(op: OperatorData) -> bool:
	for detachment in detachments:
		if detachment.operator == op:
			return true
	return false


func is_on_intel(op: OperatorData) -> bool:
	for intel in intel_ops:
		if intel.operators.has(op):
			return true
	return false


## The contract this team is out casing, if any.
func intel_op_for(mission: MissionData) -> IntelOp:
	for intel in intel_ops:
		if intel.mission == mission or intel.mission.id == mission.id:
			return intel
	return null


## Weekly income that arrives whether or not a squad goes anywhere.
func retainer_income() -> int:
	var total := 0
	for id in retainers:
		total += int(retainers[id])
	return total


## Operators who can teach: anyone who outranks a plausible trainee, plus every
## instructor. Used to populate the mentor list.
func potential_mentors() -> Array[OperatorData]:
	var mentors: Array[OperatorData] = []
	for op in roster:
		if not op.is_deployable():
			continue
		if op.career_track == GameEnums.CareerTrack.INSTRUCTOR:
			mentors.append(op)
		elif op.rank_step() >= Balance.TRAINING_MIN_RANK_GAP:
			mentors.append(op)
	return mentors


## Instructors have left the field for good and cannot be sent on contracts.
func deployable_operators() -> Array[OperatorData]:
	var free: Array[OperatorData] = []
	for op in available_operators():
		if op.career_track == GameEnums.CareerTrack.INSTRUCTOR:
			continue
		# Completely spent operators are off contracts entirely. Rotation stops
		# being advice at this point and becomes a rule.
		if op.is_exhausted():
			continue
		free.append(op)
	return free


# --- Serialisation -----------------------------------------------------------

func to_dict() -> Dictionary:
	var roster_data: Array = []
	for op in roster:
		roster_data.append(op.to_dict())

	var cemetery_data: Array = []
	for op in cemetery:
		cemetery_data.append(op.to_dict())

	var board_data: Array = []
	for mission in board:
		board_data.append(mission.to_dict())

	var recruit_data: Array = []
	for op in recruits:
		recruit_data.append(op.to_dict())

	var deployment_data: Array = []
	for deployment in deployments:
		deployment_data.append(deployment.to_dict())

	var training_data: Array = []
	for session in training:
		training_data.append(session.to_dict())

	var inventory_data: Array = []
	for id in inventory:
		inventory_data.append(String(id))

	var side_job_data: Array = []
	for job in side_jobs:
		side_job_data.append(job.to_dict())

	var detachment_data: Array = []
	for detachment in detachments:
		detachment_data.append(detachment.to_dict())

	var intel_data: Array = []
	for op in intel_ops:
		intel_data.append(op.to_dict())

	return {
		"version": 4,
		"side_jobs": side_job_data,
		"detachments": detachment_data,
		"intel_ops": intel_data,
		"retainers": retainers.duplicate(),
		"training": training_data,
		"facilities": facilities.duplicate(),
		"inventory": inventory_data,
		"reputation": reputation,
		"faction_standing": faction_standing.duplicate(),
		"deployed_this_week": deployed_this_week,
		"day": day,
		"diamonds": diamonds,
		"roster": roster_data,
		"cemetery": cemetery_data,
		"board": board_data,
		"recruits": recruit_data,
		"deployments": deployment_data,
	}


static func from_dict(data: Dictionary) -> GameState:
	var state := GameState.new()
	state.day = int(data.get("day", 1))
	state.diamonds = int(data.get("diamonds", STARTING_DIAMONDS))
	state.reputation = int(data.get("reputation", Balance.REPUTATION_START))
	state.deployed_this_week = int(data.get("deployed_this_week", 0))

	# JSON gives back string keys and float values for both of these.
	for id in data.get("facilities", {}):
		state.facilities[StringName(str(id))] = int(data["facilities"][id])
	for id in data.get("faction_standing", {}):
		state.faction_standing[StringName(str(id))] = int(data["faction_standing"][id])
	for id in data.get("inventory", []):
		state.inventory.append(StringName(str(id)))

	for entry in data.get("roster", []):
		state.roster.append(OperatorData.from_dict(entry))
	for entry in data.get("cemetery", []):
		state.cemetery.append(OperatorData.from_dict(entry))
	for entry in data.get("board", []):
		state.board.append(MissionData.from_dict(entry))

	# After the board and the roster both exist: an intel op is a link between
	# the two and cannot be rebuilt before either.
	for entry in data.get("intel_ops", []):
		var intel := IntelOp.from_dict(entry, state.roster, state.board)
		if intel != null and not intel.operators.is_empty():
			state.intel_ops.append(intel)
	for entry in data.get("recruits", []):
		state.recruits.append(OperatorData.from_dict(entry))

	# Deployments and training last: both reference roster operators by id and
	# must bind to the objects the roster already holds.
	for entry in data.get("deployments", []):
		state.deployments.append(Deployment.from_dict(entry, state.roster))
	for entry in data.get("training", []):
		var session := TrainingSession.from_dict(entry, state.roster)
		if session != null:
			state.training.append(session)
	for entry in data.get("side_jobs", []):
		state.side_jobs.append(SideJobData.from_dict(entry))
	for entry in data.get("detachments", []):
		var detachment := Detachment.from_dict(entry, state.roster)
		if detachment != null:
			state.detachments.append(detachment)
	for id in data.get("retainers", {}):
		state.retainers[StringName(str(id))] = int(data["retainers"][id])

	return state
