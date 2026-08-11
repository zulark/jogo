class_name EventLibrary
extends RefCounted

## Things that happen to the company between contracts.
##
## The design doc's note about evolution is treated as the requirement rather
## than an afterthought: every event here is gated on something the player did.
## An informant only turns up when morale is low. A brawl needs two people who
## already hate each other. A prodigy walks in because the company is worth
## joining. The Intelligence Centre shifts the mix away from the bad ones.
##
## The result is that a week's news reads as consequence rather than weather,
## which is the difference between an event system and a random number.

enum Polarity { GOOD, BAD }


## Every event, as { id, title, polarity, weight, requires } where `requires` is
## a Callable(GameState) -> bool. Effects live in apply() below.
static func catalogue() -> Array:
	return [
		# --- Bad ------------------------------------------------------------
		{
			"id": &"informant",
			"title": "Someone sold the base",
			"polarity": Polarity.BAD,
			"weight": 3,
			"requires": func(state: GameState) -> bool:
				return _average_morale(state) < 50 and state.diamonds > 500,
		},
		{
			"id": &"theft",
			"title": "Kit went missing from storage",
			"polarity": Polarity.BAD,
			"weight": 2,
			# Somebody has to WANT to steal it. "You own something" is not a
			# reason, and losing a pistol for no reason is the single most
			# frustrating thing an event system can do.
			"requires": func(state: GameState) -> bool:
				return state.lowest_morale() < 40 and _spare_item(state) != null,
		},
		{
			"id": &"brawl",
			"title": "A fight in the barracks",
			"polarity": Polarity.BAD,
			"weight": 3,
			"requires": func(state: GameState) -> bool:
				return _find_rivals(state).size() == 2,
		},
		{
			"id": &"illness",
			"title": "Something is going round",
			"polarity": Polarity.BAD,
			"weight": 2,
			# Worn-out people in a base with no doctor. Both halves are the
			# player's doing: rotation, and what they chose to build.
			"requires": func(state: GameState) -> bool:
				return (
					state.living_roster_size() >= 3
					and (state.average_fatigue() >= 35
						or state.facility_level(FacilityLibrary.INFIRMARY) == 0)
				),
		},
		{
			"id": &"client_dispute",
			"title": "A client disputes an invoice",
			"polarity": Polarity.BAD,
			"weight": 2,
			# A client you have already disappointed. Somebody who thinks well
			# of the company does not go looking through the paperwork.
			"requires": func(state: GameState) -> bool:
				return _disgruntled_client(state) != &"",
		},

		{
			"id": &"generator_failure",
			"title": "The generator went out",
			"polarity": Polarity.BAD,
			"weight": 2,
			"requires": func(state: GameState) -> bool:
				return (
					state.built_facility_count() >= 3
					and Economy.weeks_of_runway(state) <= 1
				),
		},
		{
			"id": &"supply_shortage",
			"title": "Nobody is selling",
			"polarity": Polarity.BAD,
			"weight": 2,
			# Suppliers avoid companies nobody has heard of. A well-regarded
			# company gets served.
			"requires": func(state: GameState) -> bool:
				return state.reputation < 35,
		},
		{
			"id": &"gear_failure",
			"title": "Kit failed inspection",
			"polarity": Polarity.BAD,
			"weight": 2,
			# Kit wears out from being USED. A rack of spares that never left
			# the building does not fail an inspection.
			"requires": func(state: GameState) -> bool:
				return state.deployed_last_week > 0 and _spare_item(state) != null,
		},
		{
			"id": &"payroll_late",
			"title": "Wages went out late",
			"polarity": Polarity.BAD,
			"weight": 3,
			# The company cannot cover next week's bill, and everybody can read a
			# noticeboard. Gated on the actual number rather than on debt, so it
			# fires as a warning while there is still time to act on it.
			"requires": func(state: GameState) -> bool:
				return (
					state.living_roster_size() >= 3
					and state.diamonds < state.weekly_payroll()),
		},
		{
			"id": &"poached",
			"title": "Somebody else is hiring",
			"polarity": Polarity.BAD,
			"weight": 3,
			# Reputation alone must NOT be enough: a company nobody has heard of
			# has nobody worth poaching, but a company doing well and keeping its
			# people happy has done nothing to deserve this. It takes both — a
			# name worth ringing about, and somebody willing to take the call.
			"requires": func(state: GameState) -> bool:
				return state.reputation >= 40 and _poachable(state) != null,
		},
		{
			"id": &"bad_lot",
			"title": "A bad lot came through the armoury",
			"polarity": Polarity.BAD,
			"weight": 2,
			# You cannot be sold a bad batch of anything without a shop to be sold
			# it through, and it only shows up on kit that went out.
			"requires": func(state: GameState) -> bool:
				return (
					state.deployed_last_week > 0
					and state.facility_level(FacilityLibrary.ARMOURY) > 0
					and not state.spare_instances().is_empty()),
		},
		{
			"id": &"relapse",
			"title": "Somebody went back to bed",
			"polarity": Polarity.BAD,
			"weight": 2,
			# Recovering in a building with no infirmary in it. Both halves are
			# things the player chose.
			"requires": func(state: GameState) -> bool:
				return (
					state.injured_headcount() > 0
					and state.facility_level(FacilityLibrary.INFIRMARY) == 0),
		},
		{
			"id": &"shakedown",
			"title": "Somebody official wants a word",
			"polarity": Polarity.BAD,
			"weight": 2,
			# Money worth taking, and not enough standing for anybody to think
			# twice about taking it.
			"requires": func(state: GameState) -> bool:
				return state.diamonds > 2500 and state.reputation < 45,
		},
		{
			"id": &"feud_spreads",
			"title": "People are taking sides",
			"polarity": Polarity.BAD,
			"weight": 2,
			# A rivalry the player has left alone long enough for the rest of the
			# roster to have opinions about it.
			"requires": func(state: GameState) -> bool:
				return _find_rivals(state).size() == 2 and state.living_roster_size() >= 4,
		},

		# --- Good -----------------------------------------------------------
		{
			"id": &"blackmarket_discount",
			"title": "A contact owes you a favour",
			"polarity": Polarity.GOOD,
			"weight": 2,
			"requires": func(state: GameState) -> bool:
				return state.reputation >= 25,
		},
		{
			"id": &"quiet_week",
			"title": "A week with nothing in it",
			"polarity": Polarity.GOOD,
			"weight": 2,
			# It cannot have been a quiet week if a squad was out in it.
			"requires": func(state: GameState) -> bool:
				return state.deployed_last_week == 0,
		},
		{
			"id": &"veteran_returns",
			"title": "An old hand came back",
			"polarity": Polarity.GOOD,
			"weight": 2,
			"requires": func(state: GameState) -> bool:
				return not state.cemetery.is_empty() or state.reputation >= 40,
		},
		{
			"id": &"prodigy",
			"title": "A prodigy walks in",
			"polarity": Polarity.GOOD,
			"weight": 3,
			"requires": func(state: GameState) -> bool:
				return state.reputation >= 30,
		},
		{
			"id": &"salvage",
			"title": "Salvage sold on",
			"polarity": Polarity.GOOD,
			"weight": 3,
			# Salvage comes off contracts. Money cannot arrive from work nobody
			# did.
			"requires": func(state: GameState) -> bool:
				return state.deployed_last_week > 0,
		},
		{
			"id": &"cache",
			"title": "A cache came back with the last squad",
			"polarity": Polarity.GOOD,
			"weight": 2,
			# "Came back with the last squad" requires a last squad.
			"requires": func(state: GameState) -> bool:
				return state.has_storage_room() and state.deployed_last_week > 0,
		},
		{
			"id": &"commendation",
			"title": "Word got around",
			"polarity": Polarity.GOOD,
			"weight": 2,
			# Word gets around about work that was done.
			"requires": func(state: GameState) -> bool:
				return state.reputation < 95 and state.deployed_last_week > 0,
		},
		{
			"id": &"shore_leave",
			"title": "A good week at home",
			"polarity": Polarity.GOOD,
			"weight": 3,
			"requires": func(state: GameState) -> bool:
				return _average_morale(state) < 80,
		},
		{
			"id": &"client_bonus",
			"title": "A client paid over the invoice",
			"polarity": Polarity.GOOD,
			"weight": 3,
			# Someone who already thinks well of the company. Goodwill paying out
			# in money is the whole reason standing is worth accumulating.
			"requires": func(state: GameState) -> bool:
				return _favourite_client(state) != &"",
		},
		{
			"id": &"referral",
			"title": "A client put your name forward",
			"polarity": Polarity.GOOD,
			"weight": 3,
			"requires": func(state: GameState) -> bool:
				return _favourite_client(state) != &"" and state.board.size() < 10,
		},
		{
			"id": &"plans_traded",
			"title": "Plans changed hands",
			"polarity": Polarity.GOOD,
			"weight": 2,
			# Nobody hands drawings to a company they have not heard of, and a
			# second copy of knowledge is nothing.
			"requires": func(state: GameState) -> bool:
				return state.reputation >= 50 and not _unknown_blueprints(state).is_empty(),
		},
		{
			"id": &"parts_delivery",
			"title": "A crate of parts turned up",
			"polarity": Polarity.GOOD,
			"weight": 3,
			# There has to be a bench for parts to be any use, or this is a line of
			# news about a number nobody can spend.
			"requires": func(state: GameState) -> bool:
				return (
					state.facility_level(FacilityLibrary.ARMOURY) > 0
					or state.facility_level(FacilityLibrary.QUARTERMASTER) > 0),
		},
		{
			"id": &"ward_round",
			"title": "The infirmary had a good week",
			"polarity": Polarity.GOOD,
			"weight": 3,
			"requires": func(state: GameState) -> bool:
				return (
					state.injured_headcount() > 0
					and state.facility_level(FacilityLibrary.INFIRMARY) >= 2),
		},
		{
			"id": &"local_recruit",
			"title": "Somebody's cousin needs work",
			"polarity": Polarity.GOOD,
			"weight": 2,
			# Word of mouth through the roster itself, so it wants a roster with
			# room in it and a company worth recommending.
			"requires": func(state: GameState) -> bool:
				return state.living_roster_size() < 9 and state.reputation >= 20,
		},
	]


