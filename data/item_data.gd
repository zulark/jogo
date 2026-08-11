class_name ItemData
extends Resource

## A weapon or a piece of field equipment.
##
## Two slots only — one weapon, one set of gear — so a loadout is a decision
## rather than an inventory-management chore. Weapons mostly raise what an
## operator can do; gear mostly keeps them alive. Blackmarket items break that
## rule on purpose, which is what makes them worth the reputation.

enum Slot { WEAPON, GEAR }

## WORKSHOP items are never for sale anywhere. The only way to hold one is to
## find the plans on a contract and build it, which is what makes a blueprint
## worth carrying home.
enum Source { ARMOURY, QUARTERMASTER, BLACKMARKET, WORKSHOP }

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export var slot: Slot = Slot.WEAPON
@export var source: Source = Source.ARMOURY

## Which facility level unlocks it. Blackmarket items ignore this and use
## `reputation_required` instead.
@export var tier: int = 1

@export var price: int = 500

## Reputation the company must have earned before the blackmarket will deal.
@export var reputation_required: int = 0

## Skill deltas while equipped. Keys are GameEnums.Skill.
@export var skill_modifiers: Dictionary = {}

## Flat score added to the wearer's contribution.
@export var score_modifier: float = 0.0

## Percentage points added to their chance of being harmed. Armour is negative.
@export var danger_modifier: float = 0.0

## A regional hazard this item cancels. Consumables like this are how a player
## turns "the Kivu Border is dangerous" into "the Kivu Border costs 900 a head",
## which is a decision rather than a wall.
@export var counters_hazard: GameEnums.Hazard = GameEnums.Hazard.NONE

## --- Blueprints ---
## Set on WORKSHOP items only. `price` still stands for what the thing is worth,
## because scrap and resale are priced off it; these are what it costs to make.
@export var craft_salvage: int = 0
@export var craft_price: int = 0
@export var craft_days: int = 0

## Which bench builds it, and the level that bench has to be at.
@export var craft_facility: StringName = &""
@export var craft_level: int = 2


func is_craftable() -> bool:
	return source == Source.WORKSHOP


## Kit whose name is grammatically plural, and the word you would count it in.
## "A night optics" is not English; "a set of night optics" is, and "the night
## optics ARE unserviceable" needs the verb to know.
##
## Listed rather than guessed from a trailing "s". A heuristic would have called
## "Supplemental Oxygen" singular and countable, which it is neither.
const PLURAL_NAMES := {
	&"antimalarials": "case",
	&"night_optics": "set",
	&"rebuilt_optics": "set",
	&"combat_stimulants": "box",
	&"shaped_charges": "set",
}

## Mass nouns: singular verb, but never an article. "They went out without
## supplemental oxygen."
const MASS_NAMES: Array[StringName] = [
	&"altitude_kit",
]


func is_plural() -> bool:
	return PLURAL_NAMES.has(id)


func takes_article() -> bool:
	return not is_plural() and not MASS_NAMES.has(id)


## The name as it reads inside a sentence, rather than as a label on a card.
func name_in_prose() -> String:
	return display_name.to_lower()


## "a service carbine", "a set of night optics", "supplemental oxygen". Every
## sentence that names an item goes through here — writing "a %s" by hand is what
## produced "a Antimalarials & Field Antiseptics nobody is claiming".
func indefinite() -> String:
	var name_text := name_in_prose()
	if is_plural():
		var unit: String = str(PLURAL_NAMES[id])
		return "%s %s of %s" % [TextUtil.article(unit), unit, name_text]
	if not takes_article():
		return name_text
	return TextUtil.with_article(name_text)


func definite() -> String:
	return "the " + name_in_prose()


## Verb agreement, for the handful of sentences that put one straight after the
## name. "The night optics are unserviceable", "the carbine is".
func verb_is() -> String:
	return "are" if is_plural() else "is"


func verb_was() -> String:
	return "were" if is_plural() else "was"


## Subject form — "they are on the rack" / "it is on the rack".
func pronoun() -> String:
	return "they" if is_plural() else "it"


## Object form — "a decision on them" / "a decision on it". Kept separate because
## using the subject pronoun in an object slot produces "a decision on they".
func object_pronoun() -> String:
	return "them" if is_plural() else "it"


func slot_name() -> String:
	return Slot.keys()[slot].capitalize()


func source_name() -> String:
	return Source.keys()[source].capitalize()


func skill_delta(skill: int) -> int:
	return int(skill_modifiers.get(skill, 0))


func counters(hazard: int) -> bool:
	return counters_hazard != GameEnums.Hazard.NONE and counters_hazard == hazard


## "Combat +8 · Stealth -3 · Harm -6%" — the whole effect on one line.
func effect_text() -> String:
	var parts: PackedStringArray = []
	for skill in skill_modifiers:
		parts.append("%s %+d" % [GameEnums.skill_name(skill), int(skill_modifiers[skill])])
	if not is_zero_approx(score_modifier):
		parts.append("Score %+.0f" % score_modifier)
	if not is_zero_approx(danger_modifier):
		parts.append("Harm %+.0f%%" % danger_modifier)
	return "  ·  ".join(parts)
