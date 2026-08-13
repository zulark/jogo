extends SceneTree

## Drives the HQ through every screen and captures each one.
##
##   Godot.exe --path . --script res://tests/screenshot_hq.gd
##
## Must NOT be run with --headless: the dummy renderer produces a blank image.
##
## Each step runs on its own frame with a couple of settling frames after it,
## because containers do not lay out until they have been processed.

const OUT_DIR := "res://.screenshots"
const WINDOW_SIZE := Vector2i(1280, 820)
const SETTLE := 3

## Seeded, because this harness asserts as well as captures. Unseeded it started
## a random company, so the steps that need a squad in the field to photograph
## sometimes found none and printed a check failure that meant nothing but the
## dice. A visual check tool that cries wolf gets ignored, and one whose output
## changes run to run cannot be compared against yesterday's.
const SEED := 20260810

## Mirrors hq.gd's Tab enum. Duplicated rather than reached through the instance
## because a script-level enum is not addressable from an untyped node handle.
##
## Hand-mirroring an enum is a standing trap: these drifted once already and
## TAB_CEMETERY pointed at Clients, so the "cemetery" screenshot was quietly of
## another screen. _check_tabs_match() below asserts the mirror is still true.
const TAB_ROSTER := 0
const TAB_CONTRACTS := 1
const TAB_RECRUITS := 2
const TAB_TRAINING := 3
const TAB_INTEL := 4
const TAB_BASE := 5
const TAB_MARKET := 6
const TAB_WORKSHOP := 7
const TAB_CLIENTS := 8
const TAB_BONDS := 9
const TAB_CEMETERY := 10

var _hq: Control = null
var _step := 0
var _frames := 0
var _steps: Array = []


func _initialize() -> void:
	_steps = [
		{"do": func(): pass, "shot": "hq_contracts"},
		{"do": _select_contract, "shot": "hq_contract_detail"},
		{"do": func(): _hq._show_tab(TAB_ROSTER), "shot": "hq_roster"},
		{"do": func(): _hq._show_tab(TAB_RECRUITS), "shot": "hq_recruits"},
		{"do": _open_builder, "shot": "hq_squad_builder"},
		{"do": _fill_squad, "shot": "hq_squad_builder_filled"},
		{"do": _deploy_and_run, "shot": "hq_after_action"},
		{"do": _open_kill_feed, "shot": "hq_after_action_feed"},
		{"do": _dismiss_modal_and_train, "shot": "hq_training"},
		{"do": _open_intel, "shot": "hq_intel"},
		{"do": _open_standing_work, "shot": "hq_standing_work"},
		{"do": _raise_incident, "shot": "hq_incident"},
		{"do": _raise_field_event, "shot": "hq_field_event"},
		{"do": _take_field_decision, "shot": "hq_field_event_outcome"},
		{"do": _close_field_decision, "shot": "hq_field_abort_debrief"},
		{"do": _run_until_losses, "shot": "hq_cemetery"},
		{"do": func(): _hq._show_tab(TAB_ROSTER), "shot": "hq_roster_career"},
		{"do": _scroll_operator_sheet, "shot": "hq_roster_sheet"},
		{"do": _open_hub, "shot": "hq_base"},
		{"do": _select_a_facility, "shot": "hq_base_facility"},
		{"do": _open_stocked_market, "shot": "hq_market"},
		{"do": _open_workshop, "shot": "hq_workshop"},
		{"do": _open_inventory_drawer, "shot": "hq_drawer_inventory"},
		# Last, because standing the company down for a month to reach these
		# leaves the books in a state no earlier capture should be shot in.
		{"do": _rest_and_show_board, "shot": "hq_contracts_history"},
		{"do": _open_builder_with_history, "shot": "hq_squad_builder_bonds"},
	]


