class_name NationData
extends Resource

## Where an operator is from, and what that means they grew up speaking.
##
## Nationality is identity first — it makes the roster read like people from a
## real world rather than a stat table — but it pays for itself mechanically by
## deciding which naming culture they come from.

@export var id: StringName = &""
@export var display_name: String = ""

## "Brazilian", "Afghan" — what you call a person from there.
@export var demonym: String = ""

## NameLibrary culture this nation draws names from. Several nations share one.
@export var culture: StringName = &"anglo"
