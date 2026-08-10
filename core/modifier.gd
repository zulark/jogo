class_name Modifier
extends RefCounted

## One line in the XCOM-style success breakdown: "Kovacs fears infiltration -12".
## The resolver emits these as it works, so the UI never recalculates anything —
## it just renders the list.

var label: String = ""
var value: float = 0.0
var source: GameEnums.ModifierSource = GameEnums.ModifierSource.SKILL

## Optional: which operator this line is about, for grouping in the tooltip.
var operator_id: StringName = &""


static func create(
	p_label: String,
	p_value: float,
	p_source: int,
	p_operator_id: StringName = &""
) -> Modifier:
	var m := Modifier.new()
	m.label = p_label
	m.value = p_value
	m.source = p_source
	m.operator_id = p_operator_id
	return m


func signed_text() -> String:
	return "%+.1f" % value


func to_line() -> String:
	return "%-46s %s" % [label, signed_text()]