## The bottom half of a service record — skills, what those skills are worth on
## each kind of work, temperament, traits. Everything below the fold on that
## panel went unphotographed until now, which is exactly where a layout breaks
## without anybody noticing.
func _scroll_operator_sheet() -> void:
	# Whatever the field is doing, this shot is about the sheet.
	_hq.get_node("%IncidentModal").hide()
	_hq.get_node("%AfterAction").hide()

	var roster = _hq._screen
	if roster == null:
		return
	var scroll: ScrollContainer = roster.get_node("DetailScroll")
	scroll.scroll_vertical = 100000


## A base worth photographing: some of it built, some of it still an empty plot,
## because "the skyline is the balance sheet" is only true if both show.
func _open_hub() -> void:
	_hq.get_node("%IncidentModal").hide()
	_hq.get_node("%AfterAction").hide()

	var state: GameState = Game.campaign.state
	state.diamonds += 60000
	for id in [FacilityLibrary.INFIRMARY, FacilityLibrary.ACADEMY,
			FacilityLibrary.CANTEEN, FacilityLibrary.ARMOURY]:
		Game.campaign.upgrade_facility(id)
	Game.campaign.upgrade_facility(FacilityLibrary.ACADEMY)
	Game.campaign.upgrade_facility(FacilityLibrary.ACADEMY)
	Game.campaign.upgrade_facility(FacilityLibrary.INFIRMARY)
	_hq._show_tab(TAB_BASE)


## And the panel for one of them, which is where the upgrade decision is taken.
func _select_a_facility() -> void:
	var hub = _hq._screen
	if hub != null and hub.has_method("refresh"):
		hub._world.select(&"academy")


## The workshop is only worth looking at with something on the bench and a set
## of plans in hand — an empty one is three headings and a shrug.
func _open_workshop() -> void:
	# Whatever the field is doing, this shot is about the bench. A modal left
	# open from an earlier step covers the middle third of the capture.
	_hq.get_node("%IncidentModal").hide()
	_hq.get_node("%AfterAction").hide()

	var state: GameState = Game.campaign.state
	state.diamonds += 40000
	state.salvage += 180
	Game.campaign.upgrade_facility(FacilityLibrary.QUARTERMASTER)
	Game.campaign.buy_item(ItemLibrary.get_item(&"plate_carrier"))
	for item in ItemLibrary.blueprints():
		Game.campaign.learn_blueprint(item.id)

	# One piece of kit in each state the screen has to render: worn enough to
	# want the bench, past rebuilding, and already on it.
	for instance in state.inventory:
		if instance.item_id == &"battle_rifle":
			instance.wear(58.0)
	var spent := ItemInstance.create(&"suppressed_pistol", 14.0, 38.0)
	state.inventory.append(spent)
	var booked := ItemInstance.create(&"night_optics", 44.0)
	state.inventory.append(booked)
	Game.campaign.start_repair(booked)

	_hq._show_tab(TAB_WORKSHOP)


## Give the shops something to sell, or the market screen only ever shows its
## empty state.
func _open_stocked_market() -> void:
	var state: GameState = Game.campaign.state
	state.diamonds += 40000
	Game.campaign.upgrade_facility(FacilityLibrary.ARMOURY)
	Game.campaign.upgrade_facility(FacilityLibrary.ARMOURY)
	Game.campaign.upgrade_facility(FacilityLibrary.WAREHOUSE)
	Game.campaign.buy_item(ItemLibrary.get_item(&"service_carbine"))
	Game.campaign.buy_item(ItemLibrary.get_item(&"battle_rifle"))
	_hq._show_tab(TAB_MARKET)


func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 1:
		DisplayServer.window_set_size(WINDOW_SIZE)
		root.size = WINDOW_SIZE
		# Before the HQ comes up: its _ready calls Game.ensure_started(), which
		# keeps whatever is already there.
		Game.start_seeded(SEED)
		var scene: PackedScene = load("res://ui/hq.tscn")
		_hq = scene.instantiate()
		root.add_child(_hq)
		_check_tabs_match()
		return false

	if _frames < SETTLE:
		return false

	# One step per settling window: act, let it lay out, capture, move on.
	var index: int = (_frames - SETTLE) / SETTLE
	var phase: int = (_frames - SETTLE) % SETTLE

	if index >= _steps.size():
		return true

	var step: Dictionary = _steps[index]
	if phase == 0:
		step["do"].call()
	elif phase == SETTLE - 1:
		_capture(step["shot"])

	return false


