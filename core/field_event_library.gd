class_name FieldEventLibrary
extends RefCounted

## The decision inside a contract, taken over the radio while the squad is out.
##
## `IncidentLibrary` is the desk between contracts; this is the field during one.
## Until now the player agreed the odds at the door and then watched a timer run
## down for four to seven days — the contract was a decision followed by a wait.
## A field event is the squad calling in with something the briefing did not
## cover, and it is the player, not the resolver, who decides what it costs.
##
## The rules are the ones the rest of the game already lives by:
##
## - **Gated on this contract and these people.** No patrol turns up in front of
##   a squad that did not come to be quiet; nobody argues on the radio who was
##   not already rivals; the job is only bigger than briefed if the player never
##   cased it. A field event that could fire on any contract is weather.
## - **Every option states its price in the currency the player reads.** Not
##   "this might help" — "Odds 58% → 64%, danger +6". The odds screen makes that
##   bargain everywhere else and the one place it must not break is the moment
##   the contract is already running.
## - **There is no free option.** Time, danger, money, score, standing, someone's
##   condition: every choice spends one of them. The interesting shape is when
##   they are different currencies, because then there is no dominant answer.
##
## Nothing here edits the odds directly. A decision adds a line to the breakdown
## and the percentage is re-derived from the list — see Deployment.apply_modifier.
## A percentage that moved without a line to explain it would be exactly the lie
## this game's whole scoring layer is built to avoid.

