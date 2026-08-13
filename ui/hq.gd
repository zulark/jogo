extends Control

## The shell. Header with the numbers that matter, a tab per screen, and the
## End Day button that drives the whole calendar.
##
## It owns navigation and nothing else: screens do their own work and report back
## through signals, and only Campaign is allowed to change the game.

enum Tab {
	ROSTER, CONTRACTS, RECRUITS, TRAINING, INTEL,
	BASE, MARKET, WORKSHOP, CLIENTS, BONDS, CEMETERY,
}

const ROSTER_SCENE := preload("res://ui/roster_screen.tscn")
const CONTRACTS_SCENE := preload("res://ui/contracts_screen.tscn")
const RECRUITS_SCENE := preload("res://ui/recruits_screen.tscn")
const TRAINING_SCENE := preload("res://ui/training_screen.tscn")
const INTEL_SCENE := preload("res://ui/intel_screen.tscn")
const BASE_SCENE := preload("res://ui/base_hub.tscn")
const MARKET_SCENE := preload("res://ui/market_screen.tscn")
const WORKSHOP_SCENE := preload("res://ui/workshop_screen.tscn")
const CLIENTS_SCENE := preload("res://ui/clients_screen.tscn")
const BONDS_SCENE := preload("res://ui/relationships_screen.tscn")
const STOCK_SCENE := preload("res://ui/inventory_screen.tscn")
const INFIRMARY_SCENE := preload("res://ui/infirmary_screen.tscn")
const CEMETERY_SCENE := preload("res://ui/cemetery_screen.tscn")
const SQUAD_BUILDER_SCENE := preload("res://ui/squad_builder.tscn")

@onready var _content: MarginContainer = %Content
@onready var _day_label: Label = %DayLabel
@onready var _diamonds_label: Label = %DiamondsLabel
@onready var _payroll_label: Label = %PayrollLabel
@onready var _field_label: Label = %FieldLabel
@onready var _after_action: AfterAction = %AfterAction
@onready var _incident_modal: IncidentModal = %IncidentModal
@onready var _status_row: HBoxContainer = %StatusRow
@onready var _drawer: PanelContainer = %Drawer
@onready var _drawer_title: Label = %DrawerTitle
@onready var _drawer_close: Button = %DrawerClose
@onready var _drawer_content: MarginContainer = %DrawerContent

## Which drawer is open, by key, or "" for none. Drawers are panels you consult
## WITHOUT leaving the screen you are on — checking stock halfway through
## building a squad should not cost you the squad.
var _open_drawer := ""
@onready var _end_day_button: Button = %EndDayButton
@onready var _system_button: MenuButton = %SystemButton
@onready var _tab_row: HBoxContainer = %TabRow
@onready var _tab_buttons := {
	Tab.ROSTER: %RosterTab as Button,
	Tab.CONTRACTS: %ContractsTab as Button,
	Tab.RECRUITS: %RecruitsTab as Button,
	Tab.TRAINING: %TrainingTab as Button,
	Tab.INTEL: %IntelTab as Button,
	Tab.BASE: %BaseTab as Button,
	Tab.MARKET: %MarketTab as Button,
	Tab.WORKSHOP: %WorkshopTab as Button,
	Tab.CLIENTS: %ClientsTab as Button,
	Tab.BONDS: %BondsTab as Button,
	Tab.CEMETERY: %CemeteryTab as Button,
}

## Screens run edge to edge. The base is going to be a drawn place behind this
## UI rather than a grey field, and a centred column floating in the middle of a
## painted hangar reads as a website laid over a game.
##
## The cost is real and worth stating: a row spanning a very wide window forces
## the eye from a title on the far left to its figures on the far right. The
## answer is not a narrower page but panels that hold a fixed width and wrap
## their text, which is what SIDE_PANEL_WIDTH and autowrap are for.
## A gutter, not a column. Zero left buttons flush against the window frame and
## the footer's actions touching the right edge; this is the smallest value that
## keeps the page full-bleed without anything sitting on the frame.
const CONTENT_PADDING := 16

## The window may not be squeezed below this. Godot will happily let a window
## shrink until containers overlap; a floor means a layout that fits once fits
## always, which is the whole point of fixed panel widths.
const MIN_WINDOW_SIZE := Vector2i(1180, 760)

var _current_tab: int = Tab.CONTRACTS
var _screen: Control = null

## Filled by the campaign signal while a day is being ended, then handed to the
## after-action modal in one batch.
var _pending_reports: Array[MissionReport] = []