## Select a contract, forced into the tallest shape the panel can take.
##
## The side panel grows with the contract: an assassination adds a TARGET block,
## a call-up replaces the expiry line with a longer warning, and a hazard region
## adds another. All three at once used to push the panel past the window and
## carry the header off the top of the screen with it, so that is the case worth
## capturing rather than whichever contract happened to be first.
func _select_contract() -> void:
	var screen: Control = _hq._screen
	var board: Array = Game.campaign.state.board
	if not (screen is ContractsScreen) or board.is_empty():
		return

	var mission: MissionData = board[0]
	mission.mission_type = GameEnums.MissionType.ASSASSINATION
	mission.target_name = "Akinyi Ochieng"
	mission.target_title = "regional warlord and arms broker"
	mission.is_call_up = true

	(screen as ContractsScreen)._selected = mission
	(screen as ContractsScreen).refresh()


func _open_builder() -> void:
	_hq._show_tab(TAB_CONTRACTS)
	var board: Array = Game.campaign.state.board
	if not board.is_empty():
		_hq._open_squad_builder(board[0])


func _fill_squad() -> void:
	var builder: Control = _hq._screen
	if builder == null or not builder is SquadBuilder:
		return
	var free: Array = Game.campaign.state.available_operators()
	for i in mini(4, free.size()):
		builder._squad.add(free[i], free[i].preferred_role)
	if builder._squad.size() > 0:
		builder._squad.set_leader(builder._squad.members()[0])
	builder.refresh()


## The squad builder once the company has a past.
##
## Bonds are the point of that screen and cannot exist on day one, so the
## capture above can never show them however long it is stared at. This one runs
## after the campaign has been played forward and deliberately picks the people
## who have history with each other — otherwise the shot is of an empty column
## and proves nothing.
## The board once the company has been places.
##
## The map draws the company's own record — somewhere it has worked runs ochre
## and heavier, somewhere it has buried people carries a ring — and none of that
## can exist in the day-one capture. Without this shot the whole of RegionLog is
## unphotographed, and a regression in it would be invisible.
func _rest_and_show_board() -> void:
	# The drawer from the step before is still open and would sit over this whole
	# capture — a drawer stays put across screen changes by design.
	_hq._close_drawer()
	_hq._incident_modal.hide()

	# Everyone who has been through enough contracts to have history is, by that
	# same fact, hurt or spent — so at the end of the run above the deployable
	# list is empty and the builder has nobody to show. Stand the company down
	# until its veterans can be sent somewhere again.
	for i in 60:
		if Game.campaign.state.deployable_operators().size() >= 3:
			break
		_hq._on_end_day_pressed()
		_hq._after_action.hide()
		_hq._incident_modal.hide()

	_hq._show_tab(TAB_CONTRACTS)

	var state: GameState = Game.campaign.state
	var worked := 0
	for region_id in RegionLibrary.ids():
		if RegionLog.has_history(state, region_id):
			worked += 1
	print("  [check] the map has somewhere to remember (%d regions worked): %s" % [
		worked, "OK" if worked > 0 else "FAIL"])


func _open_builder_with_history() -> void:
	_hq._show_tab(TAB_CONTRACTS)
	var board: Array = Game.campaign.state.board
	if board.is_empty():
		return
	_hq._open_squad_builder(board[0])

	var builder: Control = _hq._screen
	if not builder is SquadBuilder:
		return

	var free: Array = Game.campaign.state.deployable_operators()
	var ranked: Array = free.duplicate()
	ranked.sort_custom(func(a, b):
		return UiStyle.bonds_with(a, free).size() > UiStyle.bonds_with(b, free).size())
	for i in mini(4, ranked.size()):
		(builder as SquadBuilder)._squad.add(ranked[i], ranked[i].preferred_role)
	if (builder as SquadBuilder)._squad.size() > 0:
		(builder as SquadBuilder)._squad.set_leader(
			(builder as SquadBuilder)._squad.members()[0])
	builder.refresh()

	# A capture that quietly shows nothing is worse than no capture: it looks
	# like the feature works and would survive the feature being deleted.
	var ties: int = UiStyle.bond_ties((builder as SquadBuilder)._squad.members()).size()
	print("  [check] the builder has history to show (%d ties): %s" % [
		ties, "OK" if ties > 0 else "FAIL"])


