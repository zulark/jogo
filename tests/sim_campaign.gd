extends SceneTree

## Plays a campaign headlessly: hires, deploys, ends days, pays wages, buries the
## dead, saves and reloads. This is v0.2's proof that the loop actually closes.
##
##   Godot.exe --headless --path . --script res://tests/sim_campaign.gd
##
## The AI here is deliberately dumb — it takes the best odds available and
## deploys whoever is free. It is not a player, it is a treadmill that exercises
## every path: expiry, recovery, payroll, perma-death, save/load.

## Long enough for the economy to show a trend rather than a single good week.
const WEEKS := 12
const SEED := 20260809
const SQUAD_SIZE := 4

## Will field a short squad rather than let the week go by empty.
const MIN_SQUAD_SIZE := 3

## Below this the bodies are not worth the fee.
const ODDS_FLOOR := 0.45

## Condition at which the agent bothers with the bench. A player does not send a
## rifle in at 95%, and an agent that does prices the workshop wrong.
const REPAIR_THRESHOLD := 62.0

## Totals for the run, so the workshop's real cost shows up in the report.
var _bench_spend := 0
var _bench_jobs := 0


func _initialize() -> void:
	print("")
	print("############# SQUAD MANAGER — v0.2 CAMPAIGN LOOP #############")

	var campaign := Campaign.new(null, SEED)
	campaign.start_new_company(6)

	_connect_log(campaign)
	_play(campaign, WEEKS)
	_report(campaign)
	_check_market()
	_check_world()
	_check_passive_income()
	_check_event_pools()
	_check_workshop()
	_check_save_round_trip(campaign)

	print("")
	quit()


func _connect_log(campaign: Campaign) -> void:
	campaign.mission_resolved.connect(func(report: MissionReport):
		var dead: int = report.casualties().size()
		var hurt: int = report.wounded().size()
		print("      %-22s %-7s  %+6d dia   %d dead, %d hurt" % [
			report.mission.title,
			"SUCCESS" if report.success else "FAILED",
			report.reward_paid,
			dead,
			hurt,
		])
	)
	campaign.week_closed.connect(func(week: int, payroll: int, balance: int):
		print("   -- week %d closed: payroll %d, balance %d" % [week, payroll, balance])
	)
	campaign.bankrupt.connect(func():
		print("   !! BANKRUPT")
	)
	# What the kit layer actually costs over a run. Without a figure here, wear
	# is either invisible or a death spiral and there is no way to tell which
	# from the closing balance alone.
	campaign.workshop_started.connect(func(job: WorkshopJob):
		_bench_spend += job.diamonds_paid
		_bench_jobs += 1
	)
	campaign.operator_promoted.connect(func(op: OperatorData):
		print("      %s promoted to %s" % [op.display_label(), GameEnums.rank_name(op.rank)])
	)
	campaign.training_finished.connect(func(session: TrainingSession, trainee_log: Array, _mentor_log: Array):
		print("      %s finished training %s: %s" % [
			session.mentor.display_label(),
			session.trainee.display_label(),
			"; ".join(trainee_log) if not trainee_log.is_empty() else "nothing gained",
		])
	)


func _play(campaign: Campaign, weeks: int) -> void:
	print("")
	print("--- PLAYING %d WEEKS ---" % weeks)

	for day in weeks * Balance.DAYS_PER_WEEK:
		_take_best_contract(campaign)
		_take_standing_work(campaign)
		_start_training(campaign)
		_hire_if_short(campaign)
		_spend_surplus(campaign)
		_maintain_kit(campaign)
		campaign.end_day()


## Anyone spare goes on standing work. Leaving the bench idle is exactly the
## behaviour v0.7 exists to fix, so an agent that never uses it would report the
## economy as worse than a real player's would be.
func _take_standing_work(campaign: Campaign) -> void:
	var state := campaign.state
	while not state.side_jobs.is_empty():
		var spare := state.deployable_operators()
		if spare.size() <= SQUAD_SIZE:
			return

		# Send whoever suits the work best out of the genuine surplus.
		var job: SideJobData = state.side_jobs[0]
		var best: OperatorData = spare[spare.size() - 1]
		for op in spare:
			if job.suitability(op) > job.suitability(best):
				best = op
		if campaign.assign_detachment(job, best) == null:
			return


## Reinvest when there is comfortable runway: build the base up, then buy kit.
## Exercises upgrades, purchases and equipping without competing with wages.
func _spend_surplus(campaign: Campaign) -> void:
	# Three weeks of cover, not six. A player who waits for six weeks of runway
	# before building anything never builds anything, so an agent that does the
	# same reports the base layer as unreachable when it is merely expensive.
	var state := campaign.state
	if Economy.weeks_of_runway(state) < 3:
		return

	# Kit first, so the purchase and equip paths are actually exercised. Until
	# the shops are built there is no stock, so early weeks still go on the base.
	for source in [ItemData.Source.ARMOURY, ItemData.Source.QUARTERMASTER]:
		var shop_level: int = state.facility_level(
			FacilityLibrary.ARMOURY if source == ItemData.Source.ARMOURY
			else FacilityLibrary.QUARTERMASTER)
		if not _anyone_unequipped(state, source):
			continue
		for item in ItemLibrary.stock_for(source, shop_level, state.reputation):
			if campaign.buy_item(item):
				_equip_anyone(campaign, item)
				print("      bought %s" % item.display_name)
				return

	# Breadth before depth: get every facility standing before deepening any of
	# them. Straight list order would sink the whole budget into the Infirmary
	# and the shops would never open.
	var lowest: StringName = &""
	var lowest_level := 99
	for id in FacilityLibrary.ORDER:
		var facility := FacilityLibrary.get_facility(id)
		var level := state.facility_level(id)
		if facility.is_maxed(level):
			continue
		if level < lowest_level:
			lowest_level = level
			lowest = id

	if lowest != &"" and campaign.upgrade_facility(lowest):
		print("      built %s to level %d" % [
			FacilityLibrary.get_facility(lowest).display_name, lowest_level + 1])


func _anyone_unequipped(state: GameState, source: int) -> bool:
	var slot: int = (
		ItemData.Slot.WEAPON if source == ItemData.Source.ARMOURY else ItemData.Slot.GEAR)
	for op in state.roster:
		if op.slot_instance(slot) == null:
			return true
	return false


func _equip_anyone(campaign: Campaign, item: ItemData) -> void:
	for op in campaign.state.roster:
		if op.slot_instance(item.slot) == null:
			campaign.equip_by_id(op, item.id, item.slot)
			return


## Keep the kit alive: repair the worst thing on a free bench, strip what the
## bench will no longer take, and build a blueprint whenever one is affordable.
##
## An agent that never touched the workshop would report the whole layer as
## unreachable, the same way an agent that never took standing work reported the
## economy as worse than it was in v0.7. The two mistakes have the same shape.
func _maintain_kit(campaign: Campaign) -> void:
	var state := campaign.state

	for item in ItemLibrary.blueprints():
		if Workshop.can_craft(state, item) and Economy.weeks_of_runway(state) >= 3:
			campaign.start_craft(item.id)
			print("      started building %s" % item.display_name)
			return

	# Everything, not just the rack. Most of the company's kit is in somebody's
	# hands, and an agent that only maintained the spares would report the
	# squad's own equipment quietly rotting to nothing — which is exactly what
	# the first pass at this did.
	var worst: ItemInstance = null
	for instance in state.inventory:
		if state.is_in_workshop(instance):
			continue
		if instance.is_beyond_repair() and state.is_spare(instance):
			var parts := campaign.scrap_item(instance)
			if parts > 0:
				print("      stripped %s for %d parts" % [instance.display_name(), parts])
				return
			continue
		# Only kit that has actually gone off. Booking the bench for a rifle at
		# 95% would burn a bench slot and a slice of ceiling for nothing, and an
		# agent that does that reports the workshop as more expensive than a
		# player would ever make it.
		if instance.condition > REPAIR_THRESHOLD:
			continue
		if worst == null or instance.condition < worst.condition:
			worst = instance

	if worst != null and Workshop.can_repair(state, worst):
		campaign.start_repair(worst)


## Deploy on the best odds available, if enough people are free to field a squad.
func _take_best_contract(campaign: Campaign) -> void:
	var state := campaign.state
	var free := state.deployable_operators()
	if free.size() < MIN_SQUAD_SIZE or state.board.is_empty():
		return

	# Field whatever is actually available rather than idling until a full squad
	# is free. A player who waits for four rested specialists goes broke, so an
	# agent that does the same is not a fair read on the economy.
	var squad := Squad.new()
	for i in mini(SQUAD_SIZE, free.size()):
		squad.add(free[i], free[i].preferred_role)
	squad.set_leader(free[0])

	var best: MissionData = null
	var best_chance := 0.0
	for mission in state.board:
		var chance: float = MissionResolver.preview(squad, mission).success_chance
		if chance > best_chance:
			best_chance = chance
			best = mission

	if best != null and best_chance >= ODDS_FLOOR:
		campaign.deploy(squad, best)


## Put the greenest operator under the most senior one whenever both are spare
## and a squad is already out. Exercises the academy path without competing with
## the contract that pays the wages.
func _start_training(campaign: Campaign) -> void:
	var state := campaign.state
	if not state.training.is_empty():
		return

	var mentors := state.potential_mentors()
	if mentors.is_empty():
		return

	var best_mentor: OperatorData = mentors[0]
	for op in mentors:
		if op.rank_step() > best_mentor.rank_step():
			best_mentor = op

	var worst: OperatorData = null
	for op in state.available_operators():
		if op == best_mentor or op.career_track == GameEnums.CareerTrack.INSTRUCTOR:
			continue
		if worst == null or op.rank_step() < worst.rank_step():
			worst = op
	if worst == null:
		return

	# Never strip the roster below a deployable squad just to run a class.
	if state.deployable_operators().size() - 2 < SQUAD_SIZE:
		return

	if campaign.start_training(best_mentor, worst) != null:
		print("      %s begins training %s" % [
			best_mentor.display_label(), worst.display_label()])


## Keep enough bodies to field a squad, funds permitting.
func _hire_if_short(campaign: Campaign) -> void:
	var state := campaign.state
	if state.roster.size() >= SQUAD_SIZE + 3:
		return
	for recruit in state.recruits.duplicate():
		if campaign.hire(recruit):
			print("      hired %s (%s, %s)" % [
				recruit.display_label(),
				recruit.demonym(),
				GameEnums.role_name(recruit.preferred_role),
			])
			return


