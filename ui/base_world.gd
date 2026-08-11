class_name BaseWorld
extends Node3D

## The base as a place rather than a menu.
##
## Everything the player owns stands somewhere and says what is going on inside
## it — "2 recovering", "bench busy 2d", "no class". That is the whole reason
## this exists: a list of eight facilities with levels beside them is a table,
## and a table does not make a company feel like somewhere people live.
##
## **The art seam.** The scene holds a `Marker3D` per plot and nothing else.
## Drag those in the editor to rearrange the base. Drop a mesh scene named
## `Model` under a plot and it is used instead of the placeholder box — the
## collision, the label, the selection highlight and everything the panel knows
## about that plot go on working, because none of them depend on the geometry.
## Placeholder boxes exist to be thrown away.

## Selecting a plot, by its id.
signal plot_selected(id: StringName)

## What lives on a plot. `tab` is the HQ screen it opens, -1 for the ones that
## are only a place — the Psychologist has no screen of its own and pretending
## otherwise would be a button that goes nowhere.
##
## The five landmarks are not facilities. They exist so the base can be the
## whole of navigation rather than most of it: contracts leave from the pad,
## people arrive at the gate, the dead are at the memorial.
const PLOTS := {
	&"infirmary": {"footprint": Vector2(7.0, 5.0), "landmark": false},
	&"psychologist": {"footprint": Vector2(5.0, 5.0), "landmark": false},
	&"canteen": {"footprint": Vector2(6.0, 5.0), "landmark": false},
	&"academy": {"footprint": Vector2(7.0, 5.0), "landmark": false},
	&"intelligence": {"footprint": Vector2(6.0, 5.0), "landmark": false},
	&"armoury": {"footprint": Vector2(6.0, 5.0), "landmark": false},
	&"quartermaster": {"footprint": Vector2(6.0, 5.0), "landmark": false},
	&"warehouse": {"footprint": Vector2(8.0, 5.0), "landmark": false},

	&"pad": {"footprint": Vector2(11.0, 11.0), "landmark": true, "height": 0.25},
	&"barracks": {"footprint": Vector2(5.0, 14.0), "landmark": true, "height": 4.0},
	&"office": {"footprint": Vector2(5.0, 10.0), "landmark": true, "height": 4.6},
	&"memorial": {"footprint": Vector2(9.0, 2.0), "landmark": true, "height": 2.2},
	&"gate": {"footprint": Vector2(14.0, 1.6), "landmark": true, "height": 3.4},
}

## Height of a facility box at each level. A base that has been invested in
## should be visibly taller than one that has not — the skyline is the balance
## sheet.
const LEVEL_HEIGHTS := [0.35, 3.0, 4.4, 5.8]

const ORBIT_SPEED := 0.006
const PAN_SPEED := 0.055
const ZOOM_STEP := 4.0
const ZOOM_MIN := 18.0
const ZOOM_MAX := 88.0

## Never level with the ground. The horizon of a 400-unit plane is a straight
## line across the sky and there is nothing out there to look at — this is a
## base seen from above, not a place to stand in.
const PITCH_MIN := -78.0
const PITCH_MAX := -24.0
const PAN_LIMIT := 34.0

const DEFAULT_YAW := -20.0
const DEFAULT_PITCH := -46.0
const DEFAULT_DISTANCE := 68.0

@onready var _rig: Node3D = %CameraRig
@onready var _yaw: Node3D = %Yaw
@onready var _pitch: Node3D = %Pitch
@onready var _camera: Camera3D = %Camera
@onready var _plots: Node3D = %Plots
@onready var _sun: DirectionalLight3D = %Sun

var _selected: StringName = &""
var _hovered: StringName = &""

## Plot id -> { body, mesh, label, material }.
var _built: Dictionary = {}


func _ready() -> void:
	_sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	reset_view()
	refresh()


# --- Building the base -------------------------------------------------------

## Rebuilt from scratch on every refresh. Thirteen boxes is nothing to rebuild,
## and the alternative is a pile of code keeping meshes in step with a level
## that changes from four different screens.
func refresh() -> void:
	var state := Game.campaign.state
	_built.clear()

	for marker in _plots.get_children():
		var id := StringName(marker.name)
		if not PLOTS.has(id):
			continue
		for child in marker.get_children():
			if child.name != "Model":
				child.queue_free()
		_raise(marker, id, state)


