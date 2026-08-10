class_name OperatorFactory
extends RefCounted

## Generates operators. Used by the simulation harness now, and by the hiring
## pool in v0.2 — the recruits on offer each week come out of here.
##
## Every operator is built from an archetype (what they trained as) plus a
## quality tier (how good they got at it) plus noise, so two Marksmen are never
## identical and the roster reads like people rather than stat blocks.

enum Tier { ROOKIE, REGULAR, VETERAN, ELITE }

const TIER_BONUS := {
	Tier.ROOKIE: -18,
	Tier.REGULAR: 0,
	Tier.VETERAN: 14,
	Tier.ELITE: 26,
}

const TIER_RANK := {
	Tier.ROOKIE: GameEnums.Rank.PRIVATE,
	Tier.REGULAR: GameEnums.Rank.CORPORAL,
	Tier.VETERAN: GameEnums.Rank.SERGEANT_SECOND,
	Tier.ELITE: GameEnums.Rank.WARRANT_OFFICER,
}

## Baseline skill spread per archetype, before tier and noise.
const ARCHETYPES := {
	GameEnums.Role.ASSAULT: {
		GameEnums.Skill.COMBAT: 62,
		GameEnums.Skill.STEALTH: 30,
		GameEnums.Skill.MEDICAL: 22,
		GameEnums.Skill.TECH: 25,
		GameEnums.Skill.LEADERSHIP: 40,
		GameEnums.Skill.ENDURANCE: 58,
	},
	GameEnums.Role.MARKSMAN: {
		GameEnums.Skill.COMBAT: 68,
		GameEnums.Skill.STEALTH: 48,
		GameEnums.Skill.MEDICAL: 18,
		GameEnums.Skill.TECH: 24,
		GameEnums.Skill.LEADERSHIP: 30,
		GameEnums.Skill.ENDURANCE: 44,
	},
	GameEnums.Role.MEDIC: {
		GameEnums.Skill.COMBAT: 34,
		GameEnums.Skill.STEALTH: 32,
		GameEnums.Skill.MEDICAL: 70,
		GameEnums.Skill.TECH: 30,
		GameEnums.Skill.LEADERSHIP: 38,
		GameEnums.Skill.ENDURANCE: 46,
	},
	GameEnums.Role.SCOUT: {
		GameEnums.Skill.COMBAT: 40,
		GameEnums.Skill.STEALTH: 70,
		GameEnums.Skill.MEDICAL: 22,
		GameEnums.Skill.TECH: 40,
		GameEnums.Skill.LEADERSHIP: 30,
		GameEnums.Skill.ENDURANCE: 52,
	},
	GameEnums.Role.ENGINEER: {
		GameEnums.Skill.COMBAT: 36,
		GameEnums.Skill.STEALTH: 42,
		GameEnums.Skill.MEDICAL: 24,
		GameEnums.Skill.TECH: 70,
		GameEnums.Skill.LEADERSHIP: 32,
		GameEnums.Skill.ENDURANCE: 42,
	},
}

static func create(
	rng: RandomNumberGenerator,
	role: int = -1,
	tier: int = -1,
	taken_callsigns: Array = []
) -> OperatorData:
	if role < 0:
		role = rng.randi() % ARCHETYPES.size()
	if tier < 0:
		tier = rng.randi() % Tier.size()

	var op := OperatorData.new()

	# Nationality is decided first, because it decides the name. Picking a name
	# before knowing where someone is from is how you end up with a Japanese
	# operator called Bexley Marchetti.
	var nation := NationLibrary.random_nation(rng)
	op.nationality = nation.id
	op.operator_name = NameLibrary.full_name(rng, nation.culture)
	op.callsign = NameLibrary.callsign(rng, taken_callsigns)
	op.id = StringName("%s_%d" % [op.callsign.to_lower(), rng.randi() % 100000])
	op.preferred_role = role
	op.rank = TIER_RANK[tier]

	# A recruit who arrives as a Sergeant has served somewhere. Seed XP to match
	# the rank, part-way into the current band — otherwise the career bar reads
	# "0 / 300 toward Corporal" under the word "Sergeant", and every promotion
	# check would try to demote them.
	var band_floor: int = int(Balance.RANK_XP[op.rank])
	var band_ceiling: int = int(Balance.RANK_XP[mini(
		op.rank_step() + 1, Balance.RANK_XP.size() - 1)])
	op.xp = band_floor + rng.randi_range(0, maxi(0, (band_ceiling - band_floor) / 2))

	# Their history BEFORE you hired them, which is what explains the rank they
	# arrive with. The record with this company stays at zero and only moves
	# when something actually happens in play — a headstone should never quote a
	# number the player never watched happen.
	op.prior_service = int(float(op.xp) / (float(Balance.XP_ON_SUCCESS) * 1.5))

	# Age follows service: a Warrant Officer who has never been shot at would be
	# a strange thing to meet.
	op.age = 22 + op.rank_step() * 3 + rng.randi_range(0, 7)

	var baseline: Dictionary = ARCHETYPES[role]
	var bonus: int = TIER_BONUS[tier]
	for skill in baseline:
		var value: int = int(baseline[skill]) + bonus + rng.randi_range(-7, 7)
		op.skills[skill] = clampi(value, 5, 95)

	for axis in GameEnums.PersonalityAxis.values():
		op.personality[axis] = clampi(50 + rng.randi_range(-32, 32), 0, 100)


	# Roughly one operator in three carries something. Veterans have seen more,
	# so they are likelier to carry both a strength and a scar.
	if rng.randf() < 0.35:
		var t := TraitLibrary.random_trait(rng, GameEnums.TraitPolarity.POSITIVE)
		if t != null:
			op.traits.append(t)
	if rng.randf() < (0.15 if tier <= Tier.REGULAR else 0.35):
		var t := TraitLibrary.random_trait(rng, GameEnums.TraitPolarity.NEGATIVE)
		if t != null and not op.traits.has(t):
			op.traits.append(t)

	op.salary = _salary_for(op)
	return op



## Salary tracks what the operator is actually worth, so a strong roster is
## expensive to keep. This is the pressure that forces mission throughput.
static func _salary_for(op: OperatorData) -> int:
	var total := 0
	for skill in GameEnums.Skill.values():
		total += op.get_skill(skill)
	var average: float = float(total) / float(GameEnums.Skill.size())
	var base: float = 30.0 + average * 2.9
	base *= 1.0 + float(op.rank_step()) * 0.12
	return int(round(base / 10.0) * 10)


## A batch of recruits, one per role where possible — the shape of a hiring pool.
## Pass the callsigns already in use so nobody on the roster shares one.
static func create_pool(
	rng: RandomNumberGenerator,
	count: int,
	taken_callsigns: Array = []
) -> Array[OperatorData]:
	var taken: Array = taken_callsigns.duplicate()
	var pool: Array[OperatorData] = []
	for i in count:
		var role: int = i % ARCHETYPES.size()
		var op := create(rng, role, -1, taken)
		taken.append(op.callsign)
		pool.append(op)
	return pool
