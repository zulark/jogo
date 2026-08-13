class_name RosterScreen
extends HBoxContainer

## The roster: who you employ, what they cost, and what shape they are in.
##
## List on the left, the selected operator's full sheet on the right. The sheet
## is where skills, temperament and traits are actually legible —
## the list only has room for the things you scan by.

@onready var _list: VBoxContainer = %OperatorList
@onready var _detail: VBoxContainer = %Detail
@onready var _empty_hint: Label = %EmptyHint

var _selected: OperatorData = null
var _confirming_dismiss := false

## Sorting and filtering. A company of twenty is unmanageable without them, and
## "who is my best medic" is a question the roster should answer directly.
var _search := ""
var _sort_key: int = SORT_NAME
var _hide_unavailable := false

## Sort keys that are not skills. Negative so a GameEnums.Skill can be used
## directly as the key for everything else.
const SORT_NAME := -1
const SORT_RATING := -2

## Parallel to the sorter's items, because an OptionButton id of -1 means "use
## the index" — so "Sort: Name" registered itself as id 0, which is COMBAT, and
## picking it off the dropdown sorted the roster by combat skill. Holding the
## keys in an array indexed by position removes the collision rather than
## working around it.
var _sort_options: Array[int] = []


func _ready() -> void:
	_build_controls()


func refresh() -> void:
	var state := Game.campaign.state

	for child in _list.get_children():
		child.queue_free()

	if state.roster.is_empty():
		_empty_hint.show()
	else:
		_empty_hint.hide()

	if _selected != null and not state.roster.has(_selected):
		_selected = null
	if _selected == null and not state.roster.is_empty():
		_selected = state.roster[0]

	# Grouped by role, because "who are my medics" is the question this screen is
	# usually open to answer.
	var shown := _visible_roster(state)
	var by_role := {}
	for op in shown:
		var bucket: Array = by_role.get(op.preferred_role, [])
		bucket.append(op)
		by_role[op.preferred_role] = bucket

	for role in GameEnums.Role.values():
		var bucket: Array = by_role.get(role, [])
		if bucket.is_empty():
			continue
		_list.add_child(UiStyle.spacer(4))
		var heading := HBoxContainer.new()
		heading.add_theme_constant_override("separation", 6)
		heading.add_child(UiStyle.role_icon(role, UiStyle.SIZE_SMALL))
		heading.add_child(UiStyle.eyebrow("%s (%d)" % [
			GameEnums.role_name(role), bucket.size()]))
		_list.add_child(heading)
		for op in bucket:
			_list.add_child(_make_row(op))

	_rebuild_detail()


## Filtered and sorted, without touching the underlying roster order.
func _visible_roster(state: GameState) -> Array:
	var shown: Array = []
	var needle := _search.strip_edges().to_lower()

	for op in state.roster:
		if _hide_unavailable and not op.is_deployable():
			continue
		if not needle.is_empty():
			var haystack: String = "%s %s %s" % [
				op.display_label(), GameEnums.role_name(op.preferred_role), op.demonym()]
			if not haystack.to_lower().contains(needle):
				continue
		shown.append(op)

	if _sort_key == SORT_RATING:
		shown.sort_custom(func(a, b): return Ovr.overall(a) > Ovr.overall(b))
	elif _sort_key == SORT_NAME:
		shown.sort_custom(func(a, b): return a.display_label() < b.display_label())
	else:
		shown.sort_custom(func(a, b): return a.get_skill(_sort_key) > b.get_skill(_sort_key))
	return shown


