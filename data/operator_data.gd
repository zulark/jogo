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

## Skill -> the part of a point earned but not yet banked, 0.0-1.0.
##
## Skills are whole numbers because the roster draws them as bars, but field
## practice arrives in fractions and used to be rounded away every contract.
## That quietly capped every skill far below SKILL_FIELD_CEILING and froze the
## secondary ones outright — see Progression.add_skill_progress, which is the
## only thing that reads or writes this.
@export var skill_fraction: Dictionary = {}

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

## The specific copies they are carrying. One weapon, one set of gear — a
## loadout should be a decision, not an inventory chore. Null means they go out
## with standard issue.
##
## These are ItemInstance references rather than ids because two operators must
## never be able to hold the same rifle, and because the rifle has a condition
## that is its own rather than its type's. Not @export'ed: the link is rebuilt
## against the company's inventory on load, the same way a deployment's squad is
## rebuilt against the roster.
var weapon: ItemInstance = null
var gear: ItemInstance = null

## Only ever set by from_dict, only ever read by GameState, which owns the
## inventory these have to be re-linked against. See GameState.from_dict.
var pending_weapon_uid: StringName = &""
var pending_gear_uid: StringName = &""
var pending_weapon_id: StringName = &""
var pending_gear_id: StringName = &""

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


## What they are carrying, skipping empty slots. These are copies rather than
## types, so everything read off them is already scaled by how worn they are.
func equipment() -> Array[ItemInstance]:
	var carried: Array[ItemInstance] = []
	if weapon != null:
		carried.append(weapon)
	if gear != null:
		carried.append(gear)
	return carried


func slot_instance(slot: int) -> ItemInstance:
	return weapon if slot == ItemData.Slot.WEAPON else gear


func set_slot_instance(slot: int, instance: ItemInstance) -> void:
	if slot == ItemData.Slot.WEAPON:
		weapon = instance
	else:
		gear = instance


## The *type* in a slot, for the handful of places that care what kind of thing
## somebody is holding rather than which one — the kill feed, mostly.
func weapon_item_id() -> StringName:
	return weapon.item_id if weapon != null else &""


func gear_item_id() -> StringName:
	return gear.item_id if gear != null else &""


## Kit they are carrying that is past being any use. The roster flags it and the
## workshop is where it gets answered.
func has_unserviceable_kit() -> bool:
	for item in equipment():
		if not item.is_serviceable():
			return true
	return false


func equipment_score() -> float:
	var total := 0.0
	for item in equipment():
		total += item.score_modifier()
	return total


func equipment_danger() -> float:
	var total := 0.0
	for item in equipment():
		total += item.danger_modifier()
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


## What the company calls them, for anywhere a full name will not fit — a list
## column, a modifier line. The callsign alone where there is one, because that
## is what everybody says out loud, and it is the half that stays short.
func short_label() -> String:
	return operator_name if callsign.is_empty() else callsign


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


## Who this is, composed from what the game already knows.
##
## Generated rather than stored so it stays true as their career moves — the
## record writes itself, which is the whole appeal of a roster you get attached
## to.
##
## THE PIPELINE. This does not concatenate facts. Each stage below answers one
## question about the operator and returns **at most one sentence**, or "" when
## it has nothing worth saying:
##
##   identity     who they are, and how far into the trade
##   service      what they have run, here and elsewhere, in one arithmetic
##   capability   what they are best at
##   trait        what is on their file
##   personality  how they work, read off the axes the resolver already scores
##   record       kills and saves
##   reputation   what the rest of the roster has decided about them
##   status       the permanent facts: the instructor fork, and age
##
## Facts are GROUPED before they are written. The old version emitted "They
## worked roughly 11 contracts elsewhere before signing on." immediately followed
## by "They have not yet worked a contract for this company." — two sentences for
## one idea, the second of them a negative carrying no information. Those are now
## one sentence, and every stage that would repeat a sibling is suppressed rather
## than printed.
##
## GRAMMAR (see .docs/prose_style_guide.md §4): every stage returns a COMPLETE
## SENTENCE with an explicit subject. TextUtil.sentences() only supplies the
## stops, so a fragment stays a fragment — and IncidentLibrary pastes the whole
## thing straight after a sentence of its own, where a stack of headings reads as
## a form rather than as a person.
func resume() -> String:
	# Order is how it reads; priority is what survives the cap. A biography that
	# says everything it knows is the form this stopped being.
	var stages: Array = [
		{"priority": 0, "text": _bio_identity()},
		{"priority": 1, "text": _bio_service()},
		# An instructor cannot be deployed at all. That outranks almost anything
		# else the paragraph could say about them.
		{"priority": 3, "text": _bio_track()},
		{"priority": 2, "text": _bio_capability()},
		{"priority": 4, "text": _bio_trait()},
		{"priority": 7, "text": _bio_personality()},
		{"priority": 5, "text": _bio_record()},
		{"priority": 6, "text": _bio_reputation()},
		{"priority": 8, "text": _bio_lineage()},
		{"priority": 9, "text": _bio_age()},
	]

	var written: Array = []
	for index in stages.size():
		if not str(stages[index]["text"]).is_empty():
			written.append({"order": index, "priority": stages[index]["priority"],
				"text": stages[index]["text"]})

	written.sort_custom(func(a, b): return a["priority"] < b["priority"])
	written = written.slice(0, BIO_MAX_SENTENCES)
	written.sort_custom(func(a, b): return a["order"] < b["order"])

	var parts: Array = []
	for entry in written:
		parts.append(entry["text"])
	return TextUtil.sentences(parts)