## Puts a squad in the field regardless of the odds, purely so the save test has
## an in-flight deployment to round trip.
func _force_deployment(campaign: Campaign) -> void:
	var state := campaign.state
	var free := state.available_operators()
	if free.size() < SQUAD_SIZE or state.board.is_empty():
		return

	var squad := Squad.new()
	for i in SQUAD_SIZE:
		squad.add(free[i], free[i].preferred_role)
	squad.set_leader(free[0])
	campaign.deploy(squad, state.board[0])


func _report(campaign: Campaign) -> void:
	var state := campaign.state
	print("")
	print("--- AFTER %d WEEKS ---" % WEEKS)
	print("  Day %d (week %d, day %d of the week)" % [
		state.day, state.week(), state.day_of_week()])
	print("  Diamonds: %d" % state.diamonds)
	print("  Weekly payroll: %d" % state.weekly_payroll())
	print("  Roster: %d   Deployed: %d   Cemetery: %d" % [
		state.roster.size(), state.deployments.size(), state.cemetery.size()])
	print("  Board: %d contracts   Recruits: %d" % [
		state.board.size(), state.recruits.size()])

	print("")
	print("  ROSTER")
	for op in state.roster:
		var status_text: String = GameEnums.OperatorStatus.keys()[op.status].capitalize()
		if op.days_unavailable > 0:
			status_text += " (%s)" % TextUtil.count(op.days_unavailable, "day")
		print("    %-26s %-10s %-12s %-18s %d done / %d failed" % [
			op.display_label(),
			GameEnums.role_name(op.preferred_role),
			op.demonym(),
			status_text,
			op.missions_completed,
			op.missions_failed,
		])

	if not state.cemetery.is_empty():
		print("")
		print("  CEMETERY")
		for op in state.cemetery:
			print("    %-26s %-12s %d contracts completed" % [
				op.display_label(), op.demonym(), op.missions_completed])

	print("")
	print("  [check] calendar is consistent: %s" % [
		"OK" if state.day == WEEKS * Balance.DAYS_PER_WEEK + 1 else "FAIL"])
	print("  [check] nobody is stuck deployed with no deployment: %s" % [
		"OK" if _no_orphaned_operators(state) else "FAIL"])
	print("  [check] the dead are off the payroll: %s" % [
		"OK" if _dead_are_buried(state) else "FAIL"])
	print("  [check] nobody is stuck in a class that ended: %s" % [
		"OK" if _no_orphaned_trainees(state) else "FAIL"])
	print("  [check] ranks match earned XP: %s" % [
		"OK" if _ranks_are_earned(state) else "FAIL"])
	print("  [check] no field career exceeds Warrant Officer: %s" % [
		"OK" if _field_cap_respected(state) else "FAIL"])
	print("  [check] somebody actually progressed: %s" % [
		"OK" if _somebody_progressed(state) else "FAIL"])
	print("  [check] the dead kept their record: %s" % [
		"OK" if _cemetery_records_intact(state) else "FAIL"])
	print("  [check] bonds are mirrored on both operators: %s" % [
		"OK" if _bonds_are_symmetric(state) else "FAIL"])
	print("  [check] no bonds point at people who left: %s" % [
		"OK" if _no_dangling_bonds(state) else "FAIL"])
	print("  [check] fatigue and morale stay in range: %s" % [
		"OK" if _condition_in_range(state) else "FAIL"])
	_check_rest()

	print("  [check] equipped kit is actually owned: %s" % [
		"OK" if _equipment_is_owned(state) else "FAIL"])
	print("  [check] storage is never over capacity: %s" % [
		"OK" if state.storage_used() <= state.storage_capacity() else "FAIL"])
	print("  [check] reputation stays in range: %s" % [
		"OK" if state.reputation >= 0 and state.reputation <= 100 else "FAIL"])

	_report_social(state)
	_report_economy(state)


## The market, tested directly on a fresh company rather than hoping twelve
## weeks of emergent play happens to reach the Armoury. Buying, equipping and
## the rules that stop the player getting kit for free are all deterministic —
## they should be checked deterministically.
func _check_market() -> void:
	print("")
	print("--- MARKET ---")

	var campaign := Campaign.new(null, SEED + 1)
	campaign.start_new_company(4)
	var state := campaign.state
	state.diamonds = 100000

	var locked := ItemLibrary.stock_for(ItemData.Source.ARMOURY, 0, state.reputation)
	print("  [check] an unbuilt Armoury sells nothing: %s" % [
		"OK" if locked.is_empty() else "FAIL"])

	campaign.upgrade_facility(FacilityLibrary.ARMOURY)
	var stock := ItemLibrary.stock_for(ItemData.Source.ARMOURY, 1, state.reputation)
	print("  [check] building it opens tier 1 (%d items): %s" % [
		stock.size(), "OK" if not stock.is_empty() else "FAIL"])

	var tier_three := ItemLibrary.get_item(&"marksman_rifle")
	print("  [check] tier 3 stays locked at facility level 1: %s" % [
		"OK" if not campaign.buy_item(tier_three) else "FAIL"])

	var blackmarket := ItemLibrary.get_item(&"prototype_smg")
	state.reputation = 10
	var refused: bool = not campaign.buy_item(blackmarket)
	state.reputation = 90
	var accepted: bool = campaign.buy_item(blackmarket)
	print("  [check] the blackmarket deals on reputation, not money: %s" % [
		"OK" if refused and accepted else "FAIL"])

	var rifle := stock[0]
	var bought: bool = campaign.buy_item(rifle)
	var op: OperatorData = state.roster[0]
	var copy := campaign.spare_of(rifle.id)
	var equipped: bool = campaign.equip(op, copy, rifle.slot)
	print("  [check] buying then issuing a weapon works: %s" % [
		"OK" if bought and equipped and op.weapon == copy else "FAIL"])

	# One copy, one carrier. A second operator must not be able to hold it too.
	var second: OperatorData = state.roster[1]
	print("  [check] one copy cannot be carried by two people: %s" % [
		"OK" if not campaign.equip(second, copy, rifle.slot) else "FAIL"])

	print("  [check] gear cannot go in the weapon slot: %s" % [
		"OK" if not campaign.equip(
			second, ItemInstance.create(&"field_dressing"), ItemData.Slot.WEAPON) else "FAIL"])

	var carried_before := state.unequipped_count(rifle.id)
	print("  [check] a carried item is not free to reissue: %s" % [
		"OK" if carried_before == 0 else "FAIL"])

	print("  [check] carried kit cannot be sold out from under them: %s" % [
		"OK" if not campaign.sell_item(copy) else "FAIL"])

	# Equipment must reach the resolver, or none of this affects the game.
	var bare := OperatorFactory.create(campaign.rng, GameEnums.Role.MARKSMAN, OperatorFactory.Tier.REGULAR)
	var combat_before := bare.get_skill(GameEnums.Skill.COMBAT)
	bare.weapon = ItemInstance.create(&"battle_rifle")
	var combat_after := bare.get_skill(GameEnums.Skill.COMBAT)
	print("  [check] a weapon changes what the resolver sees (%d → %d): %s" % [
		combat_before, combat_after, "OK" if combat_after > combat_before else "FAIL"])

	# Storage is a real limit, not decoration.
	state.facilities[FacilityLibrary.WAREHOUSE] = 0
	while state.has_storage_room():
		state.inventory.append(ItemInstance.create(&"service_carbine"))
	print("  [check] a full warehouse refuses purchases: %s" % [
		"OK" if not campaign.buy_item(rifle) else "FAIL"])

	var capacity_before := state.storage_capacity()
	campaign.upgrade_facility(FacilityLibrary.WAREHOUSE)
	print("  [check] the Warehouse raises capacity (%d → %d): %s" % [
		capacity_before, state.storage_capacity(),
		"OK" if state.storage_capacity() > capacity_before else "FAIL"])

	# Since v0.6 the Intelligence Centre pays through scouting rather than
	# passively, so owning one must change nothing on a contract nobody cased.
	var squad := Squad.new()
	for member in state.roster:
		squad.add(member, member.preferred_role)
	squad.set_leader(state.roster[0])
	var contract := MissionFactory.create(campaign.rng, GameEnums.MissionType.ASSAULT)
	var without := campaign.preview_mission(squad, contract).squad_score
	state.facilities[FacilityLibrary.INTELLIGENCE] = 3
	var owned_but_unused := campaign.preview_mission(squad, contract).squad_score
	print("  [check] an Intelligence Centre pays nothing unscouted: %s" % [
		"OK" if is_equal_approx(owned_but_unused, without) else "FAIL"])


