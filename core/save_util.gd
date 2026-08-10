class_name SaveUtil
extends RefCounted

## JSON has string keys and only doubles for numbers, so every dictionary keyed
## by an enum or a StringName comes back wrong after a round trip. These put the
## keys back the way the game expects them.

static func to_int_keys(source: Dictionary) -> Dictionary:
	var result := {}
	for key in source:
		result[int(str(key).to_int())] = int(source[key])
	return result


static func to_name_keys(source: Dictionary) -> Dictionary:
	var result := {}
	for key in source:
		result[StringName(str(key))] = int(source[key])
	return result


## Godot's JSON writes every number as a float. Anything that must stay an int
## after loading goes through here.
static func as_int(value: Variant, fallback: int = 0) -> int:
	if value == null:
		return fallback
	return int(value)