## An item nobody is carrying. Every event that removes kit goes through this:
## taking a rifle out of an operator's hands between contracts is not a
## consequence the player can see coming.
static func _spare_item(state: GameState) -> ItemInstance:
	for instance in state.inventory:
		if state.is_spare(instance):
			return instance
	return null


## The client with the least patience left, or empty if every client the company
## deals with is content — in which case nobody disputes anything.
static func _disgruntled_client(state: GameState) -> StringName:
	var worst: StringName = &""
	var lowest := 40
	for id in state.faction_standing:
		var standing: int = int(state.faction_standing[id])
		if standing < lowest:
			lowest = standing
			worst = id
	return worst


## The client who thinks most of the company, or empty if nobody has warmed to it
## yet. Goodwill only pays out where goodwill was earned.
static func _favourite_client(state: GameState) -> StringName:
	var best: StringName = &""
	var highest := 40
	for id in state.faction_standing:
		var standing: int = int(state.faction_standing[id])
		if standing > highest:
			highest = standing
			best = id
	return best


## The most expensive person on the books who is also unhappy enough to listen —
## the one another company would ring, and who would let them finish the sentence.
static func _poachable(state: GameState) -> OperatorData:
	var best: OperatorData = null
	for op in state.roster:
		if op.status == GameEnums.OperatorStatus.DEAD:
			continue
		if op.morale >= Balance.MORALE_NEUTRAL:
			continue
		if best == null or op.salary > best.salary:
			best = op
	return best