## Each entry is { id, weight,
##   requires: Callable(Deployment, GameState) -> bool,
##   build: Callable(Campaign, Deployment, RandomNumberGenerator) -> Dictionary }
static func catalogue() -> Array:
	return [
		{
			"id": &"patrol_on_the_route",
			"weight": 4,
			# Only work that came to be quiet has a quiet approach to lose.
			"requires": func(deployment: Deployment, _state: GameState) -> bool:
				return _is_quiet_work(deployment.mission) and _active(deployment).size() >= 2,
			"build": func(c: Campaign, d: Deployment, rng: RandomNumberGenerator) -> Dictionary:
				return _patrol_on_the_route(c, d, rng),
		},
		{
			"id": &"bigger_than_briefed",
			"weight": 4,
			# The cause is the player going in blind. A cased contract does not
			# surprise anybody with its numbers.
			"requires": func(deployment: Deployment, _state: GameState) -> bool:
				return not deployment.mission.scouted,
			"build": func(c: Campaign, d: Deployment, rng: RandomNumberGenerator) -> Dictionary:
				return _bigger_than_briefed(c, d, rng),
		},
		{
			"id": &"weather_closing_in",
			"weight": 3,
			# Somebody went somewhere hostile without the kit for it.
			"requires": func(deployment: Deployment, state: GameState) -> bool:
				return not _uncovered(deployment).is_empty() and state.diamonds > 600,
			"build": func(c: Campaign, d: Deployment, rng: RandomNumberGenerator) -> Dictionary:
				return _weather_closing_in(c, d, rng),
		},
		{
			"id": &"worn_out_operator",
			"weight": 4,
			# Sending a tired operator out is the decision this bills for.
			"requires": func(deployment: Deployment, _state: GameState) -> bool:
				return _worn_out(deployment) != null and _active(deployment).size() >= 3,
			"build": func(c: Campaign, d: Deployment, rng: RandomNumberGenerator) -> Dictionary:
				return _worn_out_operator(c, d, rng),
		},
		{
			"id": &"rivals_on_the_radio",
			"weight": 3,
			# Two people who already hated each other, put in the same truck.
			"requires": func(deployment: Deployment, _state: GameState) -> bool:
				var pair := _rivals(deployment)
				var leader: OperatorData = deployment.squad.leader
				return pair.size() == 2 and leader != null and not pair.has(leader),
			"build": func(c: Campaign, d: Deployment, rng: RandomNumberGenerator) -> Dictionary:
				return _rivals_on_the_radio(c, d, rng),
		},
		{
			"id": &"a_man_with_a_route",
			"weight": 3,
			# These are the wrong people for this ground, which the breakdown
			# already says out loud before the squad ever leaves.
			"requires": func(deployment: Deployment, state: GameState) -> bool:
				return _suits_the_ground(deployment) < 45.0 and state.diamonds > 900,
			"build": func(c: Campaign, d: Deployment, rng: RandomNumberGenerator) -> Dictionary:
				return _a_man_with_a_route(c, d, rng),
		},
		{
			"id": &"crate_not_in_the_brief",
			"weight": 3,
			# Loud work turns up other people's cargo. Quiet work does not stop
			# to look, and a full warehouse has nowhere to put it.
			"requires": func(deployment: Deployment, state: GameState) -> bool:
				return (
					deployment.mission.risk >= 45.0
					and deployment.mission.client() != null
					and state.has_storage_room()),
			"build": func(c: Campaign, d: Deployment, rng: RandomNumberGenerator) -> Dictionary:
				return _crate_not_in_the_brief(c, d, rng),
		},
		{
			"id": &"the_target_is_moving",
			"weight": 4,
			"requires": func(deployment: Deployment, _state: GameState) -> bool:
				return (
					deployment.mission.mission_type == GameEnums.MissionType.ASSASSINATION
					and not deployment.mission.target_name.is_empty()),
			"build": func(c: Campaign, d: Deployment, rng: RandomNumberGenerator) -> Dictionary:
				return _the_target_is_moving(c, d, rng),
		},
		{
			"id": &"the_brief_has_changed",
			"weight": 3,
			# The client is on the radio wanting something else as well. Only a
			# client who commissioned this can move the goalposts on it.
			"requires": func(deployment: Deployment, _state: GameState) -> bool:
				return deployment.mission.client() != null,
			"build": func(c: Campaign, d: Deployment, rng: RandomNumberGenerator) -> Dictionary:
				return _the_brief_has_changed(c, d, rng),
		},
		{
			"id": &"people_in_the_way",
			"weight": 3,
			# Loud work in a place with people living in it. The gate is the noise:
			# nobody has to make this call on a two-man reconnaissance.
			"requires": func(deployment: Deployment, _state: GameState) -> bool:
				return (
					deployment.mission.mission_type in [
						GameEnums.MissionType.ASSAULT,
						GameEnums.MissionType.SABOTAGE,
						GameEnums.MissionType.ESCORT,
					]
					and deployment.mission.client() != null),
			"build": func(c: Campaign, d: Deployment, rng: RandomNumberGenerator) -> Dictionary:
				return _people_in_the_way(c, d, rng),
		},
		{
			"id": &"running_short",
			"weight": 3,
			# Long contracts in dangerous places burn through what the squad
			# carried in. Both halves are the contract the player accepted.
			"requires": func(deployment: Deployment, state: GameState) -> bool:
				return (
					deployment.mission.duration_days >= 5
					and deployment.mission.risk >= 40.0
					and state.diamonds > 800),
			"build": func(c: Campaign, d: Deployment, rng: RandomNumberGenerator) -> Dictionary:
				return _running_short(c, d, rng),
		},
		{
			"id": &"extraction_is_burned",
			"weight": 3,
			# The way out stopped being the way out. Dangerous work only, and only
			# once the squad is far enough in for it to be a problem.
			"requires": func(deployment: Deployment, state: GameState) -> bool:
				return (
					deployment.mission.risk >= 55.0
					and deployment.days_remaining <= maxi(1, deployment.mission.duration_days / 2)
					and state.diamonds > 1200),
			"build": func(c: Campaign, d: Deployment, rng: RandomNumberGenerator) -> Dictionary:
				return _extraction_is_burned(c, d, rng),
		},
	]