## Past this a biography stops being a description and becomes a dossier. A
## decorated ten-year veteran has more true things on file than anybody wants to
## read under their portrait.
const BIO_MAX_SENTENCES := 6


## How the company refers to them once the opening sentence has introduced them
## in full. Repeating the whole label every sentence is the other half of why the
## paragraph read as a list.
func _short_name() -> String:
	return callsign if not callsign.is_empty() else operator_name


## Identity and standing in one sentence, because they are one idea. The
## seniority tail is a noun phrase in apposition — "and a veteran of the work" —
## rather than the old ", and worth rather more than the company pays them",
## which put a second clause behind a comma in every biography in the game.
func _bio_identity() -> String:
	return "%s is %s %s and %s." % [
		display_label(),
		TextUtil.with_article(demonym()),
		GameEnums.rank_full_name(rank).to_lower(),
		_seniority(),
	]


## Everything they have run, here and elsewhere, as ONE arithmetic.
##
## A true newcomer gets nothing: the identity sentence has already said they are
## new, and "has never been out on a contract" behind "and new to the trade" is
## the same fact twice.
func _bio_service() -> String:
	var run: int = missions_completed + missions_failed
	var who := _short_name()

	if run == 0:
		if prior_service <= 0:
			return ""
		return _pick(16, SERVICE_ELSEWHERE).format({"who": who, "record": _prior_phrase()})

	var here := ""
	if missions_failed == 0:
		here = "%s has completed %s for this company without losing one" % [
			who, TextUtil.spelled(run, "contract")]
	elif missions_completed == 0:
		here = "%s has deployed %s for this company and has yet to close one" % [
			who, TextUtil.spelled(run, "time")]
	else:
		here = "%s has completed %s for this company and lost %s" % [
			who, TextUtil.spelled(missions_completed, "contract"),
			TextUtil.number(missions_failed)]

	if prior_service <= 0:
		return "%s, and has never served under anybody else." % here
	return "%s, on top of %s elsewhere." % [here, _prior_phrase()]


## Every operator on a fresh roster has service elsewhere and none here, so this
## is the single most-repeated sentence in the game — six of them are on screen
## at once on the Recruits list. It gets variants for that reason alone.
##
## GRAMMAR: a SENTENCE, with named placeholders substituted by String.format().
## `{who}` is the callsign, `{record}` is an already-counted noun phrase
## ("roughly eleven contracts", "a single contract"), so no entry may supply a
## number or an article of its own.
const SERVICE_ELSEWHERE := [
	"{who} came in with {record} behind them and has yet to deploy for this company.",
	"{who} has {record} behind them and nothing yet for this company.",
	"{who} arrived with {record} to their name and has not deployed for this company yet.",
	"{who} turned up with {record} already behind them and has not been out for this company.",
]


## "Roughly one contract" is not a quantity anybody estimates, and neither is
## "roughly two". A hedge only means anything once the number is big enough that
## nobody would have counted it exactly.
const PRIOR_HEDGE_FLOOR := 5


func _prior_phrase() -> String:
	if prior_service == 1:
		return "a single contract"
	if prior_service < PRIOR_HEDGE_FLOOR:
		return TextUtil.spelled(prior_service, "contract")
	return "roughly %s" % TextUtil.spelled(prior_service, "contract")


