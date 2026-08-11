class_name Campaign
extends RefCounted

## The rules engine: the only thing allowed to change GameState.
##
## Everything the player can do is a method here, and everything that happens
## because time passed happens in end_day(). UI calls these and listens to the
## signals; it never edits state directly. That is what keeps the game playable
## headlessly — tests/sim_campaign.gd drives this class with no scenes at all.

signal day_ended(day: int)
signal week_closed(week: int, payroll: int, balance: int)
signal squad_deployed(deployment: Deployment)
signal mission_resolved(report: MissionReport)
signal operator_recovered(op: OperatorData)
signal operator_died(op: OperatorData)
signal operator_hired(op: OperatorData)
signal operator_deserted(op: OperatorData)
signal operator_dismissed(op: OperatorData)
signal operator_promoted(op: OperatorData)
signal training_started(session: TrainingSession)
signal training_finished(session: TrainingSession, trainee_log: Array, mentor_log: Array)
signal facility_upgraded(id: StringName, level: int)
## Something has landed on the desk and wants an answer before the day is over.
signal incident_raised(incident: Dictionary)

signal intel_assigned(op: IntelOp)
signal intel_finished(op: IntelOp, result: Dictionary)
signal detachment_assigned(detachment: Detachment)
signal detachment_finished(detachment: Detachment, result: Dictionary)
signal scouting_started(mission: MissionData)
signal scouting_finished(mission: MissionData)
signal week_events(lines: Array)
signal item_bought(item: ItemData)
signal workshop_started(job: WorkshopJob)
signal workshop_finished(job: WorkshopJob)
signal board_refreshed()
signal bankrupt()

var state: GameState = null
var rng := RandomNumberGenerator.new()

## News raised mid-day (a call-up expiring, say) that the UI should show at the
## next natural break rather than interrupting the day.
var _pending_news: Array = []

## Day number of the last incident, so they do not land on consecutive days.
var _last_incident_day := -99

## The last incident's id, so the same one never lands twice running.
var _last_incident_id: StringName = &""


func _init(p_state: GameState = null, p_seed: int = -1) -> void:
	state = p_state if p_state != null else GameState.new()
	if p_seed >= 0:
		rng.seed = p_seed
	else:
		rng.randomize()


## Fresh company: a handful of operators, a board, and a pool of recruits.
func start_new_company(starting_operators: int = 5) -> void:
	state.roster = OperatorFactory.create_pool(rng, starting_operators)

	# The Armoury and Quartermaster start built. A market with nothing in it on
	# day one reads as a broken screen rather than a locked one, and the upkeep
	# is a fair price for the shop being usable immediately.
	state.facilities[FacilityLibrary.ARMOURY] = 1
	state.facilities[FacilityLibrary.QUARTERMASTER] = 1

	refresh_board()
	refresh_recruits()
	refresh_side_jobs()


## Callsigns already spoken for, so a new recruit never duplicates one.
func _taken_callsigns() -> Array:
	var taken: Array = []
	for op in state.roster:
		taken.append(op.callsign)
	for op in state.cemetery:
		taken.append(op.callsign)
	return taken


# --- Player actions ----------------------------------------------------------

func hire(op: OperatorData) -> bool:
	var cost := state.hire_cost(op)
	if cost > state.diamonds:
		return false
	if not state.recruits.has(op):
		return false

	state.diamonds -= cost
	state.recruits.erase(op)
	state.roster.append(op)
	operator_hired.emit(op)
	return true


## Let someone go. Costs a severance and upsets anyone who was close to them —
## firing a popular operator is a decision with a price, not a free delete.
func dismiss(op: OperatorData) -> bool:
	if state.is_deployed(op) or state.is_training(op) or state.is_detached(op):
		return false

	state.diamonds -= op.salary * Balance.SEVERANCE_WEEKS

	for other in state.roster:
		if other == op or not Bonds.has_bond(other, op):
			continue
		match Bonds.bond_type(other, op):
			GameEnums.BondType.ROMANCE:
				other.morale = maxi(0, other.morale + Balance.MORALE_ON_PARTNER_DEATH / 2)
			GameEnums.BondType.FRIENDSHIP:
				other.morale = maxi(0, other.morale + Balance.MORALE_ON_FRIEND_DEATH / 2)
			_:
				other.morale = mini(100, other.morale + 4)

	for other in state.roster:
		Bonds.remove(op, other)
	state.roster.erase(op)
	operator_dismissed.emit(op)
	return true


## Commit a squad to a contract. Returns the deployment, or null if the squad is
## not legal for it. The preview is taken here and frozen — see Deployment.
func deploy(squad: Squad, mission: MissionData) -> Deployment:
	if not squad.is_valid():
		return null
	if not state.board.has(mission):
		return null

	for op in squad.members():
		if op.career_track == GameEnums.CareerTrack.INSTRUCTOR:
			return null

	var report := preview_mission(squad, mission)
	var deployment := Deployment.create(mission, squad, report)

	for op in squad.members():
		op.status = GameEnums.OperatorStatus.ON_MISSION

	state.board.erase(mission)
	state.deployed_this_week += squad.size()
	state.deployments.append(deployment)
	squad_deployed.emit(deployment)
	return deployment


## The only preview the UI should call. Folds in the company-wide effects the
## resolver deliberately knows nothing about, so what the squad builder shows is
## exactly what gets rolled.
func preview_mission(squad: Squad, mission: MissionData) -> MissionReport:
	# Knowing the ground is worth nothing until a contract has actually been
	# cased — the doc describes it as scouting before the squad goes in, not a
	# passive company-wide buff. What it is worth was priced when the case
	# finished, because a desk look and a team on the ground are not worth the
	# same and the resolver should not have to know which happened.
	var intel := 0.0
	if mission.scouted:
		intel = mission.intel_bonus
	return MissionResolver.preview(squad, mission, intel)


## The strongest squad the company could actually field for this contract right
## now. Used by the board to answer "can we even do this" before the player
## spends five minutes building a squad to find out they cannot.
func best_available_squad(mission: MissionData) -> Squad:
	var profile := MissionResolver.profile_for(mission.mission_type)
	if profile == null:
		return Squad.new()

	var free := state.deployable_operators()
	if free.is_empty():
		return Squad.new()

	# Rank candidates by what they are worth on THIS job, then take as many as
	# the job actually calls for.
	var ranked: Array = []
	for op in free:
		var solo := Squad.new()
		solo.add(op)
		solo.set_leader(op)
		ranked.append({"op": op, "score": preview_mission(solo, mission).squad_score})
	ranked.sort_custom(func(a, b): return a["score"] > b["score"])

	var squad := Squad.new()
	for i in mini(profile.ideal_squad_size, ranked.size()):
		squad.add(ranked[i]["op"])
	if squad.size() > 0:
		squad.set_leader(ranked[0]["op"])
	return squad


