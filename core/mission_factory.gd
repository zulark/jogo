class_name MissionFactory
extends RefCounted

## Generates contracts for the mission board. Difficulty and risk are rolled
## semi-independently on purpose: an easy job that can still kill you is a more
## interesting decision than one where both dials always move together.

enum Grade { ROUTINE, STANDARD, HARD, DESPERATE }

const GRADE_DIFFICULTY := {
	Grade.ROUTINE: Vector2(38.0, 48.0),
	Grade.STANDARD: Vector2(52.0, 66.0),
	Grade.HARD: Vector2(68.0, 82.0),
	Grade.DESPERATE: Vector2(84.0, 98.0),
}

## Fees have to clear the weekly bill from Economy with enough left over to
## build the base, or the whole facility layer is decoration the player can
## never reach. Tuned against sim_campaign: a competent company running two
## contracts a week should afford a facility level every few weeks.
const GRADE_REWARD := {
	Grade.ROUTINE: Vector2i(1150, 2050),
	Grade.STANDARD: Vector2i(2650, 4450),
	Grade.HARD: Vector2i(5500, 8900),
	Grade.DESPERATE: Vector2i(11000, 17400),
}

const TITLES := {
	GameEnums.MissionType.ASSAULT: [
		"Clear the Depot", "Break the Roadblock", "Retake Station 9",
		"Storm the Compound", "Burn the Motor Pool", "Answer in Kind",
	],
	GameEnums.MissionType.INFILTRATION: [
		"Quiet Entry", "The Ledger", "Nobody Was There",
		"Through the Service Door", "Borrowed Uniforms", "No Alarms",
	],
	GameEnums.MissionType.RESCUE: [
		"Bring Them Home", "The Stranded Crew", "Hostage at Kerr Mill",
		"Nobody Left Behind", "The Missing Surveyor", "Pull Them Out",
	],
	GameEnums.MissionType.RECON: [
		"Eyes on the Valley", "Count the Trucks", "Mark the Perimeter",
		"Watch the Crossing", "Photograph Everything", "Two Nights Out",
	],
	GameEnums.MissionType.SABOTAGE: [
		"Cut the Power", "Salt the Wells", "The Relay Must Fall",
		"Drop the Bridge", "Silence the Tower", "Nothing Left Working",
	],
	GameEnums.MissionType.ESCORT: [
		"Convoy to Anvil", "The Long Road", "Carry the Package",
		"Get the Doctor Through", "Six Trucks, One Road", "Deliver or Die",
	],
	GameEnums.MissionType.ASSASSINATION: [
		"One Name on the List", "Close the Account", "The Quiet Removal",
		"He Will Be at the Villa", "Last Appointment", "No Second Attempt",
	],
}

## Who the contract is actually about. A named person with a title makes the
## trophy on the killer's record mean something years later.
const TARGET_TITLES := [
	"cartel accountant", "militia colonel", "arms broker",
	"provincial minister", "mine security chief", "signals officer",
	"faction quartermaster", "regional warlord",
]


static func create(
	rng: RandomNumberGenerator,
	mission_type: int = -1,
	grade: int = -1,
	taken_titles: Array = []
) -> MissionData:
	if mission_type < 0:
		mission_type = rng.randi() % GameEnums.MissionType.size()
	if grade < 0:
		grade = _roll_grade(rng)

	var m := MissionData.new()
	m.mission_type = mission_type
	m.id = StringName("m_%d" % (rng.randi() % 1000000))

	# Two contracts called "Mark the Perimeter" sitting next to each other on the
	# board read as a bug, so prefer a title nothing else is using.
	var pool: Array = TITLES.get(mission_type, ["Contract"])
	var free: Array = []
	for title in pool:
		if not taken_titles.has(title):
			free.append(title)
	if free.is_empty():
		free = pool
	m.title = free[rng.randi() % free.size()]

	var band: Vector2 = GRADE_DIFFICULTY[grade]
	m.difficulty = rng.randf_range(band.x, band.y)

	# Risk correlates with difficulty but drifts, so the board offers both
	# "hard but survivable" and "easy but lethal" contracts.
	m.risk = clampf(m.difficulty + rng.randf_range(-22.0, 18.0), 10.0, 95.0)

	var reward: Vector2i = GRADE_REWARD[grade]
	m.reward_diamonds = rng.randi_range(reward.x, reward.y)

	m.region_id = RegionLibrary.random_region(rng)
	m.duration_days = _duration_for(mission_type, rng)

	# Where the work is changes what the work is. Travel is added to the
	# duration, so a distant contract ties the squad up beyond the job itself.
	var region := m.region()
	if region != null:
		m.difficulty = clampf(m.difficulty + region.difficulty_shift, 20.0, 110.0)
		m.risk = clampf(m.risk + region.risk_shift, 10.0, 95.0)
		m.duration_days += region.travel_days

	m.expires_in_days = rng.randi_range(5, 12)

	if mission_type == GameEnums.MissionType.ASSASSINATION:
		var nation := NationLibrary.random_nation(rng)
		m.target_name = NameLibrary.full_name(rng, nation.culture)
		m.target_title = TARGET_TITLES[rng.randi() % TARGET_TITLES.size()]

	m.briefing = _write_briefing(m, rng)
	return m


