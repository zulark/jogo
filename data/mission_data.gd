class_name MissionData
extends Resource

## One contract on the board. The TYPE rules live in MissionProfile; this is the
## specific job: how hard, how dangerous, how long, how much it pays.

@export var id: StringName = &""
@export var title: String = ""
@export_multiline var briefing: String = ""

@export var mission_type: GameEnums.MissionType = GameEnums.MissionType.ASSAULT

## The score a squad must beat. Compared against the squad's total score, and
## the gap is what becomes the success percentage.
## Rough scale: 40 = milk run, 60 = standard, 75 = hard, 90 = suicide.
@export_range(0.0, 120.0, 1.0) var difficulty: float = 60.0

## How lethal it is if things go wrong, 0-100. Independent of difficulty:
## an easy job can still be deadly, and that is the interesting case.
@export_range(0.0, 100.0, 1.0) var risk: float = 40.0

## Turns the mission occupies. Operators are ON_MISSION for this many days.
@export var duration_days: int = 3

@export var reward_diamonds: int = 1000

## Days before the contract disappears from the board. Ticked in v0.2.
@export var expires_in_days: int = 7

## Region tag. Regions carry their own modifiers from v0.6; stored now so
## missions authored today do not need rewriting later.
@export var region_id: StringName = &""

## FactionLibrary id. Who commissioned this and what they will judge you on.
@export var client_id: StringName = &""

## Who the contract is actually about, on an assassination. Empty otherwise.
@export var target_name: String = ""
@export var target_title: String = ""

## Demanded by a client the company is on retainer to. Letting one expire costs
## a fine and a great deal of their goodwill.
@export var is_call_up: bool = false

## Scouting is an action, not a passive bonus — see Campaign.scout(). A contract
## only pays out the Intelligence Centre's help once it has actually been cased.
@export var scouted: bool = false
@export var scout_days_remaining: int = 0

## Score a squad sent here gets for the contract having been cased. Set when a
## scout or an intel team finishes, so how it was learned is already priced in
## by the time the resolver reads it.
@export var intel_bonus: float = 0.0


func region_name() -> String:
	return RegionLibrary.region_name(region_id)


func region() -> RegionData:
	return RegionLibrary.get_region(region_id)


func client() -> FactionData:
	return FactionLibrary.get_faction(client_id)


func client_name() -> String:
	return FactionLibrary.faction_name(client_id)


func is_being_scouted() -> bool:
	return scout_days_remaining > 0


## What this contract actually pays a company of the given standing. Every place
## that shows a fee must go through here — the board quoting one number and the
## briefing quoting another is worse than either being wrong.
func fee_for(reputation: int) -> int:
	var multiplier: float = 1.0 + Balance.REPUTATION_PAY_BONUS_MAX * (
		float(reputation) / 100.0)
	return int(round(float(reward_diamonds) * multiplier))


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"title": title,
		"briefing": briefing,
		"mission_type": int(mission_type),
		"difficulty": difficulty,
		"risk": risk,
		"duration_days": duration_days,
		"reward_diamonds": reward_diamonds,
		"expires_in_days": expires_in_days,
		"region_id": String(region_id),
		"client_id": String(client_id),
		"is_call_up": is_call_up,
		"target_name": target_name,
		"target_title": target_title,
		"scouted": scouted,
		"scout_days_remaining": scout_days_remaining,
		"intel_bonus": intel_bonus,
	}


static func from_dict(data: Dictionary) -> MissionData:
	var m := MissionData.new()
	m.id = StringName(data.get("id", ""))
	m.title = data.get("title", "")
	m.briefing = data.get("briefing", "")
	m.mission_type = int(data.get("mission_type", 0))
	m.difficulty = float(data.get("difficulty", 60.0))
	m.risk = float(data.get("risk", 40.0))
	m.duration_days = int(data.get("duration_days", 3))
	m.reward_diamonds = int(data.get("reward_diamonds", 0))
	m.expires_in_days = int(data.get("expires_in_days", 7))
	m.region_id = StringName(data.get("region_id", ""))
	m.client_id = StringName(data.get("client_id", ""))
	m.is_call_up = bool(data.get("is_call_up", false))
	m.target_name = data.get("target_name", "")
	m.target_title = data.get("target_title", "")
	m.scouted = bool(data.get("scouted", false))
	m.scout_days_remaining = int(data.get("scout_days_remaining", 0))
	m.intel_bonus = float(data.get("intel_bonus", 0.0))
	return m


func type_name() -> String:
	return GameEnums.mission_type_name(mission_type)
