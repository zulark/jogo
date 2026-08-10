class_name InventoryScreen
extends VBoxContainer

## Stock. What the company owns, who is carrying it, and what is spare.
##
## Separate from the Market on purpose: the Market is about spending money, this
## is about knowing what you already have. Once loot starts coming back from
## contracts those are genuinely different questions, and answering "do I own a
## plate carrier for this job" should not require walking a shop.

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

	# One row per distinct item, with counts — twelve identical carbines should
	# be one line saying twelve, not twelve lines.
	var counts := {}
	for id in state.inventory:
		counts[id] = int(counts.get(id, 0)) + 1

	var shown := 0
	var carried_total := 0
	for id in counts:
		var item := ItemLibrary.get_item(id)
		if item == null:
			continue
		var spare_count: int = state.unequipped_count(id)
		carried_total += int(counts[id]) - spare_count

		if _slot_filter >= 0 and item.slot != _slot_filter:
			continue
		if _only_spare and spare_count <= 0:
			continue

		_list.add_child(_make_row(item, int(counts[id]), spare_count, state))
		shown += 1

	if shown == 0:
		_list.add_child(UiStyle.text(
			"Nothing here. Buy kit in the Market, or bring it back off a contract.",
			UiStyle.SIZE_SMALL, UiStyle.TEXT_3))

	_summary.text = "%s held · %d carried · %d / %d storage" % [
		TextUtil.count(state.inventory.size(), "item"), carried_total,
		state.storage_used(), state.storage_capacity()]
	_summary.add_theme_color_override(
		"font_color", UiStyle.RUST if not state.has_storage_room() else UiStyle.TEXT_2)


func _make_row(item: ItemData, owned: int, spare: int, state: GameState) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.ROW))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header.add_child(UiStyle.identity(
		item.display_name,
		"%s  ·  Tier %d  ·  %s" % [item.slot_name(), item.tier, item.effect_text()]))
	header.add_child(UiStyle.stat("Owned", str(owned), UiStyle.TEXT, 66))
	header.add_child(UiStyle.stat(
		"Spare", str(spare), UiStyle.MINT if spare > 0 else UiStyle.TEXT_3, 62))

	var sell := UiStyle.confirm_button("Sell", "Sure?", func():
		if Game.campaign.sell_item(item.id):
			company_changed.emit()
			refresh()
	, 80)
	sell.custom_minimum_size = Vector2(80, 34)
	sell.disabled = spare <= 0
	header.add_child(sell)
	box.add_child(header)

	# Who has it. Without this the only way to find a missing item is to open
	# every operator in turn.
	var holders: PackedStringArray = []
	for op in state.roster:
		if op.weapon_id == item.id or op.gear_id == item.id:
			holders.append(op.display_label())
	if not holders.is_empty():
		var line := UiStyle.text(
			"Carried by %s" % ", ".join(holders), UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(line)

	if item.counters_hazard != GameEnums.Hazard.NONE:
		box.add_child(UiStyle.text(
			"Cancels %s hazard." % GameEnums.hazard_name(item.counters_hazard).to_lower(),
			UiStyle.SIZE_SMALL, UiStyle.STEEL))

	return card