## Deploy, then end days until the squad comes home, so the after-action modal
## has something real to show.
func _deploy_and_run() -> void:
	var builder: Control = _hq._screen
	if builder is SquadBuilder:
		(builder as SquadBuilder)._on_deploy_pressed()

	for i in 8:
		if Game.campaign.state.deployments.is_empty() and i > 0:
			break
		_hq._on_end_day_pressed()


## The tallest the debrief ever gets: every kill line expanded. If the card fits
## here it fits anywhere.
func _open_kill_feed() -> void:
	for node in _hq._after_action.find_children("*", "Button", true, false):
		if node.text.begins_with("Show kill feed"):
			node.pressed.emit()
			return
	printerr("CHECK after-action had no kill feed toggle to open")


## The Intel screen with a contract and a team already picked, so the footer
## shows the real trade rather than "pick a contract".
func _open_intel() -> void:
	_hq._show_tab(TAB_INTEL)
	var screen: Control = _hq._screen
	if screen == null or not screen is IntelScreen:
		printerr("CHECK intel tab did not open the intel screen")
		return

	var state := Game.campaign.state
	for mission in state.board:
		if not mission.scouted and not mission.is_being_scouted():
			screen._target = mission
			break

	for op in Game.campaign.intel_candidates():
		if screen._team.size() >= Balance.INTEL_MAX_TEAM:
			break
		screen._team.append(op)
	screen.refresh()


## Close the after-action modal, then set a class running so the Training screen
## has an in-progress session to show rather than three empty columns.
## Standing work with a job selected, so the panel shows the staffing controls
## rather than its "pick one" state.
func _open_standing_work() -> void:
	_hq._show_tab(TAB_CONTRACTS)
	var screen: Control = _hq._screen
	if not (screen is ContractsScreen):
		printerr("CHECK contracts tab did not open the contracts screen")
		return

	screen._showing_side_jobs = true
	var jobs: Array = Game.campaign.state.side_jobs
	if jobs.is_empty():
		printerr("CHECK no standing work on offer to capture")
	else:
		screen._selected_job = jobs[0]
	screen.refresh()


## Force an incident onto the desk. Rolling for one would make this screenshot
## depend on a 26% chance and a cooldown, so the modal is fed directly.
func _raise_incident() -> void:
	var incident := IncidentLibrary.roll(Game.campaign, Game.campaign.rng)
	if incident.is_empty():
		printerr("CHECK no incident fitted the company state")
		return
	_hq._incident_modal.show_incident(incident)


## The other kind of decision: the squad is already out, and something has come
## up that the briefing did not cover. Forced rather than rolled, for the same
## reason as the incident above — the capture should not depend on a dice roll.
func _raise_field_event() -> void:
	_hq._incident_modal.hide()

	# By this point a class has two people in it and the last debrief left others
	# in the infirmary, so there is often nobody left to send. Patching them up
	# keeps the capture from depending on what an earlier step happened to leave
	# behind.
	for op in Game.campaign.state.roster:
		if op.status == GameEnums.OperatorStatus.INJURED:
			op.days_unavailable = 0
			op.status = GameEnums.OperatorStatus.AVAILABLE
	_force_deployment()

	var deployments: Array = Game.campaign.state.deployments
	if deployments.is_empty():
		printerr("CHECK nobody in the field to raise a situation with")
		return

	# A day in, so the card reads as the middle of a contract rather than its
	# first hour — which is also the only time the decision is interesting. Never
	# past the last day: the tick that resolves a contract is not one a decision
	# can land on.
	var deployment: Deployment = deployments[0]
	if deployment.days_remaining > 1:
		deployment.days_remaining -= 1

	# Drawn until it is the one that can end the contract, because the two steps
	# after this take that option and follow it through to the debrief — the
	# longest chain of modals the game has, and the one worth capturing.
	var event: Dictionary = {}
	for attempt in 30:
		event = FieldEventLibrary.roll(Game.campaign, deployment, Game.campaign.rng)
		if event.get("id", &"") == &"bigger_than_briefed":
			break
	if event.is_empty():
		printerr("CHECK no situation fitted the contract in flight")
		return

	# The dock counts who is in the field, and this step put somebody there
	# behind its back.
	_hq._refresh_all()
	_hq._incident_modal.show_incident(event)