func _build_controls() -> void:
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)

	var field := LineEdit.new()
	field.placeholder_text = "Search name, role or nationality"
	field.custom_minimum_size = Vector2(210, 30)
	field.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL)
	field.text_changed.connect(func(value: String):
		_search = value
		refresh()
	)
	controls.add_child(field)

	var sorter := OptionButton.new()
	sorter.custom_minimum_size = Vector2(150, 30)
	sorter.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL)

	_sort_options = [SORT_NAME, SORT_RATING]
	sorter.add_item("Sort: Name")
	sorter.add_item("Sort: Rating")
	for skill in GameEnums.Skill.values():
		sorter.add_item("Sort: %s" % GameEnums.skill_name(skill))
		_sort_options.append(skill)

	sorter.item_selected.connect(func(index: int):
		_sort_key = _sort_options[index]
		refresh()
	)
	controls.add_child(sorter)

	var only_free := UiStyle.state_button("Available only", false, 140)
	only_free.pressed.connect(func():
		_hide_unavailable = not _hide_unavailable
		only_free.button_pressed = _hide_unavailable
		refresh()
	)
	controls.add_child(only_free)

	# Sits above the list, inside the left column.
	var left := _list.get_parent().get_parent()
	left.add_child(controls)
	left.move_child(controls, 0)


func _make_row(op: OperatorData) -> Button:
	var button := UiStyle.row_button(op == _selected)
	button.custom_minimum_size.y = UiStyle.ROW_HEIGHT
	button.pressed.connect(func():
		_selected = op
		_confirming_dismiss = false
		refresh()
	)

	var row := UiStyle.row_content(button)
	row.add_child(UiStyle.portrait(op, 38))

	# No role glyph on the row. This list is always grouped by role and each
	# group's heading carries the same glyph in the same colour three pixels
	# above, so the per-row copy said nothing the eye had not just read — and the
	# rating column needed the width it was holding.
	row.add_child(UiStyle.rank_icon(op.rank, UiStyle.SIZE_BODY))
	row.add_child(UiStyle.operator_identity(
		op,
		"%s   ·   %s" % [
			GameEnums.role_name(op.preferred_role),
			op.demonym(),
		]))

	# What they are worth, averaged over every kind of work on the board. This is
	# the column the roster is scanned by once the company is more than six
	# people — and it is deliberately the OVERALL figure here, because this
	# screen has no contract in front of it. The rating that decides a
	# deployment is the one in the squad builder, against the job in hand.
	row.add_child(UiStyle.stat("Rating", str(Ovr.overall(op)), UiStyle.TEXT, 56))

	row.add_child(UiStyle.fatigue_meter(op, 74))
	row.add_child(UiStyle.stat(
		"Status", UiStyle.status_text(op), UiStyle.status_color(op.status), 104))

	# Kit that has stopped working is worth saying on the list rather than only
	# inside the loadout picker. Somebody carrying a dead plate carrier is
	# strictly worse off than somebody carrying nothing, and the roster is where
	# a squad gets picked.
	row.add_child(UiStyle.stat(
		"Kit",
		"BROKEN" if op.has_unserviceable_kit() else "—",
		UiStyle.RUST if op.has_unserviceable_kit() else UiStyle.TEXT_3,
		72))

	# No salary column. The row's declared widths came to more than the list is
	# ever given, so the last column was cut off by the panel edge and the
	# identity block — which absorbs whatever is left over — was squeezed until
	# nationalities read "M…" and "Jap…". Salary was the right column to drop:
	# it is the only one already printed in full on the detail panel two inches
	# to the right, and nobody scans a roster by what people cost.

	return button