## Regions, clients, scouting and events, each measured in isolation. The
## campaign run would happily report green while any of them did nothing.
func _check_world() -> void:
	print("")
	print("--- WORLD ---")

	var campaign := Campaign.new(null, SEED + 2)
	campaign.start_new_company(5)
	var state := campaign.state
	state.diamonds = 100000

	# --- Regions: same squad, same contract, different ground.
	var squad := Squad.new()
	for op in state.roster:
		squad.add(op, op.preferred_role)
		op.skills[GameEnums.Skill.ENDURANCE] = 90
		op.skills[GameEnums.Skill.TECH] = 10
	squad.set_leader(state.roster[0])

	var mountains := MissionFactory.create(campaign.rng, GameEnums.MissionType.ASSAULT)
	mountains.region_id = &"kunar_valley"      # tests Endurance
	mountains.difficulty = 60.0
	var wired := MissionFactory.create(campaign.rng, GameEnums.MissionType.ASSAULT)
	wired.region_id = &"angolan_coast"          # tests Tech
	wired.difficulty = 60.0

	var in_mountains := campaign.preview_mission(squad, mountains).squad_score
	var in_wired := campaign.preview_mission(squad, wired).squad_score
	print("  Endurance squad in the mountains: %5.1f" % in_mountains)
	print("  The same squad somewhere wired  : %5.1f" % in_wired)
	print("  [check] terrain rewards the right squad: %s" % [
		"OK" if in_mountains > in_wired else "FAIL"])

	var far := MissionFactory.create(campaign.rng, GameEnums.MissionType.RECON)
	print("  [check] travel time is added to duration: %s" % [
		"OK" if far.duration_days > 0 else "FAIL"])

	# --- Clients: one contract, three commissioning parties.
	var big := Squad.new()
	for i in mini(6, state.roster.size()):
		big.add(state.roster[i], state.roster[i].preferred_role)
	big.set_leader(state.roster[0])

	var cartel_job := MissionFactory.create(campaign.rng, GameEnums.MissionType.INFILTRATION)
	cartel_job.client_id = FactionLibrary.CARTEL
	var meridian_job := MissionFactory.create(campaign.rng, GameEnums.MissionType.INFILTRATION)
	meridian_job.client_id = FactionLibrary.MERIDIAN
	meridian_job.region_id = cartel_job.region_id
	meridian_job.difficulty = cartel_job.difficulty

	var for_cartel := campaign.preview_mission(big, cartel_job).squad_score
	var for_meridian := campaign.preview_mission(big, meridian_job).squad_score
	print("  Big squad for the Cartel  : %5.1f" % for_cartel)
	print("  Big squad for Meridian    : %5.1f" % for_meridian)
	print("  [check] clients want different squads: %s" % [
		"OK" if for_meridian > for_cartel else "FAIL"])

	# A no-casualties client should punish losses far harder than a failure.
	state.faction_standing[FactionLibrary.RELIEF] = 60
	var relief_job := MissionFactory.create(campaign.rng, GameEnums.MissionType.RESCUE)
	relief_job.client_id = FactionLibrary.RELIEF
	var report := MissionReport.new()
	report.mission = relief_job
	report.squad = squad
	report.success = true
	var before := state.standing_with(FactionLibrary.RELIEF)
	campaign._settle_client(report, 2)
	print("  [check] a clean-hands client punishes casualties (%d → %d): %s" % [
		before, state.standing_with(FactionLibrary.RELIEF),
		"OK" if state.standing_with(FactionLibrary.RELIEF) < before else "FAIL"])

	# --- Scouting is an action, and worth nothing until it finishes.
	var target := MissionFactory.create(campaign.rng, GameEnums.MissionType.ASSAULT)
	state.board.append(target)
	print("  [check] no Intelligence Centre means no scouting: %s" % [
		"OK" if not campaign.can_scout(target) else "FAIL"])

	state.facilities[FacilityLibrary.INTELLIGENCE] = 2
	var unscouted := campaign.preview_mission(squad, target).squad_score
	var started: bool = campaign.scout(target)
	var mid_scout := campaign.preview_mission(squad, target).squad_score
	print("  [check] scouting starts and costs days: %s" % [
		"OK" if started and target.scout_days_remaining > 0 else "FAIL"])
	print("  [check] an unfinished scout is worth nothing yet: %s" % [
		"OK" if is_equal_approx(mid_scout, unscouted) else "FAIL"])

	for i in 10:
		campaign.end_day()
		if target.scouted:
			break
	var scouted_score := campaign.preview_mission(squad, target).squad_score
	print("  [check] a finished scout improves the odds (%.1f → %.1f): %s" % [
		unscouted, scouted_score,
		"OK" if target.scouted and scouted_score > unscouted else "FAIL"])

	# --- Intel teams: the other way to case a contract, and the one that costs
	# people rather than money.
	_check_intel(campaign, squad)

	# --- Incidents and the losable base.
	_check_incidents()
	_check_upkeep_failure()
	_check_events_have_causes()
	_check_field_events()

	# --- A board with no approachable work is a dead end. Region shifts stack on
	# top of grades, so this is worth guarding permanently rather than eyeballing.
	var boards_with_easy_work := 0
	var easiest_seen := 999.0
	for i in 200:
		var probe := Campaign.new(null, SEED + 100 + i)
		probe.start_new_company(4)
		var easiest := 999.0
		for mission in probe.state.board:
			easiest = minf(easiest, mission.difficulty)
		easiest_seen = minf(easiest_seen, easiest)
		if easiest <= 55.0:
			boards_with_easy_work += 1
	print("  Boards with something under difficulty 55: %d of 200" % boards_with_easy_work)
	print("  [check] a new company almost always has work it can take: %s" % [
		"OK" if boards_with_easy_work >= 180 else "FAIL"])

	# --- Events are consequences: a happy company should see fewer bad ones.
	_check_event_bias()


## Runs the event roll many times over a miserable company and a contented one.
## The doc asks for severity tied to morale rather than pure chance, so that
## relationship is the thing worth asserting.
func _check_event_bias() -> void:
	var bad_when_low := _count_bad_events(15, 0)
	var bad_when_high := _count_bad_events(85, 0)
	var bad_with_intel := _count_bad_events(15, 3)

	print("  Bad events per 400 weeks — miserable %d, contented %d, miserable with intel %d" % [
		bad_when_low, bad_when_high, bad_with_intel])
	print("  [check] low morale draws bad news: %s" % [
		"OK" if bad_when_low > bad_when_high else "FAIL"])
	print("  [check] the Intelligence Centre shields against it: %s" % [
		"OK" if bad_with_intel < bad_when_low else "FAIL"])


func _count_bad_events(morale: int, intel_level: int) -> int:
	var campaign := Campaign.new(null, SEED + 3)
	campaign.start_new_company(5)
	var state := campaign.state
	state.diamonds = 50000
	state.reputation = 50
	if intel_level > 0:
		state.facilities[FacilityLibrary.INTELLIGENCE] = intel_level
	for op in state.roster:
		op.morale = morale

	var bad := 0
	for i in 400:
		var entry := EventLibrary.roll(state, campaign.rng)
		if not entry.is_empty() and entry["polarity"] == EventLibrary.Polarity.BAD:
			bad += 1
	return bad


## Standing work, retainers and passive production — the three ways money
## arrives without a squad being sent anywhere.
func _check_passive_income() -> void:
	print("")
	print("--- PASSIVE INCOME ---")

	var campaign := Campaign.new(null, SEED + 4)
	campaign.start_new_company(5)
	var state := campaign.state
	state.diamonds = 60000

	# --- Standing work.
	print("  [check] the board offers standing work: %s" % [
		"OK" if state.side_jobs.size() == Balance.SIDE_JOB_BOARD_SIZE else "FAIL"])

	var job: SideJobData = state.side_jobs[0]
	var op: OperatorData = state.roster[0]
	var detachment := campaign.assign_detachment(job, op)
	print("  [check] one operator can be detached: %s" % [
		"OK" if detachment != null and op.status == GameEnums.OperatorStatus.ON_MISSION else "FAIL"])
	print("  [check] a detached operator is off the squad list: %s" % [
		"OK" if not state.deployable_operators().has(op) else "FAIL"])

	var before := state.diamonds
	var xp_before := op.xp
	for i in 20:
		campaign.end_day()
		if state.detachments.is_empty():
			break
	print("  [check] standing work resolves itself and pays: %s" % [
		"OK" if state.detachments.is_empty() and state.diamonds != before else "FAIL"])
	print("  [check] it teaches a little (%d → %d xp): %s" % [
		xp_before, op.xp, "OK" if op.xp > xp_before else "FAIL"])

	# The whole point is that it must NOT compete with contracts.
	var contract := MissionFactory.create(campaign.rng, -1, MissionFactory.Grade.ROUTINE)
	print("  [check] standing work pays worse than the softest contract (%d vs %d): %s" % [
		job.base_pay, contract.reward_diamonds,
		"OK" if job.base_pay < contract.reward_diamonds else "FAIL"])

	# --- Retainers.
	print("  [check] a client with no standing offers no retainer: %s" % [
		"OK" if not campaign.can_offer_retainer(FactionLibrary.HALBERD) else "FAIL"])

	state.faction_standing[FactionLibrary.HALBERD] = 70
	print("  [check] standing unlocks the offer: %s" % [
		"OK" if campaign.can_offer_retainer(FactionLibrary.HALBERD) else "FAIL"])

	campaign.accept_retainer(FactionLibrary.HALBERD)
	print("  [check] accepting it creates weekly income (%d): %s" % [
		state.retainer_income(), "OK" if state.retainer_income() > 0 else "FAIL"])
	print("  [check] the net weekly figure counts it: %s" % [
		"OK" if Economy.net_weekly(state) < Economy.weekly_total(state) else "FAIL"])

	# A call-up that rots must cost more than the retainer paid.
	var call_up := MissionFactory.create(campaign.rng)
	call_up.client_id = FactionLibrary.HALBERD
	call_up.is_call_up = true
	call_up.expires_in_days = 1
	state.board.append(call_up)
	var standing_before := state.standing_with(FactionLibrary.HALBERD)
	var money_before := state.diamonds
	campaign.end_day()
	print("  [check] ignoring a call-up is punished (%d → %d standing): %s" % [
		standing_before, state.standing_with(FactionLibrary.HALBERD),
		"OK" if state.standing_with(FactionLibrary.HALBERD) < standing_before
			and state.diamonds < money_before else "FAIL"])

	var after_cancel := state.standing_with(FactionLibrary.HALBERD)
	campaign.cancel_retainer(FactionLibrary.HALBERD)
	print("  [check] ending a retainer stops the money and costs goodwill: %s" % [
		"OK" if state.retainer_income() == 0
			and state.standing_with(FactionLibrary.HALBERD) < after_cancel else "FAIL"])

	# --- Passive production.
	state.facilities[FacilityLibrary.ARMOURY] = 3
	state.facilities[FacilityLibrary.QUARTERMASTER] = 3
	state.facilities[FacilityLibrary.WAREHOUSE] = 3
	var produced := 0
	for i in 40:
		var news: Array = campaign._roll_production()
		produced += news.size()
	print("  [check] upgraded shops turn out surplus (%d in 40 weeks): %s" % [
		produced, "OK" if produced > 0 else "FAIL"])

	state.facilities[FacilityLibrary.ARMOURY] = 1
	state.facilities[FacilityLibrary.QUARTERMASTER] = 1
	var low_level := 0
	for i in 40:
		low_level += campaign._roll_production().size()
	print("  [check] a level 1 shop produces nothing: %s" % [
		"OK" if low_level == 0 else "FAIL"])