## Take the last option on the card — on the situation forced above that is
## calling the contract off — and capture the second beat, where the player finds
## out whether the price they were quoted was the price they paid.
func _take_field_decision() -> void:
	var options: Array = _hq._incident_modal._options.get_children()
	if options.is_empty():
		printerr("CHECK the field card had no options to take")
		return
	(options[options.size() - 1] as Button).pressed.emit()


## Close it, which is where the longest chain in the game runs: a decision ends a
## contract, so the debrief for that contract has to arrive before anything else
## the day had queued up.
func _close_field_decision() -> void:
	_hq._incident_modal._done_button.pressed.emit()
	if not _hq._after_action.visible:
		printerr("CHECK calling a contract off did not produce a debrief")


func _dismiss_modal_and_train() -> void:
	_hq._after_action.hide()
	_hq._incident_modal.hide()
	var state: GameState = Game.campaign.state

	# Bring everyone home first, or every possible mentor is still in the field
	# and the screen only ever shows its empty state.
	for i in 12:
		if state.deployments.is_empty():
			break
		_hq._on_end_day_pressed()
		_hq._after_action.hide()

	var mentors: Array = state.potential_mentors()
	for mentor in mentors:
		for trainee in state.available_operators():
			if Progression.can_train(mentor, trainee):
				Game.campaign.start_training(mentor, trainee)
				break
		if not state.training.is_empty():
			break

	_hq._show_tab(TAB_TRAINING)


## Keep deploying and ending days until somebody is buried, so the Cemetery
## screen is shown with real entries rather than its empty state.
func _run_until_losses() -> void:
	# Whatever decision was on screen has been captured; leaving it up would put
	# a modal over every screenshot after this one.
	_hq._incident_modal.hide()
	for i in 90:
		if Game.campaign.state.cemetery.size() >= 2:
			break
		_force_deployment()
		_hq._on_end_day_pressed()
		_hq._after_action.hide()
	_hq._show_tab(TAB_CEMETERY)


func _force_deployment() -> void:
	var state: GameState = Game.campaign.state
	var free: Array = state.deployable_operators()
	if free.size() < 3 or state.board.is_empty():
		return
	var squad := Squad.new()
	for i in mini(4, free.size()):
		squad.add(free[i], free[i].preferred_role)
	squad.set_leader(free[0])
	Game.campaign.deploy(squad, state.board[0])


## Open the inventory drawer while sitting on another screen — the whole point
## of a drawer is that the screen underneath stays put.
##
## Opened on the copy with the most on its record, because an unselected panel
## photographs the empty state and the service record is the half worth checking.
func _open_inventory_drawer() -> void:
	_hq._show_tab(TAB_ROSTER)
	_hq._toggle_drawer("stock", "Inventory",
		load("res://ui/inventory_screen.tscn"))

	# This save never issued kit to a squad, so nothing in it has a record worth
	# photographing. Built here through the real writers, the way a played
	# company accumulates one — sim_campaign.gd is what proves the game does it.
	var state: GameState = Game.campaign.state
	var rifle: ItemInstance = null
	for instance in state.inventory:
		if instance.item_id == &"battle_rifle":
			rifle = instance
	var carrier: OperatorData = state.roster[0] if not state.roster.is_empty() else null

	if rifle != null and carrier != null:
		var job := MissionFactory.create(Game.campaign.rng, GameEnums.MissionType.ASSAULT)
		Game.campaign.equip(carrier, rifle, ItemData.Slot.WEAPON)
		ItemHistory.record_kills(rifle, carrier, 9, 12, job)
		rifle.contracts = 7
		ItemHistory.record_broken(rifle, 18, job)
		ItemHistory.record_rebuild(rifle, 21)
		if not state.cemetery.is_empty():
			ItemHistory.record_loss(rifle, state.cemetery[0], 24, job)
			ItemHistory.record_issue(rifle, carrier, 25)

	var screen = _hq._drawer_content.get_child(0)
	if rifle != null and screen != null:
		screen._selected_uid = rifle.uid
		screen.refresh()