func _rebuild_detail() -> void:
	for child in _detail.get_children():
		child.queue_free()

	if _selected == null:
		_detail.add_child(UiStyle.text("No operator selected.", UiStyle.SIZE_BODY, UiStyle.TEXT_3))
		return

	var op := _selected

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	header.add_child(UiStyle.portrait(op, 64))

	var header_text := VBoxContainer.new()
	header_text.add_theme_constant_override("separation", 2)
	UiStyle.grow(header_text)
	var display_name := UiStyle.text(op.operator_name, UiStyle.SIZE_DISPLAY, UiStyle.TEXT)
	display_name.clip_text = true
	display_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header_text.add_child(display_name)
	header.add_child(header_text)

	# The headline figure of the whole sheet. Everything under "Suited to" below
	# is this number taken apart by the kind of work — read in that order, a
	# player learns that one rating of 64 is a marksman and another is somebody
	# who is passable at everything and needed nowhere.
	header.add_child(UiStyle.stat("Rating", str(Ovr.overall(op)), UiStyle.TEXT, 76))
	_detail.add_child(header)

	# Renaming is how a roster becomes yours — the Dwarf Fortress move. Callsign
	# only, because the given name is where they are from and the callsign is
	# what the company decided to call them.
	var rename_row := HBoxContainer.new()
	rename_row.add_theme_constant_override("separation", 8)
	var field := LineEdit.new()
	field.text = op.callsign
	field.placeholder_text = "Callsign"
	field.custom_minimum_size = Vector2(180, 32)
	field.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL)
	rename_row.add_child(field)

	var apply := Button.new()
	apply.text = "Rename"
	apply.custom_minimum_size = Vector2(96, 32)
	apply.pressed.connect(func():
		var wanted := field.text.strip_edges()
		if not wanted.is_empty():
			op.callsign = wanted
			refresh()
	)
	rename_row.add_child(apply)

	# Two-step, because letting someone go costs severance and upsets whoever
	# was close to them. A single click would be a trap.
	var dismiss := UiStyle.state_button("Dismiss", _confirming_dismiss, 100)
	dismiss.disabled = (
		Game.campaign.state.is_deployed(op)
		or Game.campaign.state.is_training(op)
		or Game.campaign.state.is_detached(op)
	)
	dismiss.pressed.connect(func():
		if _confirming_dismiss:
			Game.campaign.dismiss(op)
			_confirming_dismiss = false
			_selected = null
		else:
			_confirming_dismiss = true
		refresh()
	)
	rename_row.add_child(dismiss)
	header_text.add_child(rename_row)

	if _confirming_dismiss:
		header_text.add_child(UiStyle.text(
			"Press again to let them go — %d severance, and their friends will hear about it." % (
				op.salary * Balance.SEVERANCE_WEEKS),
			UiStyle.SIZE_SMALL, UiStyle.RUST))

	var subtitle: String = "%s %s   ·   %s   ·   %s   ·   %d years old" % [
		GameEnums.rank_glyph(op.rank),
		GameEnums.rank_name(op.rank),
		GameEnums.role_name(op.preferred_role),
		op.demonym(),
		op.age,
	]
	if op.career_track == GameEnums.CareerTrack.INSTRUCTOR:
		subtitle += "   ·   Instructor"

	# The callsign leads this line now that the name has the one above to itself.
	# Still ochre, so scanning the roster by nickname works the same as it does
	# in the list rows.
	var subtitle_row := HBoxContainer.new()
	subtitle_row.add_theme_constant_override("separation", 8)
	if not op.callsign.is_empty():
		subtitle_row.add_child(UiStyle.text(
			'"%s"' % op.callsign, UiStyle.SIZE_BODY, UiStyle.OCHRE))
	# Wraps rather than truncates. This line is a list of facts, and losing the
	# last one to an ellipsis loses a fact; a second line costs nothing here.
	var subtitle_label := UiStyle.text(subtitle, UiStyle.SIZE_BODY, UiStyle.TEXT_2)
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle_row.add_child(subtitle_label)
	_detail.add_child(subtitle_row)
	_detail.add_child(UiStyle.text(
		UiStyle.status_text(op), UiStyle.SIZE_BODY, UiStyle.status_color(op.status)))

	_section("Career")
	_detail.add_child(_rank_progress(op))
	if op.career_track == GameEnums.CareerTrack.INSTRUCTOR:
		_detail.add_child(UiStyle.text(
			"Left the field. Advances by teaching.", UiStyle.SIZE_SMALL, UiStyle.TEXT_3))
	elif Progression.can_become_instructor(op):
		# The fork from the design doc: a field career ends here unless the
		# player trades it for the academy. One-way, so it is said out loud.
		_detail.add_child(UiStyle.text(
			"Field career complete. Becoming an instructor is permanent — they will never deploy again.",
			UiStyle.SIZE_SMALL, UiStyle.OCHRE))
		var promote := Button.new()
		promote.text = "Make Instructor"
		promote.custom_minimum_size = Vector2(190, 38)
		promote.pressed.connect(func():
			if Game.campaign.promote_to_instructor(op):
				refresh()
		)
		_detail.add_child(promote)

	if not op.trained_by.is_empty():
		_detail.add_child(UiStyle.text(
			"Trained by %s." % op.trained_by, UiStyle.SIZE_SMALL, UiStyle.TEXT_3))
	if not op.trainees.is_empty():
		_detail.add_child(UiStyle.text(
			"Taught %s." % TextUtil.count(op.trainees.size(), "operator"), UiStyle.SIZE_SMALL, UiStyle.STEEL))

	if op.is_ageing():
		_detail.add_child(UiStyle.text(
			"Past their physical peak. Loses a little speed each year — but not judgement.",
			UiStyle.SIZE_SMALL, UiStyle.OCHRE))
	if op.is_exhausted():
		_detail.add_child(UiStyle.text(
			"Completely spent. No contract will take them until they rest.",
			UiStyle.SIZE_SMALL, UiStyle.RUST))

	if not op.trophies.is_empty():
		_section("Trophies")
		for trophy in op.trophies:
			_detail.add_child(UiStyle.text("☠  " + trophy, UiStyle.SIZE_SMALL, UiStyle.OCHRE))
		_detail.add_child(UiStyle.text(
			"%d confirmed kills in total." % op.confirmed_kills,
			UiStyle.SIZE_SMALL, UiStyle.TEXT_3))

	_section("Record")
	var tally := HBoxContainer.new()
	tally.add_theme_constant_override("separation", 6)
	tally.add_child(UiStyle.stat(
		"Kills", str(op.confirmed_kills),
		UiStyle.RUST if op.confirmed_kills > 0 else UiStyle.TEXT_3, 74))
	tally.add_child(UiStyle.stat(
		"Saves", str(op.saves),
		UiStyle.MINT if op.saves > 0 else UiStyle.TEXT_3, 74))
	tally.add_child(UiStyle.stat(
		"Trophies", str(op.trophies.size()),
		UiStyle.OCHRE if not op.trophies.is_empty() else UiStyle.TEXT_3, 84))
	tally.add_child(UiStyle.stat(
		"Medals", str(op.medals.size()),
		UiStyle.OCHRE if not op.medals.is_empty() else UiStyle.TEXT_3, 76))
	_detail.add_child(tally)
	_detail.add_child(UiStyle.spacer(4))

	var blurb := UiStyle.text(op.resume(), UiStyle.SIZE_SMALL, UiStyle.TEXT_2)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(blurb)

	_section("Loadout")
	_detail.add_child(_slot_picker(op, ItemData.Slot.WEAPON, "Weapon"))
	_detail.add_child(_slot_picker(op, ItemData.Slot.GEAR, "Gear"))

	_section("Condition")
	_detail.add_child(_meter("Morale", op.morale, _morale_color(op.morale)))
	_detail.add_child(_meter("Fatigue", op.fatigue, _fatigue_color(op.fatigue)))
	if op.morale <= Balance.MORALE_DESERTION_THRESHOLD:
		_detail.add_child(UiStyle.text(
			"Considering leaving the company.", UiStyle.SIZE_SMALL, UiStyle.RUST))
	elif op.fatigue >= Balance.FATIGUE_WARNING:
		_detail.add_child(UiStyle.text(
			"Needs rest. Deploying them again will cost you.",
			UiStyle.SIZE_SMALL, UiStyle.OCHRE))

	var bonds := Bonds.list_for(op, Game.campaign.state.roster)
	if not bonds.is_empty():
		_section("Bonds")
		for bond in bonds:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			var other: OperatorData = bond["other"]
			var name_label := UiStyle.text(
				other.display_label(), UiStyle.SIZE_SMALL, UiStyle.TEXT)
			UiStyle.grow(name_label)
			row.add_child(name_label)
			row.add_child(UiStyle.text(
				Bonds.describe(bond["type"], bond["strength"]),
				UiStyle.SIZE_SMALL,
				Bonds.color_for(bond["type"])))
			_detail.add_child(row)

	if not op.medals.is_empty():
		_section("Medals")
		for medal_id in op.medals:
			_detail.add_child(UiStyle.text(
				"✦  " + MedalLibrary.display_name(medal_id), UiStyle.SIZE_SMALL, UiStyle.OCHRE))
			_detail.add_child(UiStyle.text(
				"     " + MedalLibrary.note(medal_id), UiStyle.SIZE_CAPTION, UiStyle.TEXT_3))

	_section("Skills")
	for skill in GameEnums.Skill.values():
		var stars: int = op.stars_in(skill)
		var caption: String = GameEnums.skill_name(skill)
		if stars > 0:
			caption += "  " + UiStyle.star_text(stars)
		# A starred skill's bar shows progress toward the NEXT star, and the
		# figure beside it shows what they are actually worth.
		_detail.add_child(_meter(
			caption, op.skill_progress(skill), UiStyle.OCHRE, op.get_skill(skill)))

	# The skills above, taken apart by what the board actually offers. This is
	# where a player learns to read the rating on a list row: the same person is
	# 78 on sabotage and 44 on assault, and the contract says which one is being
	# asked for. Sorted best first, so the top line is what they are FOR.
	_section("Suited to")
	for entry in Ovr.ranked_work(op):
		_detail.add_child(UiStyle.meter_row(
			GameEnums.mission_type_name(entry["type"]),
			int(entry["rating"]),
			UiStyle.mission_type_color(entry["type"])))
	_detail.add_child(UiStyle.text(
		"Skills only. What they are carrying counts; fatigue and morale do not.",
		UiStyle.SIZE_CAPTION, UiStyle.TEXT_3))

	_section("Temperament")
	for axis in GameEnums.PersonalityAxis.values():
		_detail.add_child(_meter(GameEnums.axis_name(axis), op.get_personality(axis)))

	_section("Traits")
	if op.traits.is_empty():
		_detail.add_child(UiStyle.text("None yet.", UiStyle.SIZE_SMALL, UiStyle.TEXT_3))
	for t in op.traits:
		_detail.add_child(UiStyle.text(
			t.display_name, UiStyle.SIZE_BODY, UiStyle.trait_color(t.polarity)))
		var description := UiStyle.text(t.description, UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(description)

	_section("Service")
	var record := HBoxContainer.new()
	record.add_theme_constant_override("separation", 6)
	# Colour only earns its place on a non-zero count; a rust "0" reads as a
	# problem where there isn't one.
	record.add_child(UiStyle.stat("Completed", str(op.missions_completed),
		UiStyle.MINT if op.missions_completed > 0 else UiStyle.TEXT_2, 92))
	record.add_child(UiStyle.stat("Failed", str(op.missions_failed),
		UiStyle.RUST if op.missions_failed > 0 else UiStyle.TEXT_2, 74))
	record.add_child(UiStyle.stat("Weekly", str(op.salary), UiStyle.TEXT, 84))
	_detail.add_child(record)


## A dropdown of everything free in storage for this slot, plus whatever they
## are already carrying. Kit is company property, so an item handed to one
## operator disappears from everyone else's list.
func _slot_picker(op: OperatorData, slot: int, caption: String) -> Control:
	var state := Game.campaign.state
	var equipped := op.slot_instance(slot)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var name_label := UiStyle.text(caption, UiStyle.SIZE_SMALL, UiStyle.TEXT_2)
	name_label.custom_minimum_size.x = 108
	row.add_child(name_label)

	var picker := OptionButton.new()
	picker.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL)
	UiStyle.grow(picker)

	# Copies, not types: which carbine matters once the company owns a new one
	# and a worn one, so every entry carries the condition it would go out in.
	var options: Array = [null]
	picker.add_item("Standard issue")

	if equipped != null:
		options.append(equipped)
		picker.add_item("%s  ·  %d%%" % [
			equipped.display_name(), int(round(equipped.condition))])

	for instance in state.available_items(slot):
		if instance == equipped:
			continue
		options.append(instance)
		picker.add_item("%s  ·  %d%%" % [
			instance.display_name(), int(round(instance.condition))])

	picker.select(maxi(0, options.find(equipped)))
	picker.item_selected.connect(func(index: int):
		Game.campaign.equip(op, options[index], slot)
		refresh()
	)
	row.add_child(picker)

	var effect := UiStyle.text(
		equipped.effect_text() if equipped != null else "",
		UiStyle.SIZE_CAPTION,
		UiStyle.condition_color(equipped) if equipped != null else UiStyle.TEXT_3)
	effect.custom_minimum_size.x = 210
	effect.clip_text = true
	row.add_child(effect)

	return row


