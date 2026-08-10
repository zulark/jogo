class_name AfterAction
extends Control

## What came back. Shown after ending a day that resolved one or more contracts.
##
## Reports queue: if two squads came home on the same day you read them one at a
## time, because a death should never be a line item scrolling past in a list.

signal closed()

@onready var _title: Label = %Title
@onready var _summary: Label = %Summary
@onready var _outcome_list: VBoxContainer = %OutcomeList
@onready var _story_list: VBoxContainer = %StoryList
@onready var _story_scroll: ScrollContainer = %StoryScroll
@onready var _outcome_scroll: ScrollContainer = %OutcomeScroll

## How tall a column may get before it scrolls instead of pushing the card
## further down the screen. The window is 820 tall; this leaves room for the
## title, the summary line and the footer.
const MAX_COLUMN_HEIGHT := 470.0
@onready var _next_button: Button = %NextButton
@onready var _remaining: Label = %Remaining

## Pages are shown one at a time: each returning squad, then the week's news.
## A death should never be a line item scrolling past, and neither should a
## traitor selling the base.
var _pages: Array = []

## The feed is behind a button rather than always open: the outcome is what the
## player needs, and the tally is what they want when they are curious.
var _feed_open := false
var _current: MissionReport = null


func show_reports(reports: Array[MissionReport], events: Array = []) -> void:
	_pages.clear()
	for report in reports:
		_pages.append({"kind": "report", "data": report})
	if not events.is_empty():
		_pages.append({"kind": "events", "data": events})

	if _pages.is_empty():
		hide()
		return
	show()
	_advance()


func _advance() -> void:
	_feed_open = false
	var page: Dictionary = _pages.pop_front()
	if page["kind"] == "report":
		_present(page["data"])
	else:
		_present_events(page["data"])


## The week's news. Fires from Campaign at the week close, and every entry is a
## consequence of something the company did — see EventLibrary.
func _present_events(events: Array) -> void:
	_title.text = "THE WEEK"
	_title.add_theme_font_override("font", UiStyle.display())
	_title.add_theme_color_override("font_color", UiStyle.OCHRE)
	_summary.text = "Word from the base while the squads were out."

	_clear_columns()

	for event in events:
		var heading := UiStyle.text(
			event["title"],
			UiStyle.SIZE_HEADING,
			UiStyle.MINT if event["good"] else UiStyle.RUST)
		_story_list.add_child(heading)

		var body := UiStyle.text(event["line"], UiStyle.SIZE_SMALL, UiStyle.TEXT_2)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_story_list.add_child(body)
		_story_list.add_child(UiStyle.spacer(4))

	_remaining.text = ""
	_next_button.text = "Continue"
	_fit_columns()


func _total_kills(report: MissionReport) -> int:
	var total := 0
	for op in report.kills:
		total += int(report.kills[op])
	return total


