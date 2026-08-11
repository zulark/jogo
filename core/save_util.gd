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


## The same, for a dictionary whose VALUES are fractions rather than counts.
## to_int_keys casts both sides, which is right for skills and stars and would
## silently round every banked part-point back to zero on load.
static func to_int_keys_float(source: Dictionary) -> Dictionary:
	var result := {}
	for key in source:
		result[int(str(key).to_int())] = float(source[key])
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
