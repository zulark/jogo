class_name ItemHistory
extends RefCounted

## What a specific piece of kit has been through, and how it reads.
##
## The post-v1.0 direction: an item is not a stat block. It came from somewhere,
## it has been in somebody's hands, it has killed people, and it outlives the
## operator who earned its reputation. `ItemInstance` holds the record and
## **this is the only class allowed to write it** — the rule `Bonds` has over
## `op.bonds`, for the same reason.
##
## Nothing here invents an event. Every entry is written at the moment the
## simulation produces the thing it describes, from the contract, the day and
## the operator that were actually involved.

# --- Origins -----------------------------------------------------------------

const ORIGIN_BOUGHT := &"bought"
const ORIGIN_FOUND := &"found"
const ORIGIN_BUILT := &"built"
const ORIGIN_UNCLAIMED := &"unclaimed"

# --- What else happens to a piece of kit -------------------------------------

const ISSUED := &"issued"
const BLOODED := &"blooded"
const LOST := &"lost"
const BROKEN := &"broken"
const REBUILT := &"rebuilt"
const NAMED := &"named"

## Never trimmed away, however long the copy lives.
const PERMANENT: Array[StringName] = [
	ORIGIN_BOUGHT, ORIGIN_FOUND, ORIGIN_BUILT, ORIGIN_UNCLAIMED, LOST, NAMED,
]

## An item earns a name the day somebody dies carrying it, and never any other
## way. Deaths are rare, so names are rare, and a named rifle on the rack means
## exactly one thing.
##
## GRAMMAR (see .docs/prose_style_guide.md §6): every entry is a SENTENCE in the
## past tense. Placeholders are named and substituted with String.format().
## `{item}` and `{they}` always refer to the item, `{who}` to a person.
##
## The item is written as its TYPE here — "the battle rifle" — never as its
## earned name, because the record is chronological and the name arrives partway
## down it. "Ivory's battle rifle was bought new on day 3" is a small lie about a
## company that had never heard of Ivory then.
const LINES := {
	ORIGIN_BOUGHT: "{item} {was} bought new from {what} on day {day}.",
	ORIGIN_FOUND: "{item} came back off {what}, in {where}, already worn.",
	ORIGIN_BUILT: "{item} {was} built at the company's own bench on day {day}.",
	ORIGIN_UNCLAIMED: "{item} turned up in stores after a contract, and nobody claimed {them}.",
	ISSUED: "{item} {was} issued to {who} on day {day}.",
	BLOODED: "{who} killed with {them} for the first time on {what}.",
	LOST: "{who} was killed on {what}, and {item_mid} {was} signed back in the same evening.",
	BROKEN: "{item} came back off {what} unserviceable.",
	REBUILT: "{item} came off the bench rebuilt, and will not go past {value}% again.",
	NAMED: "{they_cap} {have} been {what} to everyone here ever since.",
}

## Totals rather than moments, so they close the record instead of sitting in it.
const SUMMARY := {
	"contracts": "{they_cap} {have} been out on {what}.",
	"kills": "{they_cap} {have} accounted for {what}.",
	"hands": "{they_cap} {have} passed through {what}.",
}

const SOURCE_NAMES := {
	ItemData.Source.ARMOURY: "the Armoury",
	ItemData.Source.QUARTERMASTER: "the Quartermaster",
	ItemData.Source.BLACKMARKET: "a dealer nobody writes down",
}


# --- Writing -----------------------------------------------------------------

static func note(
	instance: ItemInstance,
	kind: StringName,
	day: int,
	who: String = "",
	what: String = "",
	where: String = "",
	value: int = 0
) -> void:
	if instance == null:
		return

	instance.history.append({
		"kind": String(kind),
		"day": day,
		"who": who,
		"what": what,
		"where": where,
		"value": value,
	})

	while instance.history.size() > ItemInstance.HISTORY_CAP:
		var dropped := -1
		for index in instance.history.size():
			if not PERMANENT.has(StringName(str(instance.history[index]["kind"]))):
				dropped = index
				break
		if dropped < 0:
			break
		instance.history.remove_at(dropped)


