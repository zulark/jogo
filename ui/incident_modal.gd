class_name IncidentModal
extends Control

## The day's decision, presented one at a time.
##
## Two steps on purpose: choose, then read what the choice did. Applying the
## effect and closing in one motion would make an incident feel like a message
## box that happened to have buttons — the second beat is where the player finds
## out whether the price they were quoted was the price they paid.
##
## Every option states its cost on the row before it is taken. That is the same
## bargain the odds screen makes everywhere else in this game, and an incident
## that hides its consequences would be the one place it is broken.

signal closed()

@onready var _eyebrow: Label = %Eyebrow
@onready var _title: Label = %Title
@onready var _line: Label = %Line
@onready var _options: VBoxContainer = %Options
@onready var _outcome: Label = %Outcome
@onready var _done_button: Button = %DoneButton

var _incident: Dictionary = {}


func show_incident(incident: Dictionary) -> void:
	_incident = incident
	# Where the decision came from. The desk and a squad in country are the same
	# card with the same rules, and the player should be able to tell which one
	# they are reading before they read a word of it.
	_eyebrow.text = str(incident.get("eyebrow", "ON THE DESK"))
	_title.text = str(incident.get("title", "Something happened"))
	_title.add_theme_font_override("font", UiStyle.display())
	_title.add_theme_color_override("font_color", UiStyle.TEXT)
	_line.text = str(incident.get("line", ""))

	for child in _options.get_children():
		_options.remove_child(child)
		child.queue_free()

	_outcome.text = ""
	_done_button.hide()

	for option in incident.get("options", []):
		_options.add_child(_make_option(option))

	show()


func _make_option(option: Dictionary) -> Control:
	var button := UiStyle.row_button(false)
	button.custom_minimum_size.y = UiStyle.ROW_HEIGHT_COMPACT
	button.pressed.connect(func(): _choose(option))

	var row := UiStyle.row_content(button)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.grow(box)

	box.add_child(UiStyle.text(
		str(option.get("label", "")), UiStyle.SIZE_HEADING, UiStyle.TEXT))

	# The price, stated before the click rather than after it.
	var detail := UiStyle.text(
		str(option.get("detail", "")), UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail)

	row.add_child(box)
	return button


func _choose(option: Dictionary) -> void:
	var result := ""
	var apply: Callable = option.get("apply", Callable())
	if apply.is_valid():
		result = str(apply.call())

	# The options go, so the outcome is the only thing left to read and there is
	# no half-state where a decision looks re-takeable.
	for child in _options.get_children():
		_options.remove_child(child)
		child.queue_free()

	_outcome.text = result
	_outcome.add_theme_color_override("font_color", UiStyle.TEXT_2)
	_done_button.show()
	_done_button.grab_focus()


func _on_done_pressed() -> void:
	hide()
	_incident = {}
	closed.emit()