static func _unknown_blueprints(state: GameState) -> Array[ItemData]:
	var unknown: Array[ItemData] = []
	for item in ItemLibrary.blueprints():
		if not state.knows_blueprint(item.id):
			unknown.append(item)
	return unknown


static func _average_morale(state: GameState) -> int:
	if state.roster.is_empty():
		return Balance.MORALE_NEUTRAL
	var total := 0
	for op in state.roster:
		total += op.morale
	return total / state.roster.size()


## Two operators who are at each other's throats and both at base.
static func _find_rivals(state: GameState) -> Array:
	for op in state.roster:
		if not op.is_deployable():
			continue
		for other in state.roster:
			if other == op or not other.is_deployable():
				continue
			if Bonds.bond_type(op, other) == GameEnums.BondType.RIVALRY:
				return [op, other]
	return []


## Rolls one event for the week, or returns an empty dictionary. The Intelligence
## Centre does not stop things happening — it stops so many of them being bad.
static func roll(state: GameState, rng: RandomNumberGenerator) -> Dictionary:
	var morale_pressure: float = maxf(
		0.0, float(Balance.MORALE_NEUTRAL - _average_morale(state))
	) * Balance.EVENT_MORALE_FACTOR
	if rng.randf() >= Balance.EVENT_BASE_CHANCE + morale_pressure:
		return {}

	var intel: float = state.facility_effect(FacilityLibrary.INTELLIGENCE)
	var shield: float = clampf(intel * Balance.EVENT_INTEL_SHIELD, 0.0, 0.6)

	# Low morale tilts toward bad news; intelligence tilts back.
	var bad_odds: float = clampf(0.5 + morale_pressure * 2.0 - shield, 0.1, 0.9)
	var wanted: int = Polarity.BAD if rng.randf() < bad_odds else Polarity.GOOD

	var pool: Array = []
	for entry in catalogue():
		if entry["polarity"] != wanted:
			continue
		if not entry["requires"].call(state):
			continue
		for i in int(entry["weight"]):
			pool.append(entry)

	if pool.is_empty():
		return {}
	return pool[rng.randi() % pool.size()]


