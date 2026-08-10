class_name SaveSystem
extends RefCounted

## Save and load, as JSON under user://.
##
## It exists this early on purpose. Retrofitting saves onto a grown data model
## is one of the most painful jobs in game development; with it in place from
## v0.2, every later system just adds a field to a to_dict().

const SAVE_PATH := "user://savegame.json"


static func save(state: GameState, path: String = SAVE_PATH) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not open %s for writing: %d" % [path, FileAccess.get_open_error()])
		return FileAccess.get_open_error()

	file.store_string(JSON.stringify(state.to_dict(), "\t"))
	file.close()
	return OK


static func load_game(path: String = SAVE_PATH) -> GameState:
	if not FileAccess.file_exists(path):
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open %s for reading: %d" % [path, FileAccess.get_open_error()])
		return null

	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Save file at %s is not valid JSON" % path)
		return null

	return GameState.from_dict(parsed)


static func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


static func delete_save(path: String = SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
