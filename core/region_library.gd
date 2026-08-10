class_name RegionLibrary
extends RefCounted

## The map. Eleven places, each with its own terrain, danger and distance.
##
## The three dials are deliberately independent. Somewhere can be close and
## lethal, or far and gentle, or hard ground where nothing much is at stake —
## which is what stops the board collapsing into one "danger" axis and keeps the
## question "where can I afford to work this week" open.

static var _cache: Dictionary = {}


static func _make(
	p_id: StringName,
	p_name: String,
	p_description: String,
	p_difficulty: float,
	p_risk: float,
	p_emphasis: int,
	p_note: String,
	p_travel: int,
	p_position: Vector2,
	p_hazard: int = GameEnums.Hazard.NONE
) -> RegionData:
	var region := RegionData.new()
	region.id = p_id
	region.display_name = p_name
	region.description = p_description
	region.difficulty_shift = p_difficulty
	region.risk_shift = p_risk
	region.emphasis_skill = p_emphasis
	region.emphasis_note = p_note
	region.travel_days = p_travel
	region.map_position = p_position
	region.hazard = p_hazard
	return region


static func all() -> Dictionary:
	if not _cache.is_empty():
		return _cache

	var S := GameEnums.Skill
	var list: Array[RegionData] = [
		_make(&"kunar_valley", "Kunar Valley",
			"High ground, thin air, and everyone up there knows the paths better than you do.",
			6.0, 8.0, S.ENDURANCE, "Mountainous — endurance decides who keeps up", 2, Vector2(0.685, 0.355), GameEnums.Hazard.ALTITUDE),

		_make(&"helmand_basin", "Helmand Basin",
			"Flat, open and hot. Nothing to hide behind for a hundred kilometres.",
			4.0, 10.0, S.COMBAT, "Open ground — firefights start at distance", 2, Vector2(0.660, 0.430), GameEnums.Hazard.HEAT),

		_make(&"angolan_coast", "Angolan Coast",
			"Port towns and old colonial infrastructure, most of it still wired.",
			-2.0, -4.0, S.TECH, "Wired and industrial — the doors are electronic", 1, Vector2(0.520, 0.700)),

		_make(&"niger_delta", "Niger Delta",
			"Creeks, pipelines and a hundred ways in if you know the water.",
			2.0, 4.0, S.STEALTH, "Waterways — movement is quiet or not at all", 1, Vector2(0.470, 0.560), GameEnums.Hazard.INFECTION),

		_make(&"kivu_border", "Kivu Border",
			"Dense, wet forest. Casualties here are about what the ground does to people.",
			3.0, 9.0, S.MEDICAL, "Jungle — infection kills more than gunfire", 2, Vector2(0.556, 0.625), GameEnums.Hazard.INFECTION),

		_make(&"sinai_flats", "Sinai Flats",
			"Desert crossing with a smuggling economy older than any of the states involved.",
			0.0, 2.0, S.ENDURANCE, "Desert crossing — heat wears squads down", 1, Vector2(0.575, 0.425), GameEnums.Hazard.HEAT),

		_make(&"donbas_corridor", "Donbas Corridor",
			"Industrial ruins fought over so many times the maps stopped mattering.",
			9.0, 12.0, S.COMBAT, "Contested ground — expect organised resistance", 1, Vector2(0.582, 0.268)),

		_make(&"karelian_shelf", "Karelian Shelf",
			"Forest and snow. Everything takes longer and shows up on thermal.",
			5.0, 3.0, S.STEALTH, "Snow and thermal — cover is a fiction", 2, Vector2(0.575, 0.165), GameEnums.Hazard.COLD),

		_make(&"balkan_reach", "Balkan Reach",
			"Old towns, older grudges, and paperwork that can be bought.",
			-3.0, -2.0, S.LEADERSHIP, "Urban and political — someone has to talk", 0, Vector2(0.520, 0.305)),

		_make(&"chiapas_highlands", "Chiapas Highlands",
			"Cloud forest and switchback roads nobody drives at night.",
			1.0, 0.0, S.STEALTH, "Cloud forest — visibility cuts both ways", 1, Vector2(0.205, 0.480)),

		_make(&"magdalena_gap", "Magdalena Gap",
			"River valley, cartel country, and a great deal of money moving through it.",
			4.0, 7.0, S.COMBAT, "Cartel country — everyone is armed", 1, Vector2(0.262, 0.585), GameEnums.Hazard.INFECTION),
	]

	for region in list:
		_cache[region.id] = region
	return _cache


static func ids() -> Array:
	return all().keys()


static func get_region(id: StringName) -> RegionData:
	return all().get(id, null)


static func region_name(id: StringName) -> String:
	var region := get_region(id)
	return region.display_name if region != null else "Unknown Region"



static func random_region(rng: RandomNumberGenerator) -> StringName:
	var all_ids: Array = all().keys()
	return all_ids[rng.randi() % all_ids.size()]