## Picks one situation that fits this contract, or an empty dictionary.
##
## Anything already raised on this deployment is off the list: the same squad
## radioing in twice about the same patrol reads as a bug, not as a bad night.
static func roll(
	campaign: Campaign,
	deployment: Deployment,
	rng: RandomNumberGenerator
) -> Dictionary:
	var eligible: Array = []
	var total := 0
	for entry in catalogue():
		if deployment.fired_events.has(entry["id"]):
			continue
		if not (entry["requires"] as Callable).call(deployment, campaign.state):
			continue
		eligible.append(entry)
		total += int(entry["weight"])

	if eligible.is_empty():
		return {}

	var pick: int = rng.randi_range(1, total)
	for entry in eligible:
		pick -= int(entry["weight"])
		if pick > 0:
			continue

		var built: Dictionary = (entry["build"] as Callable).call(campaign, deployment, rng)
		built["id"] = entry["id"]
		# Both kinds of decision travel on the same signal and through the same
		# modal, so they carry where they came from rather than being told apart
		# by their wording.
		built["source"] = &"field"
		# Clamped because a contract can be extended or shortened by a decision
		# taken earlier, and "day 2 of 1" is the kind of detail that makes a
		# player stop trusting the rest of the card.
		var duration: int = maxi(1, deployment.mission.duration_days)
		built["eyebrow"] = "FROM THE FIELD  ·  DAY %d OF %d  ·  %s" % [
			clampi(duration - deployment.days_remaining + 1, 1, duration),
			duration,
			deployment.mission.title.to_upper(),
		]
		return built
	return {}


# --- The situations -----------------------------------------------------------

static func _patrol_on_the_route(
	_campaign: Campaign,
	deployment: Deployment,
	_rng: RandomNumberGenerator
) -> Dictionary:
	var scout := _best(deployment, GameEnums.Skill.STEALTH)
	var stealth: float = float(scout.get_skill(
		GameEnums.Skill.STEALTH, deployment.mission.mission_type))
	var worth: float = clampf((stealth - 40.0) / 7.0, 1.5, 7.0)
	var danger := 6.0

	return {
		"title": "A patrol on the only way in",
		"line": "%s has eyes on four men sitting across the approach. They are not looking for anybody, and they are not moving either. %s" % [
			scout.display_label(), _standing_odds(deployment)],
		"options": [
			{
				"label": "Have %s clear them" % scout.display_label(),
				"detail": "%s. Danger +%d — four men missing gets noticed." % [
					_odds(deployment, worth), int(danger)],
				"apply": func() -> String:
					deployment.apply_modifier(
						"%s cleared the approach" % scout.display_label(), worth)
					deployment.raise_risk(danger)
					deployment.note("%s took the patrol off the approach before first light." % (
						scout.display_label()))
					return "The route is open. %s" % _now(deployment),
			},
			{
				"label": "Hold until they move on",
				"detail": "One more day in the field, and the fatigue that comes with it. Nothing else changes.",
				"apply": func() -> String:
					deployment.extend(1)
					deployment.note("They lay up a full day waiting for the approach to clear.")
					return "The squad went to ground. They land a day later than planned.",
			},
		],
	}


static func _bigger_than_briefed(
	campaign: Campaign,
	deployment: Deployment,
	_rng: RandomNumberGenerator
) -> Dictionary:
	var danger := 12.0
	var regroup := -3.0
	var fee: int = int(round(float(
		deployment.mission.fee_for(campaign.state.reputation)) * Balance.FAILURE_REWARD_RATIO))

	return {
		"title": "There are more of them than the brief said"
		,
		"line": "Nobody cased this contract, and it shows: the strength on the ground is roughly three times what the client wrote down. %s" % (
			_standing_odds(deployment)),
		"options": [
			{
				"label": "Press on regardless",
				"detail": "Danger +%d. The odds do not move — the job is the same job." % int(danger),
				"apply": func() -> String:
					deployment.raise_risk(danger)
					deployment.note("They pressed on into numbers nobody had counted.")
					return "They are going in as planned, against three times the brief.",
			},
			{
				"label": "Break off and go again at dawn",
				"detail": "%s. One more day in the field, and they lose the initiative." % (
					_odds(deployment, regroup)),
				"apply": func() -> String:
					deployment.apply_modifier("Surprise lost regrouping", regroup)
					deployment.extend(1)
					deployment.note("They pulled back at contact and went in again the next night.")
					return "They are going again at dawn. %s" % _now(deployment),
			},
			{
				"label": "Call the contract off",
				"detail": "It ends now, unfinished: %s instead of the full fee, and %s is told why. Everyone breaks contact and comes home." % [
					TextUtil.count(fee, "diamond"), deployment.mission.client_name()],
				"apply": func() -> String:
					deployment.note("The company called the contract off rather than send them in against those numbers.")
					campaign.abort_deployment(deployment)
					return "They are coming home. The contract is closed unfinished.",
			},
		],
	}