func _bio_capability() -> String:
	var best: Array = top_skills(1)
	if best.is_empty() or int(best[0]["value"]) <= 0:
		return ""
	var skill: int = int(best[0]["skill"])
	# A starred skill reads as 100-plus, and "at 110" is a number no scale on any
	# screen explains. Mastery is the thing worth saying there.
	if stars_in(skill) > 0:
		return "They have taken %s as far as it goes." % GameEnums.skill_name(skill).to_lower()
	return "%s is their strongest suit, at %d." % [
		GameEnums.skill_name(skill), int(best[0]["value"])]


## The trait names are a mixture of adjectives ("claustrophobic"), nouns
## ("hothead") and verb phrases ("fears assault"), and a colon is the one frame
## all three read correctly after. Positives were previously never mentioned at
## all, so half of what the factory generates never reached the page.
func _bio_trait() -> String:
	for t in traits:
		if t.polarity == GameEnums.TraitPolarity.NEGATIVE:
			return "Their file carries one note: %s." % t.display_name.to_lower()
	for t in traits:
		if t.polarity == GameEnums.TraitPolarity.POSITIVE:
			return "One thing stands out on their file: %s." % t.display_name.to_lower()
	return ""


## Seniority describes the CAREER, not the tenure. Reading it off
## missions_completed + prior_service and then calling the result "one of the
## company's old hands" told the player a walk-in who had never worked a day here
## was a veteran of the outfit — the sentence contradicted the sentence after it.
## Anyone with service elsewhere is senior in the trade; only contracts run FOR
## THIS COMPANY make them one of its own.
##
## GRAMMAR (see .docs/prose_style_guide.md §4): each entry completes the frame
## "<label> is <a nationality rank> and ___." — a lower-case NOUN PHRASE in
## apposition, with NO closing stop and NO COMMA.
##
## A noun phrase rather than the predicate phrases these used to hold, because
## the frame used to be "…, and ___." and every biography in the game therefore
## carried a second clause behind a comma before it had said anything. "A veteran
## of the work" sits behind "and" without punctuation and reads as one thought.
const SENIORITY := {
	# Contracts here outrank contracts anywhere else, so these are checked first.
	"company_veteran": [
		"one of the company's old hands",
		"one of the names this company is known by",
		"a fixture here by now",
	],
	"company_regular": [
		"an experienced hand here",
		"somebody this company has learned to rely on",
		"a known quantity around here",
	],
	"career_top": [
		"a career veteran of this work",
		"one of the older hands in the trade",
		"a veteran of about as much of this as anybody sees",
	],
	"career_senior": [
		"a veteran of the work",
		"somebody well past needing supervision",
		"an experienced hand in the trade",
	],
	"career_middle": [
		"a few contracts into the work",
		"somebody past the worst of the learning",
		"a competent pair of hands and not much more yet",
	],
	"career_new": [
		"new to the trade",
		"a recent arrival to the work",
		"somebody new enough to still be surprised by it",
	],
}


func _seniority() -> String:
	if missions_completed >= 25:
		return _pick(1, SENIORITY["company_veteran"])
	if missions_completed >= 10:
		return _pick(2, SENIORITY["company_regular"])

	# A contract that went wrong still taught them something, so failures count
	# toward experience — leaving them out described somebody with a kill and a
	# save to their name as "yet to find out what this job actually is".
	var total: int = missions_completed + missions_failed + prior_service
	if total >= 25:
		return _pick(3, SENIORITY["career_top"])
	if total >= 10:
		return _pick(4, SENIORITY["career_senior"])
	if total >= 3:
		return _pick(5, SENIORITY["career_middle"])
	return _pick(6, SENIORITY["career_new"])


