class_name TrainingScreen
extends VBoxContainer

## The academy. Pick who teaches and who learns, and lose both of them for a week.
##
## The cost is the design: training is two operators off the board at once, which
## is exactly when you can least afford it. What it buys is the only way past the
## field skill ceiling, and the only way to turn a rookie into someone worth
## deploying before they get killed learning the hard way.

signal roster_changed()

@onready var _mentor_list: VBoxContainer = %MentorList
@onready var _trainee_list: VBoxContainer = %TraineeList
@onready var _active_list: VBoxContainer = %ActiveList
@onready var _start_button: Button = %StartButton
@onready var _summary: Label = %Summary

var _mentor: OperatorData = null
var _trainee: OperatorData = null


func refresh() -> void:
	var state := Game.campaign.state

	for child in _mentor_list.get_children():
		child.queue_free()
	for child in _trainee_list.get_children():
		child.queue_free()
	for child in _active_list.get_children():
		child.queue_free()

	var mentors := state.potential_mentors()
	if _mentor != null and not mentors.has(_mentor):
		_mentor = null
	for op in mentors:
		_mentor_list.add_child(_make_person_row(op, true))
	if mentors.is_empty():
		# An empty column has to say why it is empty and what would fill it.
		# "Nobody here" tells the player nothing they can act on.
		_mentor_list.add_child(_empty_note(_no_mentors_reason(state)))

	if _trainee != null and not _trainee.is_deployable():
		_trainee = null
	var trainees := 0
	for op in state.available_operators():
		if op == _mentor or op.career_track == GameEnums.CareerTrack.INSTRUCTOR:
			continue
		_trainee_list.add_child(_make_person_row(op, false))
		trainees += 1
	if trainees == 0:
		_trainee_list.add_child(_empty_note(
			"Everyone is deployed, recovering or already in a class."))

	if state.training.is_empty():
		_active_list.add_child(UiStyle.text(
			"Nobody is training.", UiStyle.SIZE_SMALL, UiStyle.TEXT_3))
	for session in state.training:
		_active_list.add_child(_make_session_row(session))

	var can_start: bool = (
		_mentor != null and _trainee != null
		and Progression.can_train(_mentor, _trainee)
	)
	_start_button.disabled = not can_start
	_summary.text = _summary_text(can_start)


func _empty_note(message: String) -> Control:
	var note := UiStyle.text(message, UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return note


## Distinguishes "you have no senior people" from "your senior people are busy".
## They call for completely different actions.
func _no_mentors_reason(state: GameState) -> String:
	var senior := 0
	for op in state.roster:
		if op.career_track == GameEnums.CareerTrack.INSTRUCTOR \
				or op.rank_step() >= Balance.TRAINING_MIN_RANK_GAP:
			senior += 1

	if senior == 0:
		return "Nobody has reached %s yet. Rank comes from surviving contracts — or hire someone who already has." % GameEnums.rank_name(Balance.TRAINING_MIN_RANK_GAP)
	return "Everyone senior enough is deployed, recovering or already teaching. Come back when a squad is home."


func _summary_text(can_start: bool) -> String:
	if _mentor == null:
		if Game.campaign.state.potential_mentors().is_empty():
			return "No instructor available."
		return "Choose an instructor. They need to outrank the trainee by %d ranks, or have left the field." % Balance.TRAINING_MIN_RANK_GAP
	if _trainee == null:
		return "Choose who %s teaches." % _mentor.display_label()
	if not can_start:
		if _mentor.rank_step() <= _trainee.rank_step():
			return "%s does not outrank %s. Nobody teaches upward." % [
				_mentor.display_label(), _trainee.display_label()]
		return "%s needs to outrank %s by %d ranks to teach them." % [
			_mentor.display_label(), _trainee.display_label(),
			Balance.TRAINING_MIN_RANK_GAP]
	return "%s trains %s for %s. Both are off the board." % [
		_mentor.display_label(), _trainee.display_label(),
		TextUtil.count(Balance.TRAINING_DAYS, "day")]


func _make_person_row(op: OperatorData, is_mentor: bool) -> Button:
	var selected: bool = op == (_mentor if is_mentor else _trainee)
	var button := UiStyle.row_button(selected)
	button.custom_minimum_size.y = UiStyle.ROW_HEIGHT
	button.pressed.connect(func():
		if is_mentor:
			_mentor = null if _mentor == op else op
		else:
			_trainee = null if _trainee == op else op
		refresh()
	)

	var row := UiStyle.row_content(button)
	row.add_child(UiStyle.portrait(op, 34))

	var track: String = "%s %s" % [GameEnums.rank_glyph(op.rank), GameEnums.rank_name(op.rank)]
	if op.career_track == GameEnums.CareerTrack.INSTRUCTOR:
		track += "  ·  Instructor"
	row.add_child(UiStyle.identity(op.display_label(), track))

	# Training does not rest anyone, so sending an exhausted operator to a class
	# only delays the problem — the bar has to be visible while choosing.
	row.add_child(UiStyle.fatigue_meter(op, 56))

	if is_mentor and not op.trainees.is_empty():
		row.add_child(UiStyle.stat("Taught", str(op.trainees.size()), UiStyle.TEXT_2, 58))
	elif not is_mentor:
		row.add_child(UiStyle.stat(
			"Best skill", str(_best_skill(op)), UiStyle.TEXT_2, 78))

	return button


func _best_skill(op: OperatorData) -> int:
	var best := 0
	for skill in GameEnums.Skill.values():
		best = maxi(best, op.get_skill(skill))
	return best


func _make_session_row(session: TrainingSession) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.ROW))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)

	# Two lines rather than one long "A → B": a single line forces this column
	# wider than the two beside it.
	row.add_child(UiStyle.identity(
		session.trainee.display_label(),
		"taught by %s" % session.mentor.display_label()))
	row.add_child(UiStyle.stat(
		"Days left", str(session.days_remaining), UiStyle.OCHRE, 86))

	return card


func _on_start_pressed() -> void:
	if Game.campaign.start_training(_mentor, _trainee) != null:
		_mentor = null
		_trainee = null
		roster_changed.emit()
		refresh()
