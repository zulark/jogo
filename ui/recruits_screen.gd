class_name RecruitsScreen
extends VBoxContainer

## Hiring. The pool refreshes every week — sign them or they move on.
##
## The signing bonus is a multiple of weekly salary, so good people cost to land
## as well as to keep, and a cheap rookie is genuinely tempting when the balance
## is thin.

signal roster_changed()

@onready var _list: VBoxContainer = %RecruitList
@onready var _summary: Label = %Summary


func refresh() -> void:
	var state := Game.campaign.state

	for child in _list.get_children():
		child.queue_free()

	for recruit in state.recruits:
		_list.add_child(_make_row(recruit))

	# The pool is wiped and rebuilt every week close, so anyone left unhired is
	# gone for good. Say it in those words — "refreshes" undersells the loss.
	# The pool is wiped and rebuilt at the week close, so anyone left unhired is
	# gone for good — and a countdown is the difference between knowing that and
	# acting on it.
	var days_left: int = Balance.DAYS_PER_WEEK - state.day_of_week() + 1
	_summary.text = "%s looking for work · they leave in %s · balance %d" % [
		TextUtil.count(state.recruits.size(), "person", "people"),
		TextUtil.count(days_left, "day"),
		state.diamonds,
	]
	_summary.add_theme_color_override(
		"font_color", UiStyle.RUST if days_left <= 1 else UiStyle.TEXT_2)


func _make_row(recruit: OperatorData) -> Control:
	var state := Game.campaign.state
	var cost := state.hire_cost(recruit)
	var affordable := cost <= state.diamonds

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.ROW))

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	card.add_child(outer)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	outer.add_child(row)

	row.add_child(UiStyle.portrait(recruit, 44))
	row.add_child(UiStyle.role_icon(recruit.preferred_role, UiStyle.SIZE_TITLE))

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	UiStyle.grow(info)
	info.add_child(UiStyle.operator_name(recruit))
	info.add_child(UiStyle.text(
		"%s   ·   %s %s   ·   %s" % [
			GameEnums.role_name(recruit.preferred_role),
			GameEnums.rank_glyph(recruit.rank),
			GameEnums.rank_name(recruit.rank),
			recruit.demonym(),
		], UiStyle.SIZE_SMALL, UiStyle.TEXT_3))

	# You are buying numbers, so the numbers have to be on the card. Hiring blind
	# and finding out on the roster screen is not a decision, it is a lottery.
	info.add_child(UiStyle.skill_summary(recruit, 4))

	# Coloured by polarity — an amber "Field Surgeon" reads as a warning when it
	# is the reason to sign them.
	if not recruit.traits.is_empty():
		var trait_row := HBoxContainer.new()
		trait_row.add_theme_constant_override("separation", 12)
		for t in recruit.traits:
			trait_row.add_child(UiStyle.text(
				t.display_name, UiStyle.SIZE_SMALL, UiStyle.trait_color(t.polarity)))
		info.add_child(trait_row)
	row.add_child(info)

	row.add_child(UiStyle.stat(
		"To sign", str(cost), UiStyle.TEXT if affordable else UiStyle.RUST, 92))
	row.add_child(UiStyle.stat("Weekly after", str(recruit.salary), UiStyle.TEXT_2, 116))

	var hire_button := Button.new()
	hire_button.text = "Hire"
	hire_button.custom_minimum_size = Vector2(96, 40)
	hire_button.disabled = not affordable
	hire_button.pressed.connect(func():
		if Game.campaign.hire(recruit):
			roster_changed.emit()
			refresh()
	)
	row.add_child(hire_button)

	var blurb := UiStyle.text(recruit.resume(), UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(blurb)

	return card
