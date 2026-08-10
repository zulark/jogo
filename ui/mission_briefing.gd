class_name MissionBriefingPanel
extends PanelContainer

## Renders a MissionReport as the XCOM-style briefing panel: the odds, and every
## line that produced them. Reads the report and nothing else — it never
## calculates, so the number on screen can never disagree with the resolver.

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _briefing_text: Label = %BriefingText
@onready var _breakdown: VBoxContainer = %Breakdown
@onready var _squad_terms: VBoxContainer = %SquadTerms
@onready var _score_value: Label = %ScoreValue
@onready var _difficulty_value: Label = %DifficultyValue
@onready var _chance_value: Label = %ChanceValue
@onready var _chance_bar: ProgressBar = %ChanceBar


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

	_chance_value.add_theme_font_override("font", UiStyle.mono())
	_chance_value.add_theme_font_size_override("font_size", UiStyle.SIZE_DISPLAY)


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

	var percent: int = report.chance_percent()
	_chance_value.text = "%d%%" % percent
	_chance_bar.value = percent

	var odds_color: Color = UiStyle.odds_color(percent)
	_chance_value.add_theme_color_override("font_color", odds_color)

	var fill := StyleBoxFlat.new()
	fill.bg_color = odds_color
	fill.corner_radius_top_left = 3
	fill.corner_radius_top_right = 3
	fill.corner_radius_bottom_left = 3
	fill.corner_radius_bottom_right = 3
	_chance_bar.add_theme_stylebox_override("fill", fill)


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