## The week's news, collected the same way and shown after the squads.
var _pending_events: Array = []

## Incidents raised during the day, shown once the squads have been dealt with.
## A queue rather than a single slot: nothing stops two arriving if the cooldown
## is ever loosened, and dropping one silently would be worse than showing both.
var _pending_incidents: Array = []


func _ready() -> void:
	Game.ensure_started()
	Game.campaign.mission_resolved.connect(_on_mission_resolved)
	Game.campaign.week_events.connect(_on_week_events)
	Game.campaign.incident_raised.connect(_on_incident_raised)
	_after_action.closed.connect(_on_after_action_closed)
	_incident_modal.closed.connect(_on_incident_closed)
	for tab in _tab_buttons:
		_tab_buttons[tab].pressed.connect(_show_tab.bind(tab))
	# Pivot at the centre so the pulse grows both ways rather than to the right.
	_day_label.pivot_offset = Vector2(60, 12)
	_drawer.add_theme_stylebox_override(
		"panel", UiStyle.panel(UiStyle.PANEL, UiStyle.RULE_BRIGHT, 6))
	_drawer_close.pressed.connect(_close_drawer)
	_drawer_title.add_theme_font_override("font", UiStyle.display())
	# A floor rather than a fixed size: the window can grow as far as the player
	# likes, and every panel inside holds its width instead of stretching.
	DisplayServer.window_set_min_size(MIN_WINDOW_SIZE)
	_build_system_menu()
	_apply_typography()
	_apply_content_width()
	_refresh_status_bar()
	resized.connect(_apply_content_width)
	_show_tab(_current_tab)


## Save and load, off the top bar.
##
## They sat beside End Day as two of the five things on the header, which made
## the company's operational status share a line with the game engine's
## controls. Saving is not something a mercenary company does; ending a day is.
## Behind a menu they are still one click away and no longer compete with the
## figures the player is meant to be reading.
func _build_system_menu() -> void:
	var popup := _system_button.get_popup()
	popup.clear()
	popup.add_item("Save game", 0)
	popup.add_item("Load game", 1)
	popup.id_pressed.connect(func(id: int):
		if id == 0:
			_on_save_pressed()
		else:
			_on_load_pressed()
	)


func _apply_typography() -> void:
	_day_label.add_theme_font_override("font", UiStyle.display())
	_day_label.add_theme_font_size_override("font_size", UiStyle.SIZE_TITLE)
	_day_label.add_theme_color_override("font_color", UiStyle.TEXT)

	_payroll_label.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL)
	_payroll_label.add_theme_color_override("font_color", UiStyle.TEXT_3)

	_diamonds_label.add_theme_font_override("font", UiStyle.mono())
	_diamonds_label.add_theme_font_size_override("font_size", UiStyle.SIZE_TITLE)

	_field_label.add_theme_font_size_override("font_size", UiStyle.SIZE_BODY)
	_field_label.add_theme_color_override("font_color", UiStyle.STEEL)

	for tab in _tab_buttons:
		var button: Button = _tab_buttons[tab]
		button.add_theme_font_override("font", UiStyle.display())
		button.add_theme_font_size_override("font_size", UiStyle.SIZE_BODY)
		button.add_theme_color_override("font_pressed_color", UiStyle.OCHRE)
		button.add_theme_color_override("font_color", UiStyle.TEXT_3)
		button.add_theme_color_override("font_hover_color", UiStyle.TEXT)

	# The group captions. Eleven tabs of equal weight told the player nothing
	# about what kind of thing each one was; three named groups answer "where do
	# I manage operations, people, the company" before anything is clicked.
	for group in _tab_row.get_children():
		for child in group.get_children():
			if child is Label:
				child.add_theme_font_override("font", UiStyle.display())
				child.add_theme_color_override("font_color", UiStyle.TEXT_3)

	_system_button.add_theme_font_size_override("font_size", UiStyle.SIZE_TITLE)
	_system_button.add_theme_color_override("font_color", UiStyle.TEXT_3)
	_system_button.add_theme_color_override("font_hover_color", UiStyle.TEXT)


func _apply_content_width() -> void:
	_content.add_theme_constant_override("margin_left", CONTENT_PADDING)
	_content.add_theme_constant_override("margin_right", CONTENT_PADDING)


# --- Navigation --------------------------------------------------------------