func _capture(name: String) -> void:
	_check_shell_intact(name)

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var path := "%s/%s.png" % [OUT_DIR, name]
	var image: Image = root.get_texture().get_image()
	if image.save_png(path) == OK:
		print("Saved %s" % path)
	else:
		printerr("save_png failed for %s" % path)


## The header and the dock must stay where they are on every screen.
##
## A screen whose content is taller than the content area grows the shell's
## VBoxContainer past the window, and because the layout grows from its centre
## the header slides off the top and the dock off the bottom — the two things
## always meant to be reachable. An assassination contract did exactly this: its
## detail panel carries an extra TARGET block, and that one block was enough.
## Cheaper to assert than to notice in a PNG.
func _check_shell_intact(name: String) -> void:
	var header: Control = _hq.get_node("Layout/Header")
	var status: Control = _hq.get_node("Layout/StatusBar")
	var bottom: float = status.global_position.y + status.size.y

	if header.global_position.y < -0.5:
		printerr("CHECK %s: header pushed off the top (y=%.0f)"
			% [name, header.global_position.y])
	if bottom > float(WINDOW_SIZE.y) + 0.5:
		printerr("CHECK %s: dock pushed off the bottom (y=%.0f, window %d)"
			% [name, bottom, WINDOW_SIZE.y])

	# The dock quotes storage, and so does the Market. A stale dock made the two
	# disagree on screen at the same time, which reads as a broken game rather
	# than a stale label.
	var state := Game.campaign.state
	var expected := "%d/%d" % [state.storage_used(), state.storage_capacity()]
	var found := false
	for label in status.find_children("*", "Label", true, false):
		if label.text == expected:
			found = true
			break
	if not found:
		printerr("CHECK %s: dock storage is stale, expected %s" % [name, expected])


## The hand-written mirror above must still match hq.gd's Tab enum.
##
## It did not, once: a tab was inserted in the middle and TAB_CEMETERY kept
## pointing at Clients, so a screenshot named "cemetery" was of another screen
## entirely and nothing complained. Reading the real enum off the script costs
## one call and makes that impossible.
func _check_tabs_match() -> void:
	var expected := {
		"ROSTER": TAB_ROSTER,
		"CONTRACTS": TAB_CONTRACTS,
		"RECRUITS": TAB_RECRUITS,
		"TRAINING": TAB_TRAINING,
		"INTEL": TAB_INTEL,
		"BASE": TAB_BASE,
		"MARKET": TAB_MARKET,
		"WORKSHOP": TAB_WORKSHOP,
		"CLIENTS": TAB_CLIENTS,
		"BONDS": TAB_BONDS,
		"CEMETERY": TAB_CEMETERY,
	}
	var actual: Dictionary = _hq.get_script().get_script_constant_map().get("Tab", {})
	if actual.is_empty():
		printerr("CHECK could not read hq.gd's Tab enum")
		return
	for key in expected:
		if not actual.has(key):
			printerr("CHECK hq.gd has no Tab.%s" % key)
		elif int(actual[key]) != int(expected[key]):
			printerr("CHECK Tab.%s is %d in hq.gd, %d here"
				% [key, int(actual[key]), int(expected[key])])
	for key in actual:
		if not expected.has(key):
			printerr("CHECK hq.gd added Tab.%s and this mirror does not know it" % key)