## A couple of lines of what the job actually is. Composed from the pieces the
## contract already has — type, place, danger — so it never contradicts the
## numbers beside it, and every contract reads as a job rather than a row.
static func _write_briefing(m: MissionData, rng: RandomNumberGenerator) -> String:
	var region := m.region()
	var place: String = region.display_name if region != null else "the region"
	var ground: String = region.description if region != null else ""

	var opening: Array = BRIEFING_OPENINGS.get(m.mission_type, ["Work in %s."])
	var line: String = opening[rng.randi() % opening.size()] % place
	if not m.target_name.is_empty():
		line += " The target is %s, %s." % [m.target_name, m.target_title]

	# The second sentence is the honest warning, keyed to how lethal it is.
	var caution := "Resistance is expected to be light."
	if m.risk >= 75.0:
		caution = "Assume everyone there is armed and expecting you."
	elif m.risk >= 50.0:
		caution = "Expect organised opposition."

	return "%s %s %s" % [line, ground, caution]


const BRIEFING_OPENINGS := {
	GameEnums.MissionType.ASSAULT: [
		"The client wants a position in %s taken and held long enough to matter.",
		"Something in %s needs to stop operating today.",
	],
	GameEnums.MissionType.INFILTRATION: [
		"Get inside a facility in %s, take what the client asked for, and leave no record.",
		"A building in %s needs entering quietly and leaving quietly.",
	],
	GameEnums.MissionType.RESCUE: [
		"People are being held in %s. The client wants them back breathing.",
		"A crew went missing in %s. Bring out whoever is still alive.",
	],
	GameEnums.MissionType.RECON: [
		"The client wants eyes on %s and no contact whatsoever.",
		"Sit on a position in %s, count what moves, come home.",
	],
	GameEnums.MissionType.SABOTAGE: [
		"Infrastructure in %s needs to stop working, ideally without a signature.",
		"Something in %s is worth more broken than intact.",
	],
	GameEnums.MissionType.ESCORT: [
		"A convoy is crossing %s and the client will not say what is in it.",
		"Somebody needs moving through %s in one piece.",
	],
	GameEnums.MissionType.ASSASSINATION: [
		"One person in %s is to stop being a problem. The client was specific.",
		"A name, a face, and an address in %s. Nothing else is required.",
	],
}


## Board generation, where the client is decided. Standing skews who is hiring,
## so working for someone makes them offer more.
static func create_for_board(
	rng: RandomNumberGenerator,
	standing: Dictionary,
	taken_titles: Array = []
) -> MissionData:
	var m := create(rng, -1, -1, taken_titles)
	m.client_id = FactionLibrary.random_client(rng, standing)

	var client := m.client()
	if client != null:
		m.reward_diamonds = int(round(float(m.reward_diamonds) * client.pay_multiplier))
	return m


## Grades are weighted, not uniform. Routine work is what a mercenary company
## mostly does; a board where every job is a suicide mission gives the player no
## way to rebuild after a bad week, and region shifts push everything upward
## anyway.
const GRADE_WEIGHTS := {
	Grade.ROUTINE: 34,
	Grade.STANDARD: 36,
	Grade.HARD: 22,
	Grade.DESPERATE: 8,
}


static func _roll_grade(rng: RandomNumberGenerator) -> int:
	var total := 0
	for grade in GRADE_WEIGHTS:
		total += int(GRADE_WEIGHTS[grade])

	var roll: int = rng.randi() % total
	for grade in GRADE_WEIGHTS:
		roll -= int(GRADE_WEIGHTS[grade])
		if roll < 0:
			return grade
	return Grade.STANDARD


static func _duration_for(mission_type: int, rng: RandomNumberGenerator) -> int:
	match mission_type:
		GameEnums.MissionType.RECON:
			return rng.randi_range(1, 3)
		GameEnums.MissionType.INFILTRATION, GameEnums.MissionType.SABOTAGE:
			return rng.randi_range(2, 4)
		GameEnums.MissionType.ESCORT:
			return rng.randi_range(4, 7)
		_:
			return rng.randi_range(2, 5)


## A board of contracts spread across types and grades.
static func create_board(rng: RandomNumberGenerator, count: int) -> Array[MissionData]:
	var board: Array[MissionData] = []
	for i in count:
		board.append(create(rng, i % GameEnums.MissionType.size()))
	return board