func _raise(marker: Node3D, id: StringName, state: GameState) -> void:
	var spec: Dictionary = PLOTS[id]
	var landmark: bool = spec["landmark"]
	var level: int = 0 if landmark else state.facility_level(id)
	var footprint: Vector2 = spec["footprint"]
	var height: float = (
		float(spec.get("height", 3.0)) if landmark
		else LEVEL_HEIGHTS[clampi(level, 0, LEVEL_HEIGHTS.size() - 1)])

	var material := StandardMaterial3D.new()
	material.roughness = 0.85
	material.albedo_color = _plot_color(id, level, landmark)

	# A plot with real geometry under it keeps it; the box is only ever a
	# stand-in for art that does not exist yet.
	var model: Node3D = marker.get_node_or_null("Model")
	if model == null:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(footprint.x, height, footprint.y)
		mesh.mesh = box
		mesh.position = Vector3(0.0, height * 0.5, 0.0)
		mesh.material_override = material
		marker.add_child(mesh)
		model = mesh

		# A band of ochre at the base of anything built, so a level 1 hut and an
		# empty plot are not two dark boxes of slightly different heights.
		if level > 0 or landmark:
			var trim := MeshInstance3D.new()
			var trim_box := BoxMesh.new()
			trim_box.size = Vector3(footprint.x + 0.4, 0.22, footprint.y + 0.4)
			trim.mesh = trim_box
			trim.position = Vector3(0.0, 0.11, 0.0)
			var trim_material := StandardMaterial3D.new()
			trim_material.albedo_color = UiStyle.OCHRE.darkened(0.45)
			trim_material.roughness = 0.9
			trim.material_override = trim_material
			marker.add_child(trim)

	# Collision is generated regardless of what is standing there, so a plot
	# stays clickable the day its box is replaced by a model.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(footprint.x, maxf(height, 1.4), footprint.y)
	shape.shape = box_shape
	shape.position = Vector3(0.0, maxf(height, 1.4) * 0.5, 0.0)
	body.add_child(shape)
	body.set_meta("plot", String(id))
	marker.add_child(body)

	# Drawn over everything rather than behind the building in front of it: this
	# is a readout, not scenery, and a status line half-occluded by a warehouse
	# is worse than no status line.
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font = UiStyle.display()
	label.font_size = 40
	label.pixel_size = 0.028
	label.outline_size = 16
	label.outline_modulate = UiStyle.INK
	label.line_spacing = -4.0
	label.position = Vector3(0.0, height + 2.2, 0.0)
	label.no_depth_test = true
	marker.add_child(label)

	_built[id] = {"body": body, "model": model, "label": label, "material": material}
	_refresh_plot(id, state)


## The line above each plot: what it is, and what is happening in it right now.
func _refresh_plot(id: StringName, state: GameState) -> void:
	var entry: Dictionary = _built[id]
	var spec: Dictionary = PLOTS[id]
	var landmark: bool = spec["landmark"]
	var level: int = 0 if landmark else state.facility_level(id)

	var label: Label3D = entry["label"]
	label.text = "%s\n%s" % [title_of(id).to_upper(), status_of(id, state)]
	label.modulate = UiStyle.OCHRE if id == _selected else (
		UiStyle.TEXT if id == _hovered or landmark or level > 0 else UiStyle.TEXT_3)

	var material: StandardMaterial3D = entry["material"]
	material.albedo_color = _plot_color(id, level, landmark)
	if id == _selected:
		material.emission_enabled = true
		material.emission = UiStyle.OCHRE
		material.emission_energy_multiplier = 0.4
	elif id == _hovered:
		material.emission_enabled = true
		material.emission = UiStyle.TEXT
		material.emission_energy_multiplier = 0.12
	else:
		material.emission_enabled = false


func _plot_color(id: StringName, level: int, landmark: bool) -> Color:
	if landmark:
		return UiStyle.PANEL.lightened(0.10)
	if level <= 0:
		# An empty plot reads as ground rather than as a building, so the base
		# visibly has room left in it.
		return UiStyle.INK.lightened(0.06)
	return UiStyle.ROW.lightened(0.04 + 0.07 * float(level))


# --- What each plot is -------------------------------------------------------

static func is_facility(id: StringName) -> bool:
	return PLOTS.has(id) and not bool(PLOTS[id]["landmark"])


static func title_of(id: StringName) -> String:
	if is_facility(id):
		var facility := FacilityLibrary.get_facility(id)
		return facility.display_name if facility != null else String(id)
	match id:
		&"pad": return "Landing Pad"
		&"barracks": return "Barracks"
		&"office": return "Front Office"
		&"memorial": return "Memorial"
		&"gate": return "Gate"
		_: return String(id)


