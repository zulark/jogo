class_name ItemLibrary
extends RefCounted

## What the Armoury, the Quartermaster and the blackmarket sell.
##
## Tiers are unlocked by facility level, so buying kit and upgrading the base are
## the same decision seen from two sides. Blackmarket stock ignores facilities
## entirely and is gated on reputation instead — the only way to get it is to be
## worth dealing with.
##
## Almost everything has a downside. Heavy armour costs stealth, a long rifle is
## useless up close. A loadout that is strictly better than another one is not a
## choice, and the whole point of the squad builder is choices.

static var _cache: Dictionary = {}


static func _make(
	p_id: StringName,
	p_name: String,
	p_description: String,
	p_slot: int,
	p_source: int,
	p_tier: int,
	p_price: int,
	p_skills: Dictionary,
	p_score: float,
	p_danger: float,
	p_reputation: int = 0
) -> ItemData:
	var item := ItemData.new()
	item.id = p_id
	item.display_name = p_name
	item.description = p_description
	item.slot = p_slot
	item.source = p_source
	item.tier = p_tier
	item.price = p_price
	item.skill_modifiers = p_skills
	item.score_modifier = p_score
	item.danger_modifier = p_danger
	item.reputation_required = p_reputation
	return item


## Same as _make, but tags the item as cancelling a regional hazard.
static func _make_counter(
	p_hazard: int,
	p_id: StringName,
	p_name: String,
	p_description: String,
	p_slot: int,
	p_source: int,
	p_tier: int,
	p_price: int,
	p_skills: Dictionary,
	p_score: float,
	p_danger: float,
	p_reputation: int = 0
) -> ItemData:
	var item := _make(p_id, p_name, p_description, p_slot, p_source,
		p_tier, p_price, p_skills, p_score, p_danger, p_reputation)
	item.counters_hazard = p_hazard
	return item