# --- Scouting ----------------------------------------------------------------

func scout_days_for() -> int:
	var level := state.facility_level(FacilityLibrary.INTELLIGENCE)
	if level <= 0:
		return 0
	return maxi(1, Balance.SCOUT_BASE_DAYS - (level - 1))


func scout_cost() -> int:
	return state.facility_level(FacilityLibrary.INTELLIGENCE) * Balance.SCOUT_COST_PER_LEVEL


func can_scout(mission: MissionData) -> bool:
	return (
		state.facility_level(FacilityLibrary.INTELLIGENCE) > 0
		and not mission.scouted
		and not mission.is_being_scouted()
		and scout_cost() <= state.diamonds
	)


## Start casing a contract. Costs money now and days the contract may not have —
## the board keeps expiring while the scouts are out, which is the decision.
func scout(mission: MissionData) -> bool:
	if not can_scout(mission):
		return false
	state.diamonds -= scout_cost()
	mission.scout_days_remaining = scout_days_for()
	scouting_started.emit(mission)
	return true


# --- Standing work -----------------------------------------------------------

## Send one operator on a side job. No squad, no briefing — this is the bench
## earning its wages.
func assign_detachment(job: SideJobData, op: OperatorData) -> Detachment:
	if not state.side_jobs.has(job) or not op.is_deployable():
		return null
	if op.career_track == GameEnums.CareerTrack.INSTRUCTOR:
		return null

	op.status = GameEnums.OperatorStatus.ON_MISSION
	state.side_jobs.erase(job)

	var detachment := Detachment.create(job, op)
	state.detachments.append(detachment)
	detachment_assigned.emit(detachment)
	return detachment


## One decision on an ordinary day, or nothing.
##
## Deliberately fired BEFORE day_ended and the week close, so an incident that
## puts a contract on the board or takes someone off the roster is reflected in
## the numbers the player is about to look at rather than a day behind them.
func _roll_incident() -> void:
	if state.day - _last_incident_day < Balance.INCIDENT_COOLDOWN:
		return
	if rng.randf() >= Balance.INCIDENT_CHANCE:
		return

	var incident := IncidentLibrary.roll(self, rng, _last_incident_id)
	if incident.is_empty():
		return

	_last_incident_id = StringName(str(incident.get("id", "")))
	_last_incident_day = state.day
	incident_raised.emit(incident)


# --- Intel teams -------------------------------------------------------------

## Everyone who could be sent to case a contract right now.
##
## Instructors are out, as everywhere. Exhausted operators are NOT: casing is
## the one job a worn-out operator can still do, which gives the player
## something to do with people no contract will take.
func intel_candidates() -> Array[OperatorData]:
	var free: Array[OperatorData] = []
	for op in state.available_operators():
		if op.career_track == GameEnums.CareerTrack.INSTRUCTOR:
			continue
		free.append(op)
	return free


func intel_days_for(members: Array) -> int:
	return IntelOp.days_for(members, state.facility_level(FacilityLibrary.INTELLIGENCE))


func can_start_intel(mission: MissionData, members: Array) -> bool:
	if mission == null or members.is_empty():
		return false
	if members.size() > Balance.INTEL_MAX_TEAM:
		return false
	if mission.scouted or mission.is_being_scouted():
		return false
	if state.intel_op_for(mission) != null:
		return false
	for op: OperatorData in members:
		if not op.is_deployable() or op.career_track == GameEnums.CareerTrack.INSTRUCTOR:
			return false
	return true


## Send a team to case a contract. Costs no money and a great deal of time.
func assign_intel(mission: MissionData, members: Array) -> IntelOp:
	if not can_start_intel(mission, members):
		return null

	var team: Array[OperatorData] = []
	for op: OperatorData in members:
		op.status = GameEnums.OperatorStatus.ON_INTEL
		team.append(op)

	var intel := IntelOp.create(mission, team, intel_days_for(team))
	state.intel_ops.append(intel)
	intel_assigned.emit(intel)
	return intel


func _tick_intel() -> void:
	for intel: IntelOp in state.intel_ops.duplicate():
		intel.days_remaining -= 1
		if intel.days_remaining > 0:
			continue

		state.intel_ops.erase(intel)

		# The contract can expire while the team is out. They still come home;
		# the work is simply worth nothing, which is the risk of casing a job
		# that only had a few days left on it.
		var still_offered: bool = state.board.has(intel.mission)
		var result: Dictionary = {"lines": [], "bonus": 0.0, "noticed": false}
		if still_offered:
			result = intel.resolve(state, rng)
		else:
			result["lines"] = ["%s expired while the team was still out." % intel.mission.title]

		for op in intel.operators:
			if op.status == GameEnums.OperatorStatus.ON_INTEL:
				op.status = GameEnums.OperatorStatus.AVAILABLE

		var went_well: bool = still_offered and not bool(result.get("noticed", false))
		for line in result.get("lines", []):
			_pending_news.append({
				"title": "Intel",
				"line": line,
				"good": went_well,
			})

		intel_finished.emit(intel, result)


func _tick_detachments() -> void:
	# Annotated because duplicate() hands back an untyped Array, and an untyped
	# loop variable cannot infer the return of resolve().
	for detachment: Detachment in state.detachments.duplicate():
		detachment.days_remaining -= 1
		if detachment.days_remaining > 0:
			continue

		state.detachments.erase(detachment)
		var result: Dictionary = detachment.resolve(rng)
		state.diamonds += int(result["pay"])

		# resolve() may have put them in the infirmary; only send them back to
		# duty if it did not.
		if detachment.operator.status == GameEnums.OperatorStatus.ON_MISSION:
			detachment.operator.status = GameEnums.OperatorStatus.AVAILABLE

		detachment_finished.emit(detachment, result)


## One birthday a year, staggered by id so the whole roster does not age on the
## same day. Past a point the body starts going: COMBAT, STEALTH and ENDURANCE
## slip, while judgement does not — which is exactly the pressure that makes the
## instructor track worth taking.
func _tick_birthdays() -> void:
	for op in state.roster:
		var offset: int = absi(String(op.id).hash()) % Balance.DAYS_PER_YEAR
		if (state.day + offset) % Balance.DAYS_PER_YEAR != 0:
			continue

		op.age += 1
		if not op.is_ageing():
			continue

		for skill in [
			GameEnums.Skill.COMBAT,
			GameEnums.Skill.STEALTH,
			GameEnums.Skill.ENDURANCE,
		]:
			var before: int = int(op.skills.get(skill, 0))
			op.skills[skill] = maxi(5, before - Balance.AGE_DECLINE_PER_YEAR)

		_pending_news.append({
			"title": "%s turned %d" % [op.display_label(), op.age],
			"line": "Not as quick as they were. Still knows more than anyone you could hire.",
			"good": false,
		})


