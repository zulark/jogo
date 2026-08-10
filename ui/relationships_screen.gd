class_name RelationshipsScreen
extends VBoxContainer

## Who gets on with whom, and why.
##
## Every link is listed once with the contract that caused it. That last part is
## the point: a table of relationship values is bookkeeping, but "blamed each
## other for how Salt the Wells went" is the reason you think twice before
## putting those two in the same truck.

@onready var _list: VBoxContainer = %BondList
@onready var _summary: Label = %Summary
@onready var _filter_row: HBoxContainer = %FilterRow

## -1 shows everything.
var _filter: int = -1


func _ready() -> void:
	for entry in [
		{"label": "All", "type": -1},
		{"label": "Friendships", "type": GameEnums.BondType.FRIENDSHIP},
		{"label": "Rivalries", "type": GameEnums.BondType.RIVALRY},
		{"label": "Romances", "type": GameEnums.BondType.ROMANCE},
	]:
		var button := Button.new()
		button.text = entry["label"]
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(120, 32)
		var wanted: int = entry["type"]
		button.pressed.connect(func():
			_filter = wanted
			refresh()
		)
		_filter_row.add_child(button)


func refresh() -> void:
	var state := Game.campaign.state

	for child in _list.get_children():
		child.queue_free()

	var index := 0
	for child in _filter_row.get_children():
		var button := child as Button
		var types := [-1, GameEnums.BondType.FRIENDSHIP,
			GameEnums.BondType.RIVALRY, GameEnums.BondType.ROMANCE]
		button.button_pressed = _filter == types[index]
		index += 1

	# Each pair once. Bonds are mirrored, so without this every link appears
	# twice with the names swapped.
	var seen := {}
	var pairs: Array = []
	var counts := {
		GameEnums.BondType.FRIENDSHIP: 0,
		GameEnums.BondType.RIVALRY: 0,
		GameEnums.BondType.ROMANCE: 0,
	}

	for op in state.roster:
		for other in state.roster:
			if op == other or not Bonds.has_bond(op, other):
				continue
			var key: String = "|".join(
				[String(op.id), String(other.id)] if String(op.id) < String(other.id)
				else [String(other.id), String(op.id)])
			if seen.has(key):
				continue
			seen[key] = true

			var type: int = Bonds.bond_type(op, other)
			counts[type] = int(counts.get(type, 0)) + 1
			if _filter >= 0 and type != _filter:
				continue
			pairs.append({"a": op, "b": other, "type": type,
				"strength": Bonds.strength(op, other)})

	pairs.sort_custom(func(x, y): return x["strength"] > y["strength"])

	_summary.text = "%s · %s · %s" % [
		TextUtil.count(counts[GameEnums.BondType.FRIENDSHIP], "friendship"),
		TextUtil.count(counts[GameEnums.BondType.RIVALRY], "rivalry", "rivalries"),
		TextUtil.count(counts[GameEnums.BondType.ROMANCE], "romance"),
	]

	if pairs.is_empty():
		_list.add_child(UiStyle.text(
			"Nothing yet. People form opinions of each other by surviving contracts together.",
			UiStyle.SIZE_SMALL, UiStyle.TEXT_3))
		return

	for pair in pairs:
		_list.add_child(_make_row(pair))


func _make_row(pair: Dictionary) -> Control:
	var a: OperatorData = pair["a"]
	var b: OperatorData = pair["b"]
	var type: int = pair["type"]

	var card := PanelContainer.new()
	var style := UiStyle.panel(UiStyle.ROW)
	style.border_color = Bonds.color_for(type)
	style.border_width_left = 3
	card.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	card.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.add_child(UiStyle.portrait(a, 34))
	header.add_child(UiStyle.portrait(b, 34))
	header.add_child(UiStyle.identity(
		"%s  &  %s" % [a.display_label(), b.display_label()],
		Bonds.describe(type, pair["strength"])))
	header.add_child(UiStyle.stat(
		"Strength", str(pair["strength"]), Bonds.color_for(type), 84))
	box.add_child(header)

	var reason: String = Bonds.reason_for(a, b)
	if not reason.is_empty():
		var line := UiStyle.text(reason, UiStyle.SIZE_SMALL, UiStyle.TEXT_2)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(line)

	return card
