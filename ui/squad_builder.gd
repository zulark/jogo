class_name SquadBuilder
extends HBoxContainer

## Where the decision actually happens: who goes, in what slot, under whom.
##
## The briefing panel on the right is the same scene used everywhere else, fed a
## fresh preview after every change. That is the whole point — the player edits
## the squad and watches the number and its reasons move in real time, instead
## of committing blind and finding out afterwards.

signal deployed(deployment: Deployment)
signal cancelled()

@onready var _available_list: VBoxContainer = %AvailableList
@onready var _squad_list: VBoxContainer = %SquadList
@onready var _briefing: MissionBriefingPanel = %Briefing
@onready var _deploy_button: Button = %DeployButton
@onready var _warning: Label = %Warning
@onready var _mission_title: Label = %MissionTitle

var mission: MissionData = null
var _squad := Squad.new()


func setup(p_mission: MissionData) -> void:
	mission = p_mission
	_squad = Squad.new()
	refresh()


func refresh() -> void:
	if mission == null:
		return

	_mission_title.text = "%s  ·  %s" % [mission.title, mission.region_name()]

	for child in _available_list.get_children():
		child.queue_free()
	for child in _squad_list.get_children():
		child.queue_free()

	var members := _squad.members()
	for op in Game.campaign.state.deployable_operators():
		if not members.has(op):
			_available_list.add_child(_make_available_row(op))

	for op in Game.campaign.state.available_operators():
		if members.has(op) or not op.is_exhausted():
			continue
		_available_list.add_child(_make_unavailable_row(op, "Spent — needs to stand down"))

	for op in members:
		_squad_list.add_child(_make_squad_row(op))

	_briefing.show_report(Game.campaign.preview_mission(_squad, mission))

	var errors := _squad.validation_errors()
	_deploy_button.disabled = not errors.is_empty()
	_warning.text = errors[0] if not errors.is_empty() else ""
	_warning.visible = not errors.is_empty()


func _make_available_row(op: OperatorData) -> Button:
	var button := UiStyle.row_button(false)
	button.custom_minimum_size.y = UiStyle.ROW_HEIGHT
	button.pressed.connect(func():
		_squad.add(op)
		refresh()
	)

	var row := UiStyle.row_content(button)
	row.add_child(UiStyle.portrait(op, 38))
	row.add_child(UiStyle.role_icon(op.preferred_role, UiStyle.SIZE_TITLE))

	# You pick people by what they are and how worn out they are, so both have to
	# be on the row rather than a screen away.
	var box := UiStyle.operator_identity(
		op, "%s   ·   %s" % [GameEnums.role_name(op.preferred_role), op.demonym()])
	box.add_child(UiStyle.skill_summary(op, 3, UiStyle.SIZE_CAPTION))
	row.add_child(box)

	row.add_child(UiStyle.fatigue_meter(op))
	return button


## Everyone at base who is NOT deployable, with the reason. Without this an
## exhausted operator simply vanishes from the list and the player assumes a bug.
func _make_unavailable_row(op: OperatorData, reason: String) -> Control:
	var card := PanelContainer.new()
	var style := UiStyle.panel(UiStyle.PANEL)
	style.border_color = UiStyle.RULE
	card.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	row.add_child(UiStyle.portrait(op, 30))
	row.add_child(UiStyle.identity(op.display_label(), reason, UiStyle.TEXT_3))
	row.add_child(UiStyle.fatigue_meter(op, 56))
	return card


func _make_squad_row(op: OperatorData) -> Control:
	var card := PanelContainer.new()
	var is_leader: bool = _squad.leader == op
	var style := UiStyle.panel(UiStyle.ROW)
	style.content_margin_left = 12
	style.content_margin_right = 12
	if is_leader:
		style.border_color = UiStyle.STEEL
		style.border_width_left = 3
	card.add_theme_stylebox_override("panel", style)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	card.add_child(outer)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	outer.add_child(row)

	row.add_child(UiStyle.portrait(op, 38))
	row.add_child(UiStyle.role_icon(_squad.role_of(op), UiStyle.SIZE_TITLE))

	# No role picker: an operator's role is part of their profile and is changed
	# on their own sheet, not reassigned per contract — so this only reports it.
	#
	# Role alone, without the nationality. This row already carries a callsign, a
	# fatigue meter and two buttons, and the nationality pushed the line to
	# "Assault · Me…" — of the two, the role is what decides whether they belong
	# on this job.
	row.add_child(UiStyle.operator_identity(
		op,
		GameEnums.role_name(_squad.role_of(op)),
		UiStyle.STEEL if is_leader else UiStyle.TEXT))

	row.add_child(UiStyle.fatigue_meter(op, 58))

	var leader_button := UiStyle.state_button("♛ Lead" if is_leader else "Lead", is_leader, 74)
	leader_button.pressed.connect(func():
		_squad.set_leader(op)
		refresh()
	)
	row.add_child(leader_button)

	var remove_button := Button.new()
	remove_button.text = "✕"
	remove_button.custom_minimum_size = Vector2(38, 34)
	remove_button.add_theme_color_override("font_color", UiStyle.TEXT_3)
	remove_button.add_theme_color_override("font_hover_color", UiStyle.RUST)
	remove_button.pressed.connect(func():
		_squad.remove(op)
		refresh()
	)
	row.add_child(remove_button)

	# Loadout lives here, where the squad is being decided — kit only matters in
	# the context of the contract you are about to take.
	var loadout := HBoxContainer.new()
	loadout.add_theme_constant_override("separation", 8)
	loadout.add_child(_slot_picker(op, ItemData.Slot.WEAPON, "Weapon"))
	loadout.add_child(_slot_picker(op, ItemData.Slot.GEAR, "Gear"))
	outer.add_child(loadout)

	return card


## Everything free in storage for this slot, plus whatever they already carry.
## Kit is company property, so an item handed to one operator disappears from
## everyone else's list.
func _slot_picker(op: OperatorData, slot: int, caption: String) -> Control:
	var state := Game.campaign.state
	var equipped_id: StringName = op.weapon_id if slot == ItemData.Slot.WEAPON else op.gear_id

	var picker := OptionButton.new()
	picker.add_theme_font_size_override("font_size", UiStyle.SIZE_CAPTION)
	picker.custom_minimum_size.y = 30
	UiStyle.grow(picker)

	var options: Array[StringName] = [&""]
	picker.add_item("%s: standard issue" % caption)

	var equipped := ItemLibrary.get_item(equipped_id)
	if equipped != null:
		options.append(equipped_id)
		picker.add_item("%s: %s" % [caption, equipped.display_name])

	for item in state.available_items(slot):
		if item.id == equipped_id:
			continue
		options.append(item.id)
		picker.add_item("%s: %s" % [caption, item.display_name])

	picker.select(maxi(0, options.find(equipped_id)))
	picker.item_selected.connect(func(index: int):
		Game.campaign.equip(op, options[index], slot)
		refresh()
	)
	return picker


func _ready() -> void:
	# Deploying is the point of no return on this screen — people leave, days
	# pass, and there is no recalling them. It takes two presses.
	UiStyle.make_confirming(
		_deploy_button, "Deploy Squad", "Confirm — send them", _on_deploy_pressed)


func _on_deploy_pressed() -> void:
	var deployment := Game.campaign.deploy(_squad, mission)
	if deployment != null:
		deployed.emit(deployment)


func _on_back_pressed() -> void:
	cancelled.emit()
