class_name BaseHub
extends HBoxContainer

## The base you walk around, and the panel for whatever you are standing in
## front of.
##
## This replaces the old Base screen, which was eight rows in a list. The rows
## were fine and told you nothing: a company that has poured nine thousand
## diamonds into an Academy should be able to *see* it, and a base with an empty
## plot where the Infirmary should be should look like one.
##
## Navigation lives here too. Five of the thirteen plots are not facilities at
## all — the pad, the gate, the barracks, the front office, the memorial — and
## they exist so the base is the whole of the company rather than most of it.
## Clicking one opens the screen it belongs to.

signal company_changed()

## Ask the shell to change tabs. The hub does not own navigation; it asks.
signal open_tab_requested(tab: int)

## And to open one of the dock panels over whatever is showing.
signal open_drawer_requested(key: String)

const WORLD_SCENE := preload("res://ui/base_world.tscn")

## Which screen a plot belongs to, by hq.gd Tab index. Mirrored by name rather
## than by number in _ready — the harness learned this lesson in v0.8, when a
## hand-copied enum drifted and a screenshot named "cemetery" was of Clients.
const PLOT_TABS := {
	&"academy": "TRAINING",
	&"intelligence": "INTEL",
	&"armoury": "MARKET",
	&"quartermaster": "WORKSHOP",
	&"canteen": "BONDS",
	&"pad": "CONTRACTS",
	&"barracks": "ROSTER",
	&"office": "CLIENTS",
	&"memorial": "CEMETERY",
	&"gate": "RECRUITS",
}

## And the two that open a dock panel rather than a tab.
const PLOT_DRAWERS := {
	&"infirmary": "infirmary",
	&"warehouse": "stock",
}

## Pixels of movement before a press counts as a drag rather than a click. A
## selection that fires at the end of a camera swing is maddening.
const DRAG_SLOP := 5.0

@onready var _viewport_container: SubViewportContainer = %ViewportContainer
@onready var _viewport: SubViewport = %WorldViewport
@onready var _panel_title: Label = %PanelTitle
@onready var _panel_list: VBoxContainer = %PanelList
@onready var _hint: Label = %Hint

var _world: BaseWorld = null
var _dragging := false
var _panning := false
var _drag_distance := 0.0


func _ready() -> void:
	_world = WORLD_SCENE.instantiate()
	_viewport.add_child(_world)
	_world.plot_selected.connect(func(_id: StringName): _rebuild_panel())

	_viewport_container.gui_input.connect(_on_view_input)
	_panel_title.add_theme_font_override("font", UiStyle.display())
	_hint.text = "Drag to turn · right-drag to move · wheel to zoom · click a building"


func refresh() -> void:
	if _world != null:
		_world.refresh()
	_rebuild_panel()


# --- Driving the view --------------------------------------------------------
#
# All of it here rather than through the viewport's own physics picking, so a
# camera drag and a selection can never both claim the same press.

