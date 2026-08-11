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

signal company_changed()

@onready var _list: VBoxContainer = %StockList
@onready var _summary: Label = %Summary
@onready var _filter_row: HBoxContainer = %FilterRow

## -1 shows everything; otherwise an ItemData.Slot.
var _slot_filter: int = -1
var _only_spare := false


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


func _make_row(instance: ItemInstance, state: GameState) -> Control:
	var item := instance.data()
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.ROW))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header.add_child(UiStyle.identity(
		instance.display_name(),
		"%s  ·  %s" % [instance.condition_text(), instance.effect_text()]))
	header.add_child(UiStyle.condition_meter(instance, 96))

	var holder := state.holder_of(instance)
	var where := "Spare"
	var where_color := UiStyle.MINT
	if holder != null:
		where = "Issued"
		where_color = UiStyle.STEEL
	elif state.is_in_workshop(instance):
		where = "Bench"
		where_color = UiStyle.OCHRE
	header.add_child(UiStyle.stat("Status", where, where_color, 78))

	var value := Game.campaign.resale_value(instance)
	var sell := UiStyle.confirm_button("Sell %d" % value, "Sure?", func():
		if Game.campaign.sell_item(instance):
			company_changed.emit()
			refresh()
	, 96)
	sell.custom_minimum_size = Vector2(96, 34)
	sell.disabled = not state.is_spare(instance)
	header.add_child(sell)
	box.add_child(header)

	var notes: PackedStringArray = []
	if holder != null:
		notes.append("Carried by %s" % holder.display_label())
	elif state.is_in_workshop(instance):
		notes.append("On the bench")
	if instance.contracts > 0:
		notes.append(TextUtil.count(instance.contracts, "contract"))
	if instance.max_condition < Balance.CONDITION_NEW:
		notes.append("rebuilt — will not go past %d%%" % int(round(instance.max_condition)))
	if item != null and item.counters_hazard != GameEnums.Hazard.NONE:
		notes.append("cancels %s" % GameEnums.hazard_phrase(item.counters_hazard))

	if not notes.is_empty():
		var line := UiStyle.text(
			"  ·  ".join(notes), UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(line)

	return card
