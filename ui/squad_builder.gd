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
@onready var _ties: VBoxContainer = %Ties
@onready var _ties_heading: Label = %TiesHeading

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

	_build_ties(members)
	_briefing.show_report(Game.campaign.preview_mission(_squad, mission))

	var errors := _squad.validation_errors()
	_deploy_button.disabled = not errors.is_empty()
	_warning.text = errors[0] if not errors.is_empty() else ""
	_warning.visible = not errors.is_empty()


## Who these people already are to each other, and why.
##
## The resolver has scored bonds since v0.4 and this screen has never once
## mentioned them, so the term moved the odds and the player had no way to know
## which of their own decisions caused it. The causes are the point: "They
## blamed each other for how Salt the Wells went" is why the player remembers
## the pair, and it is stored on the bond already.
func _build_ties(members: Array) -> void:
	for child in _ties.get_children():
		child.queue_free()

	var ties := UiStyle.bond_ties(members)
	_ties.visible = not ties.is_empty()
	_ties_heading.visible = not ties.is_empty()

	for tie in ties:
		var color: Color = Bonds.color_for(tie["type"])
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)

		line.add_child(UiStyle.text(
			Bonds.describe(tie["type"], tie["strength"]).to_upper(),
			UiStyle.SIZE_CAPTION, color))

		# EXPAND_FILL is not optional next to clip_text: clipping drops a label's
		# minimum width to zero, so without it the names collapse to nothing and
		# the row prints the relationship with nobody in it.
		var who := UiStyle.text("%s and %s" % [
			tie["a"].short_label(), tie["b"].short_label()],
			UiStyle.SIZE_SMALL, UiStyle.TEXT)
		who.clip_text = true
		who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		UiStyle.grow(who)
		line.add_child(who)
		_ties.add_child(line)

		# A bond formed before causes were recorded has none. Printing an empty
		# line under the pair would read as a missing string rather than as a
		# link nobody wrote a reason for.
		var reason: String = tie["reason"]
		if not reason.is_empty():
			var note := UiStyle.text(reason, UiStyle.SIZE_CAPTION, UiStyle.TEXT_3)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_ties.add_child(note)


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
	#
	# Role alone, without the nationality — the same call the squad rows below
	# already make, and now for the same reason. This row gained a rating column,
	# and the second line runs callsign then role then nationality, which was the
	# line that could not afford it: "Brine" Engineer · Amer…". The role is the
	# half that decides whether somebody belongs on this contract; where they are
	# from is on their sheet.
	var box := UiStyle.operator_identity(op, GameEnums.role_name(op.preferred_role))
	# Two skills, not three. The rating column beside this is the weighted read of
	# exactly these numbers against exactly this contract, so a third raw figure
	# earns less than the width it costs — and width is what this row is short of:
	# the identity block was down to its declared floor, which is why nationalities
	# were reading "K…".
	box.add_child(UiStyle.skill_summary(op, 2, UiStyle.SIZE_CAPTION))
	row.add_child(box)

	# What they are worth ON THIS CONTRACT, which is not what the roster's rating
	# column said about them. That difference is the decision this screen exists
	# to put in front of the player: the highest overall rating in the company can
	# be the wrong person to send to a sabotage job, and the same person carrying
	# two different numbers on two screens is how they find that out.
	row.add_child(UiStyle.stat(
		"This job", str(Ovr.on_type(op, mission.mission_type)), UiStyle.TEXT, 62))

	# What adding this person would mean for the people already picked. Empty and
	# invisible when there is no history, which is most of the time early on.
	row.add_child(UiStyle.bond_column(op, _squad.members()))
	row.add_child(UiStyle.fatigue_meter(op, 58))
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

	# The same figure the available list showed, kept beside them once they are
	# picked — otherwise the number that justified the choice disappears the
	# moment it is made, and the squad cannot be read for who is carrying it.
	row.add_child(UiStyle.stat(
		"This job", str(Ovr.on_type(op, mission.mission_type)), UiStyle.TEXT, 64))

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
	var equipped := op.slot_instance(slot)

	var picker := OptionButton.new()
	picker.add_theme_font_size_override("font_size", UiStyle.SIZE_CAPTION)
	picker.custom_minimum_size.y = 30
	UiStyle.grow(picker)

	# Condition is on every line because this is the screen where it costs: a
	# carrier at 40% is a different number in the breakdown to the right.
	var options: Array = [null]
	picker.add_item("%s: standard issue" % caption)

	if equipped != null:
		options.append(equipped)
		picker.add_item("%s: %s · %d%%" % [
			caption, equipped.display_name(), int(round(equipped.condition))])

	for instance in state.available_items(slot):
		if instance == equipped:
			continue
		options.append(instance)
		picker.add_item("%s: %s · %d%%" % [
			caption, instance.display_name(), int(round(instance.condition))])

	picker.select(maxi(0, options.find(equipped)))
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
