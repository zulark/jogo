class_name IncidentLibrary
extends RefCounted

## Small things that land on the desk between contracts, each with a choice.
##
## `EventLibrary` is the week's news: it happens *to* the company and is read
## afterwards. This is the other half — an incident happens on an ordinary day
## and stops the player, because ending a day was otherwise a button press with
## nothing in it. Contracts take four to seven days, training a week, intel
## three to five, so the loop was one decision followed by five presses of End
## Day. Incidents put a decision on the days in between.
##
## Rules, and they are the whole design:
##
## - **Every incident is gated on something true about the company.** Nobody
##   asks for leave who is not unhappy; no informant turns up for a contract
##   that is already cased. An incident that could fire on day one of any save
##   is weather, not consequence.
## - **Every option states its cost before it is taken.** The odds screen makes
##   that bargain with the player everywhere else and this is no different: the
##   detail line is the honest price, not a hint.
## - **There is no free option.** "Refuse" costs morale, "allow" costs days or
##   money. An incident where one choice dominates is a message box wearing a
##   decision's clothes.

## Each entry is { id, weight, requires: Callable(GameState) -> bool,
## build: Callable(Campaign, RandomNumberGenerator) -> Dictionary }.
##
## `build` returns the concrete incident, with the people and contracts already
## chosen and captured by its option callables:
##   { title, line, options: [ { label, detail, apply: Callable() -> String } ] }
static func catalogue() -> Array:
	return [
		{
			"id": &"leave_request",
			"weight": 4,
			"requires": func(state: GameState) -> bool:
				return not _unhappy(state).is_empty(),
			"build": func(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
				return _leave_request(campaign, rng),
		},
		{
			"id": &"barracks_argument",
			"weight": 3,
			"requires": func(state: GameState) -> bool:
				return _rivals(state).size() == 2,
			"build": func(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
				return _barracks_argument(campaign, rng),
		},
		{
			"id": &"rush_job",
			"weight": 3,
			"requires": func(state: GameState) -> bool:
				return _friendly_client(state) != &"",
			"build": func(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
				return _rush_job(campaign, rng),
		},
		{
			"id": &"walk_in",
			"weight": 3,
			# People turn up at companies they have heard of. A company nobody
			# has heard of does not get walk-ins.
			"requires": func(state: GameState) -> bool:
				return state.living_roster_size() < 9 and state.reputation >= 15,
			"build": func(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
				return _walk_in(campaign, rng),
		},
		{
			"id": &"early_discharge",
			"weight": 3,
			"requires": func(state: GameState) -> bool:
				return _nearly_healed(state) != null,
			"build": func(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
				return _early_discharge(campaign, rng),
		},
		{
			"id": &"informant",
			"weight": 3,
			"requires": func(state: GameState) -> bool:
				return _uncased(state) != null and state.diamonds > 500,
			"build": func(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
				return _informant(campaign, rng),
		},
		{
			"id": &"worn_kit",
			"weight": 2,
			# Kit wears out from being carried, and since v0.13 that is a real
			# number rather than a fiction: the armourer only complains when
			# something on the rack has actually come back damaged.
			"requires": func(state: GameState) -> bool:
				return _worst_spare(state) != null,
			"build": func(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
				return _worn_kit(campaign, rng),
		},
		{
			"id": &"creditor",
			"weight": 4,
			"requires": func(state: GameState) -> bool:
				return state.diamonds < 0,
			"build": func(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
				return _creditor(campaign, rng),
		},
	]


## Picks one incident that fits the company today, or an empty dictionary.
static func roll(
	campaign: Campaign,
	rng: RandomNumberGenerator,
	avoid: StringName = &""
) -> Dictionary:
	var state := campaign.state

	var eligible: Array = []
	var total := 0
	for entry in catalogue():
		if not (entry["requires"] as Callable).call(state):
			continue
		eligible.append(entry)
		total += int(entry["weight"])

	# Never the same thing twice running. A contented company has few incidents
	# it can legitimately draw, and without this the quiet stretches turn into
	# the same walk-in seven times, which reads as a bug rather than as quiet.
	if avoid != &"" and eligible.size() > 1:
		var without: Array = []
		var trimmed := 0
		for entry in eligible:
			if entry["id"] == avoid:
				continue
			without.append(entry)
			trimmed += int(entry["weight"])
		eligible = without
		total = trimmed

	if eligible.is_empty():
		return {}

	var pick: int = rng.randi_range(1, total)
	for entry in eligible:
		pick -= int(entry["weight"])
		if pick <= 0:
			var built: Dictionary = (entry["build"] as Callable).call(campaign, rng)
			built["id"] = entry["id"]
			return built
	return {}


# --- The incidents -----------------------------------------------------------

static func _leave_request(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
	var state := campaign.state
	var candidates := _unhappy(state)
	var op: OperatorData = candidates[rng.randi_range(0, candidates.size() - 1)]
	var days := rng.randi_range(2, 4)
	var buyout: int = op.salary * 2

	return {
		"title": "A request for leave",
		"line": "%s wants %s at home. They have not asked before, and they are not asking loudly." % [
			op.display_label(), TextUtil.count(days, "day")],
		"options": [
			{
				"label": "Let them go",
				"detail": "Unavailable for %s. Comes back steadier." % TextUtil.count(days, "day"),
				"apply": func() -> String:
					op.days_unavailable = maxi(op.days_unavailable, days)
					op.status = GameEnums.OperatorStatus.INJURED
					op.morale = clampi(op.morale + 20, 0, 100)
					op.fatigue = maxi(0, op.fatigue - 15)
					return "%s went home for %s." % [
						op.display_label(), TextUtil.count(days, "day")],
			},
			{
				"label": "Pay them to stay",
				"detail": "%d diamonds. They stay available and take it well." % buyout,
				"apply": func() -> String:
					state.diamonds -= buyout
					op.morale = clampi(op.morale + 10, 0, 100)
					return "%s took the money and stayed on." % op.display_label(),
			},
			{
				"label": "Refuse",
				"detail": "Costs nothing today. They will remember it.",
				"apply": func() -> String:
					op.morale = maxi(0, op.morale - 14)
					return "%s was told no." % op.display_label(),
			},
		],
	}


static func _barracks_argument(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
	var state := campaign.state
	var pair := _rivals(state)
	var one: OperatorData = pair[0]
	var two: OperatorData = pair[1]

	return {
		"title": "A fight in the barracks",
		"line": "%s and %s have stopped pretending to get along. Somebody has to decide how this ends." % [
			one.display_label(), two.display_label()],
		"options": [
			{
				"label": "Separate them",
				"detail": "Both lose a little morale. The rivalry stays exactly where it is.",
				"apply": func() -> String:
					one.morale = maxi(0, one.morale - 5)
					two.morale = maxi(0, two.morale - 5)
					return "They were pulled apart and sent to opposite ends of the base.",
			},
			{
				"label": "Let them settle it",
				"detail": "Either they are done with it, or one of them is hurt.",
				"apply": func() -> String:
					if rng.randf() < 0.55:
						Bonds.remove(one, two)
						one.morale = clampi(one.morale + 8, 0, 100)
						two.morale = clampi(two.morale + 8, 0, 100)
						return "It burned itself out. %s and %s are done with each other's names." % [
							one.display_label(), two.display_label()]
					var hurt: OperatorData = one if rng.randf() < 0.5 else two
					hurt.status = GameEnums.OperatorStatus.INJURED
					hurt.days_unavailable = maxi(hurt.days_unavailable, rng.randi_range(2, 4))
					hurt.morale = maxi(0, hurt.morale - 8)
					return "%s came off worse and is in the infirmary." % hurt.display_label(),
			},
			{
				"label": "Discipline them both",
				"detail": "A week's pay each. Order restored, resentment included.",
				"apply": func() -> String:
					state.diamonds += one.salary + two.salary
					one.morale = maxi(0, one.morale - 12)
					two.morale = maxi(0, two.morale - 12)
					return "Both were fined a week's wages.",
			},
		],
	}


static func _rush_job(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
	var state := campaign.state
	var client := _friendly_client(state)
	var faction := FactionLibrary.get_faction(client)

	var mission := MissionFactory.create(rng)
	mission.client_id = client
	mission.expires_in_days = 2
	mission.reward_diamonds = int(round(float(mission.reward_diamonds) * 1.35))

	return {
		"title": "A job at short notice",
		"line": "%s wants people moving tomorrow and is paying over the odds for it. The offer stands for two days." % (
			faction.display_name if faction != null else "A client"),
		"options": [
			{
				"label": "Put it on the board",
				"detail": "%s, %s, pays %d. Two days to take it." % [
					mission.type_name(), mission.region_name(), mission.reward_diamonds],
				"apply": func() -> String:
					state.board.append(mission)
					return "%s went on the board with two days on it." % mission.title,
			},
			{
				"label": "Turn it down",
				"detail": "Costs 5 standing with %s." % (
					faction.display_name if faction != null else "them"),
				"apply": func() -> String:
					state.adjust_standing(client, -5)
					return "The offer was declined.",
			},
		],
	}


static func _walk_in(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
	var state := campaign.state
	var op := OperatorFactory.create(rng)
	var price: int = int(round(float(state.hire_cost(op)) * 1.25))

	return {
		"title": "Someone at the gate",
		"line": "%s heard the company was hiring and did not wait for the week to turn. %s" % [
			op.display_label(), op.resume()],
		"options": [
			{
				"label": "Sign them now",
				"detail": "%d diamonds, a quarter over the going rate. Then %d a week." % [
					price, op.salary],
				"apply": func() -> String:
					if price > state.diamonds:
						return "There was not enough in the account to sign them."
					state.diamonds -= price
					state.roster.append(op)
					return "%s signed on the spot." % op.display_label(),
			},
			{
				"label": "Tell them to come back",
				"detail": "They join this week's recruits instead, at the normal rate.",
				"apply": func() -> String:
					state.recruits.append(op)
					return "%s was told to wait with the rest." % op.display_label(),
			},
		],
	}


static func _early_discharge(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
	var op := _nearly_healed(campaign.state)
	var left := op.days_unavailable

	return {
		"title": "Signing themselves out",
		"line": "%s says they are fit and wants off the infirmary list %s early." % [
			op.display_label(), TextUtil.count(left, "day")],
		"options": [
			{
				"label": "Clear them for duty",
				"detail": "Available today, but they come back worn: fatigue +20.",
				"apply": func() -> String:
					op.days_unavailable = 0
					op.status = GameEnums.OperatorStatus.AVAILABLE
					op.fatigue = clampi(op.fatigue + 20, 0, 100)
					op.morale = clampi(op.morale + 6, 0, 100)
					return "%s is back on the roster." % op.display_label(),
			},
			{
				"label": "Make them wait",
				"detail": "They heal properly. They also sulk about it.",
				"apply": func() -> String:
					op.morale = maxi(0, op.morale - 6)
					return "%s was sent back to bed." % op.display_label(),
			},
		],
	}


static func _informant(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
	var state := campaign.state
	var mission := _uncased(state)
	var price: int = rng.randi_range(400, 900)
	var worth: float = float(rng.randi_range(3, 6))

	return {
		"title": "A man with something to sell",
		"line": "Someone who has been to %s wants paying for what he saw there. He will talk about %s." % [
			mission.region_name(), mission.title],
		"options": [
			{
				"label": "Pay him",
				"detail": "%d diamonds. %s counts as cased, worth about %+.1f." % [
					price, mission.title, worth],
				"apply": func() -> String:
					if price > state.diamonds:
						return "There was not enough in the account to pay him."
					state.diamonds -= price
					mission.scouted = true
					mission.intel_bonus = maxf(mission.intel_bonus, worth)
					return "He talked. %s is cased." % mission.title,
			},
			{
				"label": "Send him away",
				"detail": "Costs nothing. He was probably lying anyway.",
				"apply": func() -> String:
					return "He was shown the gate.",
			},
		],
	}


## The armourer, holding the worst thing on the rack.
##
## What this offers that the workshop screen does not is *speed*: the bench is
## the scarce thing, and he is proposing to do the job tonight without taking
## one. The price is that a rush refit costs more than the same repair booked
## properly, and it still costs the ceiling — there is no free restoration in
## this game and this is not one.
static func _worn_kit(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
	var state := campaign.state
	var instance := _worst_spare(state)
	var name_lower: String = instance.display_name().to_lower()
	var refit: int = int(round(float(Workshop.repair_cost(instance)) * 1.6))
	var parts: int = Workshop.scrap_value(instance)

	return {
		"title": "The armourer's complaint",
		"line": "The %s is down to %d%% and he wants a decision on it. He can turn it round tonight without tying up a bench, or strip it where it stands." % [
			name_lower, int(round(instance.condition))],
		"options": [
			{
				"label": "Pay for the rush refit",
				"detail": "%d diamonds — more than the bench would charge. Back to %d%% tonight." % [
					refit, int(round(instance.max_condition - instance.ceiling_cost_of_repair()))],
				"apply": func() -> String:
					state.diamonds -= refit
					instance.repair()
					return "The %s is back in the rack at %d%%." % [
						name_lower, int(round(instance.condition))],
			},
			{
				"label": "Strip it for parts",
				"detail": "%d parts, and the %s is gone." % [parts, name_lower],
				"apply": func() -> String:
					campaign.scrap_item(instance)
					return "The %s was stripped. %d parts on the shelf." % [name_lower, parts],
			},
		],
	}


static func _creditor(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
	var state := campaign.state
	var owed: int = absi(state.diamonds)

	return {
		"title": "Somebody wants paying",
		"line": "The company is %d diamonds under. The people it is under to have started asking in person." % owed,
		"options": [
			{
				"label": "Promise them the next contract",
				"detail": "Nothing today. Reputation -4, and they will be back.",
				"apply": func() -> String:
					state.reputation = maxi(0, state.reputation - 4)
					return "They were sent away with a promise.",
			},
			{
				"label": "Sell something to cover it",
				"detail": "Clears part of the debt from whatever storage can spare.",
				"apply": func() -> String:
					var spare := _spare_item(state)
					if spare == null:
						state.reputation = maxi(0, state.reputation - 2)
						return "There was nothing left in storage worth selling."
					var raised := int(round(float(campaign.resale_value(spare)) * 0.73))
					state.inventory.erase(spare)
					state.diamonds += raised
					return "The %s went for %d." % [spare.display_name().to_lower(), raised],
			},
		],
	}


# --- Conditions --------------------------------------------------------------

static func _unhappy(state: GameState) -> Array:
	var found: Array = []
	for op in state.roster:
		if op.is_deployable() and op.morale < 48:
			found.append(op)
	return found


static func _rivals(state: GameState) -> Array:
	for op in state.roster:
		if not op.is_deployable():
			continue
		for other in state.roster:
			if other == op or not other.is_deployable():
				continue
			if Bonds.bond_type(op, other) == GameEnums.BondType.RIVALRY:
				return [op, other]
	return []


## A client who thinks well enough of the company to ring it directly.
static func _friendly_client(state: GameState) -> StringName:
	for id in FactionLibrary.ids():
		if state.standing_with(id) >= 30:
			return id
	return &""


static func _nearly_healed(state: GameState) -> OperatorData:
	for op in state.roster:
		if op.status == GameEnums.OperatorStatus.INJURED and op.days_unavailable in [1, 2, 3]:
			return op
	return null


static func _uncased(state: GameState) -> MissionData:
	for mission in state.board:
		if not mission.scouted and not mission.is_being_scouted():
			return mission
	return null


## An item nobody is carrying. Selling kit out from under an operator mid-week
## is not a decision the player asked to make.
static func _spare_item(state: GameState) -> ItemInstance:
	for instance in state.inventory:
		if state.is_spare(instance):
			return instance
	return null


## The loosest, sorriest thing on the rack. The armourer's complaint is about a
## specific item in a specific state, so it picks the worst rather than the
## first — and returns nothing at all if the company's kit is fine, which is
## what stops the incident firing at a company that has done nothing wrong.
static func _worst_spare(state: GameState) -> ItemInstance:
	var worst: ItemInstance = null
	for instance in state.spare_instances():
		if instance.condition >= instance.max_condition:
			continue
		if worst == null or instance.condition < worst.condition:
			worst = instance
	return worst
