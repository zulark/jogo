class_name Workshop
extends RefCounted

## What repair, scrap and crafting cost. Pure arithmetic over state — Campaign
## owns the mutations, this owns the prices, and the UI quotes from here so a
## button's caption and the charge it makes can never drift apart.
##
## The design doc gives the Armoury and Quartermaster three jobs each: sell kit,
## repair kit, and build kit from blueprints found as loot. The first was v0.5.
## These are the other two, and the thing that makes them a decision rather than
## a routine is that both consume the same scarce resource — a bench, of which
## there is one per facility level.


## Which bench handles a given item. Weapons are the Armoury's, everything else
## is the Quartermaster's, which is exactly the split the shops already use.
static func facility_for(item: ItemData) -> StringName:
	if item == null:
		return &""
	if item.slot == ItemData.Slot.WEAPON:
		return FacilityLibrary.ARMOURY
	return FacilityLibrary.QUARTERMASTER


static func facility_for_instance(instance: ItemInstance) -> StringName:
	return facility_for(instance.data()) if instance != null else &""


## Benches a facility runs. Zero if it was never built, which is the whole
## answer to "why can I not repair anything" on a fresh company.
static func bench_capacity(state: GameState, facility_id: StringName) -> int:
	return state.facility_level(facility_id)


static func benches_in_use(state: GameState, facility_id: StringName) -> int:
	var count := 0
	for job: WorkshopJob in state.workshop:
		if job.facility_id == facility_id:
			count += 1
	return count


static func has_free_bench(state: GameState, facility_id: StringName) -> bool:
	return benches_in_use(state, facility_id) < bench_capacity(state, facility_id)


# --- Repair ------------------------------------------------------------------

## Priced on the damage rather than the item, so topping something up before a
## contract is cheap and letting it rot is not.
static func repair_cost(instance: ItemInstance) -> int:
	if instance == null:
		return 0
	var missing: float = maxf(0.0, instance.max_condition - instance.condition)
	var share: float = missing / Balance.CONDITION_NEW
	return maxi(1, int(round(float(instance.price()) * Balance.REPAIR_COST_RATIO * share)))


## Days scale the same way, and every level of the facility takes one off.
static func repair_days(state: GameState, instance: ItemInstance) -> int:
	if instance == null:
		return 0
	var missing: float = maxf(0.0, instance.max_condition - instance.condition)
	var share: float = missing / Balance.CONDITION_NEW
	var level: int = state.facility_level(facility_for_instance(instance))
	var days: int = int(ceil(share * float(Balance.REPAIR_DAYS_MAX)))
	return maxi(1, days - maxi(0, level - 1))


## Why the button is greyed out, in the words the player would use. Empty means
## it is not: a repair that can be booked returns "".
static func repair_blocker(state: GameState, instance: ItemInstance) -> String:
	if instance == null:
		return "Nothing selected."
	var facility_id := facility_for_instance(instance)
	var facility := FacilityLibrary.get_facility(facility_id)
	var facility_name: String = facility.display_name if facility != null else "workshop"

	if instance.condition >= instance.max_condition:
		return "Already as good as this one gets."
	if instance.is_beyond_repair():
		return "Rebuilt too many times. Strip it for parts."

	# Kit in somebody's hands at base can go on the bench — it comes off them
	# for the duration and is handed straight back when the job lands, so the
	# price is that they are without it, not a chore for the player to perform.
	# Kit in the field cannot: those people are three days away with it.
	var holder := state.holder_of(instance)
	if holder != null and state.is_away(holder):
		return "%s is in the field with it." % holder.display_label()

	if state.is_in_workshop(instance):
		return "Already on the bench."
	if bench_capacity(state, facility_id) <= 0:
		return "No %s to do the work." % facility_name
	if not has_free_bench(state, facility_id):
		return "Every %s bench is busy." % facility_name
	if repair_cost(instance) > state.diamonds:
		return "%d diamonds short." % (repair_cost(instance) - state.diamonds)
	return ""


static func can_repair(state: GameState, instance: ItemInstance) -> bool:
	return repair_blocker(state, instance).is_empty()


# --- Scrap -------------------------------------------------------------------

## Parts recovered from stripping something down. Worth more in good condition,
## and never worth nothing — a write-off still has a barrel in it, which is what
## makes a rifle that is past repair the beginning of the next one rather than
## a dead entry in the inventory.
static func scrap_value(instance: ItemInstance) -> int:
	if instance == null:
		return 0
	var quality: float = Balance.SCRAP_CONDITION_FLOOR + (
		1.0 - Balance.SCRAP_CONDITION_FLOOR) * (instance.condition / Balance.CONDITION_NEW)
	return maxi(1, int(round(float(instance.price()) * Balance.SCRAP_PER_PRICE * quality)))


static func scrap_blocker(state: GameState, instance: ItemInstance) -> String:
	if instance == null:
		return "Nothing selected."
	if state.is_carried(instance):
		return "%s is carrying it." % state.holder_name(instance)
	if state.is_in_workshop(instance):
		return "It is on the bench."
	return ""


static func can_scrap(state: GameState, instance: ItemInstance) -> bool:
	return scrap_blocker(state, instance).is_empty()


# --- Crafting ----------------------------------------------------------------

static func craft_days(state: GameState, item: ItemData) -> int:
	if item == null:
		return 0
	var level: int = state.facility_level(item.craft_facility)
	return maxi(1, item.craft_days - maxi(0, level - item.craft_level))


static func craft_blocker(state: GameState, item: ItemData) -> String:
	if item == null or not item.is_craftable():
		return "Nothing to build."
	if not state.knows_blueprint(item.id):
		return "The company has never seen the plans."

	var facility := FacilityLibrary.get_facility(item.craft_facility)
	var facility_name: String = facility.display_name if facility != null else "workshop"
	var level: int = state.facility_level(item.craft_facility)

	if level < item.craft_level:
		return "Needs a %s at level %d." % [facility_name, item.craft_level]
	if not has_free_bench(state, item.craft_facility):
		return "Every %s bench is busy." % facility_name
	if state.salvage < item.craft_salvage:
		return "%d parts short." % (item.craft_salvage - state.salvage)
	if item.craft_price > state.diamonds:
		return "%d diamonds short." % (item.craft_price - state.diamonds)
	if not state.has_storage_room():
		return "Nowhere to put it. Storage is full."
	return ""


static func can_craft(state: GameState, item: ItemData) -> bool:
	return craft_blocker(state, item).is_empty()


# --- Wear --------------------------------------------------------------------

## What a contract does to one item carried on it.
##
## Every term traces to something the player chose: how many days the job takes,
## how dangerous it was, and whether it came off. Nothing here is weather.
static func wear_for(mission: MissionData, failed: bool) -> float:
	var days: float = float(maxi(1, mission.duration_days))
	var amount: float = days * (
		Balance.WEAR_PER_CONTRACT_DAY + mission.risk * Balance.WEAR_PER_RISK_DAY)
	if failed:
		amount *= Balance.WEAR_ON_FAILURE
	return amount