func _show_tab(tab: int) -> void:
	_current_tab = tab
	for key in _tab_buttons:
		_tab_buttons[key].button_pressed = key == tab

	match tab:
		Tab.ROSTER:
			_swap_screen(ROSTER_SCENE.instantiate())
		Tab.CONTRACTS:
			var screen := CONTRACTS_SCENE.instantiate() as ContractsScreen
			screen.assemble_requested.connect(_open_squad_builder)
			_swap_screen(screen)
		Tab.RECRUITS:
			var screen := RECRUITS_SCENE.instantiate() as RecruitsScreen
			screen.roster_changed.connect(_on_company_changed)
			_swap_screen(screen)
		Tab.TRAINING:
			var screen := TRAINING_SCENE.instantiate() as TrainingScreen
			screen.roster_changed.connect(_on_company_changed)
			_swap_screen(screen)
		Tab.INTEL:
			var screen := INTEL_SCENE.instantiate() as IntelScreen
			screen.roster_changed.connect(_on_company_changed)
			_swap_screen(screen)
		Tab.BASE:
			var screen := BASE_SCENE.instantiate() as BaseHub
			screen.company_changed.connect(_on_company_changed)
			# The hub is where navigation lives now: thirteen places, and the
			# five that are not facilities exist so the base covers the whole
			# company rather than most of it. It asks; the shell moves.
			screen.open_tab_requested.connect(_show_tab)
			screen.open_drawer_requested.connect(_open_dock_panel)
			_swap_screen(screen)
		Tab.MARKET:
			var screen := MARKET_SCENE.instantiate() as MarketScreen
			screen.company_changed.connect(_on_company_changed)
			_swap_screen(screen)
		Tab.WORKSHOP:
			var screen := WORKSHOP_SCENE.instantiate() as WorkshopScreen
			screen.company_changed.connect(_on_company_changed)
			_swap_screen(screen)
		Tab.CLIENTS:
			var screen := CLIENTS_SCENE.instantiate() as ClientsScreen
			screen.company_changed.connect(_on_company_changed)
			_swap_screen(screen)
		Tab.BONDS:
			_swap_screen(BONDS_SCENE.instantiate())
		Tab.CEMETERY:
			_swap_screen(CEMETERY_SCENE.instantiate())


func _open_squad_builder(mission: MissionData) -> void:
	var builder := SQUAD_BUILDER_SCENE.instantiate() as SquadBuilder
	builder.deployed.connect(func(_deployment):
		_show_tab(Tab.CONTRACTS)
		_refresh_header()
	)
	builder.cancelled.connect(func(): _show_tab(Tab.CONTRACTS))
	_swap_screen(builder)
	builder.setup(mission)

	# The tabs stay unlit while building: this is a place you came FROM the
	# board, not a fourth destination.
	for key in _tab_buttons:
		_tab_buttons[key].button_pressed = false


func _swap_screen(screen: Control) -> void:
	for child in _content.get_children():
		child.queue_free()
	_screen = screen
	_content.add_child(screen)
	if screen.has_method("refresh"):
		screen.refresh()
	_refresh_header()

	# The dock too, not just the header. Anything that changed the company since
	# the last day end — kit bought, a facility built — left the dock quoting the
	# old figure, so the Market read "Storage 2 / 14" beside a dock still saying
	# "Inventory 0/6". Same number, on screen twice, disagreeing.
	_refresh_status_bar()


## A screen changed something the shell also displays.
##
## These used to refresh only the header, so buying kit in the Market left the
## dock reading "Inventory 0/6" while the Market itself said "Storage 2 / 14" —
## the same number, on screen twice, disagreeing. The dock is part of the shell,
## so it has to be told too.
func _on_company_changed() -> void:
	_refresh_header()
	_refresh_status_bar()


func _refresh_all() -> void:
	if _screen != null and _screen.has_method("refresh"):
		_screen.refresh()
	_refresh_header()
	_refresh_status_bar()


## Opens a panel over the current screen. The tab underneath does not change, so
## whatever was half-built there is still half-built when the drawer closes.
func _toggle_drawer(key: String, title: String, scene: PackedScene) -> void:
	if _open_drawer == key:
		_close_drawer()
		return

	for child in _drawer_content.get_children():
		child.queue_free()

	var panel := scene.instantiate()
	_drawer_content.add_child(panel)
	if panel.has_signal("company_changed"):
		panel.connect("company_changed", _on_drawer_changed)
	if panel.has_method("refresh"):
		panel.refresh()

	_open_drawer = key
	_drawer_title.text = title.to_upper()
	_drawer.show()
	_refresh_status_bar()