func _morale_color(morale: int) -> Color:
	if morale <= Balance.MORALE_DESERTION_THRESHOLD:
		return UiStyle.RUST
	if morale < Balance.MORALE_NEUTRAL:
		return UiStyle.OCHRE
	return UiStyle.MINT


## Fatigue reads backwards from every other meter here: a full bar is bad.
func _fatigue_color(fatigue: int) -> Color:
	if fatigue >= Balance.FATIGUE_WARNING:
		return UiStyle.RUST
	if fatigue >= 35:
		return UiStyle.OCHRE
	return UiStyle.TEXT_3


## XP toward the next rank, or the ceiling if there is nothing left to reach.
func _rank_progress(op: OperatorData) -> Control:
	var target := Progression.xp_for_next_rank(op)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var caption: String = "%s %s" % [GameEnums.rank_glyph(op.rank), GameEnums.rank_name(op.rank)]
	var name_label := UiStyle.text(caption, UiStyle.SIZE_SMALL, UiStyle.TEXT_2)
	name_label.custom_minimum_size.x = 108
	row.add_child(name_label)

	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.step = 0.01
	bar.value = Progression.rank_progress(op)
	bar.show_percentage = false
	bar.custom_minimum_size.y = 10
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiStyle.grow(bar)

	var track := StyleBoxFlat.new()
	track.bg_color = UiStyle.INK
	track.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = UiStyle.OCHRE if target > 0 else UiStyle.TEXT_3
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)

	var value_label := UiStyle.data(
		"%d/%d" % [op.xp, target] if target > 0 else str(op.xp),
		UiStyle.SIZE_SMALL,
		UiStyle.TEXT
	)
	value_label.custom_minimum_size.x = 96
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	return row


## Ochre label over a hairline: the divider between blocks of a service record.
func _section(caption: String) -> void:
	_detail.add_child(UiStyle.spacer(14))
	_detail.add_child(UiStyle.eyebrow(caption))
	_detail.add_child(UiStyle.rule())
	_detail.add_child(UiStyle.spacer(2))


## Label, bar, figure. Lives in UiStyle now — the same row shape draws skills
## here, what a squad brings in stealth on the briefing panel, and what an
## operator rates on each kind of work under "Suited to" above.
func _meter(
	caption: String,
	value: int,
	color: Color = UiStyle.OCHRE,
	shown_value: int = -1
) -> Control:
	return UiStyle.meter_row(caption, value, color, shown_value)
