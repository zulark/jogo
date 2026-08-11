class_name ItemInstance
extends RefCounted

## One specific copy of an item — *this* rifle, not "a rifle".
##
## The inventory used to be an array of ids. It could say the company owned two
## carbines; it could never say that one of them was worn out. Condition needs a
## per-copy home, and so does everything the post-v1.0 direction wants on top of
## it: a maker, a chain of owners, a confirmed kill count.
##
## **Benefits scale with condition, drawbacks do not.** A worn plate carrier
## still costs the stealth it always cost, still weighs what it always weighed,
## and stops less than it used to. That asymmetry is what makes wear something
## the player acts on rather than a number they watch: kit that has been let go
## is not merely weaker, it is eventually worse than carrying nothing.

## Unique across the save. Operators reference their kit by this, so two people
## can never end up holding the same rifle.
var uid: StringName = &""

## Which ItemData this is a copy of.
var item_id: StringName = &""

## 0-100. Falls on contracts, restored by the workshop.
var condition: float = Balance.CONDITION_NEW

## The ceiling condition can be restored to. Every repair takes a little off it
## permanently — a rebuilt rifle is never a new one — which is what stops repair
## being an infinite loop and gives crafting something to be for.
var max_condition: float = Balance.CONDITION_NEW

## How many contracts this specific copy has been carried on. The first line of
## the history the post-v1.0 direction wants, and cheap to keep now.
var contracts: int = 0

static var _counter: int = 0


static func create(
	p_item_id: StringName,
	p_condition: float = Balance.CONDITION_NEW,
	p_max_condition: float = Balance.CONDITION_NEW
) -> ItemInstance:
	var instance := ItemInstance.new()
	_counter += 1
	instance.uid = StringName("%s#%d" % [p_item_id, _counter])
	instance.item_id = p_item_id
	instance.max_condition = clampf(p_max_condition, 0.0, Balance.CONDITION_NEW)
	instance.condition = clampf(p_condition, 0.0, instance.max_condition)
	return instance


func data() -> ItemData:
	return ItemLibrary.get_item(item_id)


func display_name() -> String:
	var item := data()
	return item.display_name if item != null else "Unknown item"


## The three prose forms, delegated so a sentence never has to know whether it is
## holding a type or a copy. See ItemData for why the article is not guessed.
func name_in_prose() -> String:
	var item := data()
	return item.name_in_prose() if item != null else "unknown item"


func indefinite() -> String:
	var item := data()
	return item.indefinite() if item != null else "an unknown item"


func definite() -> String:
	var item := data()
	return item.definite() if item != null else "the unknown item"


func verb_is() -> String:
	var item := data()
	return item.verb_is() if item != null else "is"


func verb_was() -> String:
	var item := data()
	return item.verb_was() if item != null else "was"


func pronoun() -> String:
	var item := data()
	return item.pronoun() if item != null else "it"


func object_pronoun() -> String:
	var item := data()
	return item.object_pronoun() if item != null else "it"


func slot() -> int:
	var item := data()
	return item.slot if item != null else ItemData.Slot.WEAPON


func price() -> int:
	var item := data()
	return item.price if item != null else 0


# --- Condition ---------------------------------------------------------------

## Below this an item is on the rack, not in service: it gives none of what it
## was bought for and cannot be issued to anyone until the workshop has had it.
func is_serviceable() -> bool:
	return condition > Balance.CONDITION_UNSERVICEABLE


## How much of the item's *upside* survives. Zero once unserviceable, which is
## the point of the threshold: the drawbacks below carry on regardless.
func effectiveness() -> float:
	if not is_serviceable():
		return 0.0
	return clampf(condition / Balance.CONDITION_NEW, 0.0, 1.0)


## Past this, a repair buys back so little that replacing it is the real answer.
## The workshop refuses it and the scrap heap is what is left.
func is_beyond_repair() -> bool:
	return max_condition <= Balance.CONDITION_BEYOND_REPAIR


func wear(amount: float) -> void:
	condition = clampf(condition - amount, 0.0, max_condition)