## Applies an event and returns the line the player reads. Effects live here
## rather than in the catalogue because a Callable cannot be serialised, and the
## week-in-review needs to describe what happened in concrete numbers.
static func apply(
	entry: Dictionary,
	campaign: Campaign,
	rng: RandomNumberGenerator
) -> String:
	var state := campaign.state

	match entry["id"]:
		&"informant":
			var loss: int = mini(state.diamonds, rng.randi_range(600, 2200))
			state.diamonds -= loss
			return "Someone sold what they knew about the base. %d diamonds gone." % loss

		&"theft":
			# Pick from what is actually loose, rather than picking at random and
			# discovering it was carried. Naming the motive matters as much as
			# the loss: kit vanishing "for no reason" is infuriating, kit
			# vanishing because the barracks is miserable is a consequence.
			var stolen := _spare_item(state)
			if stolen == null:
				return "A break-in at storage, but everything worth taking was in the field."
			state.inventory.erase(stolen)
			return "%s went missing overnight. Nobody saw anything, and morale here has been bad for weeks." % (
				TextUtil.sentence_case(stolen.definite()))

		&"brawl":
			var rivals := _find_rivals(state)
			if rivals.size() < 2:
				return "Tempers flared, then cooled."
			for op in rivals:
				op.morale = maxi(0, op.morale - 12)
				op.fatigue = mini(100, op.fatigue + 10)
			Bonds.link(rivals[0], rivals[1], GameEnums.BondType.RIVALRY, 15)
			return "%s and %s came to blows. It has not improved things." % [
				rivals[0].display_label(), rivals[1].display_label()]

		&"illness":
			for op in state.roster:
				if op.is_deployable():
					op.fatigue = mini(100, op.fatigue + rng.randi_range(12, 25))
			if state.facility_level(FacilityLibrary.INFIRMARY) == 0:
				return "Something is going round, and there is no infirmary to keep it out."
			return "Something is going round the barracks. Tired people catch it first."

		&"client_dispute":
			# The client who already thinks least of the company is the one who
			# goes through the paperwork looking for something.
			var faction_id := _disgruntled_client(state)
			if faction_id == &"":
				return "An invoice was queried and settled the same day."
			state.adjust_standing(faction_id, -10)
			return "%s went back through the last invoice line by line. They were not looking for nothing." % (
				FactionLibrary.faction_name(faction_id))

		&"prodigy":
			var prodigy := OperatorFactory.create(
				rng, -1, OperatorFactory.Tier.VETERAN, campaign._taken_callsigns())
			state.recruits.append(prodigy)
			return "%s came looking for work — and is better than anything on the board." % (
				prodigy.display_label())

		&"salvage":
			var gain: int = rng.randi_range(700, 2400)
			state.diamonds += gain
			return "Salvage from an old contract finally sold. %d diamonds." % gain

		&"cache":
			var affordable: Array[ItemData] = []
			for id in ItemLibrary.all():
				var item: ItemData = ItemLibrary.all()[id]
				if item.source == ItemData.Source.BLACKMARKET or item.is_craftable():
					continue
				if item.tier <= 2:
					affordable.append(item)
			if affordable.is_empty() or not state.has_storage_room():
				return "The squad brought something back, but there was nowhere to put it."
			var found: ItemData = affordable[rng.randi() % affordable.size()]
			# Found kit, so found-kit condition: it turns up used, like the loot
			# roll's does, rather than as a free item off the shelf.
			state.inventory.append(ItemInstance.create(found.id, rng.randf_range(
				Balance.LOOT_CONDITION_MIN, Balance.LOOT_CONDITION_MAX)))
			return "The last squad came back with %s nobody is claiming." % found.indefinite()

		&"commendation":
			var bump: int = rng.randi_range(3, 7)
			state.reputation = clampi(state.reputation + bump, 0, 100)
			return "Word got around about the last job. Reputation up %d." % bump

		&"generator_failure":
			var repair: int = mini(state.diamonds, rng.randi_range(400, 1400))
			state.diamonds -= repair
			return "The generator burned out. It has been running on deferred maintenance because there was no money to service it. %d diamonds to put it right." % repair

		&"supply_shortage":
			state.reputation = maxi(0, state.reputation - rng.randi_range(2, 5))
			return "Suppliers are stalling on the company's orders. Word gets around."

		&"gear_failure":
			var doomed := _spare_item(state)
			if doomed == null:
				return "An inspection flagged half the kit, but it is all in the field."
			# Written off rather than destroyed: the parts go into the pile the
			# next build comes out of, which is what stops this reading as pure
			# subtraction. Losing the item is still the consequence.
			var parts: int = Workshop.scrap_value(doomed)
			state.inventory.erase(doomed)
			state.salvage += parts
			return "%s came back from the last contract beyond repair, and %s stripped down for %s." % [
				TextUtil.sentence_case(doomed.definite()), doomed.verb_was(),
				TextUtil.spelled(parts, "part")]

		&"blackmarket_discount":
			var windfall: int = rng.randi_range(900, 2600)
			state.diamonds += windfall
			return "A blackmarket contact settled an old debt — %d diamonds of it." % windfall

		&"quiet_week":
			for op in state.roster:
				op.fatigue = maxi(0, op.fatigue - rng.randi_range(10, 22))
			return "Nothing happened all week. Everyone came back up a little."

		&"veteran_returns":
			var veteran := OperatorFactory.create(
				rng, -1, OperatorFactory.Tier.ELITE, campaign._taken_callsigns())
			veteran.salary = int(float(veteran.salary) * 0.8)
			state.recruits.append(veteran)
			return "%s heard the company was hiring and turned up. Cheaper than they are worth." % (
				veteran.display_label())

		&"shore_leave":
			for op in state.roster:
				op.morale = mini(100, op.morale + rng.randi_range(6, 12))
			return "A quiet week and someone finally fixed the heating. Morale is up."

		# --- Added in v0.14 -------------------------------------------------

		&"payroll_late":
			var short_by: int = maxi(1, state.weekly_payroll() - maxi(0, state.diamonds))
			for op in state.roster:
				op.morale = maxi(0, op.morale - rng.randi_range(4, 9))
			return "Wages went out two days late and the noticeboard says why. Next week's bill is %s short as it stands." % (
				TextUtil.count(short_by, "diamond"))

		&"poached":
			var wanted := _poachable(state)
			if wanted == null:
				return "Somebody was ringing around asking who was any good. Nobody answered."
			var rise: int = maxi(10, int(round(float(wanted.salary) * 0.15)))
			wanted.salary += rise
			wanted.morale = maxi(0, wanted.morale - rng.randi_range(3, 7))
			return "%s took a call from another company and did not take the job. Their price for staying is %s a week, up from %d." % [
				wanted.display_label(),
				TextUtil.count(wanted.salary, "diamond"),
				wanted.salary - rise]

		&"bad_lot":
			var spares := state.spare_instances()
			if spares.is_empty():
				return "A bad batch came through, and every piece of it was still in the field."
			var damaged := 0
			for instance in spares:
				if rng.randf() < 0.5:
					continue
				instance.wear(float(rng.randi_range(8, 18)))
				damaged += 1
			if damaged == 0:
				return "A bad batch came through the armoury. This time none of it mattered."
			return "A bad batch came through the armoury, and %s on the rack came back worse for it." % (
				TextUtil.spelled(damaged, "piece"))

		&"relapse":
			var patient: OperatorData = null
			for op in state.roster:
				if op.status == GameEnums.OperatorStatus.INJURED:
					patient = op
					break
			if patient == null:
				return "Somebody was on their feet too early, and got away with it."
			var extra: int = rng.randi_range(2, 4)
			patient.days_unavailable += extra
			patient.morale = maxi(0, patient.morale - 5)
			return "%s was up too early and is back off their feet. Another %s on the list, and nowhere proper to spend them." % [
				patient.display_label(), TextUtil.spelled(extra, "day")]

		&"shakedown":
			var taken: int = mini(state.diamonds, rng.randi_range(500, 1900))
			state.diamonds -= taken
			return "Somebody with a badge went through the company's paperwork and found what they came to find. %s, and no receipt." % (
				TextUtil.count(taken, "diamond"))

		&"feud_spreads":
			var pair := _find_rivals(state)
			if pair.size() < 2:
				return "Whatever it was about, it seems to have gone quiet."
			for op in state.roster:
				op.morale = maxi(0, op.morale - rng.randi_range(2, 6))
			return "The business between %s and %s has stopped being about the two of them. Everybody has an opinion now." % [
				pair[0].display_label(), pair[1].display_label()]

		&"client_bonus":
			var patron := _favourite_client(state)
			if patron == &"":
				return "An invoice was paid on time, which is its own kind of news."
			var bonus: int = rng.randi_range(800, 2600)
			state.diamonds += bonus
			return "%s settled the last invoice at more than it said, and did not explain. %s." % [
				FactionLibrary.faction_name(patron), TextUtil.count(bonus, "diamond")]

		&"referral":
			var referrer := _favourite_client(state)
			if referrer == &"":
				return "Somebody asked after the company. Nothing came of it."
			var taken_titles: Array = []
			for existing in state.board:
				taken_titles.append(existing.title)
			var offered := MissionFactory.create(rng, -1, -1, taken_titles)
			offered.client_id = referrer
			offered.reward_diamonds = int(round(float(offered.reward_diamonds) * 1.2))
			state.board.append(offered)
			return "%s gave the company's name to somebody who needed it. %s is on the board, and it pays over the going rate." % [
				FactionLibrary.faction_name(referrer), offered.title]

		&"plans_traded":
			var unknown := _unknown_blueprints(state)
			if unknown.is_empty():
				return "Somebody offered plans the workshop already has a copy of."
			var plan: ItemData = unknown[rng.randi() % unknown.size()]
			campaign.learn_blueprint(plan.id)
			return "Somebody traded the company a set of drawings for %s. The workshop can build them now." % (
				plan.name_in_prose())

		&"parts_delivery":
			var parts: int = rng.randi_range(25, 70)
			state.salvage += parts
			return "A crate nobody ordered turned up at the gate, full of things the bench can use. %s." % (
				TextUtil.count(parts, "part"))

		&"ward_round":
			var mended := 0
			for op in state.roster:
				if op.status == GameEnums.OperatorStatus.INJURED and op.days_unavailable > 1:
					op.days_unavailable -= 1
					mended += 1
			if mended == 0:
				return "A quiet week on the ward. Nobody needed anything."
			return "The infirmary had a good week. %s will be back a day earlier than the chart said." % (
				TextUtil.spelled_capitalised(mended, "operator"))

		&"local_recruit":
			var referred := OperatorFactory.create(
				rng, -1, OperatorFactory.Tier.ROOKIE, campaign._taken_callsigns())
			referred.salary = int(float(referred.salary) * 0.85)
			state.recruits.append(referred)
			return "%s was sent along by somebody already on the books, and will work for less because of it." % (
				referred.display_label())

	return ""