## How they work, read off the personality axes the resolver already scores
## against every mission profile. Those four numbers decide whether an operator
## suits a job and were never once mentioned in prose, so the one part of the
## data that is actually about character was invisible.
##
## Only the axis furthest from neutral, and only when it is far enough out to
## mean something. An operator sitting near 50 on everything gets no line rather
## than an invented personality — which is the rule the whole file runs on.
##
## GRAMMAR: a complete SENTENCE with "They" as its subject. Nothing here may
## claim a relationship, a record or a preference the data does not hold: bonds
## are their own system, and a loner with three friendships would be a
## contradiction the player can see.
const PERSONALITY_NOTES := {
	"aggression_high": [
		"They push harder than the plan usually allows for.",
		"They tend to force a position rather than wait for it to open.",
		"They are not built for hanging back.",
		"They would rather move too early than too late.",
		"They close distance when the sensible thing is to hold it.",
	],
	"aggression_low": [
		"They would rather wait out a bad position than force it.",
		"They are slow to commit to ground they have not looked at twice.",
		"They will not be hurried into a building.",
		"They would rather arrive late than arrive wrong.",
		"Speed is not something they will trade safety for.",
	],
	"discipline_high": [
		"They keep to the plan and expect everyone else to.",
		"They do the job the way the briefing said to do it.",
		"They have very little patience for improvisation.",
		"They read the brief twice and hold everyone to it.",
		"They do not consider a plan a suggestion.",
	],
	"discipline_low": [
		"They work better off the plan than on it.",
		"They treat a briefing as a starting position.",
		"Plans tend not to survive contact with them.",
		"They improvise first and explain afterwards.",
		"They are unlikely to follow a timetable all the way through.",
	],
	"bravery_high": [
		"They do not seem to register risk the way the rest of the roster does.",
		"They go through the door first without being asked to.",
		"Fear does not appear to come into it for them.",
		"They volunteer for the part of the job nobody else wants.",
		"Nothing about the work appears to trouble them.",
	],
	"bravery_low": [
		"They are honest about being frightened, which is more than most manage.",
		"They do not pretend the work does not frighten them.",
		"They need telling twice before they will go through a door.",
		"They are in no hurry to be first out of the truck.",
		"They are not going to pretend this work is easy.",
	],
	"sociability_high": [
		"They are the one the new arrivals end up talking to.",
		"They work best with people around them.",
		"They are easy to put in a squad with anybody.",
		"They talk through a problem rather than sit on it.",
		"They are usually in the middle of whatever is going on.",
	],
	"sociability_low": [
		"They keep to themselves between contracts.",
		"They would rather work alone, and say so.",
		"They are not much for company.",
		"They answer questions and volunteer nothing.",
		"They are difficult to get more than a sentence out of.",
	],
}

## How far off neutral an axis has to sit before it says anything. The factory
## rolls 50 ± 32, so roughly two operators in five have one axis this far out and
## the rest are described by their record instead.
const PERSONALITY_THRESHOLD := 20


func _bio_personality() -> String:
	var strongest := -1
	var distance := 0
	for axis in GameEnums.PersonalityAxis.values():
		var offset: int = absi(get_personality(axis) - 50)
		if offset > distance:
			distance = offset
			strongest = axis
	if strongest < 0 or distance < PERSONALITY_THRESHOLD:
		return ""

	var key := "%s_%s" % [
		GameEnums.axis_name(strongest).to_lower(),
		"high" if get_personality(strongest) > 50 else "low",
	]
	if not PERSONALITY_NOTES.has(key):
		return ""
	return _pick(12 + strongest, PERSONALITY_NOTES[key])


## Kills and saves in one sentence. Two made the paragraph a tally.
func _bio_record() -> String:
	var kills: bool = confirmed_kills > 0
	var pulled: bool = saves > 0
	if kills and pulled:
		return "They have %s confirmed, and have pulled %s out alive." % [
			TextUtil.number(confirmed_kills), TextUtil.spelled(saves, "squadmate")]
	if kills:
		return "They have %s confirmed." % TextUtil.number(confirmed_kills)
	if pulled:
		return "They have pulled %s out alive." % TextUtil.spelled(saves, "squadmate")
	return ""


## Who taught them and who they taught. Suppressed when the closing line is
## already about their teaching, or the paragraph says it twice.
func _bio_lineage() -> String:
	var taught: bool = not trainees.is_empty() and _reputation_gate() != "instructor"
	if not trained_by.is_empty() and taught:
		return "They came up under %s, and have trained %s since." % [
			trained_by, TextUtil.spelled(trainees.size(), "operator")]
	if not trained_by.is_empty():
		return "They came up under %s." % trained_by
	if taught:
		return "They have trained %s." % TextUtil.spelled(trainees.size(), "operator")
	return ""


## The permanent facts about a career, as opposed to what they are doing this
## week. Nothing here moves day to day: a biography that changed every time
## somebody sprained an ankle would not be a biography.
func _bio_track() -> String:
	if career_track == GameEnums.CareerTrack.INSTRUCTOR:
		return "They teach now, and will not be going out again."
	return ""