func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_world.zoom(-1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_world.zoom(1.0)
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_dragging = true
					_drag_distance = 0.0
				else:
					if _dragging and _drag_distance < DRAG_SLOP:
						_world.select(_world.plot_at(event.position))
					_dragging = false
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
		return

	if event is InputEventMouseMotion:
		if _dragging:
			_drag_distance += event.relative.length()
			_world.orbit(event.relative)
		elif _panning:
			_world.pan(event.relative)
		else:
			_world.hover(_world.plot_at(event.position))


# --- The panel ---------------------------------------------------------------

func _rebuild_panel() -> void:
	for child in _panel_list.get_children():
		child.queue_free()

	var id: StringName = _world.selected() if _world != null else &""
	if id == &"":
		_build_company_panel()
		return

	_panel_title.text = BaseWorld.title_of(id).to_upper()
	if BaseWorld.is_facility(id):
		_build_facility_panel(id)
	else:
		_build_landmark_panel(id)


## Nothing selected: the books. The old Base screen put the weekly bill beside
## the facility list because every upgrade adds a line to it, and that pairing is
## worth keeping — the cost of expanding should never be on another screen.
func _build_company_panel() -> void:
	var state := Game.campaign.state
	_panel_title.text = "THE COMPANY"

	var bill := Economy.weekly_costs(state)
	for line in bill["lines"]:
		_panel_list.add_child(_ledger_row(
			line["caption"], line["detail"], str(line["amount"]), UiStyle.TEXT_2))

	var income := Economy.weekly_income(state)
	for line in income["lines"]:
		_panel_list.add_child(_ledger_row(
			line["caption"], line["detail"], "-%d" % int(line["amount"]), UiStyle.MINT))

	_panel_list.add_child(UiStyle.spacer(4))
	_panel_list.add_child(UiStyle.rule())
	_panel_list.add_child(UiStyle.spacer(4))

	var net := Economy.net_weekly(state)
	_panel_list.add_child(_ledger_row(
		"Net weekly" if int(income["total"]) > 0 else "Weekly total", "",
		str(net), UiStyle.MINT if net <= 0 else UiStyle.OCHRE))

	var weeks := Economy.weeks_of_runway(state)
	var runway := UiStyle.text(
		"In debt. Wages went unpaid and everyone knows it." if weeks < 0
		else "%s of runway at this burn rate." % TextUtil.count(weeks, "week"),
		UiStyle.SIZE_SMALL,
		UiStyle.RUST if weeks <= 2 else (UiStyle.OCHRE if weeks <= 5 else UiStyle.TEXT_2))
	runway.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel_list.add_child(runway)

	# A list of what is standing out there, so the eight upgrade costs can still
	# be compared at a glance without walking the base building by building.
	_panel_list.add_child(UiStyle.spacer(10))
	_panel_list.add_child(UiStyle.eyebrow("THE BASE"))
	for id in FacilityLibrary.ORDER:
		_panel_list.add_child(_facility_summary_row(id))


func _facility_summary_row(id: StringName) -> Control:
	var state := Game.campaign.state
	var facility := FacilityLibrary.get_facility(id)
	var level := state.facility_level(id)
	var cost := facility.cost_to_upgrade(level)

	var button := UiStyle.row_button(false)
	button.custom_minimum_size.y = 34
	# Selecting from the list turns the camera to it. Otherwise the list and the
	# base are two views of one thing that never agree with each other.
	button.pressed.connect(func():
		_world.select(id)
		_world.focus(id)
	)

	var row := UiStyle.row_content(button)
	var name_label := UiStyle.text(facility.display_name, UiStyle.SIZE_SMALL,
		UiStyle.TEXT if level > 0 else UiStyle.TEXT_3)
	name_label.clip_text = true
	UiStyle.grow(name_label)
	row.add_child(name_label)
	row.add_child(UiStyle.data(
		"L%d" % level if level > 0 else "—", UiStyle.SIZE_SMALL,
		UiStyle.MINT if facility.is_maxed(level) else UiStyle.TEXT_2))
	row.add_child(UiStyle.data(
		"%d" % cost if cost > 0 else "max", UiStyle.SIZE_CAPTION,
		UiStyle.TEXT_3 if cost > state.diamonds else UiStyle.OCHRE))
	return button


func _build_facility_panel(id: StringName) -> void:
	var state := Game.campaign.state
	var facility := FacilityLibrary.get_facility(id)
	var level := state.facility_level(id)
	var maxed := facility.is_maxed(level)
	var cost := facility.cost_to_upgrade(level)
	var affordable := cost > 0 and cost <= state.diamonds

	_panel_list.add_child(UiStyle.text(
		"Level %d of %d" % [level, facility.max_level] if level > 0 else "Not built yet",
		UiStyle.SIZE_BODY,
		UiStyle.TEXT if level > 0 else UiStyle.TEXT_3))

	# What is happening in there right now, in the same words the label above the
	# building uses. Two places, one sentence, so they cannot disagree.
	_panel_list.add_child(UiStyle.text(
		BaseWorld.status_of(id, state), UiStyle.SIZE_SMALL, UiStyle.STEEL))

	var description := UiStyle.text(facility.description, UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel_list.add_child(description)
	_panel_list.add_child(UiStyle.spacer(6))

	var figures := HBoxContainer.new()
	figures.add_theme_constant_override("separation", 10)
	if not maxed:
		figures.add_child(UiStyle.stat(
			facility.effect_caption, facility.effect_text(level + 1), UiStyle.OCHRE, 150))
	figures.add_child(UiStyle.stat(
		"Upkeep", "%d/wk" % facility.upkeep_at(level), UiStyle.TEXT_2, 92))
	_panel_list.add_child(figures)

	if maxed:
		_panel_list.add_child(UiStyle.text("Fully upgraded.", UiStyle.SIZE_SMALL, UiStyle.MINT))
	else:
		var button := Button.new()
		button.text = "%s · %d diamonds" % ["Build" if level == 0 else "Upgrade", cost]
		button.custom_minimum_size = Vector2(0, 38)
		button.disabled = not affordable
		button.pressed.connect(func():
			if Game.campaign.upgrade_facility(id):
				company_changed.emit()
				refresh()
		)
		_panel_list.add_child(button)
		if not affordable:
			_panel_list.add_child(UiStyle.text(
				"%d short." % (cost - state.diamonds), UiStyle.SIZE_SMALL, UiStyle.RUST))

	_add_open_button(id, level > 0)


func _build_landmark_panel(id: StringName) -> void:
	var state := Game.campaign.state
	_panel_list.add_child(UiStyle.text(
		BaseWorld.status_of(id, state), UiStyle.SIZE_BODY, UiStyle.STEEL))

	var description := UiStyle.text(_landmark_text(id), UiStyle.SIZE_SMALL, UiStyle.TEXT_3)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel_list.add_child(description)
	_panel_list.add_child(UiStyle.spacer(6))
	_add_open_button(id, true)


## A button only where there is somewhere to go. The Psychologist has no screen
## of its own, and a greyed-out "Open" under it would be a promise the game does
## not keep.
func _add_open_button(id: StringName, enabled: bool) -> void:
	var label := ""
	var action: Callable

	if PLOT_TABS.has(id):
		var tab: int = _tab_index(String(PLOT_TABS[id]))
		if tab < 0:
			return
		label = "Go in"
		action = func(): open_tab_requested.emit(tab)
	elif PLOT_DRAWERS.has(id):
		label = "Go in"
		action = func(): open_drawer_requested.emit(String(PLOT_DRAWERS[id]))
	else:
		return

	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 36)
	button.disabled = not enabled
	button.pressed.connect(action)
	_panel_list.add_child(button)
	if not enabled:
		_panel_list.add_child(UiStyle.text(
			"Nothing to go into until it is built.", UiStyle.SIZE_SMALL, UiStyle.TEXT_3))


## Read off hq.gd's real enum by name rather than mirroring the numbers. A
## hand-copied tab index drifted once already and pointed a screenshot at the
## wrong screen for a whole version.
##
## Found by walking up to whichever ancestor actually declares a `Tab` enum,
## rather than by node name: the shell is this screen's parent by construction,
## and a lookup that depends on it still being called "HQ" is the same
## brittleness in a different place.
func _tab_index(key: String) -> int:
	var node: Node = get_parent()
	while node != null:
		var script: Script = node.get_script()
		if script != null:
			var tabs: Dictionary = script.get_script_constant_map().get("Tab", {})
			if tabs.has(key):
				return int(tabs[key])
		node = node.get_parent()
	return -1


func _landmark_text(id: StringName) -> String:
	match id:
		&"pad":
			return "Everything leaves from here and most of it comes back. The board is worked from the pad."
		&"barracks":
			return "Where the company sleeps, argues and waits for the next one. Service records are kept here."
		&"office":
			return "Invoices, riders and the people who sign them. Standing with each client is tracked out of this room."
		&"memorial":
			return "Rank reached, contracts run, who they trained and where they died. Nobody is removed from it."
		&"gate":
			return "People turn up looking for work. Sign them this week or they move on."
	return ""


func _ledger_row(caption: String, detail: String, amount: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var caption_label := UiStyle.text(caption, UiStyle.SIZE_SMALL, UiStyle.TEXT)
	caption_label.clip_text = true
	UiStyle.grow(caption_label)
	row.add_child(caption_label)

	if not detail.is_empty():
		var detail_label := UiStyle.text(detail, UiStyle.SIZE_CAPTION, UiStyle.TEXT_3)
		detail_label.custom_minimum_size.x = 118
		detail_label.clip_text = true
		detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(detail_label)

	var amount_label := UiStyle.data(amount, UiStyle.SIZE_SMALL, color)
	amount_label.custom_minimum_size.x = 72
	amount_label.clip_text = true
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(amount_label)
	return row
