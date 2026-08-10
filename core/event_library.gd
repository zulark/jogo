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
			"requires": func(state: GameState) -> bool:
				return state.inventory.size() > 0,
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
			"requires": func(state: GameState) -> bool:
				return state.living_roster_size() >= 3,
		},
		{
			"id": &"client_dispute",
			"title": "A client disputes an invoice",
			"polarity": Polarity.BAD,
			"weight": 2,
			"requires": func(state: GameState) -> bool:
				return not state.faction_standing.is_empty(),
		},

		{
			"id": &"generator_failure",
			"title": "The generator went out",
			"polarity": Polarity.BAD,
			"weight": 2,
			"requires": func(state: GameState) -> bool:
				return state.built_facility_count() > 0 and state.diamonds > 400,
		},
		{
			"id": &"supply_shortage",
			"title": "Nobody is selling",
			"polarity": Polarity.BAD,
			"weight": 2,
			"requires": func(state: GameState) -> bool:
				return state.reputation < 90,
		},
		{
			"id": &"gear_failure",
			"title": "Kit failed inspection",
			"polarity": Polarity.BAD,
			"weight": 2,
			"requires": func(state: GameState) -> bool:
				return state.inventory.size() >= 2,
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
			"requires": func(state: GameState) -> bool:
				return true,
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
			"requires": func(_state: GameState) -> bool:
				return true,
		},
		{
			"id": &"cache",
			"title": "A cache came back with the last squad",
			"polarity": Polarity.GOOD,
			"weight": 2,
			"requires": func(state: GameState) -> bool:
				return state.has_storage_room(),
		},
		{
			"id": &"commendation",
			"title": "Word got around",
			"polarity": Polarity.GOOD,
			"weight": 2,
			"requires": func(state: GameState) -> bool:
				return state.reputation < 95,
		},
		{
			"id": &"shore_leave",
			"title": "A good week at home",
			"polarity": Polarity.GOOD,
			"weight": 3,
			"requires": func(state: GameState) -> bool:
				return _average_morale(state) < 80,
		},
	]


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
			var item_id: StringName = state.inventory[rng.randi() % state.inventory.size()]
			var item := ItemLibrary.get_item(item_id)
			# Only take something nobody is carrying — kit in the field is safe.
			if state.unequipped_count(item_id) <= 0:
				return "A break-in at storage, but everything worth taking was in the field."
			state.inventory.erase(item_id)
			return "%s went missing from storage overnight." % (
				item.display_name if item != null else "Equipment")

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
			return "Something is going round the barracks. Everyone at base is worn down."

		&"client_dispute":
			var ids: Array = state.faction_standing.keys()
			var faction_id: StringName = ids[rng.randi() % ids.size()]
			state.adjust_standing(faction_id, -10)
			return "%s is disputing an invoice. Your standing with them has suffered." % (
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
				if item.source != ItemData.Source.BLACKMARKET and item.tier <= 2:
					affordable.append(item)
			if affordable.is_empty() or not state.has_storage_room():
				return "The squad brought something back, but there was nowhere to put it."
			var found: ItemData = affordable[rng.randi() % affordable.size()]
			state.inventory.append(found.id)
			return "The last squad came back with a %s nobody is claiming." % found.display_name

		&"commendation":
			var bump: int = rng.randi_range(3, 7)
			state.reputation = clampi(state.reputation + bump, 0, 100)
			return "Word got around about the last job. Reputation up %d." % bump

		&"generator_failure":
			var repair: int = mini(state.diamonds, rng.randi_range(400, 1400))
			state.diamonds -= repair
			return "The base generator burned out. %d diamonds to put it right." % repair

		&"supply_shortage":
			state.reputation = maxi(0, state.reputation - rng.randi_range(2, 5))
			return "Suppliers are stalling on the company's orders. Word gets around."

		&"gear_failure":
			var doomed: StringName = state.inventory[rng.randi() % state.inventory.size()]
			if state.unequipped_count(doomed) <= 0:
				return "An inspection flagged half the kit, but it is all in the field."
			state.inventory.erase(doomed)
			var broken := ItemLibrary.get_item(doomed)
			return "%s failed inspection and was written off." % (
				broken.display_name if broken != null else "Equipment")

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

	return ""
