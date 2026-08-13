class_name ContractsScreen
extends VBoxContainer

## The board, shown as an operations map. Contracts sit where the work is; click
## one and the side panel says what it is.
##
## Standing work shares this screen rather than getting its own tab, because the
## trade-off between a contract and a side job is the decision, and splitting
## them across tabs would hide it.

signal assemble_requested(mission: MissionData)

@onready var _map: WorldMap = %Map
@onready var _map_panel: PanelContainer = %MapPanel
@onready var _list_scroll: ScrollContainer = %ListScroll
@onready var _list: VBoxContainer = %ContractList
@onready var _side: PanelContainer = %Side
@onready var _side_head: VBoxContainer = %SideHead
@onready var _side_box: VBoxContainer = %SideBox
@onready var _assemble_button: Button = %AssembleButton
@onready var _scout_button: Button = %ScoutButton
@onready var _empty_hint: Label = %EmptyHint
@onready var _hint: Label = %Hint

var _selected: MissionData = null
var _showing_side_jobs := false
var _selected_job: SideJobData = null


func _ready() -> void:
	_map_panel.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.INK, UiStyle.RULE))
	_side.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.PANEL))
	_map.contract_clicked.connect(func(mission: MissionData):
		_selected = mission
		refresh()
	)
	%ContractsMode.pressed.connect(func():
		_showing_side_jobs = false
		refresh()
	)
	%StandingMode.pressed.connect(func():
		_showing_side_jobs = true
		refresh()
	)


func refresh() -> void:
	var state := Game.campaign.state

	%ContractsMode.button_pressed = not _showing_side_jobs
	%StandingMode.button_pressed = _showing_side_jobs

	_map_panel.visible = not _showing_side_jobs
	_list_scroll.visible = _showing_side_jobs

	# The footer line belongs to whichever mode is showing. Standing work does
	# not expire off a board the player is watching; it expires off this list.
	_hint.text = (
		"Standing work is what the bench is for. It pays badly on purpose."
		if _showing_side_jobs
		else "Contracts expire. Letting the board rot is itself a decision.")

	for child in _list.get_children():
		child.queue_free()
	for child in _side_box.get_children():
		child.queue_free()
	for child in _side_head.get_children():
		child.queue_free()

	if _showing_side_jobs:
		_refresh_side_jobs(state)
		return

	_empty_hint.visible = state.board.is_empty()
	_assemble_button.visible = true

	if _selected != null and not state.board.has(_selected):
		_selected = null

	_map.show_board(state.board, _selected)
	_build_contract_detail()
	_assemble_button.disabled = _selected == null


# --- Contract detail ---------------------------------------------------------