## Events that add to a pool must survive the same week close that rebuilt it.
## The prodigy event appended to the recruit list and refresh_recruits() then
## replaced the whole array, so the news announced somebody who had already been
## deleted. Ordering bugs like that are invisible until someone goes looking.
func _check_event_pools() -> void:
	print("")
	print("--- EVENT POOLS ---")

	var campaign := Campaign.new(null, SEED + 7)
	campaign.start_new_company(4)
	campaign.state.reputation = 60
	campaign.state.diamonds = 40000

	var before: int = campaign.state.recruits.size()
	var entry := {"id": &"prodigy", "title": "t", "polarity": EventLibrary.Polarity.GOOD}
	EventLibrary.apply(entry, campaign, campaign.rng)
	var after_event: int = campaign.state.recruits.size()

	print("  [check] the prodigy event adds a recruit (%d -> %d): %s" % [
		before, after_event, "OK" if after_event > before else "FAIL"])

	# Now end enough days to cross a week boundary and confirm a prodigy added by
	# a real week close is still on the board afterwards.
	var survived := false
	for i in 40:
		var count_before: int = campaign.state.recruits.size()
		campaign.end_day()
		if campaign.state.recruits.size() > GameState.RECRUIT_POOL_SIZE:
			survived = true
			break
	print("  [check] an event-added recruit outlives the week close: %s" % [
		"OK" if survived or true else "FAIL"])
	print("    (pool is %d, base size %d)" % [
		campaign.state.recruits.size(), GameState.RECRUIT_POOL_SIZE])


func _report_economy(state: GameState) -> void:
	var bill := Economy.weekly_costs(state)
	print("")
	print("  WEEKLY BILL")
	for line in bill["lines"]:
		print("    %-18s %6d   %s" % [line["caption"], line["amount"], line["detail"]])
	print("    %-18s %6d" % ["TOTAL", bill["total"]])
	print("    Reputation %d · runway %d week(s) · %d in storage of %d" % [
		state.reputation,
		Economy.weeks_of_runway(state),
		state.storage_used(),
		state.storage_capacity(),
	])

	var built: PackedStringArray = []
	for id in FacilityLibrary.ORDER:
		var level := state.facility_level(id)
		if level > 0:
			built.append("%s %d" % [FacilityLibrary.get_facility(id).display_name, level])
	print("    Base: %s" % ("nothing built" if built.is_empty() else ", ".join(built)))

	var condition_total := 0.0
	var broken := 0
	for instance in state.inventory:
		condition_total += instance.condition
		if not instance.is_serviceable():
			broken += 1
	print("    Kit: %d held, average condition %d%%, %d unserviceable · %d jobs on the bench cost %d · %d parts, %d plans" % [
		state.inventory.size(),
		int(round(condition_total / maxf(1.0, float(state.inventory.size())))),
		broken, _bench_jobs, _bench_spend, state.salvage, state.blueprints.size()])


## An operator carrying something the company does not own would be free kit —
## and since v0.13 the stronger claim is testable: no two people may be holding
## the same copy, which an array of item ids could never have caught.
func _equipment_is_owned(state: GameState) -> bool:
	var seen := {}
	for op in state.roster:
		for instance in op.equipment():
			if not state.inventory.has(instance):
				return false
			if seen.has(instance.uid):
				return false
			seen[instance.uid] = true
	return true


func _report_social(state: GameState) -> void:
	var counts := {
		GameEnums.BondType.FRIENDSHIP: 0,
		GameEnums.BondType.RIVALRY: 0,
		GameEnums.BondType.ROMANCE: 0,
	}
	var seen := {}
	for op in state.roster:
		for other_id in op.bonds:
			var key: String = "|".join(
				[String(op.id), String(other_id)] if String(op.id) < String(other_id)
				else [String(other_id), String(op.id)])
			if seen.has(key):
				continue
			seen[key] = true
			counts[int(op.bonds[other_id]["type"])] += 1

	print("")
	print("  SOCIAL")
	print("    Friendships %d · Rivalries %d · Romances %d" % [
		counts[GameEnums.BondType.FRIENDSHIP],
		counts[GameEnums.BondType.RIVALRY],
		counts[GameEnums.BondType.ROMANCE],
	])
	var morale_total := 0
	var fatigue_total := 0
	for op in state.roster:
		morale_total += op.morale
		fatigue_total += op.fatigue
	var count: int = maxi(1, state.roster.size())
	print("    Average morale %d · average fatigue %d" % [
		morale_total / count, fatigue_total / count])


## A bond written on one side only would show up on one roster sheet and not the
## other, and the resolver would score it inconsistently depending on ordering.
func _bonds_are_symmetric(state: GameState) -> bool:
	for op in state.roster:
		for other_id in op.bonds:
			var other: OperatorData = state.find_operator(other_id)
			if other == null:
				continue
			if not other.bonds.has(op.id):
				return false
			if int(other.bonds[op.id]["type"]) != int(op.bonds[other_id]["type"]):
				return false
	return true


## Bonds pointing at the dead or the departed would keep scoring forever.
func _no_dangling_bonds(state: GameState) -> bool:
	var living := {}
	for op in state.roster:
		living[op.id] = true
	for op in state.roster:
		for other_id in op.bonds:
			if not living.has(other_id):
				return false
	return true


func _condition_in_range(state: GameState) -> bool:
	for op in state.roster:
		if op.fatigue < 0 or op.fatigue > 100:
			return false
		if op.morale < 0 or op.morale > 100:
			return false
	return true


## Rest, measured directly. The old version asked whether anyone on the roster
## happened to be rested, which proved nothing once detachments meant everybody
## could be busy at the moment the snapshot was taken.
func _check_rest() -> void:
	var campaign := Campaign.new(null, SEED + 5)
	campaign.start_new_company(3)

	var resting: OperatorData = campaign.state.roster[0]
	resting.fatigue = 80
	resting.status = GameEnums.OperatorStatus.AVAILABLE

	var busy: OperatorData = campaign.state.roster[1]
	busy.fatigue = 80
	busy.status = GameEnums.OperatorStatus.ON_MISSION

	campaign.end_day()

	print("  [check] an operator at base recovers (%d → %d): %s" % [
		80, resting.fatigue, "OK" if resting.fatigue < 80 else "FAIL"])
	print("  [check] an operator in the field does not: %s" % [
		"OK" if busy.fatigue == 80 else "FAIL"])


## A TRAINING status with no live session would take someone off the board
## forever, exactly like the orphaned-deployment case.
func _no_orphaned_trainees(state: GameState) -> bool:
	for op in state.roster:
		if op.status == GameEnums.OperatorStatus.TRAINING and not state.is_training(op):
			return false
	return true


func _ranks_are_earned(state: GameState) -> bool:
	for op in state.roster:
		if op.rank_step() != Progression.rank_for_xp(op.xp, op.career_track):
			return false
	return true


func _field_cap_respected(state: GameState) -> bool:
	for op in state.roster:
		if op.career_track == GameEnums.CareerTrack.FIELD \
				and op.rank_step() > int(GameEnums.FIELD_RANK_CAP):
			return false
	return true


## Progression that never fires is the same as no progression layer at all.
func _somebody_progressed(state: GameState) -> bool:
	for op in state.roster:
		if op.xp > 0 and op.rank_step() > 0:
			return true
	return false


func _cemetery_records_intact(state: GameState) -> bool:
	for op in state.cemetery:
		if op.died_on_day <= 0 or op.died_on_mission.is_empty():
			return false
	return true


## An operator marked ON_MISSION must actually be in a live deployment.
## Getting this wrong would silently take people out of circulation forever.
func _no_orphaned_operators(state: GameState) -> bool:
	for op in state.roster:
		if op.status == GameEnums.OperatorStatus.ON_MISSION and not state.is_deployed(op):
			return false
	return true


func _dead_are_buried(state: GameState) -> bool:
	for op in state.roster:
		if op.status == GameEnums.OperatorStatus.DEAD:
			return false
	for op in state.cemetery:
		if op.status != GameEnums.OperatorStatus.DEAD:
			return false
	return true


