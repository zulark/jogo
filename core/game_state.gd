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

## Consecutive weeks closed in debt. Resets the moment the books are black.
var weeks_in_debt: int = 0

## FactionLibrary id -> weekly payment. A client on this list is paying to keep
## the company on call, and may call.
var retainers: Dictionary = {}

## FacilityLibrary id -> level. Absent or 0 means not built.
var facilities: Dictionary = {}

## Every copy of every item the company owns. Equipped kit stays in here — the
## operator holds a reference to the same object, the company still owns the
## thing. One entry is one specific rifle with its own condition and history,
## which is what an array of ids could never say.
var inventory: Array[ItemInstance] = []

## Parts. Recovered from contracts and from stripping kit down, spent only on
## crafting. One number with one source and one sink, deliberately — a second
## full resource economy would be a chore, and this is the thing that makes a
## rifle too worn to repair the beginning of the next one.
var salvage: int = 0

## Item ids the company has plans for. Found on hard contracts and permanent
## once found: knowing how to build something is not a thing you can lose.
var blueprints: Array[StringName] = []

## What the Armoury and Quartermaster benches are working on.
var workshop: Array[WorkshopJob] = []

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

## How many operators went out during the week that just closed. Kept because
## the counter above is reset before events roll, and an event that wants to ask
## "was anyone actually in the field?" has nothing else to read.
var deployed_last_week: int = 0

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

## Average fatigue across everyone still alive. A company running its people
## into the ground is the cause behind several events, and this is how they ask.
func average_fatigue() -> int:
	var count := 0
	var total := 0
	for op in roster:
		if op.status == GameEnums.OperatorStatus.DEAD:
			continue
		total += op.fatigue
		count += 1
	if count == 0:
		return 0
	return int(round(float(total) / float(count)))


## The unhappiest person still on the books. Theft, desertion and informants all
## need a motive, and a motive needs somebody to hold it.
func lowest_morale() -> int:
	var lowest := 100
	for op in roster:
		if op.status == GameEnums.OperatorStatus.DEAD:
			continue
		lowest = mini(lowest, op.morale)
	return lowest


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


func find_instance(uid: StringName) -> ItemInstance:
	for instance in inventory:
		if instance.uid == uid:
			return instance
	return null


## Who is carrying this specific copy, or null. Only the living roster counts:
## an operator in the cemetery has already had their kit signed back in.
func holder_of(instance: ItemInstance) -> OperatorData:
	if instance == null:
		return null
	for op in roster:
		if op.weapon == instance or op.gear == instance:
			return op
	return null


func is_carried(instance: ItemInstance) -> bool:
	return holder_of(instance) != null


func holder_name(instance: ItemInstance) -> String:
	var op := holder_of(instance)
	return op.display_label() if op != null else ""


## Out of the base: on a contract, on standing work, or casing something. Kit in
## their hands is genuinely out of reach — everything else can be taken off them
## and handed back.
func is_away(op: OperatorData) -> bool:
	return is_deployed(op) or is_detached(op) or is_on_intel(op)


func is_in_workshop(instance: ItemInstance) -> bool:
	for job: WorkshopJob in workshop:
		if job.instance == instance:
			return true
	return false


## Free to act on: nobody is carrying it and it is not on a bench. Everything
## that takes kit away — selling, scrapping, theft, a creditor — goes through
## this, because taking a rifle out of an operator's hands between contracts is
## not a consequence the player can see coming.
func is_spare(instance: ItemInstance) -> bool:
	return not is_carried(instance) and not is_in_workshop(instance)


## Every loose copy, optionally of one slot.
func spare_instances(slot: int = -1) -> Array[ItemInstance]:
	var free: Array[ItemInstance] = []
	for instance in inventory:
		if slot >= 0 and instance.slot() != slot:
			continue
		if is_spare(instance):
			free.append(instance)
	return free


## Copies of a given item type that nobody is carrying. Kept because events and
## the market both count kit by type rather than by copy.
func unequipped_count(item_id: StringName) -> int:
	var owned := 0
	for instance in inventory:
		if instance.item_id == item_id and is_spare(instance):
			owned += 1
	return owned


func count_of(item_id: StringName) -> int:
	var owned := 0
	for instance in inventory:
		if instance.item_id == item_id:
			owned += 1
	return owned


