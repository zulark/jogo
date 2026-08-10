class_name BaseScreen
extends HBoxContainer

## The base: what has been built, and what it costs to keep running.
##
## Facilities on the left, the weekly bill on the right. They sit on one screen
## on purpose — every upgrade adds a line to the sheet beside it, so the cost of
## expanding is never somewhere else.

signal company_changed()

@onready var _facility_list: VBoxContainer = %FacilityList
@onready var _budget_list: VBoxContainer = %BudgetList
@onready var _runway: Label = %Runway


func refresh() -> void:
	for child in _facility_list.get_children():
		child.queue_free()
	for child in _budget_list.get_children():
		child.queue_free()

	for id in FacilityLibrary.ORDER:
		_facility_list.add_child(_make_facility_row(id))

	_build_budget()


func _make_facility_row(id: StringName) -> Control:
	var state := Game.campaign.state
	var facility := FacilityLibrary.get_facility(id)
	var level := state.facility_level(id)
	var maxed := facility.is_maxed(level)
	var cost := facility.cost_to_upgrade(level)
	var affordable := cost > 0 and cost <= state.diamonds

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.ROW))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	header.add_child(UiStyle.identity(
		facility.display_name,
		"Level %d of %d" % [level, facility.max_level] if level > 0 else "Not built"))

	# What the next level actually buys, in the facility's own units.
	if not maxed:
		header.add_child(UiStyle.stat(
			facility.effect_caption,
			_effect_text(facility, level + 1),
			UiStyle.OCHRE,
			132))
	header.add_child(UiStyle.stat(
		"Upkeep", "%d/wk" % facility.upkeep_at(level), UiStyle.TEXT_2, 86))
	box.add_child(header)

	var description := UiStyle.text(facility.description, UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(description)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	if maxed:
		actions.add_child(UiStyle.text(
			"Fully upgraded.", UiStyle.SIZE_SMALL, UiStyle.MINT))
	else:
		var price := UiStyle.data(
			"%d diamonds" % cost,
			UiStyle.SIZE_SMALL,
			UiStyle.TEXT if affordable else UiStyle.RUST)
		UiStyle.grow(price)
		actions.add_child(price)

		var button := Button.new()
		button.text = "Build" if level == 0 else "Upgrade"
		button.custom_minimum_size = Vector2(120, 36)
		button.disabled = not affordable
		button.pressed.connect(func():
			if Game.campaign.upgrade_facility(id):
				company_changed.emit()
				refresh()
		)
		actions.add_child(button)
	box.add_child(actions)

	return card


## Facility effects are stored as raw magnitudes; each one reads differently.
func _effect_text(facility: FacilityData, level: int) -> String:
	var value := facility.effect_at(level)
	match facility.id:
		FacilityLibrary.ARMOURY, FacilityLibrary.QUARTERMASTER:
			return "tier %d" % int(value)
		FacilityLibrary.WAREHOUSE:
			return "+%d" % int(value)
		FacilityLibrary.CANTEEN:
			return "+%d/wk" % int(value)
		FacilityLibrary.INTELLIGENCE:
			return "+%.1f" % value
		FacilityLibrary.ACADEMY:
			# The Academy raises a number; the two below lower one. Defaulting
			# everything to a minus sign made it read as a penalty.
			return "+%d%%" % int(round(value * 100.0))
		_:
			return "-%d%%" % int(round(value * 100.0))


func _build_budget() -> void:
	var state := Game.campaign.state
	var bill := Economy.weekly_costs(state)

	for line in bill["lines"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var caption := UiStyle.text(line["caption"], UiStyle.SIZE_BODY, UiStyle.TEXT)
		UiStyle.grow(caption)
		row.add_child(caption)

		var detail := UiStyle.text(line["detail"], UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
		detail.custom_minimum_size.x = 140
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(detail)

		var amount := UiStyle.data(str(line["amount"]), UiStyle.SIZE_BODY, UiStyle.TEXT_2)
		amount.custom_minimum_size.x = 84
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(amount)

		_budget_list.add_child(row)

	_budget_list.add_child(UiStyle.spacer(6))
	_budget_list.add_child(UiStyle.rule())
	_budget_list.add_child(UiStyle.spacer(6))

	# Passive income belongs on the same sheet as the costs, or the player has to
	# hold two numbers in their head to know whether the week is survivable.
	var income := Economy.weekly_income(state)
	for line in income["lines"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var caption := UiStyle.text(line["caption"], UiStyle.SIZE_BODY, UiStyle.MINT)
		UiStyle.grow(caption)
		row.add_child(caption)
		var detail := UiStyle.text(line["detail"], UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
		detail.custom_minimum_size.x = 140
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(detail)
		var amount := UiStyle.data("-%d" % int(line["amount"]), UiStyle.SIZE_BODY, UiStyle.MINT)
		amount.custom_minimum_size.x = 84
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(amount)
		_budget_list.add_child(row)

	var total_row := HBoxContainer.new()
	total_row.add_theme_constant_override("separation", 10)
	var net := Economy.net_weekly(state)
	var total_caption := UiStyle.text(
		"Net weekly" if income["total"] > 0 else "Weekly total",
		UiStyle.SIZE_HEADING, UiStyle.TEXT)
	UiStyle.grow(total_caption)
	total_row.add_child(total_caption)
	var total_value := UiStyle.data(
		str(net), UiStyle.SIZE_HEADING,
		UiStyle.MINT if net <= 0 else UiStyle.OCHRE)
	total_value.custom_minimum_size.x = 84
	total_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total_row.add_child(total_value)
	_budget_list.add_child(total_row)

	# Runway is the number that actually tells the player how much trouble they
	# are in, and it is the one thing the header cannot show.
	var weeks := Economy.weeks_of_runway(state)
	if weeks < 0:
		_runway.text = "In debt. Wages went unpaid and everyone knows it."
		_runway.add_theme_color_override("font_color", UiStyle.RUST)
	else:
		_runway.text = "%s of runway at this burn rate." % TextUtil.count(weeks, "week")
		_runway.add_theme_color_override(
			"font_color", UiStyle.RUST if weeks <= 2 else (
				UiStyle.OCHRE if weeks <= 5 else UiStyle.TEXT_2))
