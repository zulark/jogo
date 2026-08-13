class_name MissionBriefingPanel
extends PanelContainer

## Renders a MissionReport as the briefing panel: what the company makes of the
## job, and every line that produced that view. Reads the report and nothing
## else — it never calculates, so what is on screen cannot disagree with the
## resolver.
##
## The squad score and the mission difficulty stay, and stay exact. Those are
## two quantities being COMPARED, which is the judgement the player is here to
## make. What is gone is the percentage that used to sit under them and answer
## the question on their behalf — see UiStyle's assessment block.

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _briefing_text: Label = %BriefingText
@onready var _tests: VBoxContainer = %Tests
@onready var _breakdown: VBoxContainer = %Breakdown
@onready var _squad_terms: VBoxContainer = %SquadTerms
@onready var _score_value: Label = %ScoreValue
@onready var _difficulty_value: Label = %DifficultyValue
@onready var _assessment_word: Label = %AssessmentWord
@onready var _assessment_note: Label = %AssessmentNote
@onready var _gauge_slot: HBoxContainer = %GaugeSlot


## Typography is applied here rather than baked into the .tscn, so the palette
## and type scale live in exactly one file.
func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.PANEL, UiStyle.RULE, 5))

	_title.add_theme_font_override("font", UiStyle.display())
	_title.add_theme_font_size_override("font_size", UiStyle.SIZE_DISPLAY)
	_title.add_theme_color_override("font_color", UiStyle.TEXT)

	_subtitle.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL)
	_subtitle.add_theme_color_override("font_color", UiStyle.TEXT_3)

	_briefing_text.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL)
	_briefing_text.add_theme_color_override("font_color", UiStyle.TEXT_2)
	_briefing_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	for value in [_score_value, _difficulty_value]:
		value.add_theme_font_override("font", UiStyle.mono())
		value.add_theme_font_size_override("font_size", UiStyle.SIZE_HEADING)
		value.add_theme_color_override("font_color", UiStyle.TEXT)

	# The condensed face, not the monospace one. Monospace is this project's
	# signal that a figure is meant to be compared against another figure, and
	# the assessment is the one thing on this panel that is deliberately not.
	_assessment_word.add_theme_font_override("font", UiStyle.display())
	_assessment_word.add_theme_font_size_override("font_size", UiStyle.SIZE_TITLE)

	_assessment_note.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL)
	_assessment_note.add_theme_color_override("font_color", UiStyle.TEXT_2)


func show_report(report: MissionReport) -> void:
	if report == null or report.mission == null:
		return

	_title.text = report.mission.title.to_upper()
	_subtitle.text = "%s   ·   %s   ·   %s   ·   %s   ·   %d diamonds" % [
		report.mission.type_name().to_upper(),
		report.mission.client_name(),
		report.mission.region_name(),
		TextUtil.count(report.mission.duration_days, "day"),
		report.mission.fee_for(Game.campaign.state.reputation if Game.campaign else 0),
	]

	_briefing_text.text = report.mission.briefing
	_briefing_text.visible = not report.mission.briefing.is_empty()

	_build_tests(report)

	for child in _breakdown.get_children():
		child.queue_free()
	for child in _squad_terms.get_children():
		child.queue_free()

	# Per-operator lines scroll; squad-level lines are pinned below the fold
	# line. Composition and size are the terms the player can actually
	# act on, so they must never be something you have to scroll to find.
	var current_owner: StringName = &"￿"
	var is_first := true
	for modifier in report.modifiers:
		if modifier.operator_id == &"":
			_squad_terms.add_child(_make_row(modifier))
			continue
		if modifier.operator_id != current_owner:
			current_owner = modifier.operator_id
			var heading: String = str(report.operator_labels.get(current_owner, "SQUAD"))
			_breakdown.add_child(_make_heading(heading, is_first))
			is_first = false
		_breakdown.add_child(_make_row(modifier))

	_score_value.text = "%.1f" % report.squad_score
	_difficulty_value.text = "%.1f" % report.difficulty

	var color := UiStyle.assessment_color(report)
	_assessment_word.text = UiStyle.assessment_word(report)
	_assessment_word.add_theme_color_override("font_color", color)
	_assessment_note.text = UiStyle.assessment_note(report)

	for child in _gauge_slot.get_children():
		child.queue_free()
	_gauge_slot.add_child(
		UiStyle.band_gauge(UiStyle.assessment_band(report), color, 22, true))


## What the job tests, and what the squad in front of it actually brings.
##
## The block sits above the breakdown rather than inside it because it answers a
## different question. The breakdown is an account of a number that has already
## been decided; this is the requirement the player is deciding against, and a
## requirement below the fold is a requirement discovered afterwards.
##
## The bars are the squad's plain AVERAGE in each tested skill — where they are
## thin — and deliberately not an aggregate rating. There is no fourth figure
## here on purpose: SQUAD SCORE and MISSION DIFFICULTY below already answer "is
## this enough", the rows on the left answer "is this person right for it", and
## a third total would only be those two numbers wearing a different hat.
func _build_tests(report: MissionReport) -> void:
	for child in _tests.get_children():
		child.queue_free()

	var profile := MissionResolver.profile_for(report.mission.mission_type)
	_tests.visible = profile != null
	if profile == null:
		return

	var members: Array = report.squad.members() if report.squad != null else []

	_tests.add_child(UiStyle.eyebrow("What this work tests"))
	_tests.add_child(UiStyle.work_emphasis_block(profile, members))

	# Size is part of what the job asks for and belongs with the rest of it. The
	# breakdown says so too, but only once the squad is already the wrong size.
	var size_note := UiStyle.text(
		Ovr.size_note(profile), UiStyle.SIZE_CAPTION, UiStyle.TEXT_3)
	size_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tests.add_child(size_note)


func _make_heading(content: String, is_first: bool) -> Control:
	var label := UiStyle.text(content, UiStyle.SIZE_HEADING, UiStyle.TEXT)

	if is_first:
		return label

	# Breathing room above every group but the first, so the list reads as
	# blocks of people instead of one long column.
	var spacer := MarginContainer.new()
	spacer.add_theme_constant_override("margin_top", 12)
	spacer.add_child(label)
	return spacer


func _make_row(modifier: Modifier) -> Control:
	var row := HBoxContainer.new()

	var indent := Control.new()
	indent.custom_minimum_size.x = 16
	row.add_child(indent)

	var label := UiStyle.text(modifier.label, UiStyle.SIZE_SMALL, UiStyle.TEXT_2)
	UiStyle.grow(label)
	row.add_child(label)

	# Monospace so the signed figures form a straight column down the panel.
	var value := UiStyle.data(
		modifier.signed_text(),
		UiStyle.SIZE_SMALL,
		UiStyle.MINT if modifier.value >= 0.0 else UiStyle.RUST
	)
	value.custom_minimum_size.x = 68
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)

	return row