func _tick_side_job_board() -> void:
	for job in state.side_jobs.duplicate():
		job.expires_in_days -= 1
		if job.expires_in_days <= 0:
			state.side_jobs.erase(job)


func refresh_side_jobs() -> void:
	var taken: Array = []
	for job in state.side_jobs:
		taken.append(job.title)
	while state.side_jobs.size() < Balance.SIDE_JOB_BOARD_SIZE:
		var job := SideJobFactory.create(rng, taken)
		taken.append(job.title)
		state.side_jobs.append(job)


# --- Retainers ---------------------------------------------------------------

func retainer_offer(faction_id: StringName) -> int:
	var faction := FactionLibrary.get_faction(faction_id)
	if faction == null:
		return 0
	var standing := state.standing_with(faction_id)
	return int(round(
		Balance.RETAINER_BASE_WEEKLY * faction.pay_multiplier * (float(standing) / 100.0)
	))


func can_offer_retainer(faction_id: StringName) -> bool:
	return (
		not state.retainers.has(faction_id)
		and state.standing_with(faction_id) >= Balance.RETAINER_MIN_STANDING
	)


func accept_retainer(faction_id: StringName) -> bool:
	if not can_offer_retainer(faction_id):
		return false
	state.retainers[faction_id] = retainer_offer(faction_id)
	return true


## Walking away is cheaper than failing a call-up, but the client remembers.
func cancel_retainer(faction_id: StringName) -> bool:
	if not state.retainers.has(faction_id):
		return false
	state.retainers.erase(faction_id)
	state.adjust_standing(faction_id, Balance.RETAINER_CANCEL_STANDING)
	return true


## A retained client can demand work at short notice. This is what the money was
## for, and refusing costs more than the week's payment was worth.
func _roll_call_ups() -> Array:
	var news: Array = []
	for faction_id in state.retainers.keys():
		if rng.randf() >= Balance.RETAINER_CALLUP_CHANCE:
			continue

		var taken: Array = []
		for mission in state.board:
			taken.append(mission.title)

		var call_up := MissionFactory.create(rng, -1, -1, taken)
		call_up.client_id = faction_id
		call_up.is_call_up = true
		call_up.expires_in_days = Balance.RETAINER_CALLUP_DAYS
		var faction := FactionLibrary.get_faction(faction_id)
		if faction != null:
			call_up.reward_diamonds = int(round(
				float(call_up.reward_diamonds) * faction.pay_multiplier))
		state.board.append(call_up)

		news.append({
			"title": "%s is calling in the retainer" % FactionLibrary.faction_name(faction_id),
			"line": "\"%s\" must be accepted within %s or the contract is void." % [
				call_up.title, TextUtil.count(Balance.RETAINER_CALLUP_DAYS, "day")],
			"good": false,
		})
	return news


## Charged when a call-up rots on the board.
func _penalise_refusal(mission: MissionData) -> Dictionary:
	state.diamonds -= Balance.RETAINER_REFUSAL_FINE
	state.adjust_standing(mission.client_id, Balance.RETAINER_REFUSAL_STANDING)
	return {
		"title": "%s was left waiting" % mission.client_name(),
		"line": "\"%s\" expired unanswered. A %d diamond penalty, and they will remember." % [
			mission.title, Balance.RETAINER_REFUSAL_FINE],
		"good": false,
	}


# --- Passive production ------------------------------------------------------

## An upgraded Armoury or Quartermaster turns out surplus of its own. The doc
## calls it residual income — it is meant to be sold, not equipped, which is why
## it produces whatever tier it likes rather than what the player needs.
func _roll_production() -> Array:
	var news: Array = []
	for facility_id in [FacilityLibrary.ARMOURY, FacilityLibrary.QUARTERMASTER]:
		var level := state.facility_level(facility_id)
		if level < Balance.PRODUCTION_MIN_LEVEL:
			continue
		var chance: float = float(
			level - Balance.PRODUCTION_MIN_LEVEL + 1) * Balance.PRODUCTION_CHANCE_PER_LEVEL
		if rng.randf() >= chance:
			continue
		if not state.has_storage_room():
			continue

		var source: int = (
			ItemData.Source.ARMOURY if facility_id == FacilityLibrary.ARMOURY
			else ItemData.Source.QUARTERMASTER)
		var candidates := ItemLibrary.stock_for(source, level, state.reputation)
		if candidates.is_empty():
			continue

		var made: ItemData = candidates[rng.randi() % candidates.size()]
		state.inventory.append(ItemInstance.create(made.id))
		news.append({
			"title": "%s surplus" % FacilityLibrary.get_facility(facility_id).display_name,
			"line": "The line turned out %s more than the company needs this week. It will sell." % (
				made.indefinite()),
			"good": true,
		})
	return news


func _tick_scouting() -> void:
	for mission in state.board:
		if mission.scout_days_remaining <= 0:
			continue
		mission.scout_days_remaining -= 1
		if mission.scout_days_remaining <= 0:
			mission.scouted = true
			mission.intel_bonus = maxf(
				mission.intel_bonus,
				state.facility_effect(FacilityLibrary.INTELLIGENCE) * Balance.SCOUT_BONUS_FACTOR)
			scouting_finished.emit(mission)


# --- Base and market ---------------------------------------------------------

func upgrade_facility(id: StringName) -> bool:
	var facility := FacilityLibrary.get_facility(id)
	if facility == null:
		return false

	var level := state.facility_level(id)
	if facility.is_maxed(level):
		return false

	var cost := facility.cost_to_upgrade(level)
	if cost > state.diamonds:
		return false

	state.diamonds -= cost
	state.facilities[id] = level + 1
	facility_upgraded.emit(id, level + 1)
	return true


func buy_item(item: ItemData) -> bool:
	if item == null or item.price > state.diamonds:
		return false
	if not state.has_storage_room():
		return false
	if not _is_in_stock(item):
		return false

	state.diamonds -= item.price
	state.inventory.append(ItemInstance.create(item.id))
	item_bought.emit(item)
	return true


## Selling back recovers part of the price — kit the company no longer needs is
## a source of cash when the week has gone badly. What it fetches depends on the
## state it is in: nobody pays full second-hand money for a worn-out carrier.
func sell_item(instance: ItemInstance) -> bool:
	if instance == null or not state.inventory.has(instance):
		return false
	if not state.is_spare(instance):
		return false

	state.inventory.erase(instance)
	state.diamonds += resale_value(instance)
	return true


