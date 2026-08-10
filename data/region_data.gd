class_name RegionData
extends Resource

## Where a contract happens, and what that costs you.
##
## What makes somewhere a *place*
## is that it changes who you send: mountains reward endurance, cities reward
## stealth, and a fortnight's travel means the squad is gone for a fortnight
## whether the job takes an hour or a week.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

## Shifted onto every contract generated here, before grades are applied.
@export var difficulty_shift: float = 0.0
@export var risk_shift: float = 0.0

## The skill the ground itself tests. Squads strong in it do better here and
## weak ones do worse, so a region is a reason to send different people.
@export var emphasis_skill: GameEnums.Skill = GameEnums.Skill.ENDURANCE

## Shown in the breakdown, e.g. "Mountainous — endurance decides who keeps up".
@export var emphasis_note: String = ""

## Where this sits on the operations map, in 0-1 screen space. Roughly true to
## real geography, which is enough for the player to build a mental picture of
## where the company works.
@export var map_position: Vector2 = Vector2(0.5, 0.5)

## What the ground does to people who are not equipped for it. Unlike the
## emphasis skill, which asks "are these the right people", a hazard asks "did
## you spend money on the right kit" — and can be bought off entirely.
@export var hazard: GameEnums.Hazard = GameEnums.Hazard.NONE

## Added to every contract's duration. Far places tie a squad up longer than the
## work alone would suggest.
@export var travel_days: int = 0
