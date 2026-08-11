class_name CemeteryScreen
extends VBoxContainer

## The wall. Everyone who did not come back, and what they were before they went.
##
## The design doc asks for the famous dead to keep their history — contracts,
## rank reached, who they trained. That record is the entire point: perma-death
## only lands if the game can still tell you who the person was afterwards, and
## a name with eleven contracts and two trainees behind it hurts in a way a name
## alone does not.

@onready var _list: VBoxContainer = %FallenList
@onready var _summary: Label = %Summary


func refresh() -> void:
	var state := Game.campaign.state

	for child in _list.get_children():
		child.queue_free()

	if state.cemetery.is_empty():
		_summary.text = "Nobody has been lost yet."
		_list.add_child(UiStyle.text(
			"Keep it that way.", UiStyle.SIZE_SMALL, UiStyle.TEXT_3))
		return

	var contracts := 0
	for op in state.cemetery:
		contracts += op.missions_completed
	_summary.text = "%s lost · %s completed between them" % [
		TextUtil.count(state.cemetery.size(), "operator"),
		TextUtil.count(contracts, "contract")]

	# Most recent first: the last loss is the one still on the player's mind.
	var ordered := state.cemetery.duplicate()
	ordered.reverse()
	for op in ordered:
		_list.add_child(_make_entry(op))


func _make_entry(op: OperatorData) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.ROW))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	header.add_child(UiStyle.identity(
		op.display_label(),
		"%s   ·   %s   ·   %s" % [
			GameEnums.rank_name(op.rank),
			GameEnums.role_name(op.preferred_role),
			op.demonym(),
		]))
	header.add_child(UiStyle.stat(
		"With us", str(op.missions_completed), UiStyle.TEXT_2, 82))
	if op.prior_service > 0:
		header.add_child(UiStyle.stat(
			"Before", str(op.prior_service), UiStyle.TEXT_3, 72))
	header.add_child(UiStyle.stat("Day lost", str(op.died_on_day), UiStyle.RUST, 82))
	box.add_child(header)

	var circumstances: String = "Killed on %s, in %s." % [op.died_on_mission, op.died_in_region]
	if op.died_on_mission.is_empty():
		circumstances = "Cause of death unrecorded."
	box.add_child(UiStyle.text(circumstances, UiStyle.SIZE_SMALL, UiStyle.TEXT_2))

	if not op.trained_by.is_empty():
		box.add_child(UiStyle.text(
			"Trained by %s." % op.trained_by, UiStyle.SIZE_SMALL, UiStyle.TEXT_3))

	if not op.trainees.is_empty():
		box.add_child(UiStyle.text(
			"Taught %s." % TextUtil.join_names(op.trainees), UiStyle.SIZE_SMALL, UiStyle.STEEL))

	# The dead keep their own book even after they are struck from everyone
	# else's, so the wall can still say who they were close to.
	var known: Array = Bonds.list_for(op, state_people())
	if not known.is_empty():
		var closest: Dictionary = known[0]
		var other: OperatorData = closest["other"]
		box.add_child(UiStyle.text(
			"%s %s." % [
				Bonds.describe(closest["type"], closest["strength"]),
				"with %s" % other.display_label(),
			],
			UiStyle.SIZE_SMALL,
			Bonds.color_for(closest["type"])))

	if not op.traits.is_empty():
		var trait_row := HBoxContainer.new()
		trait_row.add_theme_constant_override("separation", 12)
		for t in op.traits:
			trait_row.add_child(UiStyle.text(
				t.display_name, UiStyle.SIZE_SMALL, UiStyle.trait_color(t.polarity)))
		box.add_child(trait_row)

	return card


## Bond ids are resolved against the living and the dead alike — the person a
## fallen operator was closest to may well be lying beside them.
func state_people() -> Array:
	var everyone: Array = []
	everyone.append_array(Game.campaign.state.roster)
	everyone.append_array(Game.campaign.state.cemetery)
	return everyone