func resale_value(instance: ItemInstance) -> int:
	if instance == null:
		return 0
	var quality: float = Balance.SCRAP_CONDITION_FLOOR + (
		1.0 - Balance.SCRAP_CONDITION_FLOOR) * (instance.condition / Balance.CONDITION_NEW)
	return int(round(float(instance.price()) * Balance.RESALE_RATIO * quality))


## The oldest loose copy of a type, for the handful of callers that still think
## in item ids — events taking kit, and the harness.
func spare_of(item_id: StringName) -> ItemInstance:
	for instance in state.inventory:
		if instance.item_id == item_id and state.is_spare(instance):
			return instance
	return null


func _is_in_stock(item: ItemData) -> bool:
	match item.source:
		ItemData.Source.BLACKMARKET:
			return state.reputation >= item.reputation_required
		ItemData.Source.ARMOURY:
			return item.tier <= state.facility_level(FacilityLibrary.ARMOURY)
		ItemData.Source.QUARTERMASTER:
			return item.tier <= state.facility_level(FacilityLibrary.QUARTERMASTER)
		_:
			# Blueprint kit is never on a shelf. The only way to hold one is to
			# have found the plans and built it.
			return false


## Hands a specific copy to an operator, taking it off whoever had it.
##
## A copy rather than a type, because "issue them a carbine" is not a complete
## instruction once the company owns a new one and a worn one.
func equip(op: OperatorData, instance: ItemInstance, slot: int) -> bool:
	if instance != null:
		if instance.slot() != slot or not state.inventory.has(instance):
			return false
		if not state.is_spare(instance):
			return false
		# Kit that gives nothing and still costs them stealth is not a loadout,
		# it is a mistake waiting to be made. The workshop is the answer.
		if not instance.is_serviceable():
			return false

	op.set_slot_instance(slot, instance)
	return true


## Convenience for anything that only knows the type: takes the best copy that
## is free. The harness and the after-action screen both work this way.
func equip_by_id(op: OperatorData, item_id: StringName, slot: int) -> bool:
	if item_id == &"":
		return equip(op, null, slot)
	var best: ItemInstance = null
	for instance in state.available_items(slot):
		if instance.item_id == item_id and (best == null or instance.condition > best.condition):
			best = instance
	return equip(op, best, slot)


# --- The workshop ------------------------------------------------------------
#
# The last system in the design doc: the Armoury and Quartermaster repair kit
# and build it from blueprints found as loot. Both cost a bench, and a bench is
# the scarce thing — whatever is being worked on is not on a contract.

## Put a copy on a bench. Money is charged now, days are charged from here on.
func start_repair(instance: ItemInstance) -> bool:
	if not Workshop.can_repair(state, instance):
		return false

	var facility_id := Workshop.facility_for_instance(instance)
	var cost := Workshop.repair_cost(instance)
	var days := Workshop.repair_days(state, instance)
	var job := WorkshopJob.repair(instance, facility_id, days, cost)

	# Taken off whoever was carrying it, and noted so it goes straight back to
	# them. The cost of a repair is that they are without it for a few days, not
	# that the player has to remember to reissue it afterwards.
	var holder := state.holder_of(instance)
	if holder != null:
		job.borrowed_from = holder.id
		holder.set_slot_instance(instance.slot(), null)

	state.diamonds -= cost
	state.workshop.append(job)
	workshop_started.emit(job)
	return true


## Strip a copy for parts. It is gone — this is the end of that rifle — and the
## parts are what the next one gets built out of.
func scrap_item(instance: ItemInstance) -> int:
	if not Workshop.can_scrap(state, instance):
		return 0
	if not state.inventory.has(instance):
		return 0

	var parts := Workshop.scrap_value(instance)
	state.inventory.erase(instance)
	state.salvage += parts
	return parts


## Book a build against a blueprint the company holds.
func start_craft(item_id: StringName) -> bool:
	var item := ItemLibrary.get_item(item_id)
	if not Workshop.can_craft(state, item):
		return false

	state.salvage -= item.craft_salvage
	state.diamonds -= item.craft_price
	var days := Workshop.craft_days(state, item)
	state.workshop.append(
		WorkshopJob.craft(item.id, item.craft_facility, days, item.craft_price, item.craft_salvage))
	workshop_started.emit(state.workshop[state.workshop.size() - 1])
	return true


## Plans, once seen, are known for good.
func learn_blueprint(item_id: StringName) -> bool:
	var item := ItemLibrary.get_item(item_id)
	if item == null or not item.is_craftable() or state.knows_blueprint(item_id):
		return false
	state.blueprints.append(item_id)
	return true


func _tick_workshop() -> void:
	for job: WorkshopJob in state.workshop.duplicate():
		job.days_remaining -= 1
		if job.days_remaining > 0:
			continue

		state.workshop.erase(job)

		if job.kind == WorkshopJob.Kind.REPAIR:
			# Back to this copy's ceiling, and the ceiling itself drops. A
			# rebuilt rifle is never a new one, which is what stops repair being
			# an infinite loop and gives crafting something to be for.
			job.instance.repair()

			# Straight back to whoever it came off, if they are still here and
			# their hands are still empty. If they filled the slot meanwhile,
			# that was a decision and it stands — the item goes on the rack.
			var owner := state.find_operator(job.borrowed_from)
			var returned := ""
			if owner != null and owner.slot_instance(job.instance.slot()) == null:
				owner.set_slot_instance(job.instance.slot(), job.instance)
				returned = " Back with %s." % owner.display_label()

			_pending_news.append({
				"title": "Back in service",
				"line": "%s came off the bench at %d%%.%s" % [
					TextUtil.sentence_case(job.definite()),
					int(round(job.instance.condition)), returned],
				"good": true,
			})
		else:
			# Storage can have filled while it was being built. The parts and the
			# money are already spent, so the item waits rather than evaporating:
			# it goes in as soon as there is room, and until then the news says so.
			if not state.has_storage_room():
				state.workshop.append(job)
				job.days_remaining = 1
				_pending_news.append({
					"title": "Nowhere to put it",
					"line": "%s %s finished and storage is full, so it stays on the bench." % [
						TextUtil.sentence_case(job.definite()), job.verb_is()],
					"good": false,
				})
				continue
			state.inventory.append(ItemInstance.create(job.item_id))
			_pending_news.append({
				"title": "Built in-house",
				"line": "%s came off the bench. Nobody sells these." % (
					TextUtil.sentence_case(job.definite())),
				"good": true,
			})

		workshop_finished.emit(job)