static func record_origin(
	instance: ItemInstance,
	origin: StringName,
	day: int,
	what: String = "",
	where: String = ""
) -> void:
	if instance == null or instance.origin != &"":
		return
	instance.origin = origin
	note(instance, origin, day, "", what, where)


## Bought off a shelf, so the shelf is what the record names. Blueprint kit is
## never on a shelf, and "bought new from the company's own bench" is a sentence
## that contradicts itself — so a craftable copy records the build instead.
static func record_purchase(instance: ItemInstance, day: int) -> void:
	if instance == null:
		return
	var item := instance.data()
	if item != null and item.is_craftable():
		record_build(instance, day)
		return
	var source: String = str(SOURCE_NAMES.get(
		item.source if item != null else ItemData.Source.ARMOURY, "the Armoury"))
	record_origin(instance, ORIGIN_BOUGHT, day, source)


static func record_found(instance: ItemInstance, day: int, mission: MissionData) -> void:
	if mission == null:
		record_origin(instance, ORIGIN_UNCLAIMED, day)
		return
	record_origin(instance, ORIGIN_FOUND, day, mission.title, mission.region_place())


static func record_build(instance: ItemInstance, day: int) -> void:
	record_origin(instance, ORIGIN_BUILT, day)


## Only when the holder actually changes. Kit going onto a bench and coming back
## to the same person is not a change of hands, and logging it as one would fill
## a rifle's record with the fact that it was cleaned.
static func record_issue(instance: ItemInstance, op: OperatorData, day: int) -> void:
	if instance == null or op == null:
		return
	if last_holder(instance) == op.display_label():
		return
	note(instance, ISSUED, day, op.display_label())


static func record_kills(
	instance: ItemInstance,
	op: OperatorData,
	count: int,
	day: int,
	mission: MissionData
) -> void:
	if instance == null or op == null or count <= 0:
		return
	# Gear does not kill anybody. Campaign only ever passes the weapon slot, and
	# this is what keeps "killed with the supplemental oxygen" out of the record.
	if instance.slot() != ItemData.Slot.WEAPON:
		return
	var first: bool = instance.kills == 0
	instance.kills += count
	if first:
		note(instance, BLOODED, day, op.display_label(),
			mission.title if mission != null else "an unrecorded contract")


## The holder was killed and the kit came home without them. Returns the line the
## debrief should print if this is where the copy got its name, or "".
static func record_loss(
	instance: ItemInstance,
	op: OperatorData,
	day: int,
	mission: MissionData
) -> String:
	if instance == null or op == null:
		return ""

	var title: String = mission.title if mission != null else "an unrecorded contract"
	note(instance, LOST, day, op.display_label(), title)

	if not instance.earned_name.is_empty() or not can_be_named(instance):
		return ""

	instance.earned_name = name_after(op)
	note(instance, NAMED, day, op.display_label(), instance.earned_name)
	return render(LINES[NAMED], instance, {"what": instance.earned_name})


static func record_broken(instance: ItemInstance, day: int, mission: MissionData) -> void:
	note(instance, BROKEN, day, "",
		mission.title if mission != null else "an unrecorded contract")


static func record_rebuild(instance: ItemInstance, day: int) -> void:
	if instance == null:
		return
	note(instance, REBUILT, day, "", "", "", int(round(instance.max_condition)))


## Counter-kit is stores, not somebody's kit. Antimalarials and oxygen bottles
## are drawn by the case for the country the contract is in, so "Lark's
## Supplemental Oxygen" on the rack is a joke where the rifle beside it is not.
static func can_be_named(instance: ItemInstance) -> bool:
	var item := instance.data() if instance != null else null
	return item != null and item.counters_hazard == GameEnums.Hazard.NONE


## The callsign is what the company would actually use. A name with no callsign
## behind it falls back to the whole name rather than guessing which half of it
## is the family one — Korean and Japanese pools render family-first.
static func name_after(op: OperatorData) -> String:
	if op == null:
		return ""
	return TextUtil.possessive(op.callsign if not op.callsign.is_empty() else op.operator_name)


# --- Reading -----------------------------------------------------------------

