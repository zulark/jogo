class_name IntelScreen
extends VBoxContainer

## Casing contracts. Pick a job, pick who goes to look at it, lose them for days.
##
## The Intelligence Centre can buy a look at a contract on its own — that is the
## Scout button on the board, and it is desk work. This is the other way: people
## on the ground come back with more, and cost no money at all. What they cost
## is time, and the operators best at casing (scouts, engineers) are often the
## ones the squad wanted.
##
## Exhausted operators can still be sent. Casing is the one job the field will
## not take them off, so the bench has something to do besides recover.

signal roster_changed()

@onready var _target_list: VBoxContainer = %TargetList
@onready var _team_list: VBoxContainer = %TeamList
@onready var _team_heading: Label = %TeamHeading
@onready var _active_list: VBoxContainer = %ActiveList
@onready var _send_button: Button = %SendButton
@onready var _summary: Label = %Summary

var _target: MissionData = null
var _team: Array[OperatorData] = []


func refresh() -> void:
	var state := Game.campaign.state
	var campaign := Game.campaign

	for child in _target_list.get_children():
		child.queue_free()
	for child in _team_list.get_children():
		child.queue_free()
	for child in _active_list.get_children():
		child.queue_free()

	# A contract already cased, already being cased, or already out with a team
	# is not a target. Showing it would be offering a decision that does nothing.
	var targets: Array = []
	for mission in state.board:
		if mission.scouted or mission.is_being_scouted():
			continue
		if state.intel_op_for(mission) != null:
			continue
		targets.append(mission)

	if _target != null and not targets.has(_target):
		_target = null
		_team.clear()

	for mission in targets:
		_target_list.add_child(_make_target_row(mission))
	if targets.is_empty():
		_target_list.add_child(_empty_note(
			"Every contract on the board is either cased already or has a team on it."))

	var candidates := campaign.intel_candidates()
	for member in _team.duplicate():
		if not candidates.has(member):
			_team.erase(member)

	_team_heading.text = "TEAM   ·   %d / %d" % [_team.size(), Balance.INTEL_MAX_TEAM]
	for op in candidates:
		_team_list.add_child(_make_person_row(op))
	if candidates.is_empty():
		_team_list.add_child(_empty_note(
			"Everyone is deployed, in a class or in the infirmary."))

	if state.intel_ops.is_empty():
		_active_list.add_child(UiStyle.text(
			"No teams are out.", UiStyle.SIZE_SMALL, UiStyle.TEXT_3))
	for intel in state.intel_ops:
		_active_list.add_child(_make_active_row(intel))

	_refresh_footer()


func _refresh_footer() -> void:
	var campaign := Game.campaign
	var can_send: bool = campaign.can_start_intel(_target, _team)
	_send_button.disabled = not can_send

	if _target == null:
		_summary.text = "Pick a contract to case."
		_summary.add_theme_color_override("font_color", UiStyle.TEXT_2)
		return

	if _team.is_empty():
		_summary.text = "%s   ·   pick who goes." % _target.title
		_summary.add_theme_color_override("font_color", UiStyle.TEXT_2)
		return

	# The whole trade in one line: what it is worth, what it costs, what can go
	# wrong. None of it is hidden, which is the same contract the odds screen
	# makes with the player everywhere else.
	var days := campaign.intel_days_for(_team)
	var rating := IntelOp.rating_of(_team)
	var expected: float = minf(
		Balance.INTEL_TEAM_MAX_BONUS * (rating / 100.0)
			+ Game.campaign.state.facility_effect(FacilityLibrary.INTELLIGENCE)
				* Balance.SCOUT_BONUS_FACTOR,
		Balance.INTEL_BONUS_CEILING)
	var caught: float = clampf(
		Balance.INTEL_MISHAP_BASE + _target.risk / 600.0 - rating / 400.0, 0.0, 0.35)

	_summary.text = "%s   ·   %s away   ·   worth about %+.1f   ·   %d%% chance of being seen" % [
		_target.title, TextUtil.count(days, "day"), expected, int(round(caught * 100.0))]
	_summary.add_theme_color_override(
		"font_color", UiStyle.RUST if caught >= 0.25 else UiStyle.TEXT_2)


func _make_target_row(mission: MissionData) -> Control:
	var selected: bool = mission == _target
	var button := UiStyle.row_button(selected)
	button.custom_minimum_size.y = UiStyle.ROW_HEIGHT
	button.pressed.connect(func():
		_target = mission
		refresh()
	)

	var row := UiStyle.row_content(button)
	row.add_child(UiStyle.identity(
		mission.title,
		"%s   ·   %dd left" % [mission.type_name(), mission.expires_in_days]))
	row.add_child(UiStyle.stat(
		"Threat", UiStyle.skull_text(mission.difficulty),
		UiStyle.skull_color(mission.difficulty), 76))
	row.add_child(UiStyle.stat(
		"Risk", "%.0f" % mission.risk, UiStyle.risk_color(mission.risk), 60))
	return button


func _make_person_row(op: OperatorData) -> Control:
	var selected: bool = _team.has(op)
	var button := UiStyle.row_button(selected)
	button.custom_minimum_size.y = UiStyle.ROW_HEIGHT
	button.pressed.connect(func():
		if _team.has(op):
			_team.erase(op)
		elif _team.size() < Balance.INTEL_MAX_TEAM:
			_team.append(op)
		refresh()
	)

	var row := UiStyle.row_content(button)
	row.add_child(UiStyle.role_icon(op.preferred_role, UiStyle.SIZE_TITLE))
	row.add_child(UiStyle.operator_identity(
		op, GameEnums.role_name(op.preferred_role)))

	# The one number that decides whether they are any good at this, made of the
	# two skills that feed it. Sorting the roster by "who can case a place" is
	# otherwise a job the player has to do by hand.
	var rating := IntelOp.rating_of([op] as Array)
	row.add_child(UiStyle.stat(
		"Casing", "%.0f" % rating,
		UiStyle.MINT if rating >= 65.0 else UiStyle.TEXT_2, 60))
	row.add_child(UiStyle.fatigue_meter(op, 74))
	return button


func _make_active_row(intel: IntelOp) -> Control:
	var card := PanelContainer.new()
	var style := UiStyle.panel(UiStyle.ROW)
	style.border_color = UiStyle.STEEL
	style.border_width_left = 3
	card.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)

	box.add_child(UiStyle.text(intel.mission.title, UiStyle.SIZE_HEADING, UiStyle.TEXT))

	var names: Array = []
	for op in intel.operators:
		names.append(op.display_label())
	var who := UiStyle.text(TextUtil.join_names(names), UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
	who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(who)

	box.add_child(UiStyle.text(
		"Back in %s" % TextUtil.count(intel.days_remaining, "day"),
		UiStyle.SIZE_SMALL, UiStyle.OCHRE))
	return card


func _empty_note(reason: String) -> Control:
	var label := UiStyle.text(reason, UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _ready() -> void:
	UiStyle.make_confirming(
		_send_button, "Send Team", "Confirm — send them", _on_send_pressed)


func _on_send_pressed() -> void:
	if Game.campaign.assign_intel(_target, _team) == null:
		return
	_target = null
	_team.clear()
	roster_changed.emit()
	refresh()
