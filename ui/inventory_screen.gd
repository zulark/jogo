class_name InventoryScreen
extends VBoxContainer

## Stock. What the company owns, what state it is in, and who is carrying it.
##
## Separate from the Market on purpose: the Market is about spending money, this
## is about knowing what you already have. Since v0.13 that is a different
## question again, because two carbines are no longer the same thing — one of
## them came back from the Kivu Border at 31%.
##
## Which is why this lists one row per **copy** rather than one per type. The
## v0.5 rule was that twelve identical carbines should be one line saying
## twelve; twelve carbines at twelve different conditions are twelve things, and
## collapsing them would hide the only fact on the screen worth acting on.
##
## The panel beside the list is the service record — where a copy came from, who
## has carried it, what it has killed. A row can only afford the state a player
## acts on; everything a copy has *been* through belongs next to it.

signal company_changed()

@onready var _list: VBoxContainer = %StockList
@onready var _summary: Label = %Summary
@onready var _filter_row: HBoxContainer = %FilterRow
@onready var _record: VBoxContainer = %RecordBody

## -1 shows everything; otherwise an ItemData.Slot.
var _slot_filter: int = -1
var _only_spare := false

## By uid rather than by reference, so a selection survives the item being sold,
## scrapped or lost while the screen is open.
var _selected_uid: StringName = &""


func _ready() -> void:
	for entry in [
		{"label": "All", "slot": -1},
		{"label": "Weapons", "slot": ItemData.Slot.WEAPON},
		{"label": "Gear", "slot": ItemData.Slot.GEAR},
	]:
		var button := Button.new()
		button.text = entry["label"]
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(110, 32)
		var wanted: int = entry["slot"]
		button.pressed.connect(func():
			_slot_filter = wanted
			refresh()
		)
		_filter_row.add_child(button)

	var spare := UiStyle.state_button("Spare only", false, 120)
	spare.pressed.connect(func():
		_only_spare = not _only_spare
		spare.button_pressed = _only_spare
		refresh()
	)
	_filter_row.add_child(spare)


func refresh() -> void:
	var state := Game.campaign.state

	for child in _list.get_children():
		child.queue_free()

	var index := 0
	for child in _filter_row.get_children():
		if index < 3:
			(child as Button).button_pressed = _slot_filter == [-1,
				ItemData.Slot.WEAPON, ItemData.Slot.GEAR][index]
		index += 1

	# Worst first. The reason to open this screen is nearly always something
	# that has gone wrong with a specific item, so that is what the top row is.
	var sorted := state.inventory.duplicate()
	sorted.sort_custom(func(a: ItemInstance, b: ItemInstance):
		if is_equal_approx(a.condition, b.condition):
			return a.display_name() < b.display_name()
		return a.condition < b.condition
	)

	var shown := 0
	var carried_total := 0
	var broken := 0
	for instance: ItemInstance in sorted:
		var spare_copy: bool = state.is_spare(instance)
		if not spare_copy:
			carried_total += 1
		if not instance.is_serviceable():
			broken += 1

		if _slot_filter >= 0 and instance.slot() != _slot_filter:
			continue
		if _only_spare and not spare_copy:
			continue

		_list.add_child(_make_row(instance, state))
		shown += 1

	if shown == 0:
		_list.add_child(UiStyle.text(
			"Nothing here. Buy kit in the Market, or bring it back off a contract.",
			UiStyle.SIZE_SMALL, UiStyle.TEXT_3))

	var summary := "%s held · %d issued · %d / %d storage" % [
		TextUtil.count(state.inventory.size(), "item"), carried_total,
		state.storage_used(), state.storage_capacity()]
	if broken > 0:
		summary += " · %d unserviceable" % broken
	_summary.text = summary
	_summary.add_theme_color_override("font_color",
		UiStyle.RUST if broken > 0 or not state.has_storage_room() else UiStyle.TEXT_2)

	_show_record(state)


func _make_row(instance: ItemInstance, state: GameState) -> Control:
	var button := UiStyle.row_button(instance.uid == _selected_uid)
	button.custom_minimum_size.y = UiStyle.ROW_HEIGHT_COMPACT
	button.pressed.connect(func():
		_selected_uid = instance.uid
		refresh()
	)

	var row := UiStyle.row_content(button)

	var holder := state.holder_of(instance)
	var where := "Spare"
	var where_color := UiStyle.MINT
	if holder != null:
		where = "Issued"
		where_color = UiStyle.STEEL
	elif state.is_in_workshop(instance):
		where = "Bench"
		where_color = UiStyle.OCHRE

	var second: String = instance.condition_text()
	if holder != null:
		second += "  ·  %s" % holder.display_label()
	var headline := ItemHistory.headline(instance)
	if not headline.is_empty():
		second += "  ·  %s" % headline

	row.add_child(UiStyle.identity(instance.display_name(), second))
	row.add_child(UiStyle.condition_meter(instance, 96))
	row.add_child(UiStyle.stat("Status", where, where_color, 78))

	var value := Game.campaign.resale_value(instance)
	var sell := UiStyle.confirm_button("Sell %d" % value, "Sure?", func():
		if Game.campaign.sell_item(instance):
			company_changed.emit()
			refresh()
	, 96)
	sell.custom_minimum_size = Vector2(96, 34)
	sell.disabled = not state.is_spare(instance)
	row.add_child(sell)

	return button


func _show_record(state: GameState) -> void:
	for child in _record.get_children():
		child.queue_free()

	var instance := state.find_instance(_selected_uid)
	if instance == null:
		_record.add_child(_line(
			"Pick something off the rack. Every copy keeps its own record — where "
			+ "it came from, who has carried it, and what it has done.", UiStyle.TEXT_3))
		return

	_record.add_child(UiStyle.title(instance.display_name(), UiStyle.SIZE_BODY))

	var item := instance.data()
	if item != null and not item.description.is_empty():
		_record.add_child(_line(item.description, UiStyle.TEXT_3))

	var facts := HBoxContainer.new()
	facts.add_theme_constant_override("separation", 10)
	facts.add_child(UiStyle.stat("Condition", instance.condition_text(), UiStyle.TEXT, 132))
	facts.add_child(UiStyle.stat("Contracts", str(instance.contracts), UiStyle.TEXT, 78))
	# Gear cannot kill anybody, so a kill column under a plate carrier is a zero
	# that will never be anything else.
	if instance.slot() == ItemData.Slot.WEAPON:
		facts.add_child(UiStyle.stat("Confirmed", str(instance.kills), UiStyle.TEXT, 78))
	_record.add_child(facts)

	_record.add_child(UiStyle.eyebrow("History"))
	var written := ItemHistory.lines(instance)
	if written.is_empty():
		_record.add_child(_line(
			"Nothing on it yet. It has not been anywhere.", UiStyle.TEXT_3))
	for entry in written:
		_record.add_child(_line(entry, UiStyle.TEXT_2))


## Every label in this panel wraps. An unwrapped one makes its natural width the
## panel's minimum and takes the difference out of the list beside it.
func _line(content: String, color: Color) -> Label:
	var label := UiStyle.text(content, UiStyle.SIZE_SMALL, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 400
	return label