static func _weather_closing_in(
	campaign: Campaign,
	deployment: Deployment,
	_rng: RandomNumberGenerator
) -> Dictionary:
	var state := campaign.state
	var region := deployment.mission.region()
	var exposed := _uncovered(deployment)
	var hazard_phrase: String = GameEnums.hazard_phrase(region.hazard)
	var relief: float = float(exposed.size()) * Balance.HAZARD_SCORE
	var cost: int = 260 + 70 * exposed.size()
	var danger := 8.0

	return {
		"title": "The ground is turning on them",
		"line": "%s of them went out with nothing for %s, and it is getting worse rather than better. Something can be bought and flown up, or they can put their heads down and carry on. %s" % [
			TextUtil.number_capitalised(exposed.size()), hazard_phrase,
			_standing_odds(deployment)],
		"options": [
			{
				"label": "Push through it",
				"detail": "Danger +%d, and the people without kit carry it." % int(danger),
				"apply": func() -> String:
					deployment.raise_risk(danger)
					deployment.note("They worked through %s without the kit for it." % hazard_phrase)
					return "They are carrying on. Nothing was bought.",
			},
			{
				"label": "Buy what they need and get it to them",
				"detail": "%s. %s, danger −6." % [
					TextUtil.count(cost, "diamond"), _odds(deployment, relief)],
				"apply": func() -> String:
					if cost > state.diamonds:
						return "There was not enough in the account to buy anything."
					state.diamonds -= cost
					deployment.apply_modifier("Kit bought locally and brought up", relief)
					deployment.raise_risk(-6.0)
					deployment.note("Kit was bought locally and driven out to them overnight.")
					return "It reached them before dark. %s" % _now(deployment),
			},
		],
	}


static func _worn_out_operator(
	_campaign: Campaign,
	deployment: Deployment,
	_rng: RandomNumberGenerator
) -> Dictionary:
	var op := _worn_out(deployment)
	var worth: float = deployment.report.contribution_of(op)
	var danger := 7.0

	return {
		"title": "%s is finished" % op.display_label(),
		"line": "%s was run down before this started and is now holding the rest of them up. They can be walked back to the extraction point, or the squad can slow to their pace. %s" % [
			op.display_label(), _standing_odds(deployment)],
		"options": [
			{
				"label": "Send them back",
				"detail": "%s — everything they were contributing. They come home unharmed." % (
					_odds(deployment, -worth)),
				"apply": func() -> String:
					deployment.pull_out(op)
					deployment.note("%s was walked back to the extraction point and sat out the rest." % (
						op.display_label()))
					return "%s is out of it and safe. %s" % [op.display_label(), _now(deployment)],
			},
			{
				"label": "They finish the contract",
				"detail": "Danger +%d for everybody, and %s comes back considerably worse." % [
					int(danger), op.display_label()],
				"apply": func() -> String:
					deployment.raise_risk(danger)
					op.fatigue = clampi(op.fatigue + 12, 0, 100)
					deployment.note("%s stayed in, and the squad moved at their pace." % (
						op.display_label()))
					return "%s is staying in. The whole squad is slower for it." % op.display_label(),
			},
		],
	}