## What a repair costs this copy in ceiling, permanently. Priced on the damage
## put right rather than per visit, so topping something up early is never worse
## value than letting it fall apart first.
func ceiling_cost_of_repair() -> float:
	var missing: float = maxf(0.0, max_condition - condition)
	return Balance.REPAIR_CEILING_LOSS * (missing / Balance.CONDITION_NEW)


## Off the bench: back to this copy's ceiling, and the ceiling itself a little
## lower than it was. A rebuilt rifle is never a new one.
func repair() -> void:
	max_condition = maxf(0.0, max_condition - ceiling_cost_of_repair())
	condition = max_condition


func condition_word() -> String:
	if not is_serviceable():
		return "Unserviceable"
	if condition >= 92.0:
		return "New"
	if condition >= 70.0:
		return "Serviceable"
	if condition >= 45.0:
		return "Worn"
	return "Poor"


## "Worn · 58%", or "Unserviceable" where the number would only distract.
func condition_text() -> String:
	if not is_serviceable():
		return "Unserviceable · %d%%" % int(round(condition))
	return "%s · %d%%" % [condition_word(), int(round(condition))]


# --- What the resolver reads -------------------------------------------------
#
# Every one of these is the ItemData value put through the condition rule, so
# nothing outside this class has to remember which way the asymmetry runs.

func skill_delta(skill: int) -> int:
	var item := data()
	if item == null:
		return 0
	var raw: int = item.skill_delta(skill)
	if raw <= 0:
		return raw
	return int(round(float(raw) * effectiveness()))


func score_modifier() -> float:
	var item := data()
	if item == null:
		return 0.0
	if item.score_modifier <= 0.0:
		return item.score_modifier
	return item.score_modifier * effectiveness()


## Negative is protective, so that is the half that decays. A stimulant that
## always got people hurt goes on getting them hurt.
func danger_modifier() -> float:
	var item := data()
	if item == null:
		return 0.0
	if item.danger_modifier >= 0.0:
		return item.danger_modifier
	return item.danger_modifier * effectiveness()


## Counter-kit is pass/fail rather than proportional: a torn cold weather bag
## either keeps somebody alive through the night or it does not.
func counters(hazard: int) -> bool:
	var item := data()
	return item != null and item.counters(hazard) and is_serviceable()


## The same one-line summary ItemData gives, with the condition already applied,
## so what the squad builder shows is what the resolver will use.
func effect_text() -> String:
	var item := data()
	if item == null:
		return ""
	var parts: PackedStringArray = []
	for skill in item.skill_modifiers:
		var value: int = skill_delta(skill)
		if value != 0:
			parts.append("%s %+d" % [GameEnums.skill_name(skill), value])
	var score: float = score_modifier()
	if not is_zero_approx(score):
		parts.append("Score %+.0f" % score)
	var danger: float = danger_modifier()
	if not is_zero_approx(danger):
		parts.append("Harm %+.0f%%" % danger)
	if parts.is_empty():
		return "No effect in this condition"
	return "  ·  ".join(parts)


# --- Serialisation -----------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"uid": String(uid),
		"item_id": String(item_id),
		"condition": condition,
		"max_condition": max_condition,
		"contracts": contracts,
	}


static func from_dict(data_dict: Dictionary) -> ItemInstance:
	var instance := ItemInstance.new()
	instance.uid = StringName(str(data_dict.get("uid", "")))
	instance.item_id = StringName(str(data_dict.get("item_id", "")))
	instance.max_condition = float(data_dict.get("max_condition", Balance.CONDITION_NEW))
	instance.condition = float(data_dict.get("condition", instance.max_condition))
	instance.contracts = int(data_dict.get("contracts", 0))

	# Keep the generator ahead of everything the save already used, or a copy
	# bought after loading would collide with one that came out of the file.
	var parts := String(instance.uid).split("#")
	if parts.size() == 2 and parts[1].is_valid_int():
		_counter = maxi(_counter, int(parts[1]))
	return instance


## A save written before kit had condition stored plain item ids. Those copies
## come back as new, which is the generous reading and the only one that does
## not silently damage a company's kit on upgrade.
static func from_legacy(item_id: StringName) -> ItemInstance:
	return create(item_id)
