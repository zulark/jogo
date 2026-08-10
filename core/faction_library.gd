class_name FactionLibrary
extends RefCounted

## The five people who hire you.
##
## Each pays differently and wants something different, so "which contract" and
## "which squad" stop being separable questions. A cartel job wants three quiet
## people; a mining consortium wants eight loud ones; the relief directorate
## pays badly and will drop you the moment somebody dies.

const HALBERD := &"halberd"
const CARTEL := &"magdalena_cartel"
const RELIEF := &"relief_directorate"
const MERIDIAN := &"meridian"
const BROKERS := &"brokers"

static var _cache: Dictionary = {}


static func _make(
	p_id: StringName,
	p_name: String,
	p_description: String,
	p_preference: int,
	p_note: String,
	p_pay: float,
	p_standing: int
) -> FactionData:
	var faction := FactionData.new()
	faction.id = p_id
	faction.display_name = p_name
	faction.description = p_description
	faction.preference = p_preference
	faction.preference_note = p_note
	faction.pay_multiplier = p_pay
	faction.standing_per_contract = p_standing
	return faction


static func all() -> Dictionary:
	if not _cache.is_empty():
		return _cache

	var P := FactionData.Preference
	var list: Array[FactionData] = [
		_make(HALBERD, "Halberd Group",
			"Corporate security. Everything is a line item and everything is audited.",
			P.PROFESSIONALS, "Judges a squad by its ranks. Rookies embarrass them.",
			1.15, 6),

		_make(CARTEL, "Magdalena Cartel",
			"Pays in full, on time, and never explains what the job was for.",
			P.DISCREET, "Wants nobody noticed. Every extra body is a liability.",
			1.35, 5),

		_make(RELIEF, "Relief Directorate",
			"An aid mandate with a security budget it would rather not discuss.",
			P.CLEAN_HANDS, "Tolerates no casualties. Losing people costs their trust badly.",
			0.85, 8),

		_make(MERIDIAN, "Meridian Extraction",
			"Mining consortium. Believes most problems are solved by showing up in numbers.",
			P.OVERWHELMING, "Wants a show of force. Small squads look like half measures.",
			1.10, 6),

		_make(BROKERS, "Independent Brokers",
			"Middlemen. No standards worth speaking of, which is occasionally the point.",
			P.NONE, "Takes whatever squad turns up.",
			1.0, 4),
	]

	for faction in list:
		_cache[faction.id] = faction
	return _cache


static func get_faction(id: StringName) -> FactionData:
	return all().get(id, null)


static func ids() -> Array:
	return all().keys()


static func faction_name(id: StringName) -> String:
	var faction := get_faction(id)
	return faction.display_name if faction != null else "Unknown Client"


## Clients you have never worked for offer less, and offer less often. Standing
## is what turns a one-off into a relationship.
static func random_client(rng: RandomNumberGenerator, standing: Dictionary) -> StringName:
	var pool: Array = []
	for id in all():
		# Everyone gets one ticket, plus one more for every 25 points of
		# standing — so the people who like you crowd the board.
		var weight: int = 1 + int(standing.get(id, 0)) / 25
		for i in weight:
			pool.append(id)
	return pool[rng.randi() % pool.size()]
