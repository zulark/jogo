extends SceneTree

## Renders the main scene twice — before and after a deployment — so the whole
## sandbox can be checked without launching the game by hand.
##
##   Godot.exe --path . --script res://tests/screenshot_demo.gd
##
## Must NOT be run with --headless: the dummy renderer produces a blank image.

const SCENE_PATH := "res://ui/briefing_demo.tscn"
const OUT_DIR := "res://.screenshots"
const WINDOW_SIZE := Vector2i(1000, 760)
const WARMUP_FRAMES := 4

var _frames := 0
var _demo: BriefingDemo = null


func _process(_delta: float) -> bool:
	_frames += 1

	# Nodes added before the tree is running never get _ready(), so build here
	# rather than in _initialize().
	if _frames == 1:
		DisplayServer.window_set_size(WINDOW_SIZE)
		root.size = WINDOW_SIZE
		var scene: PackedScene = load(SCENE_PATH)
		_demo = scene.instantiate()
		root.add_child(_demo)
		return false

	if _frames == WARMUP_FRAMES:
		_capture("briefing_state")
		# Drive the button handler directly: this checks the deploy path really
		# works, not just that the panel lays out.
		_demo.deploy()
		return false

	if _frames < WARMUP_FRAMES * 2:
		return false

	_capture("outcome_state")
	return true


func _capture(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var path := "%s/%s.png" % [OUT_DIR, name]
	var image: Image = root.get_texture().get_image()
	if image.save_png(path) == OK:
		print("Saved %s" % path)
	else:
		printerr("save_png failed for %s" % path)
