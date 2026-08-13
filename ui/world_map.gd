class_name WorldMap
extends Control

## The operations map. Contracts sit where the work is.
##
## There is no art yet, so this is drawn rather than textured: a graticule, the
## regions the company works in as labelled nodes, and every contract on the
## board as a marker pinned to its region. That is deliberately an *operations*
## map rather than a picture of the world — it is the thing a company would have
## on the wall, and it survives being replaced by real art later because every
## position is normalised.
##
## Markers are real Buttons rather than hit-testing in _draw(), so hover and
## focus behave the way the rest of the UI does for free.

signal contract_clicked(mission: MissionData)

const MARKER_MIN := 20
const MARKER_MAX := 34

## Contracts in the same region are fanned around it so none is hidden.
const FAN_RADIUS := 26.0

## Place-name type: small enough to stay out of the way, large enough to read.
const LABEL_SIZE := 11
const LABEL_DROP := 17.0
const LABEL_LIFT := 10.0

var _board: Array = []
var _selected: MissionData = null
var _markers: Array = []


func _ready() -> void:
	resized.connect(_reposition)


func show_board(board: Array, selected: MissionData) -> void:
	_board = board
	_selected = selected

	for marker in _markers:
		marker.queue_free()
	_markers.clear()

	# Group by region first so the fan-out knows how many share a spot.
	var by_region := {}
	for mission in board:
		var list: Array = by_region.get(mission.region_id, [])
		list.append(mission)
		by_region[mission.region_id] = list

	for region_id in by_region:
		var missions: Array = by_region[region_id]
		for i in missions.size():
			var marker := _make_marker(missions[i], i, missions.size())
			add_child(marker)
			_markers.append(marker)

	_reposition()
	queue_redraw()


func _make_marker(mission: MissionData, index: int, total: int) -> Button:
	var size: int = MARKER_MIN
	if mission.difficulty >= 75.0:
		size = MARKER_MAX
	elif mission.difficulty >= 58.0:
		size = (MARKER_MIN + MARKER_MAX) / 2

	var button := Button.new()
	button.custom_minimum_size = Vector2(size, size)
	button.size = Vector2(size, size)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "%s\n%s · %s\nDifficulty %.0f · Risk %.0f" % [
		mission.title, mission.client_name(), mission.region_name(),
		mission.difficulty, mission.risk]

	# What the company already knows about the place, if it has been. Appended
	# rather than replacing anything: this answers "have we been here before",
	# which is a different question from "what is this job".
	if Game.campaign != null:
		var history := RegionLog.summary(Game.campaign.state, mission.region_id)
		if not history.is_empty():
			button.tooltip_text += "\n\n" + history
	button.set_meta("mission", mission)
	button.set_meta("index", index)
	button.set_meta("total", total)

	var color: Color = UiStyle.risk_color(mission.risk)
	var is_selected: bool = mission == _selected

	button.add_theme_stylebox_override("normal", _marker_style(color, size, is_selected, false))
	button.add_theme_stylebox_override("hover", _marker_style(color, size, is_selected, true))
	button.add_theme_stylebox_override("pressed", _marker_style(color, size, true, true))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	button.pressed.connect(func(): contract_clicked.emit(mission))
	return button


