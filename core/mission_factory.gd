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

## The name of the JOB, as it would be written on a folder.
##
## GRAMMAR (see .docs/prose_style_guide.md): Title Case, no closing stop, no "%"
## anywhere — a title is never format-substituted but it IS pasted into sentences
## that are. Never a gendered pronoun: the title is drawn independently of the
## target, so "He Will Be at the Villa" spent a while sitting above "The target
## is Clara Ashcroft".
const TITLES := {
	GameEnums.MissionType.ASSAULT: [
		"Clear the Depot", "Break the Roadblock", "Retake Station 9",
		"Storm the Compound", "Burn the Motor Pool", "Answer in Kind",
		"Take the Pumping Station", "Off the Ridge by Dawn", "Nothing Held Back",
		"The Yard at Vulkan", "Close the Gate",
	],
	GameEnums.MissionType.INFILTRATION: [
		"Quiet Entry", "The Ledger", "Nobody Was There",
		"Through the Service Door", "Borrowed Uniforms", "No Alarms",
		"The Night Shift", "Two Floors Down", "Signed In as Someone Else",
		"The Grey Cabinet", "Out Before Six",
	],
	GameEnums.MissionType.RESCUE: [
		"Bring Them Home", "The Stranded Crew", "Hostage at Kerr Mill",
		"Nobody Left Behind", "The Missing Surveyor", "Pull Them Out",
		"Eleven Days Overdue", "The Doctor and the Driver", "Whoever Is Left",
		"Ransom Refused", "Carry Them If You Have To",
	],
	GameEnums.MissionType.RECON: [
		"Eyes on the Valley", "Count the Trucks", "Mark the Perimeter",
		"Watch the Crossing", "Photograph Everything", "Two Nights Out",
		"Nothing but Looking", "The Shape of the Place", "Numbers, Not Names",
		"Lie Still and Count", "Before Anyone Commits",
	],
	GameEnums.MissionType.SABOTAGE: [
		"Cut the Power", "Salt the Wells", "The Relay Must Fall",
		"Drop the Bridge", "Silence the Tower", "Nothing Left Working",
		"An Accident, Ideally", "The Pumps Stop Tonight", "Fouled Beyond Repair",
		"Cold Iron", "Let It Look Like Neglect",
	],
	GameEnums.MissionType.ESCORT: [
		"Convoy to Anvil", "The Long Road", "Carry the Package",
		"Get the Doctor Through", "Six Trucks, One Road", "Deliver or Die",
		"Nothing Stops Until It Arrives", "The Slow Way Round", "Two Days of Dust",
		"Everything on One Axle", "Sit on the Cargo",
	],
	GameEnums.MissionType.ASSASSINATION: [
		"One Name on the List", "Close the Account", "The Quiet Removal",
		"At the Villa by Eight", "Last Appointment", "No Second Attempt",
		"The Standing Order", "Before the Flight", "One Window Only",
		"Settled in Full", "The Short Conversation",
	],
}

