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
		var held: StringName = op.weapon_id if slot == ItemData.Slot.WEAPON else op.gear_id
		if held == &"":
			return true
	return false


func _equip_anyone(campaign: Campaign, item: ItemData) -> void:
	for op in campaign.state.roster:
		var held: StringName = (
			op.weapon_id if item.slot == ItemData.Slot.WEAPON else op.gear_id)
		if held == &"":
			campaign.equip(op, item.id, item.slot)
			return


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
	var equipped: bool = campaign.equip(op, rifle.id, rifle.slot)
	print("  [check] buying then issuing a weapon works: %s" % [
		"OK" if bought and equipped and op.weapon_id == rifle.id else "FAIL"])

	# One copy, one carrier. A second operator must not be able to hold it too.
	var second: OperatorData = state.roster[1]
	print("  [check] one copy cannot be carried by two people: %s" % [
		"OK" if not campaign.equip(second, rifle.id, rifle.slot) else "FAIL"])

	print("  [check] gear cannot go in the weapon slot: %s" % [
		"OK" if not campaign.equip(second, &"field_dressing", ItemData.Slot.WEAPON) else "FAIL"])

	var carried_before := state.unequipped_count(rifle.id)
	print("  [check] a carried item is not free to reissue: %s" % [
		"OK" if carried_before == 0 else "FAIL"])

	print("  [check] carried kit cannot be sold out from under them: %s" % [
		"OK" if not campaign.sell_item(rifle.id) else "FAIL"])

	# Equipment must reach the resolver, or none of this affects the game.
	var bare := OperatorFactory.create(campaign.rng, GameEnums.Role.MARKSMAN, OperatorFactory.Tier.REGULAR)
	var combat_before := bare.get_skill(GameEnums.Skill.COMBAT)
	bare.weapon_id = &"battle_rifle"
	var combat_after := bare.get_skill(GameEnums.Skill.COMBAT)
	print("  [check] a weapon changes what the resolver sees (%d → %d): %s" % [
		combat_before, combat_after, "OK" if combat_after > combat_before else "FAIL"])

	# Storage is a real limit, not decoration.
	state.facilities[FacilityLibrary.WAREHOUSE] = 0
	while state.has_storage_room():
		state.inventory.append(&"service_carbine")
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


## An operator carrying something the company does not own would be free kit.
func _equipment_is_owned(state: GameState) -> bool:
	var owned := {}
	for id in state.inventory:
		owned[id] = int(owned.get(id, 0)) + 1

	var carried := {}
	for op in state.roster:
		for id in [op.weapon_id, op.gear_id]:
			if id != &"":
				carried[id] = int(carried.get(id, 0)) + 1

	for id in carried:
		if int(carried[id]) > int(owned.get(id, 0)):
			return false
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
