class_name SideJobData
extends Resource

## Standing work: the small, dull, safe jobs a mercenary company actually lives
## on between contracts.
##
## One operator, no squad, no briefing screen. It resolves itself when the days
## run out, and what it pays depends on how suited the person you sent was. The
## point from the design doc is utility for the bench — an operator recovering
## their nerve or too junior for a real contract is still worth their wages if
## there is a warehouse to guard.

@export var id: StringName = &""
@export var title: String = ""
@export_multiline var description: String = ""

## The skill the work leans on. Sending the right person pays better.
@export var key_skill: GameEnums.Skill = GameEnums.Skill.COMBAT

## Competence the job expects, on the same 0-100 scale as skills.
@export_range(0.0, 100.0) var expectation: float = 45.0

@export var duration_days: int = 3
@export var base_pay: int = 400
@export var expires_in_days: int = 8


## 0-100, how well suited this operator is. Blends the key skill with rank, so
## a veteran is worth sending even slightly outside their speciality.
func suitability(op: OperatorData) -> float:
	var skill := float(op.get_skill(key_skill))
	var rank_credit := float(op.rank_step()) * 4.0
	return clampf(skill + rank_credit, 0.0, 100.0)


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"title": title,
		"description": description,
		"key_skill": int(key_skill),
		"expectation": expectation,
		"duration_days": duration_days,
		"base_pay": base_pay,
		"expires_in_days": expires_in_days,
	}


static func from_dict(data: Dictionary) -> SideJobData:
	var job := SideJobData.new()
	job.id = StringName(data.get("id", ""))
	job.title = data.get("title", "")
	job.description = data.get("description", "")
	job.key_skill = int(data.get("key_skill", 0))
	job.expectation = float(data.get("expectation", 45.0))
	job.duration_days = int(data.get("duration_days", 3))
	job.base_pay = int(data.get("base_pay", 400))
	job.expires_in_days = int(data.get("expires_in_days", 8))
	return job