## A filled disc. Call-ups get a brighter ring, because a client waiting on an
## answer is the one thing on this screen with a hard deadline.
func _marker_style(color: Color, size: int, selected: bool, hovered: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color.lightened(0.15) if hovered else color
	box.set_corner_radius_all(size / 2)
	box.border_color = UiStyle.TEXT if selected else UiStyle.INK
	box.set_border_width_all(3 if selected else 2)
	return box


func _reposition() -> void:
	for marker in _markers:
		var mission: MissionData = marker.get_meta("mission")
		var index: int = marker.get_meta("index")
		var total: int = marker.get_meta("total")
		var centre := _region_point(mission.region_id)

		# Fan upward: region labels are drawn below the node, so keeping markers
		# in the top half stops them burying the place names.
		if total > 1:
			var angle: float = PI + PI * (float(index) + 0.5) / float(total)
			centre += Vector2(cos(angle), sin(angle)) * FAN_RADIUS
		else:
			centre += Vector2(0, -FAN_RADIUS * 0.55)

		marker.position = centre - marker.size * 0.5


func _region_point(region_id: StringName) -> Vector2:
	var region := RegionLibrary.get_region(region_id)
	var normalised: Vector2 = region.map_position if region != null else Vector2(0.5, 0.5)
	return Vector2(normalised.x * size.x, normalised.y * size.y)


func _draw() -> void:
	# Ground.
	draw_rect(Rect2(Vector2.ZERO, size), UiStyle.INK)

	# Graticule. Faint enough to read as paper, dense enough to feel like a chart.
	var grid := UiStyle.RULE
	grid.a = 0.5
	for i in range(1, 12):
		var x: float = size.x * float(i) / 12.0
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid, 1.0)
	for i in range(1, 8):
		var y: float = size.y * float(i) / 8.0
		draw_line(Vector2(0, y), Vector2(size.x, y), grid, 1.0)

	# The equator gets a brighter line, which is enough to orient the eye.
	var equator := UiStyle.RULE_BRIGHT
	equator.a = 0.6
	draw_line(Vector2(0, size.y * 0.5), Vector2(size.x, size.y * 0.5), equator, 1.0)

	# Every region the company can work in, whether or not it has a contract —
	# so the map is a picture of the world rather than a picture of the board.
	var font := ThemeDB.fallback_font
	var taken: Array[Rect2] = []

	# Markers are obstacles, not just neighbours: a place name reading through a
	# contract disc is the same unreadable as two names reading through each other.
	for marker in _markers:
		taken.append(Rect2(marker.position, marker.size))

	# The company's own record, if there is a company. The map is also built by
	# the editor's scene preview, where there is not.
	var state: GameState = Game.campaign.state if Game.campaign != null else null

	for region_id in RegionLibrary.ids():
		var point := _region_point(region_id)

		# Places the company has worked are drawn heavier than places it has only
		# heard of, and a place it has buried somebody in carries a ring. This is
		# the whole difference between a map and a picture of one: after twenty
		# hours the player should recognise somewhere before reading its name.
		var worked: int = RegionLog.weight(state, region_id) if state != null else 0
		var buried: int = int(RegionLog.entry(state, region_id)["dead"]) if state != null else 0

		if worked > 0:
			if buried > 0:
				draw_arc(point, 7.0, 0.0, TAU, 20, UiStyle.RUST, 1.5)
			draw_circle(point, 2.0 + float(worked), UiStyle.OCHRE)
		else:
			draw_circle(point, 3.0, UiStyle.RULE_BRIGHT)

		var label: String = RegionLibrary.region_name(region_id)
		var extent := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE)
		var spot := _label_spot(point, extent, taken)
		taken.append(Rect2(spot - Vector2(0, extent.y), extent))

		draw_string(
			font, spot, label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE,
			UiStyle.TEXT_2 if worked > 0 else UiStyle.TEXT_3)


## Where a place name can sit without landing on anything already drawn.
##
## Every label used to be pinned down-and-right of its dot, so any two regions
## close together on the map produced "Balkan Re…" running under the Kunar Valley
## marker. Tries the candidates in order of preference and takes the first that
## is clear and on-screen; if the map is genuinely crowded it falls back to the
## first, which is no worse than the old behaviour.
func _label_spot(point: Vector2, extent: Vector2, taken: Array[Rect2]) -> Vector2:
	var half: float = extent.x * 0.5
	var candidates: Array[Vector2] = [
		point + Vector2(-half, LABEL_DROP),          # centred below
		point + Vector2(9, LABEL_DROP),              # below right
		point + Vector2(-extent.x - 9, LABEL_DROP),  # below left
		point + Vector2(-half, -LABEL_LIFT),         # centred above
		point + Vector2(9, -LABEL_LIFT),             # above right
		point + Vector2(-extent.x - 9, -LABEL_LIFT), # above left
	]

	for spot in candidates:
		# draw_string takes a baseline, so the rect hangs above the given point.
		var clamped := Vector2(
			clampf(spot.x, 2.0, maxf(2.0, size.x - extent.x - 2.0)),
			clampf(spot.y, extent.y + 2.0, maxf(extent.y + 2.0, size.y - 2.0)))
		var rect := Rect2(clamped - Vector2(0, extent.y), extent)
		var clear := true
		for other in taken:
			if rect.intersects(other):
				clear = false
				break
		if clear:
			return clamped

	return candidates[0]
