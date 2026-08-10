class_name WorkshopJob
extends RefCounted

## Something on a bench, and the days it will be there.
##
## A bench is the scarce thing, not the money: the Armoury and Quartermaster run
## one each per level, and whatever is on one is not on a contract. That is what
## makes repairing before a deployment a decision rather than a maintenance
## routine — the rifle is either in the shop or in the field.

enum Kind { REPAIR, CRAFT }

var kind: int = Kind.REPAIR

## Which bench: FacilityLibrary.ARMOURY or QUARTERMASTER.
var facility_id: StringName = &""

## REPAIR: the copy being worked on. It stays in the inventory throughout — the
## company still owns it, it simply cannot be issued.
var instance: ItemInstance = null

## CRAFT: what is being built. The copy does not exist until the job lands.
var item_id: StringName = &""

var days_remaining: int = 0
var days_total: int = 0

## What was charged when the job was booked, kept for the line the workshop
## screen shows. Money is taken up front so a company cannot start five repairs
## it could never pay for.
var diamonds_paid: int = 0
var salvage_paid: int = 0

## Who the item came off, if anyone. It goes back to them when the job lands —
## the price of a repair is that they are without it for the duration, not that
## the player has to remember to reissue it afterwards.
var borrowed_from: StringName = &""


static func repair(
	p_instance: ItemInstance,
	p_facility: StringName,
	p_days: int,
	p_cost: int
) -> WorkshopJob:
	var job := WorkshopJob.new()
	job.kind = Kind.REPAIR
	job.instance = p_instance
	job.facility_id = p_facility
	job.days_remaining = p_days
	job.days_total = p_days
	job.diamonds_paid = p_cost
	return job


static func craft(
	p_item_id: StringName,
	p_facility: StringName,
	p_days: int,
	p_cost: int,
	p_salvage: int
) -> WorkshopJob:
	var job := WorkshopJob.new()
	job.kind = Kind.CRAFT
	job.item_id = p_item_id
	job.facility_id = p_facility
	job.days_remaining = p_days
	job.days_total = p_days
	job.diamonds_paid = p_cost
	job.salvage_paid = p_salvage
	return job


func target_item() -> ItemData:
	if kind == Kind.CRAFT:
		return ItemLibrary.get_item(item_id)
	return instance.data() if instance != null else null


func display_name() -> String:
	var item := target_item()
	return item.display_name if item != null else "Unknown item"


func label() -> String:
	return "%s %s" % ["Building" if kind == Kind.CRAFT else "Repairing", display_name()]


func to_dict() -> Dictionary:
	return {
		"kind": kind,
		"facility_id": String(facility_id),
		"instance_uid": String(instance.uid) if instance != null else "",
		"item_id": String(item_id),
		"days_remaining": days_remaining,
		"days_total": days_total,
		"diamonds_paid": diamonds_paid,
		"salvage_paid": salvage_paid,
		"borrowed_from": String(borrowed_from),
	}


## Re-linked against the loaded inventory rather than carrying its own copy of
## the item, for the reason IntelOp re-links its mission: a job holding a
## private duplicate would repair something no operator could ever be issued.
## Returns null if the copy it was working on is not in the save any more.
static func from_dict(data: Dictionary, inventory: Array) -> WorkshopJob:
	var job := WorkshopJob.new()
	job.kind = int(data.get("kind", Kind.REPAIR))
	job.facility_id = StringName(str(data.get("facility_id", "")))
	job.item_id = StringName(str(data.get("item_id", "")))
	job.days_remaining = int(data.get("days_remaining", 0))
	job.days_total = int(data.get("days_total", job.days_remaining))
	job.diamonds_paid = int(data.get("diamonds_paid", 0))
	job.salvage_paid = int(data.get("salvage_paid", 0))
	job.borrowed_from = StringName(str(data.get("borrowed_from", "")))

	if job.kind == Kind.REPAIR:
		var uid := StringName(str(data.get("instance_uid", "")))
		for entry: ItemInstance in inventory:
			if entry.uid == uid:
				job.instance = entry
				break
		if job.instance == null:
			return null
	elif ItemLibrary.get_item(job.item_id) == null:
		return null

	return job