## Who the contract is actually about. A named person with a title makes the
## trophy on the killer's record mean something years later.
##
## Every one of these has to read after "The target is <name>, " — so they are
## all singular job descriptions that take an article, never a plural or a rank
## used as a name.
##
## GRAMMAR (see .docs/prose_style_guide.md): a bare singular noun phrase with NO
## article of its own — TextUtil.with_article() supplies it, which is why "union
## enforcer" comes out as "a union enforcer" and not "an". Lower case, no stop.
const TARGET_TITLES := [
	"cartel accountant", "militia colonel", "arms broker",
	"provincial minister", "mine security chief", "signals officer",
	"faction quartermaster", "regional warlord", "customs inspector",
	"union enforcer", "shipping agent", "border commander",
	"pipeline foreman", "recruiter for somebody else's war",
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


## A few lines of what the job actually is. Composed from the pieces the contract
## already has — type, place, target, danger — so it never contradicts the
## numbers beside it, and every contract reads as a job rather than a row.
##
## The order is the order a real brief would take it: what the work is, what the
## ground is like, who it is about, and what to expect on arrival. Assembled
## through TextUtil.sentences so a region with no description written yet cannot
## leave a double space in the middle of the paragraph.
static func _write_briefing(m: MissionData, rng: RandomNumberGenerator) -> String:
	var region := m.region()
	var place: String = m.region_place()
	var ground: String = region.description if region != null else ""

	var opening: Array = BRIEFING_OPENINGS.get(m.mission_type, ["Work in %s."])
	var parts: Array = [opening[rng.randi() % opening.size()] % place, ground]

	# Named people are the whole reason an assassination is memorable, so the
	# target gets its own sentence rather than being appended to the opening and
	# then interrupted by the terrain.
	if not m.target_name.is_empty():
		parts.append("The target is %s, %s" % [
			m.target_name, TextUtil.with_article(m.target_title)])

	parts.append(_caution_for(m, rng))
	return TextUtil.sentences(parts)


## The honest warning, keyed to how lethal the contract is rather than how hard.
## Several ways of saying each so a board of eight contracts does not repeat the
## same sentence three times.
##
## GRAMMAR (see .docs/prose_style_guide.md): one or more COMPLETE SENTENCES,
## capitalised, each closed with a stop, and NO format placeholder — this is the
## only briefing part that is never substituted, so a stray "%s" here would print
## raw. It always lands last in the paragraph, so it must not open with a
## connective that expects the terrain sentence before it.
const CAUTIONS := {
	"light": [
		"Resistance is expected to be light.",
		"Nobody is expecting company.",
		"Whoever is there is not being paid enough to die for it.",
		"The client does not expect this to turn into a fight.",
	],
	"organised": [
		"Expect organised opposition.",
		"Whoever holds it has held it a while, and it shows.",
		"There are people there who have done this before.",
		"Expect somebody to be awake, and expect them to have a radio.",
	],
	"heavy": [
		"Assume everyone there is armed and expecting you.",
		"They are dug in, they are alert, and they have nowhere else to go.",
		"Anybody going in should assume the first contact happens on the approach.",
		"There is no version of this that stays quiet.",
	],
}


static func _caution_for(m: MissionData, rng: RandomNumberGenerator) -> String:
	var band: String = "light"
	if m.risk >= 75.0:
		band = "heavy"
	elif m.risk >= 50.0:
		band = "organised"
	var pool: Array = CAUTIONS[band]
	return pool[rng.randi() % pool.size()]


## Every opening takes the place as it reads in a sentence — "the Kunar Valley",
## not "Kunar Valley" — so the article belongs to the region and not to the
## template. See RegionData.place().
##
## GRAMMAR (see .docs/prose_style_guide.md): EXACTLY ONE "%s", and it stands for
## the place, mid-sentence, never at the start — a region already carries its
## lower-case "the". One or more complete sentences, each closed with a stop. Any
## other per-cent sign has to be doubled, or `% place` will fail at runtime.
const BRIEFING_OPENINGS := {
	GameEnums.MissionType.ASSAULT: [
		"The client wants a position in %s taken and held long enough to matter.",
		"Something in %s needs to stop operating today.",
		"There is a compound in %s the client would rather nobody else owned by Friday.",
		"A position in %s changed hands last month. The client wants it changed back.",
		"The client is paying for a door in %s to come off its hinges.",
	],
	GameEnums.MissionType.INFILTRATION: [
		"Get inside a facility in %s, take what the client asked for, and leave no record.",
		"A building in %s needs entering quietly and leaving quietly.",
		"There is a safe in %s the client would like the contents of, and no story attached.",
		"Somewhere in %s there is a room the client is not supposed to have been in.",
		"The client wants something moved out of %s before anyone notices it is gone.",
	],
	GameEnums.MissionType.RESCUE: [
		"People are being held in %s. The client wants them back breathing.",
		"A crew went missing in %s. Bring out whoever is still alive.",
		"The client has staff in %s who stopped reporting in eleven days ago.",
		"Somebody in %s is being held against a number nobody intends to pay.",
		"There are people in %s the client is not willing to write off yet.",
	],
	GameEnums.MissionType.RECON: [
		"The client wants eyes on %s and no contact whatsoever.",
		"Sit on a position in %s, count what moves, come home.",
		"Nobody has looked at %s properly in a year, and the client is tired of guessing.",
		"The client is buying photographs of %s, and nothing else.",
		"Something in %s is being built or being moved, and the client wants to know which.",
	],
	GameEnums.MissionType.SABOTAGE: [
		"Infrastructure in %s needs to stop working, ideally without a signature.",
		"Something in %s is worth more broken than intact.",
		"There is a supply line running through %s that the client wants interrupted.",
		"The client wants something in %s to fail in a way that looks like neglect.",
		"A facility in %s is due an accident.",
	],
	GameEnums.MissionType.ESCORT: [
		"A convoy is crossing %s and the client will not say what is in it.",
		"Somebody needs moving through %s in one piece.",
		"There is a road through %s the client has stopped trusting, and cargo that has to use it.",
		"The client has a shipment going across %s and no confidence in it arriving.",
		"Someone the client values is travelling through %s, and would prefer to keep travelling.",
	],
	GameEnums.MissionType.ASSASSINATION: [
		"One person in %s is to stop being a problem. The client was specific.",
		"A name, a face, and an address in %s. Nothing else is required.",
		"There is somebody in %s the client has finished negotiating with.",
		"The client has a name, a routine and a window, all of them in %s.",
		"One person in %s is holding something up, and the client is done waiting.",
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
