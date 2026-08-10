class_name MarketScreen
extends VBoxContainer

## Buying kit. Three sources, one screen.
##
## The Armoury and Quartermaster sell what their facility level unlocks, so the
## shop and the base screen are the same decision seen from two sides. The
## blackmarket ignores facilities entirely and asks for reputation instead —
## the only way onto that shelf is to be worth dealing with.

signal company_changed()

@onready var _tabs := {
	ItemData.Source.ARMOURY: %ArmouryTab as Button,
	ItemData.Source.QUARTERMASTER: %QuartermasterTab as Button,
	ItemData.Source.BLACKMARKET: %BlackmarketTab as Button,
}
@onready var _stock_list: VBoxContainer = %StockList
@onready var _owned_list: VBoxContainer = %OwnedList
@onready var _storage: Label = %Storage
@onready var _locked_note: Label = %LockedNote

var _source: int = ItemData.Source.ARMOURY


func _ready() -> void:
	for source in _tabs:
		_tabs[source].pressed.connect(func():
			_source = source
			refresh()
		)


func refresh() -> void:
	var state := Game.campaign.state

	for source in _tabs:
		_tabs[source].button_pressed = source == _source

	for child in _stock_list.get_children():
		child.queue_free()
	for child in _owned_list.get_children():
		child.queue_free()

	var facility_level := _facility_level_for(_source)
	var stock := ItemLibrary.stock_for(_source, facility_level, state.reputation)

	for item in stock:
		_stock_list.add_child(_make_stock_row(item))

	if stock.is_empty():
		_stock_list.add_child(_empty_note(_nothing_for_sale_reason(facility_level)))
	else:
		var locked := _locked_hint(facility_level)
		_locked_note.text = locked
		_locked_note.visible = not locked.is_empty()

	# Grouped by type here, unlike the Stock panel: this column answers "do we
	# already own one of these" while looking at a price tag, and the answer is a
	# count. The condition of each individual copy is the Stock screen's job.
	var seen := {}
	for instance in state.inventory:
		if seen.has(instance.item_id):
			continue
		seen[instance.item_id] = true
		_owned_list.add_child(_make_owned_row(instance.item_id))
	if state.inventory.is_empty():
		_owned_list.add_child(_empty_note("The company owns nothing yet."))

	_storage.text = "Storage %d / %d" % [state.storage_used(), state.storage_capacity()]
	_storage.add_theme_color_override(
		"font_color", UiStyle.RUST if not state.has_storage_room() else UiStyle.TEXT_2)


func _facility_level_for(source: int) -> int:
	var state := Game.campaign.state
	match source:
		ItemData.Source.ARMOURY:
			return state.facility_level(FacilityLibrary.ARMOURY)
		ItemData.Source.QUARTERMASTER:
			return state.facility_level(FacilityLibrary.QUARTERMASTER)
		_:
			return 0


## Empty shelves have to say what would fill them.
func _nothing_for_sale_reason(facility_level: int) -> String:
	if _source == ItemData.Source.BLACKMARKET:
		return "Nobody here will deal with a company this obscure. Reputation is %d; the first shelf opens at 30." % Game.campaign.state.reputation
	if facility_level <= 0:
		return "Build the facility on the Base screen and it will start carrying stock."
	return "Everything at this level is already listed."


func _locked_hint(facility_level: int) -> String:
	if _source == ItemData.Source.BLACKMARKET or facility_level >= 3:
		return ""
	return "Higher tiers unlock at facility level %d." % (facility_level + 1)


func _empty_note(message: String) -> Control:
	var note := UiStyle.text(message, UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return note


func _make_stock_row(item: ItemData) -> Control:
	var state := Game.campaign.state
	var affordable := item.price <= state.diamonds
	var room := state.has_storage_room()

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.ROW))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	header.add_child(UiStyle.identity(
		item.display_name,
		"%s  ·  Tier %d  ·  %s" % [item.slot_name(), item.tier, item.effect_text()]))
	header.add_child(UiStyle.stat(
		"Price", str(item.price), UiStyle.TEXT if affordable else UiStyle.RUST, 92))

	var buy := Button.new()
	buy.text = "Buy"
	buy.custom_minimum_size = Vector2(88, 36)
	buy.disabled = not affordable or not room
	buy.pressed.connect(func():
		if Game.campaign.buy_item(item):
			company_changed.emit()
			refresh()
	)
	header.add_child(buy)
	box.add_child(header)

	var owned := state.unequipped_count(item.id)
	if owned > 0:
		box.add_child(UiStyle.text(
			"%d in storage" % owned, UiStyle.SIZE_SMALL, UiStyle.MINT))

	return card


func _make_owned_row(item_id: StringName) -> Control:
	var state := Game.campaign.state
	var item := ItemLibrary.get_item(item_id)
	if item == null:
		return UiStyle.text("Unknown item", UiStyle.SIZE_SMALL, UiStyle.TEXT_3)

	var total := state.count_of(item_id)
	var free := state.unequipped_count(item_id)

	# Sells the worst loose copy first. Keeping the good one is what anybody
	# would do, and making the player pick which carbine to sell from a screen
	# about buying is a decision in the wrong place — the Stock screen is where
	# a specific copy gets chosen.
	var worst: ItemInstance = null
	for instance in state.spare_instances():
		if instance.item_id != item_id:
			continue
		if worst == null or instance.condition < worst.condition:
			worst = instance

	var detail := "%d owned  ·  %d in storage" % [total, free]
	if worst != null:
		detail += "  ·  worst %d%%" % int(round(worst.condition))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(UiStyle.identity(item.display_name, detail))

	var sell := UiStyle.confirm_button(
		"Sell %d" % Game.campaign.resale_value(worst) if worst != null else "Sell",
		"Sure?",
		func():
			if Game.campaign.sell_item(worst):
				company_changed.emit()
				refresh()
	, 90)
	sell.custom_minimum_size = Vector2(90, 32)
	sell.disabled = worst == null
	row.add_child(sell)

	return row