## Open a dock panel by key from somewhere that is not the dock — the hub's
## Infirmary and Warehouse both lead into one. Kept in terms of the same keys the
## dock buttons use so there is one name per panel.
func _open_dock_panel(key: String) -> void:
	match key:
		"stock":
			if _open_drawer != "stock":
				_toggle_drawer("stock", "Inventory", STOCK_SCENE)
		"infirmary":
			if _open_drawer != "infirmary":
				_toggle_drawer("infirmary", "Infirmary", INFIRMARY_SCENE)


func _close_drawer() -> void:
	_open_drawer = ""
	_drawer.hide()
	for child in _drawer_content.get_children():
		child.queue_free()
	_refresh_status_bar()


## A drawer that changed something (selling kit, say) has to push that back to
## the screen underneath, which may well be showing the same data.
func _on_drawer_changed() -> void:
	_refresh_header()
	_refresh_status_bar()
	if _screen != null and _screen.has_method("refresh"):
		_screen.refresh()


## The dock: panels openable from anywhere, then the numbers worth noticing.
## These used to be scattered one per screen — storage only in the Market, spare
## kit only in Stock — so spotting a problem meant already being on the right
## screen.
func _refresh_status_bar() -> void:
	for child in _status_row.get_children():
		child.queue_free()

	var state := Game.campaign.state

	var ready_count := state.deployable_operators().size()
	var injured := state.injured_headcount()
	var in_field := state.detachments.size()
	for deployment in state.deployments:
		in_field += deployment.squad.size()

	var spare := state.spare_instances().size()
	var broken := state.unserviceable_spares()

	var expiring := 0
	for mission in state.board:
		if mission.expires_in_days <= 2:
			expiring += 1

	# Panels first: these open OVER whatever screen is showing.
	_status_row.add_child(_dock_button(
		"stock", "Inventory", "%d/%d" % [state.storage_used(), state.storage_capacity()],
		UiStyle.RUST if not state.has_storage_room() else UiStyle.TEXT_2,
		STOCK_SCENE))
	_status_row.add_child(_dock_button(
		"infirmary", "Infirmary", str(injured),
		UiStyle.RUST if injured > 0 else UiStyle.TEXT_3,
		INFIRMARY_SCENE))

	# Then the glanceable numbers, which are readouts rather than buttons.
	_status_row.add_child(_status_readout(
		"READY", str(ready_count), UiStyle.MINT if ready_count > 0 else UiStyle.RUST))
	_status_row.add_child(_status_readout(
		"IN FIELD", str(in_field), UiStyle.STEEL if in_field > 0 else UiStyle.TEXT_3))
	# Rust when some of that spare kit is past working: the count alone would
	# read as good news on the day half the armoury stopped being issuable.
	_status_row.add_child(_status_readout(
		"SPARE KIT", "%d" % spare if broken == 0 else "%d · %d dead" % [spare, broken],
		UiStyle.RUST if broken > 0 else (UiStyle.MINT if spare > 0 else UiStyle.TEXT_3)))
	_status_row.add_child(_status_readout(
		"EXPIRING", str(expiring), UiStyle.RUST if expiring > 0 else UiStyle.TEXT_3))
	_status_row.add_child(_status_readout(
		"RECRUITS", str(state.recruits.size()), UiStyle.TEXT_2))

	var filler := Control.new()
	UiStyle.grow(filler)
	_status_row.add_child(filler)

	var runway := Economy.weeks_of_runway(state)
	_status_row.add_child(_status_readout(
		"RUNWAY", "debt" if runway < 0 else "%dw" % runway,
		UiStyle.RUST if runway <= 2 else UiStyle.TEXT_2))


## A dock button: opens its panel over the current screen, and carries the one
## number that says whether it is worth opening.
func _dock_button(
	key: String,
	label: String,
	value: String,
	color: Color,
	scene: PackedScene
) -> Button:
	var open: bool = _open_drawer == key
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(56 + label.length() * 9 + value.length() * 9, 34)
	button.tooltip_text = "%s %s" % ["Close" if open else "Open", label]
	button.add_theme_stylebox_override(
		"normal", UiStyle.panel(UiStyle.ROW_ACTIVE if open else UiStyle.ROW,
			UiStyle.OCHRE if open else UiStyle.RULE, 3))
	button.add_theme_stylebox_override(
		"hover", UiStyle.panel(UiStyle.ROW_HOVER, UiStyle.RULE_BRIGHT, 3))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(func(): _toggle_drawer(key, label, scene))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -10

	var name_label := UiStyle.text(
		label, UiStyle.SIZE_SMALL, UiStyle.OCHRE if open else UiStyle.TEXT)
	name_label.add_theme_font_override("font", UiStyle.display())
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiStyle.grow(name_label)
	row.add_child(name_label)

	var value_label := UiStyle.data(value, UiStyle.SIZE_SMALL, color)
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value_label)

	button.add_child(row)
	return button