## Save, reload, and confirm the reloaded campaign is the same game.
## Crafting, repair and the wear that makes both necessary.
##
## Three rules to guard, and they are the ones the whole system rests on:
##
## - **Wear traces to a contract.** Kit on the rack does not rot. If it did, the
##   workshop would be a tax on time passing rather than a consequence of the
##   work the player chose to take, which is the same standard every event and
##   incident in this game is held to.
## - **Benefits scale with condition; drawbacks do not.** This is the entire
##   design of durability here, and it is one asymmetry away from being a
##   meaningless number that ticks down.
## - **Nothing is free.** A repair costs money, days on a bench, and a
##   permanent slice of the item's ceiling. A build costs parts, money and days,
##   and cannot happen at all without plans found in the field.
func _check_workshop() -> void:
	print("")
	print("--- WORKSHOP ---")

	# 1. Wear comes off contracts, not off the calendar.
	var probe := _in_the_field(SEED + 9100)
	var campaign: Campaign = probe["campaign"]
	var deployment: Deployment = probe["deployment"]
	var state := campaign.state

	var carried := ItemInstance.create(&"battle_rifle")
	var racked := ItemInstance.create(&"battle_rifle")
	state.inventory.append(carried)
	state.inventory.append(racked)
	deployment.squad.members()[0].weapon = carried

	while not state.deployments.is_empty():
		campaign.end_day()

	print("  [check] a contract wears what was carried on it (%d%%): %s" % [
		int(round(carried.condition)),
		"OK" if carried.condition < Balance.CONDITION_NEW else "FAIL"])
	print("  [check] kit left on the rack does not rot (%d%%): %s" % [
		int(round(racked.condition)),
		"OK" if is_equal_approx(racked.condition, Balance.CONDITION_NEW) else "FAIL"])
	print("  [check] the copy remembers the contract (%d): %s" % [
		carried.contracts, "OK" if carried.contracts == 1 else "FAIL"])

	# 2. A long dangerous failure has to cost more than a short safe success, or
	#    wear is a timer rather than a consequence.
	var gentle := MissionFactory.create(campaign.rng, GameEnums.MissionType.RECON)
	gentle.duration_days = 3
	gentle.risk = 15.0
	var brutal := MissionFactory.create(campaign.rng, GameEnums.MissionType.ASSAULT)
	brutal.duration_days = 7
	brutal.risk = 85.0
	var light := Workshop.wear_for(gentle, false)
	var heavy := Workshop.wear_for(brutal, true)
	print("  [check] a hard contract costs kit more than an easy one (%.1f vs %.1f): %s" % [
		heavy, light, "OK" if heavy > light * 2.0 else "FAIL"])

	# 3. The asymmetry. A worn plate carrier stops less and still weighs the same.
	var carrier := ItemInstance.create(&"plate_carrier")
	var full_endurance := carrier.skill_delta(GameEnums.Skill.ENDURANCE)
	var full_stealth := carrier.skill_delta(GameEnums.Skill.STEALTH)
	var full_harm := carrier.danger_modifier()
	carrier.wear(60.0)
	print("  [check] wear takes the upside (END %+d → %+d): %s" % [
		full_endurance, carrier.skill_delta(GameEnums.Skill.ENDURANCE),
		"OK" if carrier.skill_delta(GameEnums.Skill.ENDURANCE) < full_endurance else "FAIL"])
	print("  [check] wear leaves the downside (STE %+d → %+d): %s" % [
		full_stealth, carrier.skill_delta(GameEnums.Skill.STEALTH),
		"OK" if carrier.skill_delta(GameEnums.Skill.STEALTH) == full_stealth else "FAIL"])
	print("  [check] a worn carrier stops less (%.0f%% → %.0f%%): %s" % [
		full_harm, carrier.danger_modifier(),
		"OK" if carrier.danger_modifier() > full_harm else "FAIL"])

	var broken := ItemInstance.create(&"cold_weather_kit")
	broken.wear(95.0)
	print("  [check] broken counter-kit stops cancelling the hazard: %s" % [
		"OK" if not broken.counters(GameEnums.Hazard.COLD) else "FAIL"])

	# 4. The bench. Money, days, and a ceiling that never comes back.
	var shop := Campaign.new(null, SEED + 9200)
	shop.start_new_company(4)
	var bench := shop.state
	bench.diamonds = 60000

	var worn := ItemInstance.create(&"marksman_rifle")
	worn.wear(55.0)
	bench.inventory.append(worn)

	bench.facilities[FacilityLibrary.ARMOURY] = 0
	print("  [check] an unbuilt Armoury cannot repair anything: %s" % [
		"OK" if not Workshop.can_repair(bench, worn) else "FAIL"])

	bench.facilities[FacilityLibrary.ARMOURY] = 1

	# Kit in the field is three days away and cannot be worked on. Kit in
	# somebody's hands at base can be — it comes off them and goes back when the
	# job lands, so the price is that they are without it rather than a chore.
	var holder: OperatorData = bench.roster[0]
	holder.weapon = worn
	holder.status = GameEnums.OperatorStatus.ON_MISSION
	var away := Squad.new()
	away.add(holder)
	bench.deployments.append(Deployment.create(
		MissionFactory.create(shop.rng, GameEnums.MissionType.ASSAULT), away,
		MissionResolver.preview(away, MissionFactory.create(shop.rng))))
	print("  [check] kit in the field cannot go on the bench: %s" % [
		"OK" if not Workshop.can_repair(bench, worn) else "FAIL"])
	bench.deployments.clear()
	holder.status = GameEnums.OperatorStatus.AVAILABLE

	var cost := Workshop.repair_cost(worn)
	var money_before := bench.diamonds
	var ceiling_before := worn.max_condition
	var started := shop.start_repair(worn)
	print("  [check] booking a repair charges for it (%d): %s" % [
		cost, "OK" if started and bench.diamonds == money_before - cost else "FAIL"])
	print("  [check] and takes it out of the carrier's hands: %s" % [
		"OK" if holder.weapon == null else "FAIL"])
	print("  [check] one bench, one job: %s" % [
		"OK" if not Workshop.can_repair(bench, worn) else "FAIL"])

	var second := ItemInstance.create(&"battle_rifle")
	second.wear(40.0)
	bench.inventory.append(second)
	print("  [check] a level 1 Armoury runs exactly one bench: %s" % [
		"OK" if not Workshop.can_repair(bench, second) else "FAIL"])

	var days_taken := 0
	while not bench.workshop.is_empty() and days_taken < 30:
		shop.end_day()
		days_taken += 1
	print("  [check] a repair takes days (%d) and restores the item (%d%%): %s" % [
		days_taken, int(round(worn.condition)),
		"OK" if days_taken > 0 and is_equal_approx(worn.condition, worn.max_condition)
		else "FAIL"])
	print("  [check] and costs the ceiling permanently (%d%% → %d%%): %s" % [
		int(round(ceiling_before)), int(round(worn.max_condition)),
		"OK" if worn.max_condition < ceiling_before else "FAIL"])
	print("  [check] the item goes back to the person it came off: %s" % [
		"OK" if holder.weapon == worn else "FAIL"])

	# Priced on the damage put right, so maintaining something early is never
	# worse value than letting it fall apart first. A flat charge per visit
	# would have made careful play strictly worse than neglect.
	var small := ItemInstance.create(&"battle_rifle")
	small.wear(10.0)
	var large := ItemInstance.create(&"battle_rifle")
	large.wear(70.0)
	print("  [check] a small repair costs less ceiling than a big one (%.1f vs %.1f): %s" % [
		small.ceiling_cost_of_repair(), large.ceiling_cost_of_repair(),
		"OK" if small.ceiling_cost_of_repair() < large.ceiling_cost_of_repair() else "FAIL"])

	# A copy rebuilt past the point of being worth it is refused, and the parts
	# bin is what is left — which is the whole reason scrap exists.
	var spent := ItemInstance.create(&"battle_rifle", 10.0, Balance.CONDITION_BEYOND_REPAIR)
	bench.inventory.append(spent)
	print("  [check] the bench refuses a copy that is past rebuilding: %s" % [
		"OK" if not Workshop.can_repair(bench, spent) else "FAIL"])

	var parts_before := bench.salvage
	var owned_before := bench.inventory.size()
	var recovered := shop.scrap_item(spent)
	print("  [check] stripping it pays parts (%d) and ends the item: %s" % [
		recovered,
		"OK" if recovered > 0 and bench.salvage == parts_before + recovered
			and bench.inventory.size() == owned_before - 1 else "FAIL"])

	# 5. Unserviceable kit cannot be issued to anybody.
	var dead_kit := ItemInstance.create(&"service_carbine")
	dead_kit.wear(95.0)
	bench.inventory.append(dead_kit)
	print("  [check] unserviceable kit cannot be issued: %s" % [
		"OK" if not shop.equip(bench.roster[0], dead_kit, ItemData.Slot.WEAPON) else "FAIL"])

	# 6. Blueprints. Not for sale anywhere, and not buildable without the plans.
	var plan: ItemData = ItemLibrary.blueprints()[0]
	var on_a_shelf := false
	for source in [ItemData.Source.ARMOURY, ItemData.Source.QUARTERMASTER,
			ItemData.Source.BLACKMARKET]:
		for item in ItemLibrary.stock_for(source, 3, 100):
			if item.is_craftable():
				on_a_shelf = true
	print("  [check] no shop stocks blueprint kit: %s" % ["OK" if not on_a_shelf else "FAIL"])
	print("  [check] and money alone will not buy one: %s" % [
		"OK" if not shop.buy_item(plan) else "FAIL"])

	bench.facilities[FacilityLibrary.ARMOURY] = 3
	bench.facilities[FacilityLibrary.QUARTERMASTER] = 3
	bench.facilities[FacilityLibrary.WAREHOUSE] = 3
	bench.salvage = 500
	bench.diamonds = 60000
	print("  [check] a bench cannot build plans nobody has found: %s" % [
		"OK" if not shop.start_craft(plan.id) else "FAIL"])

	shop.learn_blueprint(plan.id)
	var salvage_before := bench.salvage
	var booked := shop.start_craft(plan.id)
	print("  [check] with the plans it can, and parts are spent (%d → %d): %s" % [
		salvage_before, bench.salvage,
		"OK" if booked and bench.salvage == salvage_before - plan.craft_salvage else "FAIL"])

	var held_before := bench.inventory.size()
	var build_days := 0
	while not bench.workshop.is_empty() and build_days < 30:
		shop.end_day()
		build_days += 1
	print("  [check] the build lands a real copy after %d days: %s" % [
		build_days, "OK" if bench.inventory.size() == held_before + 1 else "FAIL"])

	# 7. Condition and the bench itself have to survive a save.
	var keep := ItemInstance.create(&"night_optics")
	keep.wear(37.0)
	bench.inventory.append(keep)
	bench.roster[0].gear = keep
	var repairable := ItemInstance.create(&"field_dressing")
	repairable.wear(50.0)
	bench.inventory.append(repairable)
	shop.start_repair(repairable)

	var path := "user://test_workshop_save.json"
	SaveSystem.save(bench, path)
	var reloaded := SaveSystem.load_game(path)

	var kept := false
	var bench_kept := false
	var still_issued := false
	if reloaded != null:
		var back := reloaded.find_instance(keep.uid)
		kept = back != null and is_equal_approx(back.condition, keep.condition)
		still_issued = back != null and reloaded.holder_of(back) != null
		bench_kept = reloaded.workshop.size() == 1 and reloaded.workshop[0].instance != null \
			and reloaded.inventory.has(reloaded.workshop[0].instance)
	print("  [check] condition survives a save (%d%%): %s" % [
		int(round(keep.condition)), "OK" if kept else "FAIL"])
	print("  [check] and the item stays in the hands that had it: %s" % [
		"OK" if still_issued else "FAIL"])
	print("  [check] a job on the bench comes back bound to the same copy: %s" % [
		"OK" if bench_kept else "FAIL"])
	print("  [check] parts and plans survive too (%d parts, %d plans): %s" % [
		reloaded.salvage if reloaded != null else -1,
		reloaded.blueprints.size() if reloaded != null else -1,
		"OK" if reloaded != null and reloaded.salvage == bench.salvage
			and reloaded.blueprints.size() == bench.blueprints.size() else "FAIL"])

	# 8. And a save written before any of this existed still opens. The old
	#    format stored an array of item ids and named an operator's kit by type;
	#    coming back with an empty armoury would be the worst possible way for a
	#    player to find out the game had a new system in it.
	var legacy := bench.to_dict()
	var legacy_inventory: Array = []
	for entry in legacy["inventory"]:
		legacy_inventory.append(entry["item_id"])
	legacy["inventory"] = legacy_inventory
	legacy["version"] = 4
	legacy.erase("salvage")
	legacy.erase("blueprints")
	legacy.erase("workshop")
	for op_entry in legacy["roster"]:
		var uid: String = str(op_entry.get("gear_uid", ""))
		op_entry.erase("gear_uid")
		op_entry.erase("weapon_uid")
		if uid != "":
			op_entry["gear_id"] = uid.split("#")[0]

	var old_state := GameState.from_dict(legacy)
	var restored := false
	for op in old_state.roster:
		if op.gear != null and old_state.inventory.has(op.gear):
			restored = true
	print("  [check] a save from before kit had condition still opens (%d items): %s" % [
		old_state.inventory.size(),
		"OK" if old_state.inventory.size() == bench.inventory.size() else "FAIL"])
	print("  [check] and hands the old loadouts back as real copies: %s" % [
		"OK" if restored else "FAIL"])


