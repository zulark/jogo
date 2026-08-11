class_name TraitLibrary
extends RefCounted

## Starter trait pool, built in code so v0.1 runs with no authored content.
##
## In v0.2 these move to res://content/traits/*.tres and you edit them in the
## inspector. The class stays as the loader so nothing that consumes traits has
## to change when that swap happens.

static var _cache: Dictionary = {}


static func _make(
	p_id: StringName,
	p_name: String,
	p_desc: String,
	p_polarity: int,
	p_score: float,
	p_danger: float,
	p_skills: Dictionary = {},
	p_types: Array[int] = []
) -> TraitData:
	var t := TraitData.new()
	t.id = p_id
	t.display_name = p_name
	t.description = p_desc
	t.polarity = p_polarity
	t.score_modifier = p_score
	t.danger_modifier = p_danger
	t.skill_modifiers = p_skills
	t.applies_to_mission_types = p_types
	return t


## StringName -> TraitData
static func all() -> Dictionary:
	if not _cache.is_empty():
		return _cache

	var E := GameEnums
	var POS := E.TraitPolarity.POSITIVE
	var NEG := E.TraitPolarity.NEGATIVE

	# GRAMMAR (see .docs/prose_style_guide.md): a description is ONE sentence, a
	# bare verb phrase in the third person with the operator as its unstated
	# subject — "Does not flinch when it matters." The roster prints it directly
	# under the trait name with no lead-in, so a description that supplies its own
	# subject ("Something in the last contract did not come back with them.")
	# reads as being about somebody else entirely.
	var list: Array[TraitData] = [
		# --- Positive -------------------------------------------------------
		_make(&"steady_hands", "Steady Hands",
			"Does not flinch when it matters.", POS, 6.0, -3.0,
			{E.Skill.COMBAT: 5}),
		_make(&"ghost", "Ghost",
			"Has never once been seen leaving.", POS, 5.0, -4.0,
			{E.Skill.STEALTH: 8}, [E.MissionType.INFILTRATION, E.MissionType.RECON] as Array[int]),
		_make(&"field_surgeon", "Field Surgeon",
			"Keeps people breathing on the way to the truck.", POS, 7.0, -2.0,
			{E.Skill.MEDICAL: 8}),
		_make(&"natural_leader", "Natural Leader",
			"People do what they say without being asked twice.", POS, 5.0, 0.0,
			{E.Skill.LEADERSHIP: 10}),
		_make(&"tough_as_nails", "Tough as Nails",
			"Walks off things that put other people in the ground.", POS, 3.0, -9.0,
			{E.Skill.ENDURANCE: 7}),

		# --- Negative -------------------------------------------------------
		# The design doc is explicit that these should create stories, not just
		# subtract numbers. Conditional ones do that best: a trait that only
		# fires on infiltration turns one operator into a roster puzzle.
		_make(&"claustrophobic", "Claustrophobic",
			"Freezes in tunnels and vents.", NEG, -14.0, 8.0,
			{}, [E.MissionType.INFILTRATION, E.MissionType.SABOTAGE] as Array[int]),
		_make(&"hothead", "Hothead",
			"Opens fire early, every time.", NEG, -9.0, 6.0,
			{E.Skill.STEALTH: -10}),
		_make(&"shell_shocked", "Shell Shocked",
			"Has not been the same since the last contract.", NEG, -11.0, 5.0,
			{E.Skill.LEADERSHIP: -8}),
		_make(&"glory_hound", "Glory Hound",
			"Takes the shot that looks good, not the one that works.", NEG, -7.0, 11.0),
		_make(&"squeamish", "Squeamish",
			"Cannot hold a dressing steady with blood on their hands.", NEG, -10.0, 3.0,
			{E.Skill.MEDICAL: -12}, [E.MissionType.RESCUE] as Array[int]),
	]

	for t in list:
		_cache[t.id] = t
	return _cache


static func get_trait(id: StringName) -> TraitData:
	var found: TraitData = all().get(id, null)
	if found != null:
		return found
	# Fears are generated per mission type, so they are not in the static table.
	# A save file loading "fear_infiltration" needs to be able to rebuild it.
	return _rebuild_generated(id)


static func _rebuild_generated(id: StringName) -> TraitData:
	var text := String(id)
	if not text.begins_with("fear_"):
		return null
	var suffix := text.substr(5).to_upper()
	for mission_type in GameEnums.MissionType.values():
		if GameEnums.MissionType.keys()[mission_type] == suffix:
			return fear_of(mission_type)
	return null


## "Wren fears infiltration." The design doc asks for exactly this: a scar tied
## to the kind of job that caused it, so one bad night in a tunnel turns an
## operator into a roster puzzle rather than a slightly worse stat block.
static func fear_of(mission_type: int) -> TraitData:
	var key := StringName("fear_%s" % GameEnums.MissionType.keys()[mission_type].to_lower())
	if _cache.has(key):
		return _cache[key]

	var type_name: String = GameEnums.mission_type_name(mission_type)
	var t := _make(
		key,
		"Fears %s" % type_name,
		"Will not talk about the last %s job, and does not want another." % type_name.to_lower(),
		GameEnums.TraitPolarity.NEGATIVE,
		-13.0,
		9.0,
		{},
		[mission_type] as Array[int]
	)
	# all() seeds the cache; make sure it exists before writing into it.
	all()
	_cache[key] = t
	return t


static func ids() -> Array:
	return all().keys()


static func random_trait(rng: RandomNumberGenerator, polarity: int = -1) -> TraitData:
	var pool: Array[TraitData] = []
	for id in all():
		var t: TraitData = all()[id]
		if polarity < 0 or t.polarity == polarity:
			pool.append(t)
	if pool.is_empty():
		return null
	return pool[rng.randi() % pool.size()]
