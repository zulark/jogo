class_name OperatorData
extends Resource

## One mercenary. This is pure data — it never calculates mission outcomes and
## never touches the scene tree. Systems read it; MissionResolver scores it.

@export var id: StringName = &""
@export var operator_name: String = ""
@export var callsign: String = ""

## Base skills, keys are GameEnums.Skill, values 0-100.
## Read through get_skill() so trait modifiers are always included.
##
## Once a skill fills, the excess becomes a star and this resets — so for a
## starred skill this number is progress toward the NEXT star, not capability.
@export var skills: Dictionary = {}

## Skill -> 0..MAX_SKILL_STARS. Mastery beyond a filled bar.
@export var skill_stars: Dictionary = {}

## Personality axes, keys are GameEnums.PersonalityAxis, values 0-100 (50 neutral).
@export var personality: Dictionary = {}

## NationLibrary id. Drives their name and how the roster reads.
@export var nationality: StringName = &""


@export var traits: Array[TraitData] = []

@export var rank: GameEnums.Rank = GameEnums.Rank.PRIVATE
@export var xp: int = 0

## Field careers stop at Warrant Officer. Switching to INSTRUCTOR opens the four
## ranks above it and closes the field for good — it is one-way.
@export var career_track: GameEnums.CareerTrack = GameEnums.CareerTrack.FIELD

@export var preferred_role: GameEnums.Role = GameEnums.Role.ASSAULT

## ItemLibrary ids. One weapon, one set of gear — a loadout should be a decision,
## not an inventory chore. Empty means they go out with standard issue.
@export var weapon_id: StringName = &""
@export var gear_id: StringName = &""

## Weekly cost in diamonds, charged on the week boundary.
@export var salary: int = 100

@export var status: GameEnums.OperatorStatus = GameEnums.OperatorStatus.AVAILABLE

## 0-100. Climbs on deployment, falls with rest. High fatigue costs score and
## gets people hurt, which is what forces squad rotation.
@export_range(0, 100) var fatigue: int = 0

## 0-100. Rises on wins, falls on losses, wounds, missed payroll and the deaths
## of people they were close to. Too low and they walk.
@export_range(0, 100) var morale: int = Balance.MORALE_START

## Other operator id -> { "type": GameEnums.BondType, "strength": 0-100 }.
## Always mirrored on both operators — write through the Bonds helper, never
## directly, or one half of a friendship goes missing.
@export var bonds: Dictionary = {}

## Days left before status returns to AVAILABLE. Ticked by the calendar in v0.2.
@export var days_unavailable: int = 0

## History. The cemetery is the whole reason this is recorded — a name on a wall
## means nothing without the record behind it.
## Contracts run FOR THIS COMPANY. These only ever move because something
## actually happened in play — never seeded, so the number on a headstone is a
## real number.
@export var missions_completed: int = 0
@export var missions_failed: int = 0

## What they did before you hired them. Kept separate so a veteran's rank is
## explicable without lying about their record with you.
@export var prior_service: int = 0

## Confirmed kills across their whole career with this company.
@export var confirmed_kills: int = 0

## MedalLibrary ids they have been awarded. Permanent, and the reason the
## cemetery entry for a ten-year veteran reads like a life rather than a row.
@export var medals: Array[String] = []

## Squadmates they have kept alive — a medic pulling someone off the ground.
@export var saves: int = 0

## Named people they have killed. The company remembers these — see the
## assassination path in MissionResolver — and so does everyone else.
@export var trophies: Array[String] = []

## Display label of whoever trained them, and everyone they trained.
@export var trained_by: String = ""
@export var trainees: Array[String] = []

## Filled in only on death, for the cemetery entry.
@export var died_on_day: int = 0
@export var died_on_mission: String = ""
@export var died_in_region: String = ""


func stars_in(skill: int) -> int:
	return int(skill_stars.get(skill, 0))


## Where the bar is, ignoring stars. This is what the roster draws.
func skill_progress(skill: int) -> int:
	return int(skills.get(skill, 0))


## Base value plus every applicable trait's delta and whatever they are carrying.
##
## A starred skill reads as FILLED plus a bonus per star, never as the raw
## progress bar — otherwise earning a star would make an operator worse the
## instant they mastered something, which is the opposite of the point.
func get_skill(skill: int, mission_type: int = -1) -> int:
	var stars: int = stars_in(skill)
	var value: int = int(skills.get(skill, 0))
	if stars > 0:
		value = 100 + stars * Balance.STAR_BONUS
	for t in traits:
		if t == null:
			continue
		if mission_type >= 0 and not t.applies_to(mission_type):
			continue
		value += t.skill_delta(skill)
	for item in equipment():
		value += item.skill_delta(skill)
	return clampi(value, 0, 100 + Balance.MAX_SKILL_STARS * Balance.STAR_BONUS)