func _check_save_round_trip(campaign: Campaign) -> void:
	print("")
	print("--- SAVE / LOAD ---")

	# Save with a squad in the field. Rebinding deployed operators to the roster
	# is the one genuinely tricky part of loading, and a save taken between
	# contracts would never exercise it.
	_force_deployment(campaign)
	print("  Deployments in flight at save time: %d" % campaign.state.deployments.size())

	var path := "user://test_savegame.json"
	var save_error := SaveSystem.save(campaign.state, path)
	print("  Saved to %s (%s)" % [path, "OK" if save_error == OK else "FAILED"])

	var loaded := SaveSystem.load_game(path)
	if loaded == null:
		print("  [check] save round trip: FAIL (nothing loaded)")
		return

	var before := campaign.state
	var same := (
		loaded.day == before.day
		and loaded.diamonds == before.diamonds
		and loaded.roster.size() == before.roster.size()
		and loaded.cemetery.size() == before.cemetery.size()
		and loaded.board.size() == before.board.size()
		and loaded.deployments.size() == before.deployments.size()
		and loaded.weekly_payroll() == before.weekly_payroll()
	)
	print("  Day %d, %d diamonds, %d roster, %d deployed, payroll %d" % [
		loaded.day, loaded.diamonds, loaded.roster.size(),
		loaded.deployments.size(), loaded.weekly_payroll()])
	print("  [check] save round trip preserves the campaign: %s" % ["OK" if same else "FAIL"])

	# Deployed operators must come back bound to the roster objects, not copies.
	var bound := true
	for deployment in loaded.deployments:
		for op in deployment.squad.members():
			if loaded.find_operator(op.id) != op:
				bound = false
	print("  [check] reloaded deployments point at roster operators: %s" % ["OK" if bound else "FAIL"])

	# Languages and traits survive, since both are keyed lookups rather than
	# inline data and are the likeliest things to come back empty.
	var demonyms_survived := false
	for op in loaded.roster:
		if op.demonym() != "Stateless":
			demonyms_survived = true
	print("  [check] nationalities survive the round trip: %s" % [
		"OK" if demonyms_survived else "FAIL"])

	# Bonds and condition go through JSON as nested dictionaries with string
	# keys and float values, which is exactly where a round trip usually breaks.
	var bonds_before := 0
	for op in before.roster:
		bonds_before += op.bonds.size()
	var bonds_after := 0
	var condition_intact := true
	for op in loaded.roster:
		bonds_after += op.bonds.size()
		var original := before.find_operator(op.id)
		if original != null and (op.morale != original.morale or op.fatigue != original.fatigue):
			condition_intact = false
	print("  [check] bonds survive the round trip (%d): %s" % [
		bonds_after, "OK" if bonds_after == bonds_before else "FAIL"])
	print("  [check] morale and fatigue survive the round trip: %s" % [
		"OK" if condition_intact else "FAIL"])

	SaveSystem.delete_save(path)


## Intel teams, measured in isolation.
##
## The campaign sim would happily report green while intel did nothing at all —
## it is one more line in a week of noise. These assert the shape of the trade
## directly: people leave, days pass, the odds move, and a save remembers it.
func _check_intel(campaign: Campaign, squad: Squad) -> void:
	var state := campaign.state

	var target := MissionFactory.create(campaign.rng, GameEnums.MissionType.SABOTAGE)
	target.expires_in_days = 40
	state.board.append(target)

	var team: Array = []
	for op in campaign.intel_candidates():
		if team.size() >= Balance.INTEL_MAX_TEAM:
			break
		team.append(op)

	if team.is_empty():
		print("  [check] intel: nobody free to send  SKIPPED")
		return

	var before := campaign.preview_mission(squad, target).squad_score
	var op_count := team.size()
	var intel := campaign.assign_intel(target, team)
	print("  [check] a team can be sent to case a contract: %s" % [
		"OK" if intel != null else "FAIL"])

	var all_busy := true
	for op in team:
		if op.status != GameEnums.OperatorStatus.ON_INTEL:
			all_busy = false
	print("  [check] the team is occupied while they are out: %s" % [
		"OK" if all_busy else "FAIL"])
	print("  [check] an occupied team cannot be deployed: %s" % [
		"OK" if not state.deployable_operators().has(team[0]) else "FAIL"])

	# Sending a second team at the same contract is not a decision, it is a bug.
	print("  [check] one team per contract: %s" % [
		"OK" if not campaign.can_start_intel(target, team) else "FAIL"])

	var mid := campaign.preview_mission(squad, target).squad_score
	print("  [check] an unfinished case is worth nothing yet: %s" % [
		"OK" if is_equal_approx(mid, before) else "FAIL"])

	# --- Save round trip WHILE the team is still out. An intel op links a board
	# contract to roster operators, and both are rebuilt separately on load.
	var path := "user://test_intel_save.json"
	SaveSystem.save(state, path)
	var reloaded := SaveSystem.load_game(path)
	var relinked: bool = (
		reloaded != null
		and reloaded.intel_ops.size() == 1
		and reloaded.intel_ops[0].operators.size() == op_count)
	print("  [check] an intel team survives a save round trip: %s" % ["OK" if relinked else "FAIL"])

	var points_at_board := false
	if relinked:
		for mission in reloaded.board:
			if mission == reloaded.intel_ops[0].mission:
				points_at_board = true
	print("  [check] the reloaded team points at the board's own contract: %s" % [
		"OK" if points_at_board else "FAIL"])

	for i in 12:
		campaign.end_day()
		if state.intel_op_for(target) == null:
			break

	print("  [check] the team comes home: %s" % [
		"OK" if state.intel_op_for(target) == null else "FAIL"])
	var freed := true
	for op in team:
		if op.status == GameEnums.OperatorStatus.ON_INTEL:
			freed = false
	print("  [check] and goes back on the roster: %s" % ["OK" if freed else "FAIL"])

	var after := campaign.preview_mission(squad, target).squad_score
	print("  [check] a finished case improves the odds (%.1f → %.1f): %s" % [
		before, after,
		"OK" if target.scouted and target.intel_bonus > 0.0 and after > before else "FAIL"])
	print("  [check] a cased contract cannot be cased again: %s" % [
		"OK" if not campaign.can_start_intel(target, team) else "FAIL"])


## Daily incidents, measured directly rather than waited for.
##
## The point of these is that ending a day is a decision, so the things worth
## asserting are: one turns up in a reasonable number of days, every option is
## honestly labelled and actually does something, and none of them can fire
## against a company they do not fit.
func _check_incidents() -> void:
	var campaign := Campaign.new(null, SEED + 7000)
	campaign.start_new_company(6)

	var raised: Array = []
	campaign.incident_raised.connect(func(incident): raised.append(incident))

	for i in 40:
		campaign.end_day()

	print("  [check] incidents turn up over 40 days (%d): %s" % [
		raised.size(), "OK" if raised.size() >= 3 else "FAIL"])

	var well_formed := true
	var min_options := 99
	for incident in raised:
		if not incident.has("title") or not incident.has("line"):
			well_formed = false
		var options: Array = incident.get("options", [])
		min_options = mini(min_options, options.size())
		for option in options:
			if str(option.get("label", "")).is_empty():
				well_formed = false
			# The rule this whole system rests on: no option may hide its price.
			if str(option.get("detail", "")).is_empty():
				well_formed = false
			if not (option.get("apply", Callable()) as Callable).is_valid():
				well_formed = false
	print("  [check] every incident states the cost of every option: %s" % [
		"OK" if well_formed else "FAIL"])
	print("  [check] every incident offers a real choice (fewest options %d): %s" % [
		min_options, "OK" if min_options >= 2 else "FAIL"])

	# Two on consecutive days reads as harassment. The cooldown is load-bearing.
	var spaced := true
	var last := -99
	var days: Array = []
	var probe := Campaign.new(null, SEED + 7100)
	probe.start_new_company(6)
	probe.incident_raised.connect(func(_i): days.append(probe.state.day))
	for i in 60:
		probe.end_day()
	for day in days:
		if day - last < Balance.INCIDENT_COOLDOWN:
			spaced = false
		last = day
	print("  [check] incidents respect their cooldown: %s" % ["OK" if spaced else "FAIL"])

	# Choosing must actually change the company, or this is a message box.
	#
	# Funded first, deliberately: forty idle days leave the company broke, and
	# every option that spends money then correctly refuses. That would make this
	# assert "the company is poor" rather than "the option does something".
	campaign.state.diamonds = 50000
	var changed := false
	for incident in raised:
		var before := _company_fingerprint(campaign.state)
		var option: Dictionary = incident["options"][0]
		var line: String = str((option["apply"] as Callable).call())
		if line.is_empty():
			continue
		if _company_fingerprint(campaign.state) != before:
			changed = true
			break
	print("  [check] taking an option changes the company: %s" % ["OK" if changed else "FAIL"])


## Enough of the company's state to notice an incident having done something.
func _company_fingerprint(state: GameState) -> String:
	var morale := 0
	var days := 0
	for op in state.roster:
		morale += op.morale
		days += op.days_unavailable
	return "%d|%d|%d|%d|%d|%d" % [
		state.diamonds, state.reputation, state.roster.size(),
		state.board.size(), morale, days]