static func _rivals_on_the_radio(
	_campaign: Campaign,
	deployment: Deployment,
	rng: RandomNumberGenerator
) -> Dictionary:
	var pair := _rivals(deployment)
	var one: OperatorData = pair[0]
	var two: OperatorData = pair[1]
	var leader: OperatorData = deployment.squad.leader
	var split := -4.0
	var settled := 5.0
	var soured := -7.0

	# The leader the player picked is the whole reason this option exists, so the
	# odds it works are theirs and are stated rather than hidden.
	var leadership: float = float(leader.get_skill(
		GameEnums.Skill.LEADERSHIP, deployment.mission.mission_type))
	var holds: float = clampf(leadership / 100.0, 0.2, 0.9)

	return {
		"title": "They are having it out on the radio",
		"line": "%s and %s are arguing on an open net, in country, with the objective two hours away. %s is asking whether to intervene. %s" % [
			one.display_label(), two.display_label(), leader.display_label(),
			_standing_odds(deployment)],
		"options": [
			{
				"label": "Split them up for the rest of it",
				"detail": "%s. Quiet, and the rivalry is exactly where it was." % _odds(deployment, split),
				"apply": func() -> String:
					deployment.apply_modifier(
						"%s and %s working apart" % [one.display_label(), two.display_label()],
						split)
					deployment.note("They were split up and worked opposite ends of the objective.")
					return "They finished the contract apart. %s" % _now(deployment),
			},
			{
				"label": "Let %s settle it" % leader.display_label(),
				"detail": "%s leadership holds it %d%% of the time: %s. It does not: %s, and both of them sour." % [
					TextUtil.possessive(leader.display_label()), int(round(holds * 100.0)),
					_odds(deployment, settled), _odds(deployment, soured)],
				"apply": func() -> String:
					if rng.randf() < holds:
						deployment.apply_modifier(
							"%s put a stop to it" % leader.display_label(), settled)
						one.morale = clampi(one.morale + 5, 0, 100)
						two.morale = clampi(two.morale + 5, 0, 100)
						deployment.note("%s put a stop to it, and it stayed stopped." % (
							leader.display_label()))
						return "%s ended it in one sentence. %s" % [
							leader.display_label(), _now(deployment)]
					deployment.apply_modifier(
						"The argument never ended", soured)
					one.morale = maxi(0, one.morale - 8)
					two.morale = maxi(0, two.morale - 8)
					deployment.note("The argument ran the whole contract and everybody heard it.")
					return "It did not hold. %s" % _now(deployment),
			},
		],
	}


static func _a_man_with_a_route(
	campaign: Campaign,
	deployment: Deployment,
	rng: RandomNumberGenerator
) -> Dictionary:
	var state := campaign.state
	var region := deployment.mission.region()
	var worth := 5.0
	var cost: int = rng.randi_range(450, 850)

	return {
		"title": "Somebody local, with a truck"
		,
		"line": "These are not people who know this ground, and it is costing them hours. A man who does knows the back road onto the objective and wants paying for it. %s" % (
			_standing_odds(deployment)),
		"options": [
			{
				"label": "Pay him",
				"detail": "%s. %s." % [TextUtil.count(cost, "diamond"), _odds(deployment, worth)],
				"apply": func() -> String:
					if cost > state.diamonds:
						return "There was not enough in the account to pay him."
					state.diamonds -= cost
					deployment.apply_modifier("A local who knows the ground", worth)
					deployment.note("A local was paid to put them on the back road through %s." % (
						region.place() if region != null else "the valley"))
					return "He took them in the back way. %s" % _now(deployment),
			},
			{
				"label": "Let them find it themselves",
				"detail": "One more day in the field, and no money changes hands.",
				"apply": func() -> String:
					deployment.extend(1)
					deployment.note("They spent a day finding the route the hard way.")
					return "They are working it out on their own. It costs them a day.",
			},
		],
	}


static func _crate_not_in_the_brief(
	campaign: Campaign,
	deployment: Deployment,
	rng: RandomNumberGenerator
) -> Dictionary:
	var state := campaign.state
	var client := deployment.mission.client()
	var found := _findable_item(deployment, rng)
	var weight := -3.0
	var standing := 4

	return {
		"title": "Somebody else's cargo",
		"line": "There is a crate on the objective that is not in anybody's brief. It holds %s, and it is heavy. %s" % [
			found.indefinite(), _standing_odds(deployment)],
		"options": [
			{
				"label": "Carry it out",
				"detail": "%s — dead weight all the way to extraction. %s comes home with them." % [
					_odds(deployment, weight), TextUtil.sentence_case(found.definite())],
				"apply": func() -> String:
					deployment.apply_modifier("Carrying %s out" % found.definite(), weight)
					deployment.carried_out.append(found.id)
					deployment.note("They carried %s away with them." % found.indefinite())
					return "They are taking it. %s" % _now(deployment),
			},
			{
				"label": "Burn it where it stands",
				"detail": "Nothing to sell, nothing to carry. %s will hear that the shipment never arrived: standing +%d." % [
					client.display_name, standing],
				"apply": func() -> String:
					state.adjust_standing(client.id, standing)
					deployment.note("The crate was burned where it stood.")
					return "It burned. %s will hear about it from their own people." % (
						client.display_name),
			},
		],
	}