## The player's "end turn". Everything that costs days moves one day closer.
func end_day() -> void:
	state.day += 1

	_tick_birthdays()
	_tick_deployments()
	_tick_detachments()
	_tick_intel()
	_tick_training()
	_tick_recovery()
	_tick_scouting()
	_tick_workshop()
	_tick_board()
	_tick_side_job_board()

	_roll_incident()
	day_ended.emit(state.day)

	if state.day_of_week() == 1 and state.day > 1:
		_close_week()

	if not _pending_news.is_empty():
		week_events.emit(_pending_news.duplicate())
		_pending_news.clear()


# --- Time ---------------------------------------------------------------------

func _tick_deployments() -> void:
	# Iterate a copy: resolving a deployment removes it from the list.
	for deployment in state.deployments.duplicate():
		deployment.days_remaining -= 1
		if deployment.days_remaining <= 0:
			_resolve(deployment)
			continue
		_roll_field_event(deployment)


## The squad calls in with something the briefing did not cover.
##
## Only while they are still out: a radio call and the debrief on the same day
## would arrive in the wrong order, and a decision with no days left to run is
## not a decision. One per contract — see Balance.FIELD_EVENTS_PER_DEPLOYMENT.
func _roll_field_event(deployment: Deployment) -> void:
	if deployment.fired_events.size() >= Balance.FIELD_EVENTS_PER_DEPLOYMENT:
		return
	if rng.randf() >= Balance.FIELD_EVENT_CHANCE:
		return

	var event := FieldEventLibrary.roll(self, deployment, rng)
	if event.is_empty():
		return

	deployment.fired_events.append(StringName(str(event.get("id", ""))))

	# The desk keeps quiet on a day the field called. Two modals in a row over
	# one day's end is the sort of thing that makes a player stop reading them,
	# and of the two the squad in the country is the one that matters.
	_last_incident_day = state.day
	incident_raised.emit(event)


## The player pulls the plug on a contract that is already running.
##
## A failure, and priced as one — part fee, reputation, the client told why —
## but not the same failure as being beaten: breaking contact deliberately is
## far less likely to cost somebody their life than losing does.
func abort_deployment(deployment: Deployment) -> bool:
	if not state.deployments.has(deployment):
		return false
	_resolve(deployment, true)
	return true


func _resolve(deployment: Deployment, withdrawal: bool = false) -> void:
	var report := MissionResolver.roll(deployment.report, rng, withdrawal)
	state.deployments.erase(deployment)
	# Reputation moves the fee, through the same helper the board and briefing
	# quote from, so the payout matches what was advertised.
	var full_fee := report.mission.fee_for(state.reputation)
	report.reward_paid = (
		full_fee if report.success
		else int(round(float(full_fee) * Balance.FAILURE_REWARD_RATIO))
	)
	state.diamonds += report.reward_paid

	# Bonds evolve before the casualties are applied, so a pair that both came
	# home is judged on the contract they actually shared.
	report.bond_log = Bonds.evolve_after_mission(report, rng)

	var dead: Array = report.casualties()

	for op in deployment.squad.members():
		var fate: int = report.fates.get(op, GameEnums.Fate.UNHARMED)
		var rank_before: int = op.rank_step()

		_apply_condition(op, report, fate, dead)

		if report.success:
			op.missions_completed += 1
		else:
			op.missions_failed += 1

		# XP, skill growth, traits and promotion all happen here, and the report
		# carries the change log so the after-action screen can show it.
		# The Psychologist cannot undo what happened — the doc is explicit that a
		# trait is part of who they are now — but it makes a scar less likely to
		# form in the first place.
		report.progression[op] = Progression.apply_mission_result(
			op, report, rng, state.facility_effect(FacilityLibrary.PSYCHOLOGIST))
		if op.rank_step() > rank_before:
			operator_promoted.emit(op)

		match fate:
			GameEnums.Fate.KILLED:
				op.status = GameEnums.OperatorStatus.DEAD
				op.died_on_day = state.day
				op.died_on_mission = report.mission.title
				# Stored as it reads in a sentence — "the Kunar Valley" — because
				# the only thing that ever prints it is the headstone.
				op.died_in_region = report.mission.region_place()
				state.roster.erase(op)
				state.cemetery.append(op)
				operator_died.emit(op)
			GameEnums.Fate.WOUNDED, GameEnums.Fate.TRAUMATIZED:
				op.status = GameEnums.OperatorStatus.INJURED
				var days: int = int(report.recovery_days.get(op, 1))
				# The Infirmary shortens physical recovery; the Psychologist
				# shortens the other kind. Neither ever reaches zero.
				var relief: float = state.facility_effect(
					FacilityLibrary.PSYCHOLOGIST if fate == GameEnums.Fate.TRAUMATIZED
					else FacilityLibrary.INFIRMARY)
				op.days_unavailable = maxi(1, int(round(float(days) * (1.0 - relief))))
			_:
				op.status = GameEnums.OperatorStatus.AVAILABLE

	# After everyone's morale has been settled — the hit for losing a friend is
	# computed above and needs the bond to still exist when it runs.
	for lost in dead:
		Bonds.detach(lost, state.roster)

	_wear_kit(deployment, report, dead)
	_award_saves(report)
	_award_loot(report)
	_award_salvage(report)
	_award_blueprint(report)
	_land_carried_kit(deployment, report)
	_award_trophy(report)
	_award_medals(report)
	report.story = MissionStory.write(report, rng)
	_settle_reputation(report, dead.size())
	_settle_client(report, dead.size())
	mission_resolved.emit(report)


## Standing with the specific client who commissioned this. A no-casualties
## client punishes losses savagely; everyone else mostly cares whether the job
## got done.
func _settle_client(report: MissionReport, casualties: int) -> void:
	var client := report.mission.client()
	if client == null:
		return

	var change := 0
	if report.success:
		change += client.standing_per_contract
	else:
		change += Balance.CLIENT_STANDING_ON_FAILURE

	if client.preference == FactionData.Preference.CLEAN_HANDS and casualties > 0:
		change += casualties * Balance.CLIENT_CLEAN_HANDS_CASUALTY

	state.adjust_standing(client.id, change)
	report.client_standing_change = change