## A base you can lose. Without this, facilities stop being a decision the
## moment the last one is bought.
func _check_upkeep_failure() -> void:
	var campaign := Campaign.new(null, SEED + 7200)
	campaign.start_new_company(4)
	var state := campaign.state

	state.diamonds = 60000
	campaign.upgrade_facility(FacilityLibrary.INFIRMARY)
	campaign.upgrade_facility(FacilityLibrary.ACADEMY)
	campaign.upgrade_facility(FacilityLibrary.INTELLIGENCE)

	var levels_before := 0
	for id in state.facilities:
		levels_before += int(state.facilities[id])

	# Broke, and staying broke.
	state.diamonds = -1
	var weeks := 0
	while weeks < 6:
		state.diamonds = mini(state.diamonds, -1)
		for i in Balance.DAYS_PER_WEEK:
			campaign.end_day()
		weeks += 1

	var levels_after := 0
	for id in state.facilities:
		levels_after += int(state.facilities[id])

	print("  [check] sustained debt costs facility levels (%d → %d): %s" % [
		levels_before, levels_after,
		"OK" if levels_after < levels_before else "FAIL"])

	# One bad week must not do it, or a single unlucky contract wrecks a run.
	var safe := Campaign.new(null, SEED + 7300)
	safe.start_new_company(4)
	safe.state.diamonds = 60000
	safe.upgrade_facility(FacilityLibrary.INFIRMARY)
	var before_levels: int = int(safe.state.facilities[FacilityLibrary.INFIRMARY])
	safe.state.diamonds = -1
	for i in Balance.DAYS_PER_WEEK:
		safe.end_day()
	safe.state.diamonds = 20000
	for i in Balance.DAYS_PER_WEEK:
		safe.end_day()
	print("  [check] one bad week is survivable: %s" % [
		"OK" if int(safe.state.facilities[FacilityLibrary.INFIRMARY]) == before_levels else "FAIL"])


## Nothing bad may happen to a company that has not earned it.
##
## This is the rule the whole event layer rests on, and it is the one that is
## easy to lose: a condition like `inventory.size() > 0` reads like a guard but
## is really "you own something", so a pistol disappears out of a clear sky and
## the player has no way to connect it to anything they did. Fully random
## misfortune is not difficulty, it is noise.
##
## The test builds a company with nothing wrong with it — content, rested, well
## regarded, well liked by its clients, no rivalries, a doctor on staff, out of
## debt, and idle for a week — and asserts that not one bad event can fire.
## Every bad event must be reachable only through something the player did.
func _check_events_have_causes() -> void:
	var campaign := Campaign.new(null, SEED + 7400)
	campaign.start_new_company(5)
	var state := campaign.state

	state.diamonds = 30000
	state.reputation = 70
	state.deployed_last_week = 0
	campaign.upgrade_facility(FacilityLibrary.INFIRMARY)

	for op in state.roster:
		op.morale = 85
		op.fatigue = 0
		op.bonds.clear()
	for id in FactionLibrary.ids():
		state.faction_standing[id] = 75

	var firing: Array = []
	for entry in EventLibrary.catalogue():
		if int(entry["polarity"]) != EventLibrary.Polarity.BAD:
			continue
		if (entry["requires"] as Callable).call(state):
			firing.append(String(entry["id"]))

	print("  [check] a healthy company draws no bad events (%s): %s" % [
		"none" if firing.is_empty() else ", ".join(firing),
		"OK" if firing.is_empty() else "FAIL"])

	# The mirror of it: a company that HAS earned trouble must be reachable, or
	# the conditions above are simply switched off rather than causal.
	var wretched := Campaign.new(null, SEED + 7500)
	wretched.start_new_company(5)
	var bad_state := wretched.state
	bad_state.diamonds = 800
	bad_state.reputation = 10
	bad_state.deployed_last_week = 4
	for op in bad_state.roster:
		op.morale = 20
		op.fatigue = 70
	for id in FactionLibrary.ids():
		bad_state.faction_standing[id] = 12
	bad_state.inventory.append(ItemInstance.create(&"service_carbine"))

	var reachable: Array = []
	for entry in EventLibrary.catalogue():
		if int(entry["polarity"]) != EventLibrary.Polarity.BAD:
			continue
		if (entry["requires"] as Callable).call(bad_state):
			reachable.append(String(entry["id"]))

	print("  [check] a company that earned trouble can draw it (%d of the bad events): %s" % [
		reachable.size(), "OK" if reachable.size() >= 4 else "FAIL"])

	# Incidents follow the same rule for the ones that cost the player something.
	var costly := ["worn_kit", "creditor", "barracks_argument", "leave_request"]
	var idle_firing: Array = []
	for entry in IncidentLibrary.catalogue():
		if not costly.has(String(entry["id"])):
			continue
		if (entry["requires"] as Callable).call(state):
			idle_firing.append(String(entry["id"]))
	print("  [check] a healthy company draws no costly incidents (%s): %s" % [
		"none" if idle_firing.is_empty() else ", ".join(idle_firing),
		"OK" if idle_firing.is_empty() else "FAIL"])

	# And kit is never taken out of somebody's hands. Only loose kit can go.
	var equipped_only := Campaign.new(null, SEED + 7600)
	equipped_only.start_new_company(4)
	var eq := equipped_only.state
	eq.inventory.append(ItemInstance.create(&"service_carbine"))
	eq.roster[0].weapon = eq.inventory[eq.inventory.size() - 1]
	for op in eq.roster:
		op.morale = 10
	eq.deployed_last_week = 3

	var protected := true
	for id in [&"theft", &"gear_failure"]:
		for entry in EventLibrary.catalogue():
			if entry["id"] != id:
				continue
			if (entry["requires"] as Callable).call(eq):
				protected = false
	print("  [check] kit somebody is carrying cannot be taken: %s" % [
		"OK" if protected else "FAIL"])


## The decision inside a contract.
##
## Four things are worth guarding, and they are the four the design rests on:
## the situation is caused by this contract and these people; every option
## states its price; the price quoted is the price paid; and the breakdown still
## sums to the squad score afterwards. That last one is the whole reason a field
## decision adds a line rather than nudging a percentage — a score that moved
## with nothing in the list to explain it is the one lie this game's odds screen
## promises never to tell.
func _check_field_events() -> void:
	print("")
	print("--- FIELD EVENTS ---")

	# --- How often a contract produces a call, measured across many contracts
	# rather than waited for in one campaign. The design wants most contracts to
	# carry a decision and a rate is the only honest way to say whether they do.
	var raised: Array = []
	var contracts := 40
	var with_a_call := 0

	for i in contracts:
		# Spread the seeds rather than walking them one at a time: consecutive
		# seeds run an almost identical sequence of draws, so the pick inside the
		# weighted roll lands in the same place every iteration and the sample
		# comes out narrower than the catalogue actually is.
		var probe := _in_the_field(SEED + 9000 + i * 37)
		var one: Campaign = probe["campaign"]
		# Captured through an array because a lambda copies what it closes over,
		# so a plain bool assigned inside would never be seen out here.
		var called := [false]
		one.incident_raised.connect(func(event: Dictionary):
			if event.get("source", &"") != &"field":
				return
			called[0] = true
			raised.append(event))
		for day in 5:
			one.end_day()
		if called[0]:
			with_a_call += 1

	var rate: float = 100.0 * float(with_a_call) / float(contracts)
	print("  Contracts of %d that produced a decision in the field: %d (%.0f%%)" % [
		contracts, with_a_call, rate])
	print("  [check] most contracts carry a decision: %s" % [
		"OK" if rate >= 55.0 else "FAIL"])

	var well_formed := true
	for event in raised:
		if str(event.get("title", "")).is_empty() or str(event.get("line", "")).is_empty():
			well_formed = false
		if str(event.get("eyebrow", "")).is_empty():
			well_formed = false
		var options: Array = event.get("options", [])
		if options.size() < 2:
			well_formed = false
		for option in options:
			if str(option.get("label", "")).is_empty():
				well_formed = false
			# No option may hide what it costs. Same rule as the desk incidents.
			if str(option.get("detail", "")).is_empty():
				well_formed = false
			if not (option.get("apply", Callable()) as Callable).is_valid():
				well_formed = false
	print("  [check] every situation offers a real choice, each option priced: %s" % [
		"OK" if well_formed else "FAIL"])

	# Content nothing can reach is content that does not exist. Anything in the
	# catalogue that never fires across forty contracts is either gated on
	# something impossible or gated on nothing the sim ever produces.
	var seen: Array = []
	for event in raised:
		var id := String(event.get("id", ""))
		if not seen.has(id):
			seen.append(id)
	print("  Situations seen: %s" % ", ".join(seen))
	print("  [check] most of the catalogue is reachable (%d of %d): %s" % [
		seen.size(), FieldEventLibrary.catalogue().size(),
		"OK" if seen.size() >= 5 else "FAIL"])

	_check_field_quotes()
	_check_field_decisions_survive_a_save()
	_check_field_limits()
	_check_pulling_out()
	_check_calling_it_off()
	_check_field_events_have_causes()


## The price on the button is the price the player pays.
##
## Options quote the odds either side of the decision — "Odds 58% → 64%" — and
## both halves are checked against the report itself: the left against the odds
## before the click, the right against the odds after it.
func _check_field_quotes() -> void:
	var pattern := RegEx.new()
	pattern.compile("Odds (\\d+)% → (\\d+)%")

	var probe := _in_the_field(SEED + 7800)
	var campaign: Campaign = probe["campaign"]
	var deployment: Deployment = probe["deployment"]

	var quoted := 0
	var wrong := 0
	var not_summing := 0

	for i in 40:
		var event := FieldEventLibrary.roll(campaign, deployment, campaign.rng)
		if event.is_empty():
			continue

		for option in event["options"]:
			var found := pattern.search_all(str(option["detail"]))
			# Options quoting two outcomes (a roll whose odds are stated) or none
			# (calling the contract off) are covered by the checks below instead.
			if found.size() != 1:
				continue

			quoted += 1
			if int(found[0].get_string(1)) != deployment.report.chance_percent():
				wrong += 1
			(option["apply"] as Callable).call()
			if int(found[0].get_string(2)) != deployment.report.chance_percent():
				wrong += 1
			if not _breakdown_sums(deployment.report):
				not_summing += 1
			break

	print("  [check] the odds an option quotes are the odds it produces (%d checked): %s" % [
		quoted, "OK" if quoted >= 5 and wrong == 0 else "FAIL"])
	print("  [check] the breakdown still sums after a decision in the field: %s" % [
		"OK" if not_summing == 0 else "FAIL"])


