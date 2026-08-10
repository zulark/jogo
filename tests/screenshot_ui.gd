extends SceneTree

## Renders a UI scene with real data and saves a PNG. This is how UI gets checked
## without a human opening the editor: build the scene, run this, look at the
## image, fix the layout, run again.
##
##   Godot.exe --path . --script res://tests/screenshot_ui.gd
##
## Must NOT be run with --headless: the dummy renderer produces a blank image.

const SCENE_PATH := "res://ui/mission_briefing.tscn"
const OUT_PATH := "res://.screenshots/mission_briefing.png"
const WINDOW_SIZE := Vector2i(880, 620)
const SEED := 20260809

## Frames to let containers settle after populating, before capturing.
const WARMUP_FRAMES := 4

var _frames := 0


func _process(_delta: float) -> bool:
	_frames += 1

	# Build on the first processed frame rather than in _initialize(): nodes added
	# before the tree is running do not get their _ready() call, so every @onready
	# reference inside the panel would still be null.
	if _frames == 1:
		_build()
		return false

	if _frames <= WARMUP_FRAMES + 1:
		return false

	_capture()
	return true


func _build() -> void:
	DisplayServer.window_set_size(WINDOW_SIZE)
	root.size = WINDOW_SIZE

	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	var scene: PackedScene = load(SCENE_PATH)
	var panel: MissionBriefingPanel = scene.instantiate()
	root.add_child(panel)
	panel.show_report(_build_sample_report(rng))


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_PATH.get_base_dir())
	var image: Image = root.get_texture().get_image()
	var error: int = image.save_png(OUT_PATH)
	if error == OK:
		print("Saved %s (%dx%d)" % [OUT_PATH, image.get_width(), image.get_height()])
	else:
		printerr("save_png failed with error %d" % error)


func _build_sample_report(rng: RandomNumberGenerator) -> MissionReport:
	var E := GameEnums
	var F := OperatorFactory

	var squad := Squad.new()
	squad.add(F.create(rng, E.Role.ASSAULT, F.Tier.VETERAN), E.Role.ASSAULT)
	squad.add(F.create(rng, E.Role.MEDIC, F.Tier.REGULAR), E.Role.MEDIC)
	squad.add(F.create(rng, E.Role.SCOUT, F.Tier.VETERAN), E.Role.SCOUT)
	squad.add(F.create(rng, E.Role.MARKSMAN, F.Tier.ROOKIE), E.Role.MARKSMAN)
	squad.set_leader(squad.members()[0])

	var mission := MissionFactory.create(rng, E.MissionType.RESCUE, MissionFactory.Grade.HARD)
	return MissionResolver.preview(squad, mission)