static func _the_target_is_moving(
	_campaign: Campaign,
	deployment: Deployment,
	_rng: RandomNumberGenerator
) -> Dictionary:
	var mission := deployment.mission
	var rushed := -5.0
	var tightened := 6.0

	return {
		"title": "%s is leaving in the morning" % mission.target_name,
		"line": "The window everybody planned around has moved. %s, %s, is on a flight at first light — so it happens tonight, unprepared, or it happens later against a target who now travels carefully. %s" % [
			mission.target_name, mission.target_title, _standing_odds(deployment)],
		"options": [
			{
				"label": "Tonight, ready or not",
				"detail": "%s. No look at the ground, no rehearsal." % _odds(deployment, rushed),
				"apply": func() -> String:
					deployment.apply_modifier("Rushed: no look at the ground", rushed)
					deployment.note("They went that night, with no rehearsal and no second look.")
					return "It happens tonight. %s" % _now(deployment),
			},
			{
				"label": "Wait for a proper window",
				"detail": "One more day in the field, and difficulty rises to %d as the target's people tighten up. %s." % [
					int(round(mission.difficulty + tightened)),
					_odds(deployment, 0.0, tightened)],
				"apply": func() -> String:
					deployment.raise_difficulty(tightened)
					deployment.extend(1)
					deployment.note("They let the window go and waited for a better one.")
					return "They are waiting. %s" % _now(deployment),
			},
		],
	}


static func _the_brief_has_changed(
	campaign: Campaign,
	deployment: Deployment,
	rng: RandomNumberGenerator
) -> Dictionary:
	var state := campaign.state
	var client := deployment.mission.client()
	var harder := 7.0
	var bonus: int = rng.randi_range(700, 2200)
	var standing := 6

	return {
		"title": "%s wants one more thing" % client.display_name,
		"line": "%s is on the radio with an addition to the brief — something they say was always implied and is plainly not. It can be done, and it will cost the squad time on the objective. %s" % [
			client.display_name, _standing_odds(deployment)],
		"options": [
			{
				"label": "Take the extra work",
				"detail": "Difficulty rises to %d, and they pay %s for it. Standing +%d." % [
					int(round(deployment.mission.difficulty + harder)),
					TextUtil.count(bonus, "diamond"), standing],
				"apply": func() -> String:
					deployment.raise_difficulty(harder)
					state.diamonds += bonus
					state.adjust_standing(client.id, standing)
					deployment.note("The client added to the brief mid-contract, and the squad took it on.")
					return "They are doing both. %s" % _now(deployment),
			},
			{
				"label": "The contract is the contract",
				"detail": "Nothing changes on the ground. Standing -%d with %s." % [
					standing, client.display_name],
				"apply": func() -> String:
					state.adjust_standing(client.id, -standing)
					deployment.note("The client was reminded what they had actually paid for.")
					return "%s was read the contract back to them." % client.display_name,
			},
		],
	}


static func _people_in_the_way(
	campaign: Campaign,
	deployment: Deployment,
	_rng: RandomNumberGenerator
) -> Dictionary:
	var state := campaign.state
	var client := deployment.mission.client()
	var careful := -6.0
	var standing := 7
	var danger := 9.0

	return {
		"title": "There are people living on the objective",
		"line": "The objective has families in it — nobody's fault, nobody's fighters, and directly in the way of how this was planned. They can be moved out first, or the plan can go ahead as written. %s" % (
			_standing_odds(deployment)),
		"options": [
			{
				"label": "Clear them out first",
				"detail": "%s — it costs surprise and most of the night. %s will hear how it was handled: standing +%d." % [
					_odds(deployment, careful), client.display_name, standing],
				"apply": func() -> String:
					deployment.apply_modifier("Moving civilians out first", careful)
					state.adjust_standing(client.id, standing)
					deployment.note("They spent the night clearing families off the objective before anything started.")
					return "Everyone is out. %s" % _now(deployment),
			},
			{
				"label": "Go ahead as planned",
				"detail": "The odds do not move. Danger +%d, and %s will hear about it: standing -%d." % [
					int(danger), client.display_name, standing],
				"apply": func() -> String:
					deployment.raise_risk(danger)
					state.adjust_standing(client.id, -standing)
					deployment.note("The plan went ahead with the objective still occupied.")
					return "It went ahead as written.",
			},
		],
	}


