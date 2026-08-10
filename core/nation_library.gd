class_name NationLibrary
extends RefCounted

## Where operators are from. Nationality drives their name (via NameLibrary's
## cultures) and gives the roster a face — it is identity rather than mechanics.

static var _cache: Dictionary = {}


static func _make(
	p_id: StringName,
	p_name: String,
	p_demonym: String,
	p_culture: StringName
) -> NationData:
	var nation := NationData.new()
	nation.id = p_id
	nation.display_name = p_name
	nation.demonym = p_demonym
	nation.culture = p_culture
	return nation


## StringName -> NationData
static func all() -> Dictionary:
	if not _cache.is_empty():
		return _cache

	var list: Array[NationData] = [
		_make(&"usa", "United States", "American", &"anglo"),
		_make(&"uk", "United Kingdom", "British", &"anglo"),
		_make(&"brazil", "Brazil", "Brazilian", &"lusophone"),
		_make(&"mexico", "Mexico", "Mexican", &"hispanic"),
		_make(&"colombia", "Colombia", "Colombian", &"hispanic"),
		_make(&"france", "France", "French", &"francophone"),
		_make(&"germany", "Germany", "German", &"germanic"),
		_make(&"poland", "Poland", "Polish", &"slavic_west"),
		_make(&"russia", "Russia", "Russian", &"slavic_east"),
		_make(&"ukraine", "Ukraine", "Ukrainian", &"slavic_east"),
		_make(&"serbia", "Serbia", "Serbian", &"balkan"),
		_make(&"egypt", "Egypt", "Egyptian", &"arabic"),
		_make(&"afghanistan", "Afghanistan", "Afghan", &"afghan"),
		_make(&"nigeria", "Nigeria", "Nigerian", &"west_african"),
		_make(&"kenya", "Kenya", "Kenyan", &"east_african"),
		_make(&"south_korea", "South Korea", "Korean", &"korean"),
		_make(&"japan", "Japan", "Japanese", &"japanese"),
		_make(&"india", "India", "Indian", &"indian"),
	]

	for nation in list:
		_cache[nation.id] = nation
	return _cache


static func get_nation(id: StringName) -> NationData:
	return all().get(id, null)


static func random_nation(rng: RandomNumberGenerator) -> NationData:
	var ids: Array = all().keys()
	return all()[ids[rng.randi() % ids.size()]]