## The panel is in two halves, and which half a thing lands in is the whole of
## the information hierarchy here.
##
## The HEAD is pinned and never scrolls: what this job is, how hard it is, and
## what the company makes of it. That is the decision, and it used to be the
## part that fell off the bottom — the assessment sat below the fold behind four
## blocks of supporting prose, so the one thing the player is on this screen to
## learn was the one thing they had to go looking for.
##
## The BODY scrolls: the briefing, what the job asks for, the client, the
## ground. All of it worth reading, none of it worth pushing the decision off
## the screen.
func _build_contract_detail() -> void:
	if _selected == null:
		_scout_button.visible = false
		_side_head.add_child(UiStyle.text(
			"Pick a contract off the map.", UiStyle.SIZE_BODY, UiStyle.TEXT_3))
		_side_head.add_child(UiStyle.spacer(8))
		var legend := UiStyle.text(
			"Marker size is difficulty. Colour is how lethal it is if it goes wrong.",
			UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
		legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_side_head.add_child(legend)

		_side_head.add_child(UiStyle.spacer(4))
		var places := UiStyle.text(
			"Ochre places are ones the company has worked, heavier the more often. A ring means somebody died there.",
			UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
		places.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_side_head.add_child(places)
		return

	var mission := _selected
	_build_contract_head(mission)
	_build_contract_body(mission)
	_refresh_scout_button()


func _build_contract_head(mission: MissionData) -> void:
	_side_head.add_child(UiStyle.title(mission.title, UiStyle.SIZE_TITLE))

	# The kind of work and the money are the two facts that decide whether a
	# contract is worth reading at all, so they lead rather than sitting in a
	# grey line of small print with the region.
	var headline := HBoxContainer.new()
	headline.add_theme_constant_override("separation", 8)
	headline.add_child(UiStyle.pill(
		mission.type_name(), UiStyle.mission_type_color(mission.mission_type)))
	headline.add_child(UiStyle.pill(
		"%d diamonds" % mission.fee_for(Game.campaign.state.reputation), UiStyle.MINT))
	var where := UiStyle.text(mission.region_name(), UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
	where.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	where.clip_text = true
	where.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	headline.add_child(where)
	_side_head.add_child(headline)

	_side_head.add_child(UiStyle.rule())

	# Threat, danger and duration share one row. They are three captioned figures
	# of the same shape, and stacking them cost sixty pixels of pinned height for
	# nothing — height this panel spends better on the assessment below.
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	var threat := UiStyle.threat_block(mission.difficulty)
	UiStyle.grow(threat)
	stats.add_child(threat)
	var danger := UiStyle.stat(
		"Danger", "%.0f" % mission.risk, UiStyle.risk_color(mission.risk), 70)
	danger.tooltip_text = "How likely the people you send come home hurt or not at all. Separate from threat — a quiet job in a lethal place is low threat and high danger."
	stats.add_child(danger)
	stats.add_child(UiStyle.stat("Days", str(mission.duration_days), UiStyle.TEXT_2, 50))
	_side_head.add_child(stats)

	_side_head.add_child(UiStyle.rule())

	# Can we even do this? Answered before the player builds a squad to find out.
	_side_head.add_child(_capability_readout(mission))


func _build_contract_body(mission: MissionData) -> void:
	if not mission.briefing.is_empty():
		_side_box.add_child(UiStyle.eyebrow("Briefing"))
		var brief := UiStyle.text(mission.briefing, UiStyle.SIZE_SMALL, UiStyle.TEXT_2)
		brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_side_box.add_child(brief)
		_side_box.add_child(UiStyle.spacer(2))

	# What the job actually asks for, stated before the player opens the squad
	# builder. Finding out that escort work wants five people and a medic by
	# assembling four and watching the score drop is a puzzle with the pieces
	# face down.
	_side_box.add_child(UiStyle.eyebrow("What it asks for"))
	_side_box.add_child(_requirements_readout(mission))

	var region_hazard := mission.region()
	if region_hazard != null and region_hazard.hazard != GameEnums.Hazard.NONE:
		_side_box.add_child(UiStyle.spacer(4))
		# Wrapped. Without this the sentence's natural width became the panel's
		# minimum width, and the panel took it out of the map beside it.
		var hazard_note := UiStyle.text(
			"%s country. Without the kit that cancels it, everyone you send is more likely to be hurt." % (
				GameEnums.hazard_country(region_hazard.hazard)),
			UiStyle.SIZE_SMALL, UiStyle.OCHRE)
		hazard_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_side_box.add_child(hazard_note)

	if not mission.target_name.is_empty():
		_side_box.add_child(UiStyle.spacer(4))
		_side_box.add_child(UiStyle.eyebrow("Target"))
		var target_label := UiStyle.text(
			"%s — %s" % [mission.target_name, mission.target_title],
			UiStyle.SIZE_BODY, UiStyle.RUST)
		target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_side_box.add_child(target_label)

	_side_box.add_child(UiStyle.spacer(4))
	var client := mission.client()
	if client != null:
		_side_box.add_child(UiStyle.eyebrow("Client"))
		var client_label := UiStyle.text(client.display_name, UiStyle.SIZE_BODY)
		client_label.clip_text = true
		client_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_side_box.add_child(client_label)
		var note := UiStyle.text(client.preference_note, UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_side_box.add_child(note)

	var region := mission.region()
	if region != null:
		_side_box.add_child(UiStyle.spacer(4))
		_side_box.add_child(UiStyle.eyebrow("Ground"))
		var ground := UiStyle.text(region.emphasis_note, UiStyle.SIZE_SMALL, UiStyle.TEXT_2)
		ground.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_side_box.add_child(ground)

	# What the company already knows about this place from having been there.
	# Absent entirely the first time, which is the point — somewhere the company
	# has worked four times and buried two people should not read like somewhere
	# it has only ever seen on a map.
	var history := RegionLog.summary(Game.campaign.state, mission.region_id)
	if not history.is_empty():
		_side_box.add_child(UiStyle.spacer(4))
		_side_box.add_child(UiStyle.eyebrow("Our record here"))
		var record := UiStyle.text(history, UiStyle.SIZE_SMALL, UiStyle.TEXT_2)
		record.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_side_box.add_child(record)

	_side_box.add_child(UiStyle.spacer(4))
	var expiry_color: Color = (
		UiStyle.RUST if mission.expires_in_days <= 2 else UiStyle.TEXT_3)
	var expiry: String = "Offer stands for %s." % (
		TextUtil.count(mission.expires_in_days, "more day"))
	if mission.is_call_up:
		expiry = "CALL-UP. %s will fine you if this expires unanswered." % mission.client_name()
		expiry_color = UiStyle.RUST
	var expiry_label := UiStyle.text(expiry, UiStyle.SIZE_SMALL, expiry_color)
	expiry_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side_box.add_child(expiry_label)


## The best squad the company could field, and what it would score. A bar the
## player can read in a second, so the map answers "is this for us" without a
## detour through the squad builder.
## Squad size, the roles the job will not go without, and the skills it tests.
##
## All three already exist in MissionProfile and all three were invisible until
## the score moved. Reading them off the profile rather than restating them means
## they cannot drift from what the resolver actually does.
func _requirements_readout(mission: MissionData) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)

	var profile := MissionResolver.profile_for(mission.mission_type)
	if profile == null:
		var vague := UiStyle.text(
			"Nothing specific — bring who you can.", UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
		vague.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(vague)
		return box

	var size_label := UiStyle.text(
		Ovr.size_note(profile), UiStyle.SIZE_SMALL, UiStyle.TEXT_2)
	size_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(size_label)

	if not profile.required_roles.is_empty():
		var roles := HBoxContainer.new()
		roles.add_theme_constant_override("separation", 10)
		roles.add_child(UiStyle.text("Must include", UiStyle.SIZE_SMALL, UiStyle.TEXT_3))
		for role in profile.required_roles:
			roles.add_child(UiStyle.role_tag(role, UiStyle.SIZE_SMALL))
		box.add_child(roles)

	# What the job tests, split into what it is chiefly about and what it merely
	# also wants. "Tested on stealth, tech and combat" gave three skills equal
	# billing where the profile weights them 0.55/0.25/0.20 — true, and no use for
	# choosing between two people who are strong in different ones.
	#
	# No squad here, so this prints the requirement and nothing else. The same
	# block on the briefing panel draws a bar per skill, because there a squad
	# exists to measure against it.
	box.add_child(UiStyle.spacer(2))
	box.add_child(UiStyle.work_emphasis_block(profile))

	return box


## What the company makes of this job, measured against the best squad it could
## actually put on it.
##
## This used to be a percentage. It is a band and a short list of what is wrong
## now, because the percentage answered the question the board exists to ask.
## "95%" ends the screen; "Favourable, but you are two over strength for quiet
## work and Ash is exhausted" sends the player to the squad builder with
## something to do when they get there.
##
## Deliberately still no names. Telling the player exactly who to send removes
## the decision this screen sets up — the band says whether the contract is
## within reach, and working out who goes is the game.
func _capability_readout(mission: MissionData) -> Control:
	var squad := Game.campaign.best_available_squad(mission)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	if squad.size() == 0:
		box.add_child(UiStyle.eyebrow("Our assessment"))
		box.add_child(UiStyle.text(
			"Nobody is free to take this.", UiStyle.SIZE_BODY, UiStyle.RUST))
		return box

	var report := Game.campaign.preview_mission(squad, mission)
	box.add_child(UiStyle.assessment_block(report, "Best we could field"))

	var concerns := UiStyle.assessment_concerns(report, 2)
	if not concerns.is_empty():
		box.add_child(UiStyle.eyebrow("Concerns"))
		box.add_child(UiStyle.concerns_readout(report, 2))
	return box


func _refresh_scout_button() -> void:
	var campaign := Game.campaign
	_scout_button.visible = true

	if _selected.scouted:
		_scout_button.text = "Already cased"
		_scout_button.disabled = true
	elif _selected.is_being_scouted():
		_scout_button.text = "Scouting (%dd)" % _selected.scout_days_remaining
		_scout_button.disabled = true
	elif campaign.state.facility_level(FacilityLibrary.INTELLIGENCE) <= 0:
		_scout_button.text = "No Intelligence Centre"
		_scout_button.disabled = true
	else:
		_scout_button.text = "Scout (%d, %dd)" % [
			campaign.scout_cost(), campaign.scout_days_for()]
		_scout_button.disabled = not campaign.can_scout(_selected)


func _on_scout_pressed() -> void:
	if _selected != null and Game.campaign.scout(_selected):
		refresh()


func _on_assemble_pressed() -> void:
	if _selected != null:
		assemble_requested.emit(_selected)


# --- Standing work -----------------------------------------------------------

func _refresh_side_jobs(state: GameState) -> void:
	_empty_hint.visible = state.side_jobs.is_empty()
	_scout_button.visible = false
	_assemble_button.visible = false

	if _selected_job != null and not state.side_jobs.has(_selected_job):
		_selected_job = null

	for job in state.side_jobs:
		_list.add_child(_make_job_row(job))
	for detachment in state.detachments:
		_list.add_child(_make_detachment_row(detachment))

	if _selected_job == null:
		var bench := UiStyle.text(
			"Standing work pays badly and takes one operator. It is what the bench is for.",
			UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
		bench.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_side_box.add_child(bench)
		return

	var job := _selected_job
	_side_box.add_child(UiStyle.title(job.title, UiStyle.SIZE_TITLE))

	var headline := HBoxContainer.new()
	headline.add_theme_constant_override("separation", 8)
	headline.add_child(UiStyle.pill("Standing work", UiStyle.STEEL))
	headline.add_child(UiStyle.pill("%d diamonds" % job.base_pay, UiStyle.MINT))
	_side_box.add_child(headline)

	var description := UiStyle.text(job.description, UiStyle.SIZE_SMALL, UiStyle.TEXT_2)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side_box.add_child(description)

	_side_box.add_child(UiStyle.spacer(6))
	_side_box.add_child(UiStyle.rule())
	_side_box.add_child(UiStyle.spacer(6))

	var facts := HBoxContainer.new()
	facts.add_theme_constant_override("separation", 4)
	facts.add_child(UiStyle.stat(
		"Tests", GameEnums.skill_name(job.key_skill), UiStyle.TEXT_2, 108))
	facts.add_child(UiStyle.stat("Wants", "%d" % int(job.expectation), UiStyle.TEXT_2, 66))
	facts.add_child(UiStyle.stat("Days", str(job.duration_days), UiStyle.TEXT_2, 56))
	facts.add_child(UiStyle.stat(
		"Expires", "%dd" % job.expires_in_days,
		UiStyle.RUST if job.expires_in_days <= 2 else UiStyle.TEXT_3, 72))
	_side_box.add_child(facts)

	_side_box.add_child(UiStyle.spacer(8))
	_side_box.add_child(UiStyle.eyebrow("Who goes"))

	# Sorted by how well suited they are, because the whole decision is "who is
	# least wasted on this". An unsorted roster makes the player do that by hand.
	var candidates: Array[OperatorData] = []
	for op in Game.campaign.state.deployable_operators():
		candidates.append(op)
	candidates.sort_custom(func(a, b): return job.suitability(a) > job.suitability(b))

	if candidates.is_empty():
		var nobody := UiStyle.text(
			"Nobody is free. Standing work needs someone who could otherwise deploy.",
			UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
		nobody.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_side_box.add_child(nobody)
		return

	var picker := OptionButton.new()
	picker.custom_minimum_size.y = 34
	picker.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL)
	picker.add_item("Send nobody")
	for op in candidates:
		picker.add_item("%s   ·   suits %d" % [
			op.display_label(), int(job.suitability(op))])
	_side_box.add_child(picker)

	var send := UiStyle.confirm_button("Send", "Confirm — send them", func():
		var index: int = picker.selected
		if index <= 0:
			return
		if Game.campaign.assign_detachment(job, candidates[index - 1]) != null:
			_selected_job = null
			refresh()
	, 200)
	send.disabled = true
	picker.item_selected.connect(func(index: int):
		send.disabled = index <= 0
	)
	_side_box.add_child(send)


## A summary, not a control panel.
##
## Every row used to carry its own operator dropdown and Send button while the
## side panel showed only a title and a description — so the list was where you
## acted and the panel was decoration, which is the reverse of how Contracts mode
## works two clicks away. Selecting a job now fills the panel and the panel is
## where it gets staffed, so both halves of this screen behave the same way.
func _make_job_row(job: SideJobData) -> Button:
	var button := UiStyle.row_button(job == _selected_job)
	button.custom_minimum_size.y = UiStyle.ROW_HEIGHT_COMPACT
	button.pressed.connect(func():
		_selected_job = job
		refresh()
	)

	var row := UiStyle.row_content(button)
	row.add_child(UiStyle.identity(
		job.title,
		"%s   ·   wants %d   ·   %s" % [
			GameEnums.skill_name(job.key_skill),
			int(job.expectation),
			TextUtil.count(job.duration_days, "day"),
		]))
	row.add_child(UiStyle.stat("Pays", str(job.base_pay), UiStyle.MINT, 88))
	row.add_child(UiStyle.stat(
		"Expires", "%dd" % job.expires_in_days,
		UiStyle.RUST if job.expires_in_days <= 2 else UiStyle.TEXT_3, 68))
	return button


func _make_detachment_row(detachment: Detachment) -> Control:
	var card := PanelContainer.new()
	var style := UiStyle.panel(UiStyle.PANEL)
	style.border_color = UiStyle.STEEL
	style.border_width_left = 3
	card.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	row.add_child(UiStyle.identity(
		detachment.job.title,
		"%s is out on this" % detachment.operator.display_label()))
	row.add_child(UiStyle.stat(
		"Back in", "%dd" % detachment.days_remaining, UiStyle.STEEL, 78))

	return card
