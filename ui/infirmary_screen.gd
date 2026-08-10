class_name InfirmaryScreen
extends VBoxContainer

## Who is hurt, how long for, and what it is costing.
##
## Lives as a drawer rather than a tab because it is a thing you consult while
## doing something else — halfway through building a squad, wondering whether
## the medic is back yet. Making that a tab switch would mean losing the squad
## you were assembling.

@onready var _list: VBoxContainer = %PatientList
@onready var _summary: Label = %Summary


func refresh() -> void:
	var state := Game.campaign.state

	for child in _list.get_children():
		child.queue_free()

	var patients: Array = []
	for op in state.roster:
		if op.status == GameEnums.OperatorStatus.INJURED:
			patients.append(op)
	patients.sort_custom(func(a, b): return a.days_unavailable < b.days_unavailable)

	var relief: float = state.facility_effect(FacilityLibrary.INFIRMARY)
	var weekly := Economy.medical_cost(state)

	if patients.is_empty():
		_summary.text = "Nobody is hurt. The infirmary is costing you nothing this week."
		_summary.add_theme_color_override("font_color", UiStyle.MINT)
		_list.add_child(UiStyle.text(
			"Everyone is fit for duty.", UiStyle.SIZE_SMALL, UiStyle.TEXT_3))
		return

	_summary.text = "%s in the infirmary · %d a week in medical · recovery %d%% faster" % [
		TextUtil.count(patients.size(), "operator"),
		weekly,
		int(round(relief * 100.0)),
	]
	_summary.add_theme_color_override("font_color", UiStyle.RUST)

	for op in patients:
		_list.add_child(_make_row(op))


func _make_row(op: OperatorData) -> Control:
	var card := PanelContainer.new()
	var style := UiStyle.panel(UiStyle.ROW)
	style.border_color = UiStyle.RUST
	style.border_width_left = 3
	card.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	row.add_child(UiStyle.portrait(op, 34))
	row.add_child(UiStyle.role_icon(op.preferred_role, UiStyle.SIZE_HEADING))
	row.add_child(UiStyle.operator_identity(
		op, "%s   ·   %s" % [GameEnums.role_name(op.preferred_role), op.demonym()]))

	# The number the player is actually here for.
	row.add_child(UiStyle.stat(
		"Back in", TextUtil.count(op.days_unavailable, "day"), UiStyle.OCHRE, 96))
	row.add_child(UiStyle.stat(
		"Morale", str(op.morale),
		UiStyle.RUST if op.morale <= Balance.MORALE_DESERTION_THRESHOLD else UiStyle.TEXT_2,
		70))

	return card