## Said about people the years have genuinely caught up with, not everybody past
## the line where the numbers start moving. Decline begins at AGE_DECLINE_START,
## which is early enough that a third of any roster is over it — and a sentence
## printed about a third of the roster stops being about anybody.
const BIO_AGE_MARGIN := 6


func _bio_age() -> String:
	if age < Balance.AGE_DECLINE_START + BIO_AGE_MARGIN:
		return ""
	return "At %d, the physical side of it no longer comes free." % age


## What the rest of the roster has decided about them.
##
## The one line here that is a story rather than a readout — and it is still not
## invented: every pool is gated on a record the player watched accumulate, so
## the sentence names its own cause. An operator with nothing on their file gets
## no line at all rather than a flattering guess.
## Each key names the record that earns it, so a line can never be drawn for
## somebody it is not true of. GRAMMAR: a complete sentence, no placeholder.
const REPUTATION := {
	"killer": [
		"The rest of the roster has stopped asking them how many.",
		"People who have worked with them do not tell the stories in front of them.",
		"Nobody here brings up the tally twice.",
	],
	"saver": [
		"There are people on this roster who are only here because of them.",
		"The infirmary knows them by name, and not as a patient.",
		"More than one person here owes them a debt nobody wrote down.",
	],
	"instructor": [
		"The newer hands here learned the job standing behind them.",
		"They are who the new arrivals get handed to.",
		"Nobody here teaches it the way they do.",
	],
	"unlucky": [
		"Their name comes up when this company talks about bad luck.",
		"They have been on the wrong contracts more often than not.",
		"Somebody in accounts has noticed which jobs they were on.",
	],
	# Nothing here may claim the file is empty. A trait prints one line above
	# this — "One thing stands out on their file: ghost." — and "there is nothing
	# on their file but the signature" underneath it contradicted it outright.
	"untested": [
		"Nobody here has seen them work yet.",
		"There is nothing behind the signature yet.",
		"The company is taking them on faith.",
	],
}


## Which record, if any, has earned them a closing line. Separate from the line
## itself so _bio_lineage() can ask the same question and stay quiet rather than
## reporting the trainee count directly above a sentence about their teaching.
const REPUTATION_SALTS := {
	"killer": 7, "saver": 8, "instructor": 9, "unlucky": 10, "untested": 11,
}


func _reputation_gate() -> String:
	if confirmed_kills >= 25:
		return "killer"
	if saves >= 3:
		return "saver"
	if trainees.size() >= 2:
		return "instructor"
	if missions_failed > missions_completed and missions_failed + missions_completed >= 3:
		return "unlucky"
	if missions_completed + missions_failed + prior_service == 0:
		return "untested"
	return ""


func _bio_reputation() -> String:
	var gate := _reputation_gate()
	if gate.is_empty():
		return ""
	return _pick(int(REPUTATION_SALTS[gate]), REPUTATION[gate])


## A choice that is stable for this operator.
##
## `resume()` runs every time the roster or the recruit list redraws, so the
## variation has to be a function of WHO they are rather than of when it was
## asked — prose that reshuffled on every repaint would not read as a person.
## Derived from the id like portrait_color(), so it also survives a save/load.
## `salt` keeps the pools independent: without it every pool would land on the
## same index and an operator's whole résumé would be variant 2 throughout.
func _pick(salt: int, pool: Array) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = String(id).hash() + salt * 7919
	return str(pool[rng.randi() % pool.size()])


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
		"skill_fraction": skill_fraction.duplicate(),
		"personality": personality.duplicate(),
		"nationality": String(nationality),
		"trait_ids": trait_ids,
		"rank": int(rank),
		"xp": xp,
		"career_track": int(career_track),
		"preferred_role": int(preferred_role),
		"weapon_uid": String(weapon.uid) if weapon != null else "",
		"gear_uid": String(gear.uid) if gear != null else "",
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
	op.skill_fraction = SaveUtil.to_int_keys_float(data.get("skill_fraction", {}))
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
	# Held rather than resolved: the inventory these point into does not exist
	# yet at this point in the load. `weapon_id` is the pre-condition save
	# format, kept so an existing company does not lose its kit on upgrade.
	op.pending_weapon_uid = StringName(str(data.get("weapon_uid", "")))
	op.pending_gear_uid = StringName(str(data.get("gear_uid", "")))
	op.pending_weapon_id = StringName(str(data.get("weapon_id", "")))
	op.pending_gear_id = StringName(str(data.get("gear_id", "")))
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