## A medic in the squad pulls someone out. Only fires when there was actually
## someone to pull out, so the line in the feed is always true.
func _award_saves(report: MissionReport) -> void:
	var medic: OperatorData = null
	for op in report.squad.members():
		if report.squad.role_of(op) != GameEnums.Role.MEDIC:
			continue
		if report.fates.get(op, GameEnums.Fate.UNHARMED) == GameEnums.Fate.KILLED:
			continue
		medic = op
		break
	if medic == null:
		return

	for op in report.squad.members():
		if op == medic:
			continue
		if report.fates.get(op, GameEnums.Fate.UNHARMED) != GameEnums.Fate.WOUNDED:
			continue
		medic.saves += 1
		medic.morale = mini(100, medic.morale + Balance.SAVE_MORALE)
		op.morale = mini(100, op.morale + Balance.SAVED_MORALE)
		report.saves[medic] = op
		# Both names, because this reason is read off either operator's sheet and
		# "kept them alive" is ambiguous from the medic's side.
		Bonds.link(medic, op, GameEnums.BondType.FRIENDSHIP,
			Balance.BOND_STRENGTH_GAIN,
			"%s kept %s alive on %s." % [
				medic.display_label(), op.display_label(), report.mission.title])
		return


## Killing is its own reward, up to a point. Capped so a bloodbath does not
## produce a euphoric squad.
func _award_kill_morale(report: MissionReport) -> void:
	for op in report.kills:
		if report.fates.get(op, GameEnums.Fate.UNHARMED) == GameEnums.Fate.KILLED:
			continue
		var gain: int = mini(
			int(report.kills[op]) * Balance.KILL_MORALE_PER, Balance.KILL_MORALE_CAP)
		op.morale = mini(100, op.morale + gain)


## What the contract did to the kit that went on it.
##
## Every term traces to something the player chose — how long the job was, how
## dangerous, and whether it came off — which is what keeps wear a consequence
## rather than a tax. Kit signed back in off somebody who did not come home is
## recovered rather than lost: a rifle outliving the person who earned its
## reputation is the point, and burying an operator is expensive enough already.
func _wear_kit(deployment: Deployment, report: MissionReport, dead: Array) -> void:
	var base := Workshop.wear_for(report.mission, not report.success)

	for op in deployment.squad.members():
		var killed: bool = dead.has(op)
		for item in op.equipment():
			var was_serviceable: bool = item.is_serviceable()
			item.contracts += 1
			item.wear(base + (Balance.WEAR_ON_DEATH if killed else 0.0))
			if was_serviceable and not item.is_serviceable():
				report.kit_notes.append(
					"%s came back unserviceable, and cannot be issued to anybody until the workshop has had a look."
					% TextUtil.sentence_case(item.definite()))

		if not killed:
			continue

		# The company takes its kit back. Clearing the slots rather than leaving
		# the headstone holding a rifle keeps one rule true everywhere: exactly
		# one living operator can be carrying any given copy.
		for item in op.equipment():
			report.kit_notes.append("%s %s signed back in off %s, in the state you would expect." % [
				TextUtil.sentence_case(item.definite()), item.verb_was(), op.display_label()])
		op.weapon = null
		op.gear = null


## Parts off a finished job. Success only: salvage is what gets stripped out of
## a position the squad actually held at the end of it.
func _award_salvage(report: MissionReport) -> void:
	if not report.success:
		return
	var parts: int = int(round(report.mission.difficulty * Balance.SALVAGE_PER_DIFFICULTY))
	if parts <= 0:
		return
	state.salvage += parts
	report.salvage_gained = parts


## Plans for something no shop stocks. Hard contracts only, and never for a
## blueprint the company already holds — a second copy of knowledge is nothing.
func _award_blueprint(report: MissionReport) -> void:
	if not report.success:
		return
	if report.mission.difficulty < Balance.BLUEPRINT_MIN_DIFFICULTY:
		return
	if rng.randf() >= Balance.BLUEPRINT_CHANCE:
		return

	var unknown: Array[ItemData] = []
	for item in ItemLibrary.blueprints():
		if not state.knows_blueprint(item.id):
			unknown.append(item)
	if unknown.is_empty():
		return

	var found: ItemData = unknown[rng.randi() % unknown.size()]
	learn_blueprint(found.id)
	report.blueprint_found = found.id


## What the squad carried home. Only on success, only if there is room, and
## weighted low — loot supplements the fee rather than replacing it.
func _award_loot(report: MissionReport) -> void:
	if not report.success:
		return
	if rng.randf() >= Balance.LOOT_CHANCE:
		return
	if not state.has_storage_room():
		return

	var candidates: Array[ItemData] = []
	for id in ItemLibrary.all():
		var item: ItemData = ItemLibrary.all()[id]
		# Harder contracts turn up better kit; nothing blackmarket, because that
		# shelf is supposed to be earned through reputation, and nothing built
		# from plans, because those are supposed to be built.
		if item.source == ItemData.Source.BLACKMARKET or item.is_craftable():
			continue
		if item.tier > (2 if report.mission.difficulty >= 70.0 else 1):
			continue
		candidates.append(item)

	if candidates.is_empty():
		return
	var found: ItemData = candidates[rng.randi() % candidates.size()]
	state.inventory.append(_found_copy(found.id))
	report.loot.append(found.id)


## Kit picked up in the field has already had a life. It arrives usable and
## worn, which is what makes the workshop worth walking to rather than a chore
## bolted onto a free gift.
func _found_copy(item_id: StringName) -> ItemInstance:
	return ItemInstance.create(item_id, rng.randf_range(
		Balance.LOOT_CONDITION_MIN, Balance.LOOT_CONDITION_MAX))


## Anything the squad decided to carry out with them, landed when they land.
##
## Not when they found it: an item sitting in the warehouse while the people
## holding it are still in a valley is a lie the inventory screen would tell.
func _land_carried_kit(deployment: Deployment, report: MissionReport) -> void:
	for id in deployment.carried_out:
		if not state.has_storage_room():
			return
		state.inventory.append(_found_copy(id))
		report.loot.append(id)


## Medals, checked against the whole record after every contract.
func _award_medals(report: MissionReport) -> void:
	_award_kill_morale(report)

	var desperate: bool = report.success and report.chance_percent() <= 25
	for op in report.squad.members():
		if report.fates.get(op, GameEnums.Fate.UNHARMED) == GameEnums.Fate.KILLED:
			continue
		var took_trophy: bool = (
			not report.trophy_line.is_empty()
			and report.trophy_line.begins_with(op.display_label()))
		var earned := MedalLibrary.award_earned(op, desperate, took_trophy)
		if earned.is_empty():
			continue
		var existing: Array = report.progression.get(op, [])
		existing.append_array(earned)
		report.progression[op] = existing