## Copies of a given slot that can actually be issued to someone right now.
## Unserviceable kit is left out: handing an operator something that gives them
## nothing and still costs them stealth is not a choice worth offering.
func available_items(slot: int) -> Array[ItemInstance]:
	var free: Array[ItemInstance] = []
	for instance in spare_instances(slot):
		if instance.is_serviceable():
			free.append(instance)
	free.sort_custom(func(a, b): return a.condition > b.condition)
	return free


## Loose kit that is past being any use. The one number worth flagging outside
## the workshop screen, because it is the reason to walk to it.
func unserviceable_spares() -> int:
	var count := 0
	for instance in spare_instances():
		if not instance.is_serviceable():
			count += 1
	return count


func knows_blueprint(item_id: StringName) -> bool:
	return blueprints.has(item_id)


## Binds every operator's loadout back to the copies the inventory holds.
##
## Two formats have to work. A current save names the exact copy by uid. A save
## from before kit had condition names only the item *type*, in which case any
## unclaimed copy of that type will do — the alternative is silently taking an
## upgrading player's equipment off them.
func _relink_equipment() -> void:
	var claimed := {}
	for op in roster:
		for slot in [ItemData.Slot.WEAPON, ItemData.Slot.GEAR]:
			var is_weapon: bool = slot == ItemData.Slot.WEAPON
			var uid: StringName = op.pending_weapon_uid if is_weapon else op.pending_gear_uid
			if uid == &"":
				continue
			var instance := find_instance(uid)
			if instance == null or claimed.has(instance.uid):
				continue
			claimed[instance.uid] = true
			op.set_slot_instance(slot, instance)

	for op in roster:
		for slot in [ItemData.Slot.WEAPON, ItemData.Slot.GEAR]:
			var is_weapon: bool = slot == ItemData.Slot.WEAPON
			if op.slot_instance(slot) != null:
				continue
			var item_id: StringName = op.pending_weapon_id if is_weapon else op.pending_gear_id
			if item_id == &"":
				continue
			for instance in inventory:
				if instance.item_id != item_id or claimed.has(instance.uid):
					continue
				claimed[instance.uid] = true
				op.set_slot_instance(slot, instance)
				break

	for op in roster:
		op.pending_weapon_uid = &""
		op.pending_gear_uid = &""
		op.pending_weapon_id = &""
		op.pending_gear_id = &""


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
	for instance in inventory:
		inventory_data.append(instance.to_dict())

	var workshop_data: Array = []
	for job in workshop:
		workshop_data.append(job.to_dict())

	var blueprint_data: Array = []
	for id in blueprints:
		blueprint_data.append(String(id))

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
		"version": 5,
		"salvage": salvage,
		"blueprints": blueprint_data,
		"workshop": workshop_data,
		"side_jobs": side_job_data,
		"detachments": detachment_data,
		"intel_ops": intel_data,
		"weeks_in_debt": weeks_in_debt,
		"retainers": retainers.duplicate(),
		"training": training_data,
		"facilities": facilities.duplicate(),
		"inventory": inventory_data,
		"reputation": reputation,
		"faction_standing": faction_standing.duplicate(),
		"deployed_this_week": deployed_this_week,
		"deployed_last_week": deployed_last_week,
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
	state.deployed_last_week = int(data.get("deployed_last_week", 0))

	# JSON gives back string keys and float values for both of these.
	for id in data.get("facilities", {}):
		state.facilities[StringName(str(id))] = int(data["facilities"][id])
	for id in data.get("faction_standing", {}):
		state.faction_standing[StringName(str(id))] = int(data["faction_standing"][id])
	state.salvage = int(data.get("salvage", 0))
	for id in data.get("blueprints", []):
		state.blueprints.append(StringName(str(id)))

	# A save written before kit had condition stored plain ids. Those copies come
	# back new rather than worn, which is the only reading that does not quietly
	# damage an existing company's armoury on upgrade.
	for entry in data.get("inventory", []):
		if entry is Dictionary:
			state.inventory.append(ItemInstance.from_dict(entry))
		else:
			state.inventory.append(ItemInstance.from_legacy(StringName(str(entry))))

	for entry in data.get("roster", []):
		state.roster.append(OperatorData.from_dict(entry))

	# Now that both exist, hand everybody back the copy they were carrying. This
	# has to bind to the objects the inventory holds, not to duplicates, or a
	# contract would wear a rifle nobody could ever repair.
	state._relink_equipment()

	for entry in data.get("workshop", []):
		var job := WorkshopJob.from_dict(entry, state.inventory)
		if job != null:
			state.workshop.append(job)
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
