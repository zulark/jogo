class_name WorkshopScreen
extends VBoxContainer

## The bench. Repair what came back, strip what is finished, build what nobody
## sells.
##
## The scarce thing on this screen is not money, it is bench time: the Armoury
## and Quartermaster run one bench per level, and whatever is on one is not on a
## contract. So every action states both prices — diamonds and days — the way
## the odds screen states its modifiers, because a repair booked the morning of
## a deployment is a rifle the squad does not have.

signal company_changed()

@onready var _benches: HBoxContainer = %Benches
@onready var _jobs_list: VBoxContainer = %JobsList
@onready var _kit_list: VBoxContainer = %KitList
@onready var _blueprint_list: VBoxContainer = %BlueprintList
@onready var _salvage_label: Label = %SalvageLabel


func refresh() -> void:
	var state := Game.campaign.state

	_salvage_label.text = "%s in the parts bin" % TextUtil.count(state.salvage, "part")
	_salvage_label.add_theme_color_override(
		"font_color", UiStyle.OCHRE if state.salvage > 0 else UiStyle.TEXT_3)

	_build_benches(state)
	_build_jobs(state)
	_build_kit(state)
	_build_blueprints(state)


## One block per facility, saying how many benches it runs and how many are
## free. Without this the answer to "why can I not start this" is buried in a
## disabled button's tooltip.
func _build_benches(state: GameState) -> void:
	for child in _benches.get_children():
		child.queue_free()

	for facility_id in [FacilityLibrary.ARMOURY, FacilityLibrary.QUARTERMASTER]:
		var facility := FacilityLibrary.get_facility(facility_id)
		var capacity := Workshop.bench_capacity(state, facility_id)
		var used := Workshop.benches_in_use(state, facility_id)
		var color := UiStyle.TEXT_3
		if capacity <= 0:
			color = UiStyle.RUST
		elif used < capacity:
			color = UiStyle.MINT
		_benches.add_child(UiStyle.stat(
			facility.display_name, "%d / %d" % [used, capacity], color, 150))


func _build_jobs(state: GameState) -> void:
	for child in _jobs_list.get_children():
		child.queue_free()

	if state.workshop.is_empty():
		_jobs_list.add_child(_note("Both benches are clear."))
		return

	for job: WorkshopJob in state.workshop:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.ROW))

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)

		var facility := FacilityLibrary.get_facility(job.facility_id)
		row.add_child(UiStyle.identity(
			job.label(),
			"%s bench" % (facility.display_name if facility != null else "Workshop")))
		row.add_child(UiStyle.stat(
			"Days left", str(job.days_remaining), UiStyle.OCHRE, 84))
		_jobs_list.add_child(card)


## Everything the company owns, worst first, with what the bench would charge to
## put it right and what the pile would pay to end it.
func _build_kit(state: GameState) -> void:
	for child in _kit_list.get_children():
		child.queue_free()

	var sorted := state.inventory.duplicate()
	sorted.sort_custom(func(a: ItemInstance, b: ItemInstance): return a.condition < b.condition)

	var shown := 0
	for instance: ItemInstance in sorted:
		if state.is_in_workshop(instance):
			continue
		_kit_list.add_child(_kit_row(instance, state))
		shown += 1

	if shown == 0:
		_kit_list.add_child(_note(
			"Nothing on the rack. Kit comes back from contracts needing work."))