## A named target, killed. The doc asks for this to feel like a trophy, so it is
## recorded on the operator forever, lifts the whole company's morale, and lifts
## the person who did it enormously — this is how a roster produces a legend.
func _award_trophy(report: MissionReport) -> void:
	if report.mission.mission_type != GameEnums.MissionType.ASSASSINATION:
		return
	if not report.success or report.mission.target_name.is_empty():
		return

	var candidates: Array = []
	for op in report.squad.members():
		if report.fates.get(op, GameEnums.Fate.UNHARMED) != GameEnums.Fate.KILLED:
			candidates.append(op)
	if candidates.is_empty():
		return

	# The marksman gets it if there is one; otherwise whoever shot best.
	var killer: OperatorData = candidates[0]
	for op in candidates:
		var is_marksman: bool = report.squad.role_of(op) == GameEnums.Role.MARKSMAN
		var best_is_marksman: bool = report.squad.role_of(killer) == GameEnums.Role.MARKSMAN
		if is_marksman and not best_is_marksman:
			killer = op
		elif is_marksman == best_is_marksman 				and op.get_skill(GameEnums.Skill.COMBAT) > killer.get_skill(GameEnums.Skill.COMBAT):
			killer = op

	var trophy: String = "%s, %s — %s" % [
		report.mission.target_name,
		TextUtil.with_article(report.mission.target_title),
		report.mission.region_name()]
	killer.trophies.append(trophy)
	killer.morale = mini(100, killer.morale
		+ Balance.TROPHY_MORALE_KILLER + Balance.TROPHY_MORALE_LEGEND)

	for op in state.roster:
		if op != killer:
			op.morale = mini(100, op.morale + Balance.TROPHY_MORALE_COMPANY)

	state.reputation = clampi(state.reputation + Balance.TROPHY_REPUTATION, 0, 100)
	report.trophy_line = "%s killed %s, %s, in %s." % [
		killer.display_label(),
		report.mission.target_name,
		TextUtil.with_article(report.mission.target_title),
		report.mission.region_place()]


## What the client tells the next client. Failing costs more than succeeding
## earns, and losing people looks bad either way.
func _settle_reputation(report: MissionReport, casualties: int) -> void:
	var change := 0.0
	if report.success:
		change += Balance.REPUTATION_ON_SUCCESS
		change += report.mission.difficulty * Balance.REPUTATION_DIFFICULTY_FACTOR
	else:
		change += Balance.REPUTATION_ON_FAILURE
	change += float(casualties) * Balance.REPUTATION_PER_CASUALTY

	state.reputation = clampi(state.reputation + int(round(change)), 0, 100)
	report.reputation_change = int(round(change))


## Fatigue from the contract, and how they took it. Losing someone they were
## close to is the heaviest single thing that happens to an operator here.
func _apply_condition(
	op: OperatorData,
	report: MissionReport,
	fate: int,
	dead: Array
) -> void:
	if fate == GameEnums.Fate.KILLED:
		return

	var days: int = report.mission.duration_days
	var gained: float = (
		float(days) * Balance.FATIGUE_PER_DEPLOYED_DAY
		+ report.mission.risk * Balance.FATIGUE_RISK_FACTOR
	)
	op.fatigue = clampi(op.fatigue + int(round(gained)), 0, 100)

	var morale_change: int = (
		Balance.MORALE_ON_SUCCESS if report.success else Balance.MORALE_ON_FAILURE
	)
	if fate == GameEnums.Fate.WOUNDED or fate == GameEnums.Fate.TRAUMATIZED:
		morale_change += Balance.MORALE_ON_WOUND

	for lost in dead:
		if not Bonds.has_bond(op, lost):
			continue
		match Bonds.bond_type(op, lost):
			GameEnums.BondType.ROMANCE:
				morale_change += Balance.MORALE_ON_PARTNER_DEATH
			GameEnums.BondType.FRIENDSHIP:
				morale_change += Balance.MORALE_ON_FRIEND_DEATH
			_:
				morale_change += Balance.MORALE_ON_RIVAL_DEATH

	op.morale = clampi(op.morale + morale_change, 0, 100)
	report.morale_change[op] = morale_change


## Put a trainee under a mentor. Both go off the board for the duration.
func start_training(mentor: OperatorData, trainee: OperatorData) -> TrainingSession:
	if not Progression.can_train(mentor, trainee):
		return null
	if state.is_training(mentor) or state.is_training(trainee):
		return null

	mentor.status = GameEnums.OperatorStatus.TRAINING
	trainee.status = GameEnums.OperatorStatus.TRAINING

	# The Academy shortens the class, which is the part that actually hurts —
	# two operators off the board for a week.
	var academy: float = state.facility_effect(FacilityLibrary.ACADEMY)
	var days: int = maxi(3, int(round(float(Balance.TRAINING_DAYS) * (1.0 - academy * 0.4))))

	var session := TrainingSession.create(mentor, trainee, days)
	state.training.append(session)
	training_started.emit(session)
	return session


## One-way: the field closes and the instructor ranks open.
func promote_to_instructor(op: OperatorData) -> bool:
	if not Progression.can_become_instructor(op):
		return false
	op.career_track = GameEnums.CareerTrack.INSTRUCTOR
	operator_promoted.emit(op)
	return true


func _tick_training() -> void:
	for session in state.training.duplicate():
		session.days_remaining -= 1
		if session.days_remaining > 0:
			continue

		state.training.erase(session)
		var result := Progression.apply_training(
			session.mentor, session.trainee, rng,
			state.facility_effect(FacilityLibrary.ACADEMY))

		# Only return them to duty if nothing else claimed them meanwhile.
		for op in [session.mentor, session.trainee]:
			if op.status == GameEnums.OperatorStatus.TRAINING:
				op.status = GameEnums.OperatorStatus.AVAILABLE

		training_finished.emit(session, result["trainee"], result["mentor"])


func _tick_recovery() -> void:
	for op in state.roster:
		# Rest only counts at base. Deployed and training operators do not
		# recover, which is what stops training being a free rest cure.
		if op.status != GameEnums.OperatorStatus.ON_MISSION \
				and op.status != GameEnums.OperatorStatus.TRAINING:
			op.fatigue = maxi(0, op.fatigue - Balance.FATIGUE_RECOVERY_PER_DAY)

		if op.days_unavailable <= 0:
			continue
		op.days_unavailable -= 1
		if op.days_unavailable <= 0:
			op.days_unavailable = 0
			op.status = GameEnums.OperatorStatus.AVAILABLE
			operator_recovered.emit(op)


## Contracts do not wait. Letting the board rot is itself a decision — and for a
## retained client's call-up it is an expensive one.
func _tick_board() -> void:
	for mission in state.board.duplicate():
		mission.expires_in_days -= 1
		if mission.expires_in_days > 0:
			continue
		state.board.erase(mission)
		if mission.is_call_up and state.retainers.has(mission.client_id):
			_pending_news.append(_penalise_refusal(mission))