static func all() -> Dictionary:
	if not _cache.is_empty():
		return _cache

	var S := GameEnums.Skill
	var WEAPON := ItemData.Slot.WEAPON
	var GEAR := ItemData.Slot.GEAR
	var ARMOURY := ItemData.Source.ARMOURY
	var QUARTERMASTER := ItemData.Source.QUARTERMASTER
	var BLACKMARKET := ItemData.Source.BLACKMARKET

	var list: Array[ItemData] = [
		# --- Armoury, tier 1 ------------------------------------------------
		_make(&"service_carbine", "Service Carbine",
			"Standard issue. Does the job and nothing more.",
			WEAPON, ARMOURY, 1, 900, {S.COMBAT: 6}, 0.0, -1.0),
		_make(&"suppressed_pistol", "Suppressed Pistol",
			"Quiet, close, and not much use in a firefight.",
			WEAPON, ARMOURY, 1, 1100, {S.STEALTH: 8, S.COMBAT: -2}, 0.0, 0.0),

		# --- Armoury, tier 2 ------------------------------------------------
		_make(&"battle_rifle", "Battle Rifle",
			"Heavy, accurate, and impossible to hide.",
			WEAPON, ARMOURY, 2, 2600, {S.COMBAT: 13, S.STEALTH: -6}, 0.0, -2.0),
		_make(&"breaching_kit", "Breaching Kit",
			"Charges, cutters and a very short fuse.",
			WEAPON, ARMOURY, 2, 2400, {S.TECH: 12, S.COMBAT: 3}, 0.0, 1.0),

		# --- Armoury, tier 3 ------------------------------------------------
		_make(&"marksman_rifle", "Marksman Rifle",
			"Ends a contract from somewhere the client will never find.",
			WEAPON, ARMOURY, 3, 5800, {S.COMBAT: 20, S.STEALTH: 4}, 2.0, -4.0),

		# --- Quartermaster, tier 1 ------------------------------------------
		_make(&"field_dressing", "Field Dressing Kit",
			"Enough to get someone to the truck.",
			GEAR, QUARTERMASTER, 1, 800, {S.MEDICAL: 8}, 0.0, -3.0),
		_make(&"light_webbing", "Light Webbing",
			"Carries what they need without slowing them down.",
			GEAR, QUARTERMASTER, 1, 700, {S.ENDURANCE: 6}, 0.0, -1.0),

		# --- Quartermaster, tier 2 ------------------------------------------
		_make(&"plate_carrier", "Plate Carrier",
			"Stops what matters. Everything takes longer in it.",
			GEAR, QUARTERMASTER, 2, 2800, {S.ENDURANCE: 8, S.STEALTH: -7}, 0.0, -11.0),
		_make(&"night_optics", "Night Optics",
			"Turns a bad night into an ordinary one.",
			GEAR, QUARTERMASTER, 2, 3000, {S.STEALTH: 11, S.COMBAT: 4}, 0.0, -2.0),

		# --- Quartermaster, tier 3 ------------------------------------------
		_make(&"trauma_pack", "Field Trauma Pack",
			"A surgeon's kit in a rucksack.",
			GEAR, QUARTERMASTER, 3, 6200, {S.MEDICAL: 18, S.ENDURANCE: 5}, 1.0, -9.0),

		# --- Counter-kit ----------------------------------------------------
		# Cheap, unglamorous, and the difference between a jungle contract being
		# a coin flip and being a job. Every one of these turns a regional hazard
		# from a wall into a line on the invoice.
		_make_counter(GameEnums.Hazard.INFECTION, &"antimalarials", "Antimalarials & Field Antiseptics",
			"Cancels the infection risk of wet, hot country.",
			GEAR, QUARTERMASTER, 1, 620, {S.MEDICAL: 3}, 0.0, -1.0),
		_make_counter(GameEnums.Hazard.HEAT, &"desert_kit", "Desert Load-Out",
			"Shade, salts and enough water to matter. Cancels heat attrition.",
			GEAR, QUARTERMASTER, 1, 580, {S.ENDURANCE: 4}, 0.0, -1.0),
		_make_counter(GameEnums.Hazard.COLD, &"cold_weather_kit", "Cold Weather Kit",
			"Layers, stove and a bag rated for it. Cancels exposure.",
			GEAR, QUARTERMASTER, 1, 640, {S.ENDURANCE: 4}, 0.0, -1.0),
		_make_counter(GameEnums.Hazard.ALTITUDE, &"altitude_kit", "Supplemental Oxygen",
			"Bottles and a mask for approaches nobody acclimatised for.",
			GEAR, QUARTERMASTER, 2, 1150, {S.ENDURANCE: 6}, 0.0, -2.0),

		# --- Blackmarket ----------------------------------------------------
		# Gated on reputation rather than facilities, and priced accordingly.
		_make(&"ghost_suite", "Signals Ghost Suite",
			"Nobody logged them entering. Nobody will log them leaving.",
			GEAR, BLACKMARKET, 3, 11000, {S.STEALTH: 16, S.TECH: 10}, 4.0, -5.0, 45),
		_make(&"prototype_smg", "Prototype SMG",
			"Serial numbers ground off by whoever had it before.",
			WEAPON, BLACKMARKET, 3, 12500, {S.COMBAT: 18, S.STEALTH: 8}, 3.0, -3.0, 55),
		_make(&"combat_stimulants", "Combat Stimulants",
			"They will not feel the hit. They will feel everything else afterwards.",
			GEAR, BLACKMARKET, 2, 8000, {S.COMBAT: 12, S.ENDURANCE: 14}, 2.0, 6.0, 30),
	]

	for item in list:
		_cache[item.id] = item
	return _cache


static func get_item(id: StringName) -> ItemData:
	return all().get(id, null)


## What a given shop will sell right now, given facility levels and reputation.
static func stock_for(source: int, facility_level: int, reputation: int) -> Array[ItemData]:
	var stock: Array[ItemData] = []
	for id in all():
		var item: ItemData = all()[id]
		if item.source != source:
			continue
		if source == ItemData.Source.BLACKMARKET:
			if reputation >= item.reputation_required:
				stock.append(item)
		elif item.tier <= facility_level:
			stock.append(item)
	stock.sort_custom(func(a, b): return a.tier < b.tier)
	return stock