func _present(report: MissionReport) -> void:
	_current = report
	# A contract the company called off is not a contract it lost. Quoting a roll
	# against the odds would be a lie either way: no dice were thrown, the player
	# made the call, and the card should say so.
	if report.withdrew:
		_title.text = "CONTRACT CALLED OFF"
	else:
		_title.text = "CONTRACT COMPLETE" if report.success else "CONTRACT FAILED"
	_title.add_theme_font_override("font", UiStyle.display())
	_title.add_theme_color_override(
		"font_color", UiStyle.MINT if report.success else UiStyle.RUST)

	var outcome: String = (
		"ended from the field at %d%%" % report.chance_percent() if report.withdrew
		else "rolled %d against %d%%" % [
			int(report.roll_value * 100.0), report.chance_percent()])
	_summary.text = "%s  ·  %s for %s  ·  %s  ·  paid %d diamonds" % [
		report.mission.title,
		report.mission.region_name(),
		report.mission.client_name(),
		outcome,
		report.reward_paid,
	]

	_clear_columns()

	# The narrative goes in its own column. Stacking it above the ledger made the
	# card grow downward until it left the screen; side by side it uses width,
	# which the screen has, instead of height, which it does not.
	if not report.trophy_line.is_empty():
		var trophy := UiStyle.text(
			"☠  " + report.trophy_line, UiStyle.SIZE_HEADING, UiStyle.OCHRE)
		trophy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_story_list.add_child(trophy)
		_story_list.add_child(UiStyle.text(
			"The whole company heard about it.", UiStyle.SIZE_SMALL, UiStyle.TEXT_3))
		_story_list.add_child(UiStyle.spacer(8))

	for line in report.story:
		var entry := UiStyle.text(line, UiStyle.SIZE_SMALL, UiStyle.TEXT_2)
		entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_story_list.add_child(entry)

	if not report.loot.is_empty():
		var names: Array = []
		for id in report.loot:
			var item := ItemLibrary.get_item(id)
			if item != null:
				names.append(item.display_name)
		if not names.is_empty():
			_story_list.add_child(UiStyle.spacer(8))
			_story_list.add_child(UiStyle.text(
				"Brought back: %s" % TextUtil.join_names(names),
				UiStyle.SIZE_SMALL, UiStyle.MINT))

	# Plans first: a blueprint is the rarest thing a contract produces and the
	# only one that changes what the company can build from here on.
	if report.blueprint_found != &"":
		var plan := ItemLibrary.get_item(report.blueprint_found)
		if plan != null:
			_story_list.add_child(UiStyle.spacer(8))
			var line := UiStyle.text(
				"Plans recovered: %s. The workshop can build these now." % plan.display_name,
				UiStyle.SIZE_SMALL, UiStyle.OCHRE)
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_story_list.add_child(line)

	if report.salvage_gained > 0:
		_story_list.add_child(UiStyle.text(
			"Stripped off the site: %s." % TextUtil.count(report.salvage_gained, "part"),
			UiStyle.SIZE_SMALL, UiStyle.TEXT_2))

	# What the contract did to the kit. Only the lines worth reading — something
	# that stopped working out there, or something signed back in off a body.
	if not report.kit_notes.is_empty():
		_story_list.add_child(UiStyle.spacer(8))
		for note in report.kit_notes:
			var line := UiStyle.text(note, UiStyle.SIZE_SMALL, UiStyle.RUST)
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_story_list.add_child(line)

	for op in report.squad.members():
		_outcome_list.add_child(_make_row(report, op))

		var morale_delta: int = int(report.morale_change.get(op, 0))
		if morale_delta != 0:
			_outcome_list.add_child(UiStyle.text(
				"      Morale %+d" % morale_delta,
				UiStyle.SIZE_SMALL,
				UiStyle.MINT if morale_delta > 0 else UiStyle.RUST))

		# What the contract changed about them. Without this the whole
		# progression layer happens invisibly and the player feels none of it.
		for line in report.progression.get(op, []):
			var change := UiStyle.text("      " + line, UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
			if line.begins_with("Promoted"):
				change = UiStyle.text("      " + line, UiStyle.SIZE_SMALL, UiStyle.OCHRE)
			elif line.begins_with("Left with"):
				change = UiStyle.text("      " + line, UiStyle.SIZE_SMALL, UiStyle.RUST)
			elif line.begins_with("Picked up"):
				change = UiStyle.text("      " + line, UiStyle.SIZE_SMALL, UiStyle.MINT)
			elif line.begins_with("Awarded"):
				change = UiStyle.text("      ✦ " + line, UiStyle.SIZE_SMALL, UiStyle.OCHRE)
			elif line.contains("star") and line.contains("mastered"):
				change = UiStyle.text("      ★ " + line, UiStyle.SIZE_SMALL, UiStyle.OCHRE)
			_outcome_list.add_child(change)

	# What happened between them out there. This is where the roster stops being
	# a spreadsheet and starts being people who know each other.
	if not report.bond_log.is_empty():
		_story_list.add_child(UiStyle.spacer(8))
		for line in report.bond_log:
			var bond_line := UiStyle.text(line, UiStyle.SIZE_SMALL, UiStyle.STEEL)
			bond_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_story_list.add_child(bond_line)

	if report.client_standing_change != 0:
		_story_list.add_child(UiStyle.spacer(8))
		_story_list.add_child(UiStyle.text(
			"%s: standing %+d" % [
				report.mission.client_name(), report.client_standing_change],
			UiStyle.SIZE_SMALL,
			UiStyle.MINT if report.client_standing_change > 0 else UiStyle.RUST))

	# The feed lives in the narrative column, not the ledger. Below six operators'
	# worth of skill lines the toggle was scrolled half off the card; here it sits
	# in the space the story leaves, and opens into that space.
	if not report.kill_feed.is_empty():
		_story_list.add_child(UiStyle.spacer(10))
		var toggle := Button.new()
		toggle.text = "%s kill feed · %s confirmed" % [
			"Hide" if _feed_open else "Show", TextUtil.number(_total_kills(report))]
		toggle.custom_minimum_size = Vector2(240, 32)
		toggle.pressed.connect(func():
			_feed_open = not _feed_open
			_present(report)
		)
		_story_list.add_child(toggle)

		if _feed_open:
			_story_list.add_child(UiStyle.spacer(2))
			for line in report.kill_feed:
				var kill_line := UiStyle.text(
					"·  " + line, UiStyle.SIZE_SMALL, UiStyle.TEXT_2)
				kill_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_story_list.add_child(kill_line)

	_remaining.text = "%s more to review" % TextUtil.number(_pages.size()) if not _pages.is_empty() else ""
	_next_button.text = "Next" if not _pages.is_empty() else "Continue"
	_fit_columns()


func _make_row(report: MissionReport, op: OperatorData) -> Control:
	var fate: int = report.fates.get(op, GameEnums.Fate.UNHARMED)
	var days: int = int(report.recovery_days.get(op, 0))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var name_label := UiStyle.text(op.display_label(), UiStyle.SIZE_HEADING)
	UiStyle.grow(name_label)
	row.add_child(name_label)

	var xp: int = int(report.xp_gained.get(op, 0))
	var xp_label := UiStyle.data("+%d xp" % xp if xp > 0 else "—", UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
	xp_label.custom_minimum_size.x = 76
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(xp_label)

	var fate_label := UiStyle.text(_fate_text(fate, days), UiStyle.SIZE_BODY, _fate_color(fate))
	fate_label.custom_minimum_size.x = 200
	fate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(fate_label)

	return row


func _fate_text(fate: int, days: int) -> String:
	match fate:
		GameEnums.Fate.KILLED:
			return "Killed in action"
		GameEnums.Fate.WOUNDED:
			return "Wounded · out %s" % TextUtil.count(days, "day")
		GameEnums.Fate.TRAUMATIZED:
			return "Traumatised · out %s" % TextUtil.count(days, "day")
		_:
			return "Came home clean"


func _fate_color(fate: int) -> Color:
	match fate:
		GameEnums.Fate.KILLED:
			return UiStyle.RUST
		GameEnums.Fate.WOUNDED, GameEnums.Fate.TRAUMATIZED:
			return UiStyle.OCHRE
		_:
			return UiStyle.MINT


func _on_next_pressed() -> void:
	if _pages.is_empty():
		hide()
		closed.emit()
		return
	_advance()


## Sizes each column to its own content, up to the cap.
##
## Fixed-height columns meant a two-line week-events page reserved the same room
## as a six-operator debrief, and a long debrief used to run off the bottom of
## the screen entirely. Now the card takes the height it needs and no more; past
## the cap the column scrolls, and an empty column gives its width to the other.
func _fit_columns() -> void:
	# Two frames: the first lays the columns out at their real width, the second
	# lets the labels re-wrap to it. Measuring before that reads pre-layout junk.
	await get_tree().process_frame
	await get_tree().process_frame

	for scroll: ScrollContainer in [_story_scroll, _outcome_scroll]:
		var list: VBoxContainer = scroll.get_child(0).get_child(0)
		scroll.visible = list.get_child_count() > 0
		if scroll.visible:
			scroll.custom_minimum_size.y = minf(_content_height(list), MAX_COLUMN_HEIGHT)


## The drawn height of a column, taken from where its last child actually sits.
##
## get_combined_minimum_size() is useless here: a Label set to autowrap reports
## its minimum height as though it were wrapping at one character per line, so a
## six-line story column claimed to need eight thousand pixels. The laid-out
## rectangles are the only honest number.
func _content_height(list: VBoxContainer) -> float:
	var bottom := 0.0
	for child: Control in list.get_children():
		bottom = maxf(bottom, child.position.y + child.size.y)
	return bottom + 4.0


## Empties both columns *now*, not at the end of the frame.
##
## queue_free() alone leaves the old nodes parented for the rest of the frame,
## so a re-render (opening the kill feed, say) drew the new content underneath
## the old, and the fitter measured both at once.
func _clear_columns() -> void:
	for list: VBoxContainer in [_story_list, _outcome_list]:
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
