class_name MissionProfile
extends Resource

## The tactical rules of one mission TYPE — what skills it tests, how big a
## squad it wants, which roles it demands, what kind of person suits it.
##
## This is where "infiltration punishes large squads, rescue requires a medic"
## from the design doc actually lives.
##
## Six defaults are built in code (see defaults()). In v0.2 they become .tres
## files under res://content/mission_profiles/ so you can tune them in the
## inspector instead of asking me to edit constants.

@export var mission_type: GameEnums.MissionType = GameEnums.MissionType.ASSAULT
@export var display_name: String = ""

## Skill -> weight. Should sum to 1.0. This is "what the job tests".
@export var skill_weights: Dictionary = {}

## Squad size the job is designed around.
@export var ideal_squad_size: int = 4

## Deviation from ideal_squad_size that costs nothing.
@export var size_tolerance: int = 1

## Score lost per operator beyond the tolerance band, going over.
@export var oversize_penalty: float = 4.0

## Score lost per operator short of the tolerance band.
@export var undersize_penalty: float = 6.0

## Roles the job cannot be done properly without.
@export var required_roles: Array[int] = []

## Score lost for each required role the squad does not fill.
@export var missing_role_penalty: float = 12.0

@export var personality_prefs: Array[PersonalityPref] = []


## 0-100. How well this operator's skills match what the mission tests.
func skill_match(op: OperatorData) -> float:
	var total := 0.0
	for skill in skill_weights:
		total += float(op.get_skill(skill, mission_type)) * float(skill_weights[skill])
	return total


## Always <= 0. Cost of putting the wrong personalities on this job.
func personality_cost(op: OperatorData) -> float:
	var cost := 0.0
	for pref in personality_prefs:
		if pref == null:
			continue
		var distance: int = absi(op.get_personality(pref.axis) - pref.ideal)
		cost -= float(distance) * pref.weight * Balance.PERSONALITY_COST
	return cost


## Always <= 0. The cost of bringing MORE people than the job wants — the
## infiltration rule from the design doc.
##
## Being short-handed is no longer punished here. It is expressed by the absence
## of the manpower bonus below, which is the same thing said in a way the player
## can act on: "you get less because there are fewer of you" reads as a reason to
## bring someone, where a penalty reads as a mistake you already made.
func size_cost(squad_size: int) -> float:
	var high := ideal_squad_size + size_tolerance
	if squad_size > high:
		return -float(squad_size - high) * oversize_penalty
	return 0.0


## The divisor for weighted operator contributions: the sum of the decay series
## over the number of people this job actually calls for.
##
## Fixing it to the IDEAL rather than the actual squad size is the whole trick.
## A full squad divides by exactly what it brings and scores its true average; a
## short squad divides by the same number with fewer terms on top, so it scores
## proportionally less. Numbers therefore matter without a separate penalty, and
## adding a body can never subtract.
func contribution_denominator() -> float:
	var total := 0.0
	for i in maxi(1, ideal_squad_size):
		total += pow(Balance.SQUAD_CONTRIBUTION_DECAY, i)
	return maxf(total, 0.01)


## Returns the required roles that nobody in `filled_roles` covers.
func missing_roles(filled_roles: Array[int]) -> Array[int]:
	var missing: Array[int] = []
	for role in required_roles:
		if not role in filled_roles:
			missing.append(role)
	return missing


static func _make(
	p_type: int,
	p_name: String,
	p_weights: Dictionary,
	p_ideal: int,
	p_tolerance: int,
	p_required: Array[int],
	p_prefs: Array[PersonalityPref]
) -> MissionProfile:
	var profile := MissionProfile.new()
	profile.mission_type = p_type
	profile.display_name = p_name
	profile.skill_weights = p_weights
	profile.ideal_squad_size = p_ideal
	profile.size_tolerance = p_tolerance
	profile.required_roles = p_required
	profile.personality_prefs = p_prefs
	return profile


