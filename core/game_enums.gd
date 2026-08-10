class_name GameEnums
extends RefCounted

## Central enum registry. Every system refers to these instead of magic strings,
## so renaming a role or mission type is a one-line change.


## Operator competences. Values are stored 0-100 on OperatorData.
enum Skill {
	COMBAT,     ## Direct engagement, weapon handling.
	STEALTH,    ## Moving unseen, silent takedowns.
	MEDICAL,    ## Field treatment, keeps wounded alive.
	TECH,       ## Hacking, demolition, electronics.
	LEADERSHIP, ## Holding the squad together under pressure.
	ENDURANCE,  ## Physical resilience, reduces harm taken.
}

## Slots an operator can occupy inside a squad. LEADER is a flag on Squad,
## not a role: the leader also fills one of the roles below.
enum Role {
	ASSAULT,
	MARKSMAN,
	MEDIC,
	SCOUT,
	ENGINEER,
}

enum MissionType {
	ASSAULT,      ## Loud, direct. Rewards numbers and firepower.
	INFILTRATION, ## Punishes large squads, demands stealth.
	RESCUE,       ## Requires a medic, extraction under fire.
	RECON,        ## Small, quiet, information gathering.
	SABOTAGE,     ## Demands tech, moderate stealth.
	ESCORT,       ## Protect an asset, sustained pressure.
	ASSASSINATION,## One named person. Someone comes home with a story.
}

## What the ground itself does to people, independent of who is shooting.
## Countered by carrying the right kit — see ItemData.counters_hazard.
enum Hazard {
	NONE,
	INFECTION,   ## Wet heat. Wounds go bad.
	HEAT,        ## Open desert. Attrition by exhaustion.
	COLD,        ## Snow and exposure.
	ALTITUDE,    ## Thin air on long approaches.
}

## Personality axes, stored 0-100 with 50 as neutral.
## Mission profiles express a preferred value per axis; distance from it costs.
enum PersonalityAxis {
	AGGRESSION,  ## 0 = cautious, 100 = reckless.
	DISCIPLINE,  ## 0 = improviser, 100 = by the book.
	BRAVERY,     ## 0 = fearful, 100 = fearless.
	SOCIABILITY, ## 0 = loner, 100 = team player.
}

## Promotion ladder. Index order matters: rank bonus scales with it.
##
## The first six are the field track and it stops at Warrant Officer. From there
## an operator either keeps working contracts at that ceiling, or gives up the
## field for good and becomes an instructor — the four ranks above are earned
## only by teaching. That fork is a real cost: your best veteran either keeps
## fighting or stops forever to make everyone else better.
enum Rank {
	PRIVATE,
	CORPORAL,
	SERGEANT_THIRD,
	SERGEANT_SECOND,
	SERGEANT_FIRST,
	WARRANT_OFFICER,
	LIEUTENANT,
	CAPTAIN,
	MAJOR,
	COLONEL,
}

## Field careers cap here. Going further means leaving the field.
const FIELD_RANK_CAP := Rank.WARRANT_OFFICER

enum CareerTrack {
	FIELD,
	INSTRUCTOR,
}

enum OperatorStatus {
	AVAILABLE,
	ON_MISSION,
	INJURED,
	TRAINING,
	DEAD,
	## Away casing a contract. Appended rather than inserted: these are written
	## to save files as plain integers, so the existing order cannot move.
	ON_INTEL,
}

## What happened to a single operator on a mission.
enum Fate {
	UNHARMED,
	WOUNDED,      ## Unavailable for a number of days.
	TRAUMATIZED,  ## Unavailable, and picks up a negative trait (v0.3).
	KILLED,       ## Permanent.
}

## What two operators are to each other. Formed by surviving contracts together
## and by how their temperaments rub. Romance is deliberately rare — a roster
## full of couples stops being a mercenary company.
enum BondType {
	FRIENDSHIP,
	RIVALRY,
	ROMANCE,
}

enum TraitPolarity {
	POSITIVE,
	NEGATIVE,
	NEUTRAL,
}

## Category tags for the modifiers shown in the mission breakdown UI,
## so the tooltip can group and colour them.
enum ModifierSource {
	SKILL,
	ROLE_FIT,
	PERSONALITY,
	TRAIT,
	LEADERSHIP,
	SQUAD_SIZE,
	COMPOSITION,
	MISSION_DIFFICULTY,
	CONDITION,
	BOND,
}


static func skill_name(skill: int) -> String:
	return Skill.keys()[skill].capitalize()


static func role_name(role: int) -> String:
	return Role.keys()[role].capitalize()


## Placeholder role icons. Glyphs rather than textures so there is nothing to
## import and nothing to license — swap ROLE_GLYPHS for a texture lookup when
## there is art and every caller stays the same.
const ROLE_GLYPHS := {
	Role.ASSAULT: "⚔",
	Role.MARKSMAN: "➤",
	Role.MEDIC: "✚",
	Role.SCOUT: "◎",
	Role.ENGINEER: "⚙",
}

## Each role also gets a colour, so the icon carries identity at a glance even
## where the label is too small to read.
const ROLE_COLOURS := {
	Role.ASSAULT: "e0656f",
	Role.MARKSMAN: "cf9d3f",
	Role.MEDIC: "74c98d",
	Role.SCOUT: "7fa8c9",
	Role.ENGINEER: "b48ad8",
}


static func role_glyph(role: int) -> String:
	return str(ROLE_GLYPHS.get(role, "•"))


static func role_color(role: int) -> Color:
	return Color(str(ROLE_COLOURS.get(role, "a8b0a8")))


static func mission_type_name(mission_type: int) -> String:
	return MissionType.keys()[mission_type].capitalize()


static func rank_name(rank: int) -> String:
	return Rank.keys()[rank].capitalize().replace("_", " ")


## Insignia. Chevrons climb the field track, diamonds climb the instructor
## track, and the Warrant Officer pip sits between them — so the career fork is
## legible at a glance without reading a word.
const RANK_GLYPHS := {
	Rank.PRIVATE: "·",
	Rank.CORPORAL: "▴",
	Rank.SERGEANT_THIRD: "▴▴",
	Rank.SERGEANT_SECOND: "▴▴▴",
	Rank.SERGEANT_FIRST: "▴▴▴▴",
	Rank.WARRANT_OFFICER: "◈",
	Rank.LIEUTENANT: "◆",
	Rank.CAPTAIN: "◆◆",
	Rank.MAJOR: "◆◆◆",
	Rank.COLONEL: "◆◆◆◆",
}


static func rank_glyph(rank: int) -> String:
	return str(RANK_GLYPHS.get(rank, "·"))


## Enlisted ranks are quiet, the Warrant Officer pip is ochre because that is
## where the player has a decision to make, and the instructor track is steel.
static func rank_color(rank: int) -> Color:
	if rank >= Rank.LIEUTENANT:
		return Color("7fa8c9")
	if rank == Rank.WARRANT_OFFICER:
		return Color("cf9d3f")
	return Color("a8b0a8")


static func axis_name(axis: int) -> String:
	return PersonalityAxis.keys()[axis].capitalize()


static func track_name(track: int) -> String:
	return CareerTrack.keys()[track].capitalize()


static func bond_name(bond: int) -> String:
	return BondType.keys()[bond].capitalize()


static func hazard_name(hazard: int) -> String:
	return Hazard.keys()[hazard].capitalize()