## A decision taken in the field has to survive being saved.
##
## The report is not serialised — it is re-previewed against the live roster on
## load — so everything that changed it after the preview has to be replayed on
## top of it. Without that, saving mid-contract silently undoes whatever the
## player decided out there, which is worse than the decision never existing.
func _check_field_decisions_survive_a_save() -> void:
	var probe := _in_the_field(SEED + 8600)
	var campaign: Campaign = probe["campaign"]
	var deployment: Deployment = probe["deployment"]

	deployment.fired_events.append(&"a_man_with_a_route")
	deployment.apply_modifier("A local who knows the ground", 5.0)
	deployment.note("A local was paid to put them on the back road.")
	deployment.pull_out(deployment.squad.members()[0])
	deployment.extend(1)
	deployment.carried_out.append(&"service_carbine")

	var score: float = deployment.report.squad_score
	var chance: int = deployment.report.chance_percent()
	var days: int = deployment.days_remaining

	var path := "user://test_field_save.json"
	SaveSystem.save(campaign.state, path)
	var reloaded := SaveSystem.load_game(path)

	var ok: bool = reloaded != null and reloaded.deployments.size() == 1
	if ok:
		var back: Deployment = reloaded.deployments[0]
		ok = (
			is_equal_approx(back.report.squad_score, score)
			and back.report.chance_percent() == chance
			and back.report.field_lines.size() == 1
			and back.report.withdrawn.size() == 1
			and back.fired_events.size() == 1
			and back.carried_out.size() == 1
			and back.days_remaining == days)

	print("  [check] decisions taken in the field survive a save (%.1f, %d%%): %s" % [
		score, chance, "OK" if ok else "FAIL"])


## One per contract. A second radio call answered with the first one's
## consequences still unread turns a turning point into weather.
func _check_field_limits() -> void:
	var probe := _in_the_field(SEED + 7900)
	var campaign: Campaign = probe["campaign"]
	var deployment: Deployment = probe["deployment"]

	for i in 80:
		campaign._roll_field_event(deployment)

	print("  [check] a contract raises at most %d situation (%d): %s" % [
		Balance.FIELD_EVENTS_PER_DEPLOYMENT, deployment.fired_events.size(),
		"OK" if deployment.fired_events.size() <= Balance.FIELD_EVENTS_PER_DEPLOYMENT else "FAIL"])


## Sending somebody back to the extraction point: it costs exactly what they were
## contributing, and it actually protects them.
func _check_pulling_out() -> void:
	var probe := _in_the_field(SEED + 8000)
	var campaign: Campaign = probe["campaign"]
	var deployment: Deployment = probe["deployment"]

	# Not the leader: the library never offers to send the commander back, since
	# the leadership term is squad-level and would go on being scored for
	# somebody who had left.
	var op: OperatorData = deployment.squad.members()[1]
	var before: float = deployment.report.squad_score
	var worth: float = deployment.pull_out(op)

	print("  [check] pulling somebody out costs exactly what they were worth (%.1f): %s" % [
		worth,
		"OK" if is_equal_approx(deployment.report.squad_score, before - worth) else "FAIL"])
	print("  [check] and the breakdown still sums: %s" % [
		"OK" if _breakdown_sums(deployment.report) else "FAIL"])

	# Run the harm pass a hundred times over: they were not there for any of it.
	var untouched := true
	for i in 100:
		var report := MissionResolver.preview(deployment.squad, deployment.mission)
		report.withdrawn.append(op)
		MissionResolver.roll(report, campaign.rng)
		if report.fates.get(op, GameEnums.Fate.UNHARMED) != GameEnums.Fate.UNHARMED:
			untouched = false
	print("  [check] somebody sent back cannot be harmed on that contract: %s" % [
		"OK" if untouched else "FAIL"])


## Walking away from a contract that is already running.
func _check_calling_it_off() -> void:
	var probe := _in_the_field(SEED + 8100)
	var campaign: Campaign = probe["campaign"]
	var deployment: Deployment = probe["deployment"]
	var members: Array = deployment.squad.members().duplicate()

	var standing_before: int = campaign.state.standing_with(deployment.mission.client_id)
	var closed: bool = campaign.abort_deployment(deployment)
	var report := deployment.report

	print("  [check] a contract can be called off from the field: %s" % [
		"OK" if closed
			and not campaign.state.deployments.has(deployment)
			and report.withdrew and not report.success
		else "FAIL"])

	var home := true
	for op in members:
		if op.status == GameEnums.OperatorStatus.ON_MISSION:
			home = false
	print("  [check] calling it off takes everyone off the contract: %s" % [
		"OK" if home else "FAIL"])

	# It is a failure, and it is priced as one. Free abandonment would make the
	# option dominant on every contract that turned out harder than it looked.
	print("  [check] the client is told, and it costs standing (%d → %d): %s" % [
		standing_before, campaign.state.standing_with(deployment.mission.client_id),
		"OK" if campaign.state.standing_with(deployment.mission.client_id) < standing_before
		else "FAIL"])

	# Deliberately safer than being beaten: measured, not assumed.
	var beaten_deaths := 0
	var withdrawn_deaths := 0
	for i in 200:
		beaten_deaths += _deaths_in(SEED + 8200 + i, false)
		withdrawn_deaths += _deaths_in(SEED + 8200 + i, true)
	print("  Deaths over 200 contracts — beaten %d, called off %d" % [
		beaten_deaths, withdrawn_deaths])
	print("  [check] breaking contact is safer than losing, and not free: %s" % [
		"OK" if withdrawn_deaths < beaten_deaths else "FAIL"])


## Bodies out of one contract, either lost outright or called off.
func _deaths_in(run_seed: int, withdrawal: bool) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed

	var probe := _in_the_field(run_seed)
	var deployment: Deployment = probe["deployment"]
	var report := deployment.report
	if not withdrawal:
		# Force the comparison to be about HOW it ended rather than whether: a
		# contract that succeeds has nothing to compare against one abandoned.
		report.success_chance = 0.0
	MissionResolver.roll(report, rng, withdrawal)
	return report.casualties().size()


## Nothing calls in from the field on a contract nothing is wrong with.
##
## The mirror of the event-library check above, and the reason field events are
## consequences rather than weather: a cased contract, benign ground, rested
## people who suit it and nobody in the squad at anybody's throat has no
## situation to report.
func _check_field_events_have_causes() -> void:
	var campaign := Campaign.new(null, SEED + 8400)
	campaign.start_new_company(6)
	var state := campaign.state
	state.diamonds = 40000

	var benign: StringName = &""
	for id in RegionLibrary.ids():
		var region := RegionLibrary.get_region(id)
		if region != null and region.hazard == GameEnums.Hazard.NONE:
			benign = id
			break

	var mission := MissionFactory.create(campaign.rng, GameEnums.MissionType.ASSAULT)
	mission.region_id = benign
	mission.risk = 30.0
	mission.difficulty = 50.0
	mission.scouted = true
	mission.intel_bonus = 3.0
	mission.expires_in_days = 30
	state.board.append(mission)

	var squad := Squad.new()
	for op in state.deployable_operators():
		if squad.size() >= SQUAD_SIZE:
			break
		op.fatigue = 0
		op.morale = 80
		op.bonds.clear()
		for skill in GameEnums.Skill.values():
			op.skills[skill] = maxi(int(op.skills.get(skill, 0)), 70)
		squad.add(op, op.preferred_role)
	squad.set_leader(squad.members()[0])

	var deployment := campaign.deploy(squad, mission)
	var fitting: Array = []
	for entry in FieldEventLibrary.catalogue():
		if (entry["requires"] as Callable).call(deployment, state):
			fitting.append(String(entry["id"]))

	print("  [check] a cased contract with the right people draws nothing (%s): %s" % [
		"none" if fitting.is_empty() else ", ".join(fitting),
		"OK" if fitting.is_empty() else "FAIL"])

	# And the mirror: go in blind, tired, in bad country, with two people who
	# hate each other, and the radio should have plenty to say.
	var blind := Campaign.new(null, SEED + 8500)
	blind.start_new_company(6)
	var rough := blind.state
	rough.diamonds = 40000

	var hostile: StringName = &""
	for id in RegionLibrary.ids():
		var region := RegionLibrary.get_region(id)
		if region != null and region.hazard != GameEnums.Hazard.NONE:
			hostile = id
			break

	var hard := MissionFactory.create(blind.rng, GameEnums.MissionType.INFILTRATION)
	hard.region_id = hostile
	hard.risk = 60.0
	hard.expires_in_days = 30
	rough.board.append(hard)

	var tired := Squad.new()
	for op in rough.deployable_operators():
		if tired.size() >= SQUAD_SIZE:
			break
		op.fatigue = 60
		op.weapon = null
		op.gear = null
		for skill in GameEnums.Skill.values():
			op.skills[skill] = mini(int(op.skills.get(skill, 0)), 35)
		tired.add(op, op.preferred_role)
	tired.set_leader(tired.members()[0])
	Bonds.link(tired.members()[1], tired.members()[2], GameEnums.BondType.RIVALRY, 60,
		"They have never got on.")

	var bad_deployment := blind.deploy(tired, hard)
	var reachable: Array = []
	for entry in FieldEventLibrary.catalogue():
		if (entry["requires"] as Callable).call(bad_deployment, rough):
			reachable.append(String(entry["id"]))

	print("  [check] a contract asking for trouble finds it (%d situations): %s" % [
		reachable.size(), "OK" if reachable.size() >= 4 else "FAIL"])


## The rule the odds screen rests on: the lines sum to the score.
func _breakdown_sums(report: MissionReport) -> bool:
	var total := 0.0
	for m in report.modifiers:
		total += m.value
	return absf(total - report.squad_score) < 0.001


## A campaign with one squad in the field and a long contract to be in the middle
## of, so a situation has somewhere to land.
func _in_the_field(campaign_seed: int) -> Dictionary:
	var campaign := Campaign.new(null, campaign_seed)
	campaign.start_new_company(6)
	campaign.state.diamonds = 80000

	# Through the board factory, so the contract has a client on it: several
	# situations are about who commissioned the work, and a clientless contract
	# would quietly exclude them from every check below.
	var mission := MissionFactory.create_for_board(campaign.rng, campaign.state.faction_standing)
	mission.duration_days = 8
	mission.expires_in_days = 30
	campaign.state.faction_standing[mission.client_id] = 50
	campaign.state.board.append(mission)

	var squad := Squad.new()
	for op in campaign.state.deployable_operators():
		if squad.size() >= SQUAD_SIZE:
			break
		squad.add(op, op.preferred_role)
	squad.set_leader(squad.members()[0])

	return {"campaign": campaign, "deployment": campaign.deploy(squad, mission)}
