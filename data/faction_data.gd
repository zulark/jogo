class_name FactionData
extends Resource

## A client. Who is paying, what they want, and what they will not tolerate.
##
## The design doc asks for contractors with preferences — "só aceita squads
## discretos" — and for standing with them to move price and availability. The
## preference is the interesting half: it means the best squad for a contract
## depends on who commissioned it, not just what the job is.

## How this client judges a squad. Each one is scored by the resolver, so the
## preference shows up as a line in the breakdown rather than a hidden rule.
enum Preference {
	NONE,          ## Takes what it can get.
	DISCREET,      ## Punishes numbers. Deniability matters more than force.
	OVERWHELMING,  ## Wants a show of force and pays for bodies.
	PROFESSIONALS, ## Judges the squad by rank. Rookies embarrass them.
	CLEAN_HANDS,   ## Tolerates no casualties — judged after the fact, not before.
}

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export var preference: Preference = Preference.NONE

## One line, shown wherever the client is named.
@export var preference_note: String = ""

## Applied to every fee this client offers.
@export var pay_multiplier: float = 1.0

## Standing gained per contract completed for them, before modifiers.
@export var standing_per_contract: int = 6


func preference_name() -> String:
	return Preference.keys()[preference].capitalize().replace("_", " ")