## A glanceable figure. Not a button — these are things to notice, not act on.
func _status_readout(caption: String, value: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var caption_label := UiStyle.text(caption, UiStyle.SIZE_CAPTION, UiStyle.TEXT_3)
	caption_label.add_theme_font_override("font", UiStyle.display())
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(caption_label)

	var value_label := UiStyle.data(value, UiStyle.SIZE_SMALL, color)
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value_label)

	var pad := Control.new()
	pad.custom_minimum_size.x = 12
	row.add_child(pad)
	return row


# --- Header ------------------------------------------------------------------

func _refresh_header() -> void:
	var state := Game.campaign.state
	_day_label.text = "Day %d   ·   Week %d, day %d" % [
		state.day, state.week(), state.day_of_week()]
	_diamonds_label.text = "%d diamonds" % state.diamonds
	_diamonds_label.add_theme_color_override(
		"font_color", UiStyle.RUST if state.diamonds < 0 else UiStyle.TEXT)

	# The weekly total, not just wages — the number that actually leaves the
	# account. Reputation sits beside it because it is the other slow dial.
	_payroll_label.text = "%d/wk running costs · %s on the books · reputation %d" % [
		Economy.weekly_total(state),
		TextUtil.count(state.living_roster_size(), "operator"),
		state.reputation,
	]

	var in_field := state.detachments.size()
	for deployment in state.deployments:
		in_field += deployment.squad.size()
	_field_label.text = "%s in the field" % TextUtil.number_capitalised(in_field)
	_field_label.visible = in_field > 0


# --- Time --------------------------------------------------------------------

## Ending the day is the one button pressed dozens of times a session, and it
## used to give nothing back — the header numbers changed silently and it was
## easy to wonder whether the press registered. A brief pulse on the day counter
## is enough to confirm the world moved.
func _flash_day() -> void:
	var tween := create_tween()
	_day_label.modulate = UiStyle.OCHRE
	_day_label.scale = Vector2(1.06, 1.06)
	tween.tween_property(_day_label, "modulate", Color.WHITE, 0.35)
	tween.parallel().tween_property(_day_label, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_end_day_pressed() -> void:
	_pending_reports.clear()
	_pending_events.clear()
	_pending_incidents.clear()
	Game.campaign.end_day()
	_flash_day()

	_refresh_all()
	_advance_queue()


func _on_after_action_closed() -> void:
	_refresh_all()
	_advance_queue()


## Everything the day produced, one card at a time and in that order: squads that
## came home first, then the week's news, then the decisions still waiting for an
## answer. A death should never be stacked behind a modal about worn kit.
##
## Re-entered after every close rather than run once, because a decision can
## itself end a contract — calling one off over the radio produces a debrief
## that has to be read before whatever was queued behind it.
func _advance_queue() -> void:
	if not _pending_reports.is_empty() or not _pending_events.is_empty():
		var reports := _pending_reports.duplicate()
		var events := _pending_events.duplicate()
		_pending_reports.clear()
		_pending_events.clear()
		_refresh_status_bar()
		_after_action.show_reports(reports, events)
		return

	if not _pending_incidents.is_empty():
		_incident_modal.show_incident(_pending_incidents.pop_front())


func _on_incident_raised(incident: Dictionary) -> void:
	_pending_incidents.append(incident)


func _on_incident_closed() -> void:
	_refresh_all()
	_advance_queue()


func _on_mission_resolved(report: MissionReport) -> void:
	_pending_reports.append(report)


func _on_week_events(lines: Array) -> void:
	_pending_events.append_array(lines)


func _on_save_pressed() -> void:
	Game.save_game()


func _on_load_pressed() -> void:
	if Game.load_game():
		Game.campaign.mission_resolved.connect(_on_mission_resolved)
		Game.campaign.week_events.connect(_on_week_events)
		Game.campaign.incident_raised.connect(_on_incident_raised)
		_show_tab(_current_tab)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_SPACE and not _after_action.visible 				and not _incident_modal.visible:
			_on_end_day_pressed()
