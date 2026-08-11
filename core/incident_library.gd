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
		{
			"id": &"mentor_offer",
			"weight": 3,
			# Somebody senior enough to teach, somebody green enough to learn, and
			# both of them standing around at base. The Academy is not required —
			# it makes the offer worth more, which the detail line says.
			"requires": func(state: GameState) -> bool:
				return _teaching_pair(state).size() == 2,
			"build": func(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
				return _mentor_offer(campaign, rng),
		},
		{
			"id": &"sell_the_story",
			"weight": 3,
			# There has to have been a contract to tell a story about, and somebody
			# has to have heard of the company before they come asking for it.
			"requires": func(state: GameState) -> bool:
				return state.deployed_last_week > 0 and state.reputation >= 25,
			"build": func(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
				return _sell_the_story(campaign, rng),
		},
		{
			"id": &"dealer_at_the_gate",
			"weight": 3,
			# The blackmarket comes to companies it has heard of, and only when
			# there is somewhere to put what it is selling.
			"requires": func(state: GameState) -> bool:
				return (
					state.reputation >= 35
					and state.has_storage_room()
					and state.diamonds > 3000),
			"build": func(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
				return _dealer_at_the_gate(campaign, rng),
		},
		{
			"id": &"family_of_the_dead",
			"weight": 3,
			# Only a company that has buried somebody gets this letter. The whole
			# point of the cemetery is that it goes on costing something.
			"requires": func(state: GameState) -> bool:
				return not state.cemetery.is_empty() and state.living_roster_size() >= 2,
			"build": func(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
				return _family_of_the_dead(campaign, rng),
		},
		{
			"id": &"run_into_the_ground",
			"weight": 3,
			# Somebody the player has worked past the point of usefulness. The
			# rotation pressure the whole fatigue system exists for, made into a
			# decision instead of a number going up.
			"requires": func(state: GameState) -> bool:
				return _spent(state) != null,
			"build": func(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
				return _run_into_the_ground(campaign, rng),
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
			op.display_label(), TextUtil.spelled(days, "day")],
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
				"detail": "%s contract in %s, paying %s. Two days to take it." % [
					TextUtil.sentence_case(
						TextUtil.with_article(mission.type_name().to_lower())),
					mission.region_place(),
					TextUtil.count(mission.reward_diamonds, "diamond")],
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

	# The résumé opens with the name, so the framing sentence must not — "Lark
	# heard the company was hiring. Lark is an Afghan warrant officer" is the
	# same person introduced twice in a row.
	return {
		"title": "Someone at the gate",
		"line": "Somebody at the gate heard the company was hiring and did not wait for the week to turn. %s" % (
			op.resume()),
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
			op.display_label(), TextUtil.spelled(left, "day")],
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
			mission.region_place(), mission.title],
		"options": [
			{
				"label": "Pay him",
				"detail": "%s. %s counts as cased, worth about %+.1f to the odds." % [
					TextUtil.count(price, "diamond"), mission.title, worth],
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
	# Some kit is a plural — "night optics" — so nothing here may put a verb
	# straight after the item's name. See ItemData.definite().
	var named: String = instance.definite()
	var refit: int = int(round(float(Workshop.repair_cost(instance)) * 1.6))
	var parts: int = Workshop.scrap_value(instance)

	return {
		"title": "The armourer's complaint",
		"line": "He has %s in front of him, down to %d%%, and he wants a decision on %s tonight. He can turn the job round without tying up a bench, or strip the whole thing for parts." % [
			named, int(round(instance.condition)), instance.object_pronoun()],
		"options": [
			{
				"label": "Pay for the rush refit",
				"detail": "%s — more than the bench would charge. Back to %d%% tonight." % [
					TextUtil.count(refit, "diamond"),
					int(round(instance.max_condition - instance.ceiling_cost_of_repair()))],
				"apply": func() -> String:
					state.diamonds -= refit
					instance.repair()
					return "%s went back in the rack at %d%%." % [
						TextUtil.sentence_case(named), int(round(instance.condition))],
			},
			{
				"label": "Strip it for parts",
				"detail": "%s, and %s %s gone for good." % [
					TextUtil.spelled_capitalised(parts, "part"), named, instance.verb_is()],
				"apply": func() -> String:
					campaign.scrap_item(instance)
					return "%s went to the parts bin. %s on the shelf." % [
						TextUtil.sentence_case(named), TextUtil.spelled_capitalised(parts, "part")],
			},
		],
	}


static func _creditor(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
	var state := campaign.state
	var owed: int = absi(state.diamonds)

	return {
		"title": "Somebody wants paying",
		"line": "The company is %s in the red, and the people it owes have stopped writing letters about it. There is one of them at the desk now." % (
			TextUtil.count(owed, "diamond")),
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
					return "%s went out of the gate for %s." % [
						TextUtil.sentence_case(spare.definite()),
						TextUtil.count(raised, "diamond")],
			},
		],
	}


static func _mentor_offer(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
	var state := campaign.state
	var pair := _teaching_pair(state)
	var mentor: OperatorData = pair[0]
	var trainee: OperatorData = pair[1]
	var academy: int = state.facility_level(FacilityLibrary.ACADEMY)
	var academy_note: String = (
		"The Academy is at level %d, so it will take better than it otherwise would." % academy
		if academy > 0
		else "There is no Academy to run it in, so they will make do with the yard.")

	return {
		"title": "An offer to teach",
		"line": "%s has watched %s work and has offered to take them in hand for a week. Neither of them is available for contracts while it runs." % [
			mentor.display_label(), trainee.display_label()],
		"options": [
			{
				"label": "Put them together",
				"detail": "Both off the board for a week. %s" % academy_note,
				"apply": func() -> String:
					if campaign.start_training(mentor, trainee) == null:
						return "The class could not be arranged today after all."
					mentor.morale = clampi(mentor.morale + 6, 0, 100)
					return "%s started teaching %s this morning." % [
						mentor.display_label(), trainee.display_label()],
			},
			{
				"label": "Not this week",
				"detail": "Both stay available. %s takes it as a comment on their judgement." % (
					mentor.display_label()),
				"apply": func() -> String:
					mentor.morale = maxi(0, mentor.morale - 8)
					return "%s was told the roster could not spare either of them." % (
						mentor.display_label()),
			},
		],
	}


static func _sell_the_story(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
	var state := campaign.state
	var fee: int = rng.randi_range(900, 2400)
	var client := _least_favourite_client(state)
	var client_name: String = (
		FactionLibrary.faction_name(client) if client != &"" else "the last client")

	return {
		"title": "Somebody is writing it up",
		"line": "A journalist has most of the last contract already and wants the company's side of it. They are offering to pay for the quotes.",
		"options": [
			{
				"label": "Give them the story",
				"detail": "%s and reputation +6. %s will not enjoy reading it: standing -8." % [
					TextUtil.count(fee, "diamond"), client_name],
				"apply": func() -> String:
					state.diamonds += fee
					state.reputation = clampi(state.reputation + 6, 0, 100)
					if client != &"":
						state.adjust_standing(client, -8)
					return "It runs on Thursday, with the company named in it.",
			},
			{
				"label": "Say nothing",
				"detail": "No money, no coverage. Clients who prefer quiet contractors notice that too.",
				"apply": func() -> String:
					if client != &"":
						state.adjust_standing(client, 3)
					return "They were given a coffee and nothing else.",
			},
		],
	}


static func _dealer_at_the_gate(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
	var state := campaign.state
	var offered := _blackmarket_offer(state, rng)
	# A quarter under the asking price, which is the whole reason to take a
	# stranger's word for where it came from.
	var price: int = int(round(float(offered.price) * 0.75))

	return {
		"title": "A dealer at the gate",
		"line": "Somebody with a van is offering %s at a price that says nobody asked where it came from." % (
			offered.indefinite()),
		"options": [
			{
				"label": "Buy it",
				"detail": "%s, a quarter under the blackmarket price. Reputation -3 for dealing at the gate." % (
					TextUtil.count(price, "diamond")),
				"apply": func() -> String:
					if price > state.diamonds:
						return "There was not enough in the account to take it."
					if not state.has_storage_room():
						return "There was nowhere left in storage to put it."
					state.diamonds -= price
					state.inventory.append(ItemInstance.create(offered.id, rng.randf_range(
						Balance.LOOT_CONDITION_MIN, Balance.LOOT_CONDITION_MAX)))
					state.reputation = maxi(0, state.reputation - 3)
					return "It is in the warehouse, and the van is gone.",
			},
			{
				"label": "Send them away",
				"detail": "Costs nothing. Whatever it was, it is somebody else's problem now.",
				"apply": func() -> String:
					return "The van left without unloading.",
			},
		],
	}


static func _family_of_the_dead(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
	var state := campaign.state
	var lost: OperatorData = state.cemetery[state.cemetery.size() - 1]
	var gratuity: int = maxi(400, lost.salary * 6)

	return {
		"title": "A letter about %s" % lost.display_label(),
		"line": "%s was killed on %s, and the family has written to ask whether there is anything owed. Legally there is not." % [
			lost.display_label(),
			lost.died_on_mission if not lost.died_on_mission.is_empty() else "a contract",
		],
		"options": [
			{
				"label": "Pay it anyway",
				"detail": "%s. The rest of the roster hears about it within a day." % (
					TextUtil.count(gratuity, "diamond")),
				"apply": func() -> String:
					state.diamonds -= gratuity
					for op in state.roster:
						op.morale = clampi(op.morale + 7, 0, 100)
					return "It went out the same afternoon, and everybody knows it did.",
			},
			{
				"label": "Write back and explain the contract",
				"detail": "Costs nothing today. The roster hears about that too.",
				"apply": func() -> String:
					for op in state.roster:
						op.morale = maxi(0, op.morale - 5)
					return "The letter was answered in full, and correctly.",
			},
		],
	}


static func _run_into_the_ground(campaign: Campaign, rng: RandomNumberGenerator) -> Dictionary:
	var state := campaign.state
	var op := _spent(state)
	var days := rng.randi_range(2, 4)
	var stimulants: int = rng.randi_range(700, 1300)

	return {
		"title": "%s is running on nothing" % op.display_label(),
		"line": "%s is at %d%% fatigue and has not been off the roster in weeks. The medic has said so in writing, which is not something they normally bother doing." % [
			op.display_label(), op.fatigue],
		"options": [
			{
				"label": "Stand them down",
				"detail": "Off the board for %s. Comes back at something like a working state." % (
					TextUtil.count(days, "day")),
				"apply": func() -> String:
					op.days_unavailable = maxi(op.days_unavailable, days)
					op.status = GameEnums.OperatorStatus.INJURED
					op.fatigue = maxi(0, op.fatigue - 45)
					op.morale = clampi(op.morale + 8, 0, 100)
					return "%s was taken off everything for %s." % [
						op.display_label(), TextUtil.count(days, "day")],
			},
			{
				"label": "Buy them something to keep going",
				"detail": "%s. Fatigue drops now and comes back worse in a week." % (
					TextUtil.count(stimulants, "diamond")),
				"apply": func() -> String:
					if stimulants > state.diamonds:
						return "There was not enough in the account for that."
					state.diamonds -= stimulants
					op.fatigue = maxi(0, op.fatigue - 25)
					op.morale = maxi(0, op.morale - 10)
					return "%s is available, and the medic has stopped speaking to the office." % (
						op.display_label()),
			},
			{
				"label": "They carry on as they are",
				"detail": "Costs nothing today. They stay on the board at %d%% fatigue." % op.fatigue,
				"apply": func() -> String:
					op.morale = maxi(0, op.morale - 12)
					return "%s stayed on the board." % op.display_label(),
			},
		],
	}


# --- Conditions --------------------------------------------------------------

## A senior operator and the greenest person at base, both free today. Returns
## [mentor, trainee] or an empty array.
static func _teaching_pair(state: GameState) -> Array:
	if not state.training.is_empty():
		return []

	var mentor: OperatorData = null
	for op in state.potential_mentors():
		if mentor == null or op.rank_step() > mentor.rank_step():
			mentor = op
	if mentor == null:
		return []

	var trainee: OperatorData = null
	for op in state.available_operators():
		if op == mentor or op.career_track == GameEnums.CareerTrack.INSTRUCTOR:
			continue
		if not Progression.can_train(mentor, op):
			continue
		if trainee == null or op.rank_step() < trainee.rank_step():
			trainee = op
	if trainee == null:
		return []
	return [mentor, trainee]


## The client with the least patience left. Used where an action annoys somebody
## — better it lands on a relationship that was already cool.
static func _least_favourite_client(state: GameState) -> StringName:
	var worst: StringName = &""
	var lowest := 999
	for id in FactionLibrary.ids():
		var standing: int = state.standing_with(id)
		if standing < lowest:
			lowest = standing
			worst = id
	return worst


## Something off the blackmarket shelf the company could plausibly be shown.
static func _blackmarket_offer(state: GameState, rng: RandomNumberGenerator) -> ItemData:
	var stock := ItemLibrary.stock_for(
		ItemData.Source.BLACKMARKET, 3, maxi(state.reputation, 30))
	if stock.is_empty():
		stock = ItemLibrary.stock_for(ItemData.Source.ARMOURY, 3, state.reputation)
	return stock[rng.randi() % stock.size()]


## The most worn-out person at base, if anybody is far enough gone that the
## roster is being damaged by it.
static func _spent(state: GameState) -> OperatorData:
	var worst: OperatorData = null
	for op in state.roster:
		if not op.is_deployable() or op.fatigue < 70:
			continue
		if worst == null or op.fatigue > worst.fatigue:
			worst = op
	return worst


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
