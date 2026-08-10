class_name Game
extends RefCounted

## The one live Campaign, reachable from anywhere.
##
## Deliberately a static class rather than an autoload. Autoloads do not exist
## when Godot is started with `--script`, which would make every UI screen that
## touches the campaign impossible to drive from a test harness. Static members
## work identically in the editor, in a normal run, and headless.
##
## It is a holder and nothing more: all the rules live in Campaign.

static var campaign: Campaign = null


## Called by whatever comes up first. Safe to call repeatedly.
static func ensure_started(starting_operators: int = 6) -> Campaign:
	if campaign == null:
		new_company(starting_operators)
	return campaign


static func new_company(starting_operators: int = 6) -> Campaign:
	campaign = Campaign.new()
	campaign.start_new_company(starting_operators)
	return campaign


static func save_game() -> Error:
	if campaign == null:
		return ERR_UNCONFIGURED
	return SaveSystem.save(campaign.state)


static func load_game() -> bool:
	var state := SaveSystem.load_game()
	if state == null:
		return false
	campaign = Campaign.new(state)
	return true


static func has_save() -> bool:
	return SaveSystem.has_save()


## Tests need a deterministic campaign; this replaces whatever is loaded.
static func start_seeded(seed_value: int, starting_operators: int = 6) -> Campaign:
	campaign = Campaign.new(null, seed_value)
	campaign.start_new_company(starting_operators)
	return campaign
