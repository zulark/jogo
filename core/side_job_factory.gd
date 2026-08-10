class_name SideJobFactory
extends RefCounted

## Generates standing work. Deliberately unglamorous: guarding a warehouse,
## driving a convoy, teaching a client's own people to shoot straight.

const JOBS := [
	{
		"title": "Warehouse watch",
		"skill": GameEnums.Skill.COMBAT,
		"description": "Sit on a bonded warehouse for a week. Nothing will happen. Something might.",
	},
	{
		"title": "Convoy escort, domestic",
		"skill": GameEnums.Skill.ENDURANCE,
		"description": "Ride the length of a haulage route and back. Long days, paved roads.",
	},
	{
		"title": "Range instruction",
		"skill": GameEnums.Skill.COMBAT,
		"description": "Teach a client's security staff which end of the rifle matters.",
	},
	{
		"title": "Site survey",
		"skill": GameEnums.Skill.TECH,
		"description": "Walk a compound and write down every way into it.",
	},
	{
		"title": "Clinic cover",
		"skill": GameEnums.Skill.MEDICAL,
		"description": "Stand in at a company clinic while their own staff are away.",
	},
	{
		"title": "Close protection, low profile",
		"skill": GameEnums.Skill.STEALTH,
		"description": "Walk two paces behind somebody unimportant for a fortnight.",
	},
	{
		"title": "Liaison duty",
		"skill": GameEnums.Skill.LEADERSHIP,
		"description": "Sit in meetings on the company's behalf and be reassuring.",
	},
]


static func create(rng: RandomNumberGenerator, taken_titles: Array = []) -> SideJobData:
	var free: Array = []
	for entry in JOBS:
		if not taken_titles.has(entry["title"]):
			free.append(entry)
	if free.is_empty():
		free = JOBS

	var chosen: Dictionary = free[rng.randi() % free.size()]

	var job := SideJobData.new()
	job.id = StringName("sj_%d" % (rng.randi() % 1000000))
	job.title = chosen["title"]
	job.description = chosen["description"]
	job.key_skill = chosen["skill"]
	job.expectation = rng.randf_range(30.0, 62.0)
	job.duration_days = rng.randi_range(4, 9)

	# Pay tracks the time it eats and what it expects, but the ceiling is low on
	# purpose: this should never compete with a real contract, only fill a gap.
	job.base_pay = int(round(
		float(job.duration_days) * Balance.SIDE_JOB_PAY_PER_DAY
		* (0.7 + job.expectation / 100.0)
	))
	job.expires_in_days = rng.randi_range(6, 12)
	return job


static func create_board(
	rng: RandomNumberGenerator,
	count: int,
	taken_titles: Array = []
) -> Array[SideJobData]:
	var taken: Array = taken_titles.duplicate()
	var board: Array[SideJobData] = []
	for i in count:
		var job := create(rng, taken)
		taken.append(job.title)
		board.append(job)
	return board