## What they are carrying, skipping empty slots.
func equipment() -> Array[ItemData]:
	var carried: Array[ItemData] = []
	var weapon := ItemLibrary.get_item(weapon_id)
	if weapon != null:
		carried.append(weapon)
	var gear := ItemLibrary.get_item(gear_id)
	if gear != null:
		carried.append(gear)
	return carried


func equipment_score() -> float:
	var total := 0.0
	for item in equipment():
		total += item.score_modifier
	return total


func equipment_danger() -> float:
	var total := 0.0
	for item in equipment():
		total += item.danger_modifier
	return total


func get_personality(axis: int) -> int:
	return clampi(int(personality.get(axis, 50)), 0, 100)


func nation() -> NationData:
	return NationLibrary.get_nation(nationality)


func demonym() -> String:
	var data := nation()
	return data.demonym if data != null else "Stateless"


func is_deployable() -> bool:
	return status == GameEnums.OperatorStatus.AVAILABLE


## Completely spent. They can still be taught and still take standing work, but
## no contract will have them — at which point rotation stops being advice and
## becomes a rule.
func is_exhausted() -> bool:
	return fatigue >= Balance.FATIGUE_EXHAUSTED


## Age, and what it does. Physical skills start going after a point; judgement
## does not, which is what makes an ageing veteran worth keeping as an instructor
## rather than worth firing.
@export var age: int = 30


func is_ageing() -> bool:
	return age >= Balance.AGE_DECLINE_START


func has_trait(trait_id: StringName) -> bool:
	for t in traits:
		if t != null and t.id == trait_id:
			return true
	return false


## Traits that fire on this mission type. Used by the resolver and the UI tooltip.
func active_traits(mission_type: int) -> Array[TraitData]:
	var result: Array[TraitData] = []
	for t in traits:
		if t != null and t.applies_to(mission_type):
			result.append(t)
	return result


func display_label() -> String:
	if callsign.is_empty():
		return operator_name
	return "%s \"%s\"" % [operator_name, callsign]


func rank_step() -> int:
	return int(rank)


## The two or three skills worth knowing about, best first. Used everywhere an
## operator is being judged at a glance — hiring, squad selection — because
## "Marksman" says what they trained as and this says whether they are any good
## at it.
func top_skills(count: int = 3) -> Array:
	var ranked: Array = []
	for skill in GameEnums.Skill.values():
		ranked.append({"skill": skill, "value": get_skill(skill)})
	ranked.sort_custom(func(a, b): return a["value"] > b["value"])
	return ranked.slice(0, count)


## A stable colour for this operator, derived from their id. Stands in for a
## portrait until there is art, and stays the same across sessions so the eye
## learns it the way it would learn a face.
func portrait_color() -> Color:
	var hash_value: int = String(id).hash()
	var hue: float = float(hash_value % 360) / 360.0
	return Color.from_hsv(hue, 0.42, 0.55)


func initials() -> String:
	var parts := operator_name.split(" ", false)
	if parts.size() >= 2:
		return "%s%s" % [parts[0].substr(0, 1), parts[1].substr(0, 1)]
	return operator_name.substr(0, 2).to_upper()


## A few sentences about who this is, composed from what the game already knows.
## Generated rather than stored so it stays true as their career moves — the
## record writes itself, which is the whole appeal of a roster you get attached to.
func resume() -> String:
	var parts: Array = []
	var total: int = missions_completed + prior_service

	var seniority: String = "a new hire"
	if total >= 25:
		seniority = "one of the company's old hands"
	elif total >= 10:
		seniority = "an experienced hand"
	elif total >= 3:
		seniority = "still finding their feet"

	# One proper opening sentence rather than three fragments jammed together.
	parts.append("%s is %s %s %s, and %s" % [
		display_label(),
		TextUtil.article(demonym()),
		demonym(),
		GameEnums.rank_name(rank).to_lower(),
		seniority,
	])

	if prior_service > 0:
		parts.append("They worked roughly %s elsewhere before signing on" % (
			TextUtil.spelled(prior_service, "contract")))

	if missions_completed > 0 or missions_failed > 0:
		var failures: String = (
			"none gone wrong" if missions_failed == 0
			else "%s gone wrong" % TextUtil.number(missions_failed))
		parts.append("With this company: %s completed, %s" % [
			TextUtil.count(missions_completed, "contract"), failures])
	elif prior_service > 0:
		parts.append("They have not yet worked a contract for this company")

	if confirmed_kills > 0:
		parts.append("%s confirmed" % TextUtil.count(confirmed_kills, "kill"))
	if saves > 0:
		parts.append("They have pulled %s out alive" % (
			TextUtil.spelled(saves, "squadmate")))

	var best: Array = top_skills(1)
	if not best.is_empty() and int(best[0]["value"]) > 0:
		parts.append("Their strongest skill is %s, at %d" % [
			GameEnums.skill_name(best[0]["skill"]).to_lower(), int(best[0]["value"])])

	if not trained_by.is_empty():
		parts.append("Brought on by %s" % trained_by)
	if not trainees.is_empty():
		parts.append("They have trained %s" % TextUtil.spelled(trainees.size(), "operator"))

	for t in traits:
		if t.polarity == GameEnums.TraitPolarity.NEGATIVE:
			parts.append("Noted on their file: %s" % t.display_name.to_lower())
			break

	return TextUtil.sentences(parts)