static func _running_short(
	campaign: Campaign,
	deployment: Deployment,
	rng: RandomNumberGenerator
) -> Dictionary:
	var state := campaign.state
	var cost: int = rng.randi_range(600, 1200)
	var resupplied := 5.0
	var rationed := -6.0

	return {
		"title": "They are running short",
		"line": "Ammunition, water and batteries are all on the same list, and the list is nearly done. A drop can be arranged through somebody local, or they can make what they have last. %s" % (
			_standing_odds(deployment)),
		"options": [
			{
				"label": "Arrange a drop",
				"detail": "%s. %s." % [TextUtil.count(cost, "diamond"), _odds(deployment, resupplied)],
				"apply": func() -> String:
					if cost > state.diamonds:
						return "There was not enough in the account to arrange anything."
					state.diamonds -= cost
					deployment.apply_modifier("Resupplied in the field", resupplied)
					deployment.note("A resupply was bought locally and put in front of them overnight.")
					return "It reached them. %s" % _now(deployment),
			},
			{
				"label": "They make it last",
				"detail": "%s. No money changes hands and nobody is happy about it." % (
					_odds(deployment, rationed)),
				"apply": func() -> String:
					deployment.apply_modifier("Rationing ammunition and water", rationed)
					for op in _active(deployment):
						op.morale = maxi(0, op.morale - 4)
					deployment.note("They finished the contract on what they carried in.")
					return "They are making it last. %s" % _now(deployment),
			},
		],
	}


static func _extraction_is_burned(
	campaign: Campaign,
	deployment: Deployment,
	rng: RandomNumberGenerator
) -> Dictionary:
	var state := campaign.state
	var cost: int = rng.randi_range(900, 1800)
	var danger := 11.0

	return {
		"title": "The way out is no longer the way out",
		"line": "Somebody has put a checkpoint on the extraction route, and it is not moving. There is a boat that can be hired, or they can walk out the long way. %s" % (
			_standing_odds(deployment)),
		"options": [
			{
				"label": "Hire the boat",
				"detail": "%s. They come out clean, and the contract lands on time." % (
					TextUtil.count(cost, "diamond")),
				"apply": func() -> String:
					if cost > state.diamonds:
						return "There was not enough in the account to hire anything."
					state.diamonds -= cost
					deployment.note("The extraction was bought rather than fought for.")
					return "They are coming out by water. Nobody saw them go.",
			},
			{
				"label": "Walk out the long way",
				"detail": "One more day in the field, and danger +%d on the way." % int(danger),
				"apply": func() -> String:
					deployment.raise_risk(danger)
					deployment.extend(1)
					deployment.note("They walked out the long way rather than pay for a boat.")
					return "They are walking. It costs them a day and a good deal of luck.",
			},
		],
	}


# --- What the player is being quoted ------------------------------------------

## The one sentence every option owes the player: what it costs, in the units
## that are actually on screen.
##
## This used to read "Odds 58% → 64%". With the success percentage gone from
## every screen the player sees, quoting it here would be the leak that puts it
## back — a handful of field decisions is all it takes to learn what each band
## is worth in points and go back to optimising a number.
##
## So the price is quoted twice over, in the two units that survive. The squad
## score is exact and is on the breakdown the player read before they deployed;
## it is also literally the value of the `Modifier` this option will append, so
## the quote and the consequence cannot drift apart. The band says whether that
## amount of score is enough to change the company's read of the job, which is
## the part the raw figure does not answer.
static func _odds(
	deployment: Deployment,
	score_delta: float,
	difficulty_delta: float = 0.0
) -> String:
	var report := deployment.report
	var before: int = UiStyle.assessment_band(report)
	var after: int = UiStyle.assessment_band_for(MissionResolver.chance_for(
		report.squad_score + score_delta, report.difficulty + difficulty_delta))

	var parts: PackedStringArray = []
	if not is_zero_approx(score_delta):
		parts.append("Squad score %+.1f" % score_delta)
	if not is_zero_approx(difficulty_delta):
		parts.append("threat %+.1f" % difficulty_delta)

	# Against the ceiling — or the floor — points of score genuinely buy nothing,
	# and a band arrow pointing at itself reads as a broken label rather than as
	# the truth it is. Say what is actually happening instead.
	if after == before:
		parts.append("still reads %s" % UiStyle.assessment_word_for(before).to_lower())
	else:
		parts.append("%s → %s" % [
			UiStyle.assessment_word_for(before).to_lower(),
			UiStyle.assessment_word_for(after).to_lower()])
	return ", ".join(parts)


