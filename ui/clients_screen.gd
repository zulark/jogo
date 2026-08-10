class_name ClientsScreen
extends VBoxContainer

## Who hires you, how they feel about it, and who is paying to keep you on call.
##
## Standing is per-client and slow to move, so this screen is mostly a ledger —
## but it is where the retainer decision lives, and that one has teeth: the money
## arrives every week whether or not you work, right up until they call.

signal company_changed()

@onready var _list: VBoxContainer = %ClientList
@onready var _summary: Label = %Summary


func refresh() -> void:
	var state := Game.campaign.state

	for child in _list.get_children():
		child.queue_free()

	for id in FactionLibrary.ids():
		_list.add_child(_make_row(id))

	var income := state.retainer_income()
	if income > 0:
		_summary.text = "%d diamonds a week on retainer from %s." % [
			income, TextUtil.count(state.retainers.size(), "client")]
		_summary.add_theme_color_override("font_color", UiStyle.MINT)
	else:
		_summary.text = "No retainers. Reach %d standing with a client and they will offer one." % (
			Balance.RETAINER_MIN_STANDING)
		_summary.add_theme_color_override("font_color", UiStyle.TEXT_2)


func _make_row(faction_id: StringName) -> Control:
	var state := Game.campaign.state
	var campaign := Game.campaign
	var faction := FactionLibrary.get_faction(faction_id)
	var standing := state.standing_with(faction_id)
	var retained := state.retainers.has(faction_id)

	var card := PanelContainer.new()
	var style := UiStyle.panel(UiStyle.ROW)
	if retained:
		style.border_color = UiStyle.OCHRE
		style.border_width_left = 3
	card.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	header.add_child(UiStyle.identity(
		faction.display_name,
		faction.preference_note))
	header.add_child(UiStyle.stat(
		"Standing", str(standing), _standing_color(standing), 88))
	header.add_child(UiStyle.stat(
		"Pays", "%+d%%" % int(round((faction.pay_multiplier - 1.0) * 100.0)),
		UiStyle.TEXT_2, 74))
	box.add_child(header)

	var description := UiStyle.text(faction.description, UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(description)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)

	if retained:
		var note := UiStyle.text(
			"On retainer: %d a week. They may call at any time — refusing costs %d and their goodwill." % [
				int(state.retainers[faction_id]), Balance.RETAINER_REFUSAL_FINE],
			UiStyle.SIZE_SMALL, UiStyle.OCHRE)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiStyle.grow(note)
		actions.add_child(note)

		var end_it := func():
			if campaign.cancel_retainer(faction_id):
				company_changed.emit()
				refresh()
		var cancel := UiStyle.confirm_button(
			"End retainer", "Confirm — end it", end_it, 140)
		cancel.custom_minimum_size = Vector2(140, 36)
		actions.add_child(cancel)

	elif campaign.can_offer_retainer(faction_id):
		var offer := UiStyle.text(
			"Offering %d a week to keep you on call." % campaign.retainer_offer(faction_id),
			UiStyle.SIZE_SMALL, UiStyle.MINT)
		UiStyle.grow(offer)
		actions.add_child(offer)

		var accept := Button.new()
		accept.text = "Accept retainer"
		accept.custom_minimum_size = Vector2(150, 36)
		accept.pressed.connect(func():
			if campaign.accept_retainer(faction_id):
				company_changed.emit()
				refresh()
		)
		actions.add_child(accept)

	else:
		var short: int = Balance.RETAINER_MIN_STANDING - standing
		actions.add_child(UiStyle.text(
			"%s more standing before they would put you on retainer." % (
				TextUtil.number_capitalised(short)),
			UiStyle.SIZE_SMALL, UiStyle.TEXT_3))

	box.add_child(actions)
	return card


func _standing_color(standing: int) -> Color:
	if standing >= Balance.RETAINER_MIN_STANDING:
		return UiStyle.MINT
	if standing >= 20:
		return UiStyle.TEXT
	return UiStyle.TEXT_3