## MissionType -> MissionProfile, built fresh each call.
static func defaults() -> Dictionary:
	var E := GameEnums
	var profiles := {}

	# Loud and direct. Wants numbers, firepower and aggression.
	var assault := _make(
		E.MissionType.ASSAULT,
		"Assault",
		{
			E.Skill.COMBAT: 0.55,
			E.Skill.ENDURANCE: 0.25,
			E.Skill.LEADERSHIP: 0.20,
		},
		5, 1,
		[E.Role.ASSAULT] as Array[int],
		[
			PersonalityPref.create(E.PersonalityAxis.AGGRESSION, 75, 0.6),
			PersonalityPref.create(E.PersonalityAxis.BRAVERY, 80, 0.8),
		] as Array[PersonalityPref]
	)
	assault.oversize_penalty = 2.0
	assault.undersize_penalty = 8.0
	profiles[E.MissionType.ASSAULT] = assault

	# The design doc's example: a big squad is a liability here.
	var infiltration := _make(
		E.MissionType.INFILTRATION,
		"Infiltration",
		{
			E.Skill.STEALTH: 0.55,
			E.Skill.TECH: 0.25,
			E.Skill.COMBAT: 0.20,
		},
		3, 0,
		[E.Role.SCOUT] as Array[int],
		[
			PersonalityPref.create(E.PersonalityAxis.AGGRESSION, 25, 0.9),
			PersonalityPref.create(E.PersonalityAxis.DISCIPLINE, 80, 0.7),
		] as Array[PersonalityPref]
	)
	infiltration.oversize_penalty = 9.0
	infiltration.undersize_penalty = 5.0
	profiles[E.MissionType.INFILTRATION] = infiltration

	# The other doc example: no medic, no rescue.
	var rescue := _make(
		E.MissionType.RESCUE,
		"Rescue",
		{
			E.Skill.MEDICAL: 0.40,
			E.Skill.COMBAT: 0.30,
			E.Skill.ENDURANCE: 0.30,
		},
		4, 1,
		[E.Role.MEDIC] as Array[int],
		[
			PersonalityPref.create(E.PersonalityAxis.BRAVERY, 75, 0.7),
			PersonalityPref.create(E.PersonalityAxis.SOCIABILITY, 70, 0.5),
		] as Array[PersonalityPref]
	)
	rescue.missing_role_penalty = 20.0
	profiles[E.MissionType.RESCUE] = rescue

	var recon := _make(
		E.MissionType.RECON,
		"Recon",
		{
			E.Skill.STEALTH: 0.50,
			E.Skill.TECH: 0.30,
			E.Skill.ENDURANCE: 0.20,
		},
		2, 1,
		[E.Role.SCOUT] as Array[int],
		[
			PersonalityPref.create(E.PersonalityAxis.AGGRESSION, 20, 0.8),
			PersonalityPref.create(E.PersonalityAxis.DISCIPLINE, 75, 0.6),
		] as Array[PersonalityPref]
	)
	recon.oversize_penalty = 7.0
	profiles[E.MissionType.RECON] = recon

	var sabotage := _make(
		E.MissionType.SABOTAGE,
		"Sabotage",
		{
			E.Skill.TECH: 0.50,
			E.Skill.STEALTH: 0.30,
			E.Skill.COMBAT: 0.20,
		},
		3, 1,
		[E.Role.ENGINEER] as Array[int],
		[
			PersonalityPref.create(E.PersonalityAxis.DISCIPLINE, 85, 0.8),
		] as Array[PersonalityPref]
	)
	sabotage.missing_role_penalty = 18.0
	profiles[E.MissionType.SABOTAGE] = sabotage

	# Long, grinding, defensive. Cohesion and stamina over flash.
	var escort := _make(
		E.MissionType.ESCORT,
		"Escort",
		{
			E.Skill.COMBAT: 0.35,
			E.Skill.ENDURANCE: 0.35,
			E.Skill.LEADERSHIP: 0.30,
		},
		4, 1,
		[] as Array[int],
		[
			PersonalityPref.create(E.PersonalityAxis.DISCIPLINE, 70, 0.6),
			PersonalityPref.create(E.PersonalityAxis.SOCIABILITY, 65, 0.5),
		] as Array[PersonalityPref]
	)
	profiles[E.MissionType.ESCORT] = escort

	# One person, one shot, and a very short list of people who should be there.
	var assassination := _make(
		E.MissionType.ASSASSINATION,
		"Assassination",
		{
			E.Skill.COMBAT: 0.45,
			E.Skill.STEALTH: 0.40,
			E.Skill.TECH: 0.15,
		},
		2, 0,
		[E.Role.MARKSMAN] as Array[int],
		[
			PersonalityPref.create(E.PersonalityAxis.DISCIPLINE, 85, 0.9),
			PersonalityPref.create(E.PersonalityAxis.AGGRESSION, 30, 0.7),
		] as Array[PersonalityPref]
	)
	assassination.oversize_penalty = 12.0
	assassination.undersize_penalty = 4.0
	assassination.missing_role_penalty = 16.0
	profiles[E.MissionType.ASSASSINATION] = assassination

	return profiles