## One line, always true, always about right now. This is the difference between
## a model of a base and a base.
##
## Written out rather than run through TextUtil.count wherever the noun does not
## simply take an s. "2 recoverings", "2 burieds" and "0 of 2 benchs busy" were
## all in the first version of this, and every one of them is the sort of thing
## that is invisible in code and the only thing you see on screen.
static func status_of(id: StringName, state: GameState) -> String:
	match id:
		&"infirmary":
			if state.facility_level(id) <= 0:
				return "not built"
			var hurt := state.injured_headcount()
			return "empty" if hurt == 0 else "%d recovering" % hurt
		&"psychologist":
			if state.facility_level(id) <= 0:
				return "not built"
			var scarred := 0
			for op in state.roster:
				for t in op.traits:
					if t != null and t.polarity == GameEnums.TraitPolarity.NEGATIVE:
						scarred += 1
						break
			return "nobody marked" if scarred == 0 else "%d marked" % scarred
		&"canteen":
			if state.facility_level(id) <= 0:
				return "not built"
			return "morale %d" % _average_morale(state)
		&"academy":
			if state.facility_level(id) <= 0:
				return "not built"
			return "no class" if state.training.is_empty() else TextUtil.count(
				state.training.size(), "class running", "classes running")
		&"intelligence":
			if state.facility_level(id) <= 0:
				return "not built"
			return "nothing out" if state.intel_ops.is_empty() else TextUtil.count(
				state.intel_ops.size(), "team out", "teams out")
		&"armoury", &"quartermaster":
			var level := state.facility_level(id)
			if level <= 0:
				return "not built"
			var busy := Workshop.benches_in_use(state, id)
			return "%d of %d %s busy" % [
				busy, level, TextUtil.noun(level, "bench", "benches")]
		&"warehouse":
			return "%d of %d stored" % [state.storage_used(), state.storage_capacity()]
		&"pad":
			var out := state.detachments.size()
			for deployment in state.deployments:
				out += deployment.squad.size()
			if out > 0:
				return "%d in the field" % out
			return TextUtil.count(state.board.size(), "contract offered", "contracts offered")
		&"barracks":
			return "%d ready · %d resting" % [
				state.deployable_operators().size(), state.injured_headcount()]
		&"office":
			return "%s on retainer" % TextUtil.count(state.retainers.size(), "client")
		&"memorial":
			return "nobody yet" if state.cemetery.is_empty() else "%d buried" % (
				state.cemetery.size())
		&"gate":
			# Both forms spelled out: count() pluralises the last word, and "5
			# recruit waitings" is the sort of thing nobody notices in code and
			# everybody notices on screen.
			return TextUtil.count(
				state.recruits.size(), "recruit waiting", "recruits waiting")
	return ""


static func _average_morale(state: GameState) -> int:
	if state.roster.is_empty():
		return 0
	var total := 0
	for op in state.roster:
		total += op.morale
	return total / state.roster.size()


# --- Selection ---------------------------------------------------------------

func select(id: StringName) -> void:
	if _selected == id:
		return
	_selected = id
	_repaint()
	plot_selected.emit(id)


func selected() -> StringName:
	return _selected


func _repaint() -> void:
	var state := Game.campaign.state
	for id in _built:
		_refresh_plot(id, state)


## What the cursor is over, or "" for the ground. Raycast rather than physics
## picking so the container keeps every event and the camera controls and the
## selection never fight over one drag.
func plot_at(point: Vector2) -> StringName:
	var space := get_world_3d().direct_space_state
	var from := _camera.project_ray_origin(point)
	var query := PhysicsRayQueryParameters3D.create(
		from, from + _camera.project_ray_normal(point) * 400.0)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return &""
	var collider: Object = hit.get("collider")
	if collider == null or not collider.has_meta("plot"):
		return &""
	return StringName(str(collider.get_meta("plot")))


func hover(id: StringName) -> void:
	if _hovered == id:
		return
	_hovered = id
	_repaint()


# --- Camera ------------------------------------------------------------------

func orbit(delta: Vector2) -> void:
	_yaw.rotation.y -= delta.x * ORBIT_SPEED
	_pitch.rotation_degrees.x = clampf(
		_pitch.rotation_degrees.x - delta.y * rad_to_deg(ORBIT_SPEED), PITCH_MIN, PITCH_MAX)


## Panning follows the ground rather than the screen, so dragging left moves the
## base left however the camera happens to be turned.
func pan(delta: Vector2) -> void:
	var scale: float = PAN_SPEED * (_camera.position.z / 40.0)
	var right := _yaw.global_transform.basis.x
	var forward := -_yaw.global_transform.basis.z
	var moved := _rig.position - right * delta.x * scale - forward * delta.y * scale
	_rig.position = Vector3(
		clampf(moved.x, -PAN_LIMIT, PAN_LIMIT), 0.0,
		clampf(moved.z, -PAN_LIMIT, PAN_LIMIT))


func zoom(steps: float) -> void:
	_camera.position.z = clampf(_camera.position.z + steps * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)


## Bring a plot to the middle of the view. Used when the panel selects something
## the player cannot currently see.
func focus(id: StringName) -> void:
	var marker: Node3D = _plots.get_node_or_null(String(id))
	if marker == null:
		return
	var to := marker.position
	_rig.position = Vector3(
		clampf(to.x, -PAN_LIMIT, PAN_LIMIT), 0.0, clampf(to.z, -PAN_LIMIT, PAN_LIMIT))


func reset_view() -> void:
	_rig.position = Vector3.ZERO
	_yaw.rotation_degrees = Vector3(0.0, DEFAULT_YAW, 0.0)
	_pitch.rotation_degrees = Vector3(DEFAULT_PITCH, 0.0, 0.0)
	_camera.position = Vector3(0.0, 0.0, DEFAULT_DISTANCE)