## The item as the RECORD refers to it: by type, never by earned name. See LINES.
static func render(template: String, instance: ItemInstance, fields: Dictionary) -> String:
	var item := instance.data()
	var definite: String = item.definite() if item != null else "the item"

	var values := {
		"item": TextUtil.sentence_case(definite),
		"item_mid": definite,
		"was": instance.verb_was(),
		"is": instance.verb_is(),
		"them": instance.object_pronoun(),
		"they": instance.pronoun(),
		"they_cap": TextUtil.sentence_case(instance.pronoun()),
		"have": "have" if instance.pronoun() == "they" else "has",
		"day": 0,
		"who": "",
		"what": "",
		"where": "",
		"value": 0,
	}
	values.merge(fields, true)
	return template.format(values)


## The whole service record, oldest first, as sentences.
static func lines(instance: ItemInstance) -> Array[String]:
	var written: Array[String] = []
	if instance == null:
		return written

	for entry in instance.history:
		var kind := StringName(str(entry.get("kind", "")))
		if not LINES.has(kind):
			continue
		written.append(render(LINES[kind], instance, {
			"day": int(entry.get("day", 0)),
			"who": str(entry.get("who", "")),
			"what": str(entry.get("what", "")),
			"where": str(entry.get("where", "")),
			"value": int(entry.get("value", 0)),
		}))

	if instance.contracts > 0:
		written.append(render(SUMMARY["contracts"], instance, {
			"what": TextUtil.spelled(instance.contracts, "contract")}))
	if instance.kills > 0:
		written.append(render(SUMMARY["kills"], instance, {
			"what": TextUtil.spelled(instance.kills, "man", "men")}))

	var hands: int = holders(instance).size()
	if hands > 1:
		written.append(render(SUMMARY["hands"], instance, {
			"what": TextUtil.spelled(hands, "pair of hands", "pairs of hands")}))

	return written


## Everyone who has been issued this copy, in order, without repeats.
static func holders(instance: ItemInstance) -> Array[String]:
	var found: Array[String] = []
	if instance == null:
		return found
	for entry in instance.history:
		if str(entry.get("kind", "")) != String(ISSUED):
			continue
		var who := str(entry.get("who", ""))
		if not who.is_empty() and not found.has(who):
			found.append(who)
	return found


static func last_holder(instance: ItemInstance) -> String:
	var found := holders(instance)
	return found[found.size() - 1] if not found.is_empty() else ""


## Kit this operator was killed carrying that the company still holds and still
## calls theirs. Matched on both the name and the record, so a copy that has
## outlived two people is only ever attributed to the one it is named after.
static func kit_outliving(op: OperatorData, inventory: Array) -> Array[ItemInstance]:
	var kept: Array[ItemInstance] = []
	if op == null:
		return kept
	var name := name_after(op)
	for instance: ItemInstance in inventory:
		if instance.earned_name != name:
			continue
		for entry in instance.history:
			if str(entry.get("kind", "")) == String(LOST) \
					and str(entry.get("who", "")) == op.display_label():
				kept.append(instance)
				break
	return kept


## What the wall says about the kit. This is the whole point of naming: a rifle
## that outlives the person who earned its reputation, said where they are.
static func memorial_line(op: OperatorData, inventory: Array) -> String:
	var kept := kit_outliving(op, inventory)
	if kept.is_empty():
		return ""

	if kept.size() == 1:
		var one: ItemInstance = kept[0]
		var line := "%s %s still in service" % [
			TextUtil.sentence_case(one.definite()), one.verb_is()]
		if one.kills > 0:
			line += ", with %s confirmed" % TextUtil.number(one.kills)
		return line + "."

	# All named after the same person, so the possessive is said once.
	var names: Array = []
	for instance in kept:
		names.append(instance.name_in_prose())
	return "%s %s are still in service." % [
		TextUtil.sentence_case(kept[0].earned_name), TextUtil.join_names(names)]


## The one line a list row can afford: what makes this copy different from an
## identical one on the same rack. Empty when nothing does.
static func headline(instance: ItemInstance) -> String:
	if instance == null:
		return ""
	var parts: PackedStringArray = []
	if instance.kills > 0:
		parts.append("%d confirmed" % instance.kills)
	var hands: int = holders(instance).size()
	if hands > 1:
		parts.append("%d hands" % hands)
	return "  ·  ".join(parts)
