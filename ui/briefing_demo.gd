class_name BriefingDemo
extends Control

## Playable sandbox for the v0.1 resolver — the project's main scene until the
## real game loop lands in v0.2.
##
## Rolls a random roster, throws a random subset at a random contract, shows the
## odds and the full breakdown, and lets you deploy and see who comes back. It
## exists so the maths can be FELT rather than read off a table: run it a dozen
## times and you learn quickly whether the game is too lethal, whether squad
## composition reads clearly, and whether the breakdown explains itself.

const ROSTER_SIZE := 8
const MIN_SQUAD := 3
const MAX_SQUAD := 5

const SUCCESS_COLOR := Color("6fcf87")
const FAILURE_COLOR := Color("e06b76")

@onready var _briefing: MissionBriefingPanel = %Briefing
@onready var _outcome: PanelContainer = %Outcome
@onready var _outcome_title: Label = %OutcomeTitle
@onready var _outcome_body: Label = %OutcomeBody
@onready var _deploy_button: Button = %DeployButton
@onready var _hint: Label = %Hint

var _rng := RandomNumberGenerator.new()
var _roster: Array[OperatorData] = []
var _report: MissionReport = null


func _ready() -> void:
	_rng.randomize()
	_roster = OperatorFactory.create_pool(_rng, ROSTER_SIZE)
	new_contract()


## New random mission, new random squad drawn from the standing roster.
func new_contract() -> void:
	_outcome.hide()
	_deploy_button.disabled = false

	var mission := MissionFactory.create(_rng)
	_report = MissionResolver.preview(_random_squad(), mission)
	_briefing.show_report(_report)

	_hint.text = "Risk %.0f  ·  a failed contract is %.0f%% deadlier" % [
		mission.risk,
		(Balance.FAILURE_DANGER_MULT - 1.0) * 100.0,
	]


func deploy() -> void:
	if _report == null:
		return

	MissionResolver.roll(_report, _rng)
	_deploy_button.disabled = true

	_outcome_title.text = "CONTRACT COMPLETE" if _report.success else "CONTRACT FAILED"
	_outcome_title.add_theme_color_override(
		"font_color",
		SUCCESS_COLOR if _report.success else FAILURE_COLOR
	)

	var lines: PackedStringArray = []
	lines.append("Rolled %d against %d%%   ·   paid %d diamonds" % [
		int(_report.roll_value * 100.0),
		_report.chance_percent(),
		_report.reward_paid,
	])
	for op in _report.squad.members():
		var fate: int = _report.fates.get(op, GameEnums.Fate.UNHARMED)
		var days: int = int(_report.recovery_days.get(op, 0))
		lines.append("%s — %s%s" % [
			op.display_label(),
			_fate_text(fate),
			(" for %s" % TextUtil.count(days, "day")) if days > 0 else "",
		])
	_outcome_body.text = "\n".join(lines)
	_outcome.show()


func _fate_text(fate: int) -> String:
	match fate:
		GameEnums.Fate.KILLED:
			return "killed in action"
		GameEnums.Fate.WOUNDED:
			return "wounded, out"
		GameEnums.Fate.TRAUMATIZED:
			return "traumatised, out"
		_:
			return "came home clean"


## Random subset of the roster, each operator in the role they trained for.
func _random_squad() -> Squad:
	var pool := _roster.duplicate()
	pool.shuffle()

	var squad := Squad.new()
	var size: int = mini(_rng.randi_range(MIN_SQUAD, MAX_SQUAD), pool.size())
	for i in size:
		squad.add(pool[i], pool[i].preferred_role)
	squad.set_leader(pool[0])
	return squad


func _on_new_contract_pressed() -> void:
	new_contract()


func _on_deploy_pressed() -> void:
	deploy()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey and event.keycode == KEY_SPACE:
		if _deploy_button.disabled:
			new_contract()
		else:
			deploy()