## What being unable to pay for the base actually costs.
##
## A week in the red is a warning. Two in a row and something gets let go: the
## most expensive facility drops a level, refunding a little and cutting the
## upkeep that could not be met. Without this the base was a one-way ratchet and
## the economy stopped mattering the moment the last facility was bought.
func _settle_upkeep(missed_payroll: bool) -> void:
	if not missed_payroll:
		state.weeks_in_debt = 0
		return

	state.weeks_in_debt += 1
	if state.weeks_in_debt < Balance.UPKEEP_GRACE_WEEKS:
		_pending_news.append({
			"title": "The books are red",
			"line": "The week closed short. Another like it and something in the base goes.",
			"good": false,
		})
		return

	var worst: StringName = &""
	var worst_upkeep := 0
	for id in state.facilities:
		var level: int = int(state.facilities[id])
		if level <= 0:
			continue
		var facility := FacilityLibrary.get_facility(id)
		if facility == null:
			continue
		var upkeep: int = facility.upkeep_at(level)
		if upkeep > worst_upkeep:
			worst_upkeep = upkeep
			worst = id

	if worst == &"":
		_pending_news.append({
			"title": "Nothing left to sell",
			"line": "The company is in debt and there is no base left to cut.",
			"good": false,
		})
		return

	var facility := FacilityLibrary.get_facility(worst)
	var level: int = int(state.facilities[worst])
	state.facilities[worst] = level - 1
	state.diamonds += int(round(float(facility.cost_to_upgrade(level - 1)) * 0.4))
	state.weeks_in_debt = 0

	_pending_news.append({
		"title": "Something had to go",
		"line": "Two weeks short. The %s was cut back to level %d to stop the bleeding." % [
			facility.display_name, level - 1],
		"good": false,
	})


func _close_week() -> void:
	# The whole bill, not just wages: rations, ammunition, medical and the base
	# itself. This is the budget sheet the design doc asks for, and it is the
	# reason a big roster and a big base are decisions rather than upgrades.
	var bill := Economy.weekly_costs(state)
	var total: int = int(bill["total"])
	state.diamonds -= total
	state.deployed_last_week = state.deployed_this_week
	state.deployed_this_week = 0

	# Retainers pay whether or not anyone went anywhere. That is the whole
	# proposition — and the call-ups below are the price of it.
	var retainer_pay := state.retainer_income()
	if retainer_pay > 0:
		state.diamonds += retainer_pay

	var missed_payroll: bool = state.diamonds < 0
	_settle_upkeep(missed_payroll)

	_settle_morale(missed_payroll)
	_check_desertions()

	# The boards are rebuilt FIRST. Events run after, because some of them add to
	# those pools — a prodigy walking in appends to the recruit list, and doing
	# that before refresh_recruits() wiped them in the same tick. The news said
	# someone had turned up and the tab was empty.
	refresh_board()
	refresh_recruits()
	refresh_side_jobs()

	# Everything that happens "over the week" is gathered into one bulletin, so
	# the player reads it in one place instead of guessing what changed.
	_pending_news.append_array(_roll_call_ups())
	_pending_news.append_array(_roll_production())
	var event := _roll_event_news()
	if not event.is_empty():
		_pending_news.append(event)

	# The day counter has already rolled into the new week by the time this runs,
	# so the week that just CLOSED is the one before it.
	week_closed.emit(state.week() - 1, total, state.diamonds)

	# Debt is the fail state. Nothing enforces it yet beyond the signal — v0.5
	# decides whether that means game over or operators walking out.
	if state.diamonds < 0:
		bankrupt.emit()


## One roll a week. Whether anything happens, and whether it is good news,
## both depend on the state the player has put the company in.
func _roll_event_news() -> Dictionary:
	var entry := EventLibrary.roll(state, rng)
	if entry.is_empty():
		return {}

	var line := EventLibrary.apply(entry, self, rng)
	if line.is_empty():
		return {}

	return {
		"title": entry["title"],
		"line": line,
		"good": entry["polarity"] == EventLibrary.Polarity.GOOD,
	}


## Nothing stays raw forever: morale drifts back toward neutral each week. If the
## week's wages could not be paid, everyone feels it at once.
func _settle_morale(missed_payroll: bool) -> void:
	for op in state.roster:
		if missed_payroll:
			op.morale = clampi(op.morale + Balance.MORALE_UNPAID, 0, 100)
			continue

		# The Canteen pushes morale up rather than merely letting it drift back,
		# so a well-fed company can sit above neutral instead of tending to it.
		var canteen: int = int(state.facility_effect(FacilityLibrary.CANTEEN))
		if canteen > 0:
			op.morale = clampi(op.morale + canteen, 0, 100)

		if op.morale < Balance.MORALE_NEUTRAL:
			op.morale = mini(op.morale + Balance.MORALE_DRIFT_PER_WEEK, Balance.MORALE_NEUTRAL)
		elif op.morale > Balance.MORALE_NEUTRAL and canteen <= 0:
			op.morale = maxi(op.morale - Balance.MORALE_DRIFT_PER_WEEK, Balance.MORALE_NEUTRAL)


## People who have had enough walk. The threshold is well above the chance of
## it actually happening, so the roster flags someone as considering it for
## weeks before they go — a warning the player can still act on.
func _check_desertions() -> void:
	for op in state.roster.duplicate():
		if op.morale > Balance.MORALE_DESERTION_THRESHOLD:
			continue
		if state.is_deployed(op) or state.is_training(op):
			continue
		if rng.randf() >= Balance.DESERTION_CHANCE:
			continue

		# Leaving cuts the bonds, so nobody keeps a friendship with a ghost.
		for other in state.roster:
			Bonds.remove(op, other)
		state.roster.erase(op)
		operator_deserted.emit(op)


# --- Board and recruits ------------------------------------------------------

## Tops the board back up rather than replacing it, so a contract the player is
## saving for does not vanish on the week boundary.
func refresh_board() -> void:
	while state.board.size() < GameState.BOARD_SIZE:
		var taken: Array = []
		for mission in state.board:
			taken.append(mission.title)
		state.board.append(
			MissionFactory.create_for_board(rng, state.faction_standing, taken))
	board_refreshed.emit()


## Recruits DO get replaced every week: the people on offer move on if you do
## not sign them. This is the assumption behind the hiring screen — an XCOM-style
## refreshing pool rather than a persistent list you scout over time.
func refresh_recruits() -> void:
	state.recruits = OperatorFactory.create_pool(
		rng, GameState.RECRUIT_POOL_SIZE, _taken_callsigns()
	)
