class_name FacilityLibrary
extends RefCounted

## The eight areas of the base from the design doc, and what each level buys.
##
## Every facility earns its keep in a system that already exists, so upgrading is
## never abstract score: the Infirmary shortens the recovery days you are already
## counting, the Canteen pushes back on the morale decay you are already
## watching, the Armoury raises the tier of gear the shop will sell you.

const INFIRMARY := &"infirmary"
const PSYCHOLOGIST := &"psychologist"
const CANTEEN := &"canteen"
const ACADEMY := &"academy"
const INTELLIGENCE := &"intelligence"
const WAREHOUSE := &"warehouse"
const ARMOURY := &"armoury"
const QUARTERMASTER := &"quartermaster"

## Render order on the base screen: the ones that keep people alive first.
const ORDER: Array[StringName] = [
	INFIRMARY, PSYCHOLOGIST, CANTEEN, ACADEMY,
	INTELLIGENCE, ARMOURY, QUARTERMASTER, WAREHOUSE,
]

static var _cache: Dictionary = {}


static func _make(
	p_id: StringName,
	p_name: String,
	p_description: String,
	p_effect_caption: String,
	p_costs: Array[int],
	p_upkeep: Array[int],
	p_effect: Array[float]
) -> FacilityData:
	var facility := FacilityData.new()
	facility.id = p_id
	facility.display_name = p_name
	facility.description = p_description
	facility.effect_caption = p_effect_caption
	facility.upgrade_costs = p_costs
	facility.upkeep = p_upkeep
	facility.effect = p_effect
	facility.max_level = p_costs.size()
	return facility


static func all() -> Dictionary:
	if not _cache.is_empty():
		return _cache

	var list: Array[FacilityData] = [
		_make(INFIRMARY, "Infirmary",
			"Wounded operators come back sooner.",
			"recovery time",
			[2200, 5200, 9800] as Array[int],
			[90, 190, 320] as Array[int],
			[0.18, 0.32, 0.45] as Array[float]),

		_make(PSYCHOLOGIST, "Psychologist",
			"Reduces how often the field leaves a lasting mark, and shortens the time it takes to work through one. It never removes a trait — what happened to them stays part of who they are.",
			"chance of a lasting scar",
			[2600, 6000, 11000] as Array[int],
			[110, 220, 360] as Array[int],
			[0.20, 0.35, 0.50] as Array[float]),

		_make(CANTEEN, "Canteen",
			"Somewhere decent to eat. Pushes morale back up every week.",
			"morale recovered weekly",
			[1600, 3800, 7200] as Array[int],
			[70, 150, 260] as Array[int],
			[3.0, 6.0, 10.0] as Array[float]),

		_make(ACADEMY, "Academy",
			"Proper facilities to teach in. Training transfers more, and takes less time.",
			"training effectiveness",
			[2400, 5600, 10400] as Array[int],
			[100, 200, 340] as Array[int],
			[0.25, 0.50, 0.85] as Array[float]),

		_make(INTELLIGENCE, "Intelligence Centre",
			"Scouts a contract before the squad goes in. Worth flat score on every deployment.",
			"score on every contract",
			[3000, 6800, 12500] as Array[int],
			[130, 260, 420] as Array[int],
			[3.0, 6.5, 11.0] as Array[float]),

		_make(ARMOURY, "Armoury",
			"Sells weapons, repairs them, and builds them from recovered plans. Each level unlocks a better tier and adds a bench — and a bench working on a rifle is a rifle the squad has not got.",
			"weapon tier, and benches",
			[1800, 4400, 8600] as Array[int],
			[80, 170, 290] as Array[int],
			[1.0, 2.0, 3.0] as Array[float]),

		_make(QUARTERMASTER, "Quartermaster",
			"Sells field equipment, repairs it, and builds it from recovered plans. Each level unlocks a better tier and adds a bench.",
			"equipment tier, and benches",
			[1800, 4400, 8600] as Array[int],
			[80, 170, 290] as Array[int],
			[1.0, 2.0, 3.0] as Array[float]),

		_make(WAREHOUSE, "Warehouse",
			"Somewhere to keep what you buy. Raises how much kit the company can hold.",
			"storage slots",
			[1200, 2800, 5400] as Array[int],
			[50, 110, 190] as Array[int],
			[8.0, 18.0, 32.0] as Array[float]),
	]

	for facility in list:
		_cache[facility.id] = facility
	return _cache


static func get_facility(id: StringName) -> FacilityData:
	return all().get(id, null)


## Base storage before any Warehouse is built.
const BASE_STORAGE := 6