static func _standing_odds(deployment: Deployment) -> String:
	return "It reads %s from here." % UiStyle.assessment_word(deployment.report).to_lower()


static func _now(deployment: Deployment) -> String:
	return "It reads %s now." % UiStyle.assessment_word(deployment.report).to_lower()


# --- Conditions ---------------------------------------------------------------

## Everyone still on the contract. Somebody sent back earlier is not there to be
## written about.
static func _active(deployment: Deployment) -> Array:
	var members: Array = []
	for op in deployment.squad.members():
		if deployment.report.withdrawn.has(op):
			continue
		members.append(op)
	return members


static func _is_quiet_work(mission: MissionData) -> bool:
	return mission.mission_type in [
		GameEnums.MissionType.INFILTRATION,
		GameEnums.MissionType.RECON,
		GameEnums.MissionType.SABOTAGE,
		GameEnums.MissionType.ASSASSINATION,
	]


static func _best(deployment: Deployment, skill: int) -> OperatorData:
	var best: OperatorData = null
	for op in _active(deployment):
		if best == null or op.get_skill(skill) > best.get_skill(skill):
			best = op
	return best


## Everyone out there without the kit for what the ground does. The same test the
## resolver ran when it priced the hazard, so the two never disagree.
static func _uncovered(deployment: Deployment) -> Array:
	var region := deployment.mission.region()
	if region == null or region.hazard == GameEnums.Hazard.NONE:
		return []

	var exposed: Array = []
	for op in _active(deployment):
		var covered := false
		for item in op.equipment():
			if item.counters(region.hazard):
				covered = true
				break
		if not covered:
			exposed.append(op)
	return exposed


## The most worn-out person out there, if anybody is far enough gone to matter.
##
## Never the leader. Their contribution is read off the breakdown when they are
## pulled out, and the leadership term is a squad-level line that carries no
## operator id — so sending the commander home would take their skills off the
## score and leave the company still being scored for their leadership. Nobody
## walks the commander back anyway.
static func _worn_out(deployment: Deployment) -> OperatorData:
	var worst: OperatorData = null
	for op in _active(deployment):
		if op.fatigue < 55 or op == deployment.squad.leader:
			continue
		if worst == null or op.fatigue > worst.fatigue:
			worst = op
	return worst


static func _rivals(deployment: Deployment) -> Array:
	var members: Array = _active(deployment)
	for i in members.size():
		for j in range(i + 1, members.size()):
			if Bonds.bond_type(members[i], members[j]) == GameEnums.BondType.RIVALRY:
				return [members[i], members[j]]
	return []


## How well this squad reads the ground it was sent to, on the region's own
## measure. Below the middle of the range they are the wrong people for it, which
## the breakdown already told the player before they left.
static func _suits_the_ground(deployment: Deployment) -> float:
	var region := deployment.mission.region()
	if region == null:
		return 100.0

	var members: Array = _active(deployment)
	if members.is_empty():
		return 100.0

	var total := 0.0
	for op in members:
		total += float(op.get_skill(region.emphasis_skill, deployment.mission.mission_type))
	return total / float(members.size())


## Something plausible to find on a contract this hard. Same shelf the loot roll
## draws from: nothing blackmarket, and nothing better than the job deserves.
static func _findable_item(deployment: Deployment, rng: RandomNumberGenerator) -> ItemData:
	var candidates: Array[ItemData] = []
	var ceiling: int = 2 if deployment.mission.difficulty >= 70.0 else 1
	for id in ItemLibrary.all():
		var item: ItemData = ItemLibrary.all()[id]
		if item.source == ItemData.Source.BLACKMARKET or item.tier > ceiling:
			continue
		candidates.append(item)
	if candidates.is_empty():
		return ItemLibrary.all().values()[0]
	return candidates[rng.randi() % candidates.size()]