func _kit_row(instance: ItemInstance, state: GameState) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.ROW))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)

	var holder := state.holder_of(instance)
	header.add_child(UiStyle.identity(
		instance.display_name(),
		"Issued to %s" % holder.display_label() if holder != null else "In storage"))
	header.add_child(UiStyle.condition_meter(instance, 96))

	var cost := Workshop.repair_cost(instance)
	var days := Workshop.repair_days(state, instance)
	var blocker := Workshop.repair_blocker(state, instance)

	var repair := Button.new()
	repair.text = "Repair" if not blocker.is_empty() else "Repair  %d · %dd" % [cost, days]
	repair.custom_minimum_size = Vector2(146, 34)
	repair.disabled = not blocker.is_empty()
	repair.tooltip_text = blocker
	repair.pressed.connect(func():
		if Game.campaign.start_repair(instance):
			company_changed.emit()
			refresh()
	)
	header.add_child(repair)

	var parts := Workshop.scrap_value(instance)
	var scrap_blocker := Workshop.scrap_blocker(state, instance)
	var scrap := UiStyle.confirm_button("Strip  %d" % parts, "Sure?", func():
		if Game.campaign.scrap_item(instance) > 0:
			company_changed.emit()
			refresh()
	, 104)
	scrap.custom_minimum_size = Vector2(104, 34)
	scrap.disabled = not scrap_blocker.is_empty()
	scrap.tooltip_text = scrap_blocker
	header.add_child(scrap)
	box.add_child(header)

	# The price of a repair in the one currency the screen cannot put in a
	# button: what the item will never be again.
	var notes: PackedStringArray = []
	if instance.is_beyond_repair():
		notes.append("Rebuilt too many times — the bench will not take it back")
	elif instance.condition < instance.max_condition:
		notes.append("Ceiling %d%%, and this repair takes %.1f more off it, permanently" % [
			int(round(instance.max_condition)), instance.ceiling_cost_of_repair()])
		# Only where there is something to answer. "Already as good as this one
		# gets" under every healthy item is noise dressed as information.
		if not blocker.is_empty():
			notes.append(blocker)

	if not notes.is_empty():
		var line := UiStyle.text("  ·  ".join(notes), UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(line)

	return card


## Plans the company holds, and a line about the ones it does not. A blueprint
## nobody has found is still worth naming — it is the reason to take the harder
## contract.
func _build_blueprints(state: GameState) -> void:
	for child in _blueprint_list.get_children():
		child.queue_free()

	var known := 0
	for item in ItemLibrary.blueprints():
		if not state.knows_blueprint(item.id):
			continue
		known += 1
		_blueprint_list.add_child(_blueprint_row(item, state))

	var unknown: int = ItemLibrary.blueprints().size() - known
	if known == 0:
		_blueprint_list.add_child(_note(
			"No plans yet. They turn up on hard contracts that come off — %s still out there."
			% TextUtil.count(unknown, "set")))
	elif unknown > 0:
		_blueprint_list.add_child(_note(
			"%s still out there, on contracts hard enough to be carrying them."
			% TextUtil.count(unknown, "other set")))


func _blueprint_row(item: ItemData, state: GameState) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.ROW))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	box.add_child(UiStyle.title(item.display_name, UiStyle.SIZE_BODY))

	# Wrapped rather than clipped: this column is pinned at 430 and a blueprint's
	# effect line is the longest in the game — "Stealth +13 · Combat +3 ·
	# Endurance -4 · Score +1 · Harm -2%" loses its last term to a clip, and the
	# last term is the one that makes it a trade rather than an upgrade.
	var effect := UiStyle.text(item.effect_text(), UiStyle.SIZE_SMALL, UiStyle.TEXT_2)
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(effect)

	var description := UiStyle.text(item.description, UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(description)

	var blocker := Workshop.craft_blocker(state, item)
	var build := Button.new()
	build.text = "Build  %d parts · %d · %dd" % [
		item.craft_salvage, item.craft_price, Workshop.craft_days(state, item)]
	build.custom_minimum_size = Vector2(0, 34)
	build.disabled = not blocker.is_empty()
	build.tooltip_text = blocker
	build.pressed.connect(func():
		if Game.campaign.start_craft(item.id):
			company_changed.emit()
			refresh()
	)
	box.add_child(build)

	if not blocker.is_empty():
		box.add_child(UiStyle.text(blocker, UiStyle.SIZE_SMALL, UiStyle.RUST))

	return card


func _note(message: String) -> Control:
	var note := UiStyle.text(message, UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return note