# --- Serialisation -----------------------------------------------------------
# Saves go through plain dictionaries rather than ResourceSaver: a save file has
# to survive the class gaining fields, and JSON degrades gracefully where a
# packed resource does not.

func to_dict() -> Dictionary:
	var trait_ids: Array = []
	for t in traits:
		if t != null:
			trait_ids.append(String(t.id))
	return {
		"id": String(id),
		"operator_name": operator_name,
		"callsign": callsign,
		"skills": skills.duplicate(),
		"skill_stars": skill_stars.duplicate(),
		"personality": personality.duplicate(),
		"nationality": String(nationality),
		"trait_ids": trait_ids,
		"rank": int(rank),
		"xp": xp,
		"career_track": int(career_track),
		"preferred_role": int(preferred_role),
		"weapon_id": String(weapon_id),
		"gear_id": String(gear_id),
		"salary": salary,
		"status": int(status),
		"fatigue": fatigue,
		"morale": morale,
		"bonds": bonds.duplicate(true),
		"days_unavailable": days_unavailable,
		"missions_completed": missions_completed,
		"missions_failed": missions_failed,
		"prior_service": prior_service,
		"confirmed_kills": confirmed_kills,
		"trophies": trophies,
		"medals": medals,
		"saves": saves,
		"age": age,
		"trained_by": trained_by,
		"trainees": trainees,
		"died_on_day": died_on_day,
		"died_on_mission": died_on_mission,
		"died_in_region": died_in_region,
	}


static func from_dict(data: Dictionary) -> OperatorData:
	var op := OperatorData.new()
	op.id = StringName(data.get("id", ""))
	op.operator_name = data.get("operator_name", "")
	op.callsign = data.get("callsign", "")
	op.skills = SaveUtil.to_int_keys(data.get("skills", {}))
	op.skill_stars = SaveUtil.to_int_keys(data.get("skill_stars", {}))
	op.personality = SaveUtil.to_int_keys(data.get("personality", {}))
	op.nationality = StringName(data.get("nationality", ""))

	var loaded_traits: Array[TraitData] = []
	for trait_id in data.get("trait_ids", []):
		var t := TraitLibrary.get_trait(StringName(trait_id))
		if t != null:
			loaded_traits.append(t)
	op.traits = loaded_traits

	op.rank = int(data.get("rank", 0))
	op.xp = int(data.get("xp", 0))
	op.career_track = int(data.get("career_track", 0))
	op.preferred_role = int(data.get("preferred_role", 0))
	op.weapon_id = StringName(data.get("weapon_id", ""))
	op.gear_id = StringName(data.get("gear_id", ""))
	op.salary = int(data.get("salary", 0))
	op.status = int(data.get("status", 0))
	op.fatigue = int(data.get("fatigue", 0))
	op.morale = int(data.get("morale", Balance.MORALE_START))

	# JSON hands back string keys and float values; rebuild both.
	var loaded_bonds := {}
	for other_id in data.get("bonds", {}):
		var entry: Dictionary = data["bonds"][other_id]
		loaded_bonds[StringName(str(other_id))] = {
			"type": int(entry.get("type", 0)),
			"strength": int(entry.get("strength", 0)),
			"reason": str(entry.get("reason", "")),
		}
	op.bonds = loaded_bonds

	op.days_unavailable = int(data.get("days_unavailable", 0))
	op.missions_completed = int(data.get("missions_completed", 0))
	op.missions_failed = int(data.get("missions_failed", 0))
	op.prior_service = int(data.get("prior_service", 0))
	op.confirmed_kills = int(data.get("confirmed_kills", 0))
	var loaded_medals: Array[String] = []
	for entry in data.get("medals", []):
		loaded_medals.append(str(entry))
	op.medals = loaded_medals
	op.saves = int(data.get("saves", 0))

	var loaded_trophies: Array[String] = []
	for entry in data.get("trophies", []):
		loaded_trophies.append(str(entry))
	op.trophies = loaded_trophies
	op.age = int(data.get("age", 30))
	op.trained_by = data.get("trained_by", "")

	var loaded_trainees: Array[String] = []
	for name in data.get("trainees", []):
		loaded_trainees.append(str(name))
	op.trainees = loaded_trainees

	op.died_on_day = int(data.get("died_on_day", 0))
	op.died_on_mission = data.get("died_on_mission", "")
	op.died_in_region = data.get("died_in_region", "")
	return op
