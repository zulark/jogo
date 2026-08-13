class_name UiStyle
extends RefCounted

## The visual system. One palette, one type scale, one set of builders.
##
## DIRECTION — the company's paperwork.
## This screen is a back office: service records, contract riders, after-action
## reports. So the interface is built like a form rather than a dashboard.
## Numbers are set in a monospace face and right-aligned into fixed columns, so
## a stat block reads the same way on every screen and figures line up down the
## page. Headings use a condensed face, the way a stencilled label would.
##
## The palette is an olive-shifted charcoal rather than the usual blue-black —
## the colour of a field desk, not a spaceship. Ochre carries structure and
## attention (it is the folder tab, the stencil, the selected row's edge), and
## the semantic colours are reserved strictly for outcomes: mint came home, rust
## did not.
##
## FONTS come from the operating system rather than shipped assets, so there is
## nothing to import and nothing to license. If a face is missing the list falls
## through to Godot's default. Swap `_MONO_NAMES` / `_DISPLAY_NAMES` for a real
## font file when the game gets an art pass.


# --- Colour ------------------------------------------------------------------

const INK := Color("0e100f")            ## Page.
const PANEL := Color("171a18")          ## Panels sitting on the page.
const ROW := Color("1e2320")            ## List rows.
const ROW_HOVER := Color("272d29")
const ROW_ACTIVE := Color("2c332d")

const RULE := Color("333a35")           ## Hairlines and quiet borders.
const RULE_BRIGHT := Color("4a534c")

const TEXT := Color("eef0ec")           ## Primary.
const TEXT_2 := Color("a8b0a8")         ## Secondary — fine down to 12px.
const TEXT_3 := Color("858e86")         ## Tertiary — never below 12px.

const OCHRE := Color("cf9d3f")          ## Structure, attention, selection.
const MINT := Color("74c98d")           ## Good outcome.
const RUST := Color("e0656f")           ## Bad outcome.
const STEEL := Color("7fa8c9")          ## The leader, and things in the field.


# --- Type --------------------------------------------------------------------
# One step per role. Nothing in the UI should invent a size outside this list.

const SIZE_DISPLAY := 30
const SIZE_TITLE := 21
const SIZE_HEADING := 17
const SIZE_BODY := 15
const SIZE_SMALL := 13
const SIZE_CAPTION := 12

const _MONO_NAMES := [
	"Consolas", "JetBrains Mono", "DejaVu Sans Mono", "Menlo", "Courier New", "monospace",
]
const _DISPLAY_NAMES := [
	"Bahnschrift", "Roboto Condensed", "Arial Narrow", "Oswald", "Segoe UI", "sans-serif",
]

static var _mono: Font = null
static var _display: Font = null


## Figures, codes, currency — anything that wants to line up in a column.
static func mono() -> Font:
	if _mono == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(_MONO_NAMES)
		_mono = font
	return _mono


## Screen titles and section labels.
static func display() -> Font:
	if _display == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(_DISPLAY_NAMES)
		font.font_weight = 600
		_display = font
	return _display


# --- Builders ----------------------------------------------------------------

static func text(content: String, size: int = SIZE_BODY, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = content
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node


## Monospace. Use for every number the player compares against another number.
static func data(content: String, size: int = SIZE_BODY, color: Color = TEXT) -> Label:
	var node := text(content, size, color)
	node.add_theme_font_override("font", mono())
	return node


static func title(content: String, size: int = SIZE_TITLE, color: Color = TEXT) -> Label:
	var node := text(content, size, color)
	node.add_theme_font_override("font", display())
	return node


## The small ochre label above a block. Says what kind of thing follows.
static func eyebrow(content: String) -> Label:
	var node := title(content.to_upper(), SIZE_CAPTION, OCHRE)
	return node


## A precise hairline. HSeparator's thickness is theme-dependent; this is not.
static func rule(color: Color = RULE, height: int = 1) -> ColorRect:
	var line := ColorRect.new()
	line.color = color
	line.custom_minimum_size.y = height
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return line


static func grow(node: Control) -> Control:
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func spacer(height: int) -> Control:
	var node := Control.new()
	node.custom_minimum_size.y = height
	return node


## THE SIGNATURE BLOCK.
## A caption over a monospace figure, right-aligned in a fixed column. Contracts,
## the roster and the briefing all use it, so the eye learns one shape and reads
## every screen with it. Fixed width is what makes columns line up down a list.
## A fixed-width figure with its caption above it.
##
## The width given here is a CONTRACT, not a suggestion. Both labels clip, which
## drops their minimum width to zero and leaves the box's own minimum as the only
## thing setting the size. Without that a long value quietly widened the column
## and took the difference out of whatever shared the row — a "FATIGUE 71%"
## caption in a 52-pixel column was enough to clip an operator's name, so rows
## changed shape depending on how tired somebody was.
static func stat(caption: String, value: String, color: Color = TEXT, width: int = 74) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size.x = width

	var caption_label := text(caption.to_upper(), SIZE_CAPTION, TEXT_3)
	caption_label.add_theme_font_override("font", display())
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption_label.clip_text = true
	box.add_child(caption_label)

	var value_label := data(value, SIZE_HEADING, color)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.clip_text = true
	value_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(value_label)

	return box


static func panel(bg: Color = PANEL, border: Color = RULE, radius: int = 4) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box


## Selection is structural, not coloured text: the row keeps its type colours and
## grows an ochre edge, the way a tab sticks out of a folder.
static func _row_style(bg: Color, selected: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(3)
	if selected:
		box.border_color = OCHRE
		box.border_width_left = 3
	else:
		box.border_color = RULE
		box.border_width_left = 1
		box.border_width_top = 1
		box.border_width_right = 1
		box.border_width_bottom = 1
	return box


static func row_button(selected: bool = false) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.button_pressed = selected
	button.focus_mode = Control.FOCUS_NONE

	button.add_theme_stylebox_override("normal", _row_style(ROW_ACTIVE if selected else ROW, selected))
	button.add_theme_stylebox_override("hover", _row_style(ROW_HOVER, selected))
	button.add_theme_stylebox_override("pressed", _row_style(ROW_ACTIVE, true))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button


## A Button's minimum size ignores its children, so row content is anchored and
## the row height must be set explicitly. Anything shorter than the content
## silently overlaps the row beneath it — use these, do not invent a height.
## The width below which a name stops being a name. Identity blocks clip, so
## their own minimum is zero; this is the floor that keeps a row from handing
## every spare pixel to the stat columns beside it.
const IDENTITY_MIN_WIDTH := 136

const ROW_HEIGHT := 66
const ROW_HEIGHT_COMPACT := 58


## Row content lives in a child HBox so a row can hold columns.
## Inset from the edge, or the right-hand column sits on the border.
static func row_content(button: Button) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_right = -16
	box.offset_top = 6
	box.offset_bottom = -6
	button.add_child(box)
	return box


## Two lines of identity: who they are, and the details you scan past.
static func identity(primary: String, secondary: String, primary_color: Color = TEXT) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size.x = IDENTITY_MIN_WIDTH

	# Clipped, so a long name can never widen the row past its column and push
	# the stat block off the edge. Truncation beats a broken layout.
	var primary_label := text(primary, SIZE_HEADING, primary_color)
	primary_label.clip_text = true
	primary_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(primary_label)

	var secondary_label := text(secondary, SIZE_SMALL, TEXT_3)
	secondary_label.clip_text = true
	secondary_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(secondary_label)

	grow(box)
	return box


## Buttons whose meaning is a state rather than an action — "this one is the
## leader". Godot's default toggle styling is too quiet to read at a glance.
static func state_button(content: String, active: bool, width: int = 62) -> Button:
	var button := Button.new()
	button.text = content
	button.toggle_mode = true
	button.button_pressed = active
	button.custom_minimum_size = Vector2(width, 34)
	var color: Color = OCHRE if active else TEXT_3
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_pressed_color", color)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_font_size_override("font_size", SIZE_SMALL)
	return button


# --- Semantic colour ---------------------------------------------------------

## Placeholder portrait: initials on a colour derived from the operator's id, so
## it is stable across sessions and the eye learns it like a face. Swap the
## contents for a TextureRect when there is art; every caller stays the same.
static func portrait(op: OperatorData, size: int = 42) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(size, size)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var box := StyleBoxFlat.new()
	box.bg_color = op.portrait_color()
	box.border_color = RULE_BRIGHT
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	frame.add_theme_stylebox_override("panel", box)

	var label := text(op.initials(), maxi(11, size / 3), TEXT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(label)
	return frame


## A slim bar. Used for fatigue in list rows, where a number would be one more
## thing to read and a bar is understood without reading.
static func meter_bar(value: int, color: Color, width: int = 70) -> Control:
	var bar := ProgressBar.new()
	bar.max_value = 100
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, 8)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var track := StyleBoxFlat.new()
	track.bg_color = INK
	track.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


## Fatigue reads backwards from every other meter: a full bar is bad. Ochre at
## rest, rust once they genuinely need standing down.
static func fatigue_meter(op: OperatorData, width: int = 70) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size.x = width

	# The caption fits the width it was given rather than the other way round.
	# "FATIGUE 100%" needs about 72 pixels; below that the word goes and the
	# number stays, because the number is the part being read.
	var caption := text(
		("FATIGUE %d%%" % op.fatigue) if width >= 72 else ("%d%%" % op.fatigue),
		SIZE_CAPTION,
		RUST if op.fatigue >= Balance.FATIGUE_WARNING else TEXT_3)
	caption.add_theme_font_override("font", display())
	caption.clip_text = true
	box.add_child(caption)
	box.add_child(meter_bar(
		op.fatigue,
		RUST if op.fatigue >= Balance.FATIGUE_WARNING else OCHRE,
		width))
	return box


## Kit condition reads forwards: a full bar is good, and it goes rust at the
## point the item stops working rather than at some softer warning line, because
## unserviceable is a state with consequences and "a bit worn" is not.
static func condition_color(instance: ItemInstance) -> Color:
	if instance == null:
		return TEXT_3
	if not instance.is_serviceable():
		return RUST
	if instance.condition < 45.0:
		return OCHRE
	return MINT


## The same block the fatigue meter is, for the other number that decides what a
## squad is worth. Clipped, so a declared width is a promise — see v0.8.
static func condition_meter(instance: ItemInstance, width: int = 88) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size.x = width

	var color := condition_color(instance)
	var caption := text(
		instance.condition_text() if width >= 128 else ("%d%%" % int(round(instance.condition))),
		SIZE_CAPTION,
		color)
	caption.add_theme_font_override("font", display())
	caption.clip_text = true
	box.add_child(caption)
	box.add_child(meter_bar(int(round(instance.condition)), color, width))
	return box


## "Combat 74 · Stealth 61 · Endurance 55" — what they are actually good at,
## short enough for a list row.
static func skill_summary(op: OperatorData, count: int = 3, size: int = SIZE_SMALL) -> Label:
	var parts: PackedStringArray = []
	for entry in op.top_skills(count):
		parts.append("%s %d" % [
			GameEnums.skill_name(entry["skill"]), int(entry["value"])])

	# Clipped, for the reason every other label in an identity block is: this one
	# sits inside `operator_identity`, whose own minimum width is a floor rather
	# than a size, and an unclipped child overrides it. Three skill names is
	# comfortably the widest line in the block, so it was setting the width of the
	# whole row and pushing the columns to its right off the edge of the list.
	var label := text("   ".join(parts), size, TEXT_2)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


## "★★☆☆☆" — mastery at a glance, next to the skill name.
static func star_text(stars: int) -> String:
	if stars <= 0:
		return ""
	return "%s%s" % ["★".repeat(stars), "☆".repeat(Balance.MAX_SKILL_STARS - stars)]


## A name with the callsign picked out. Callsigns are what the company actually
## calls people, so they should not read as part of the legal name — colouring
## them is the cheapest way to make a roster scannable by nickname.
static func operator_name(
	op: OperatorData,
	size: int = SIZE_HEADING,
	name_color: Color = TEXT
) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# EXPAND_FILL matters: clip_text sets the minimum width to zero, so without
	# it the given name collapses to nothing and only the callsign survives.
	var given := text(op.operator_name, size, name_color)
	given.clip_text = true
	given.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	given.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(given)

	# And the callsign must keep its own width, or the same collapse moves to it.
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if not op.callsign.is_empty():
		box.add_child(text('"%s"' % op.callsign, size, OCHRE))

	return box


## Two lines of identity: the legal name, then how the company refers to them.
##
## The callsign sits on the SECOND line rather than beside the name. Side by side
## the two compete for one row, and in a narrow list the name always lost —
## "Jonas Rein... \"Ivo" was the failure mode, with both halves mangled at once.
## Splitting them means the name gets the full column width and never truncates,
## and the callsign still leads its line in ochre, so scanning by nickname works
## exactly as before.
static func operator_identity(
	op: OperatorData,
	secondary: String,
	name_color: Color = TEXT
) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var given := text(op.operator_name, SIZE_HEADING, name_color)
	given.clip_text = true
	given.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(given)

	# A floor, not a fixed size. Clipping drops a label's minimum width to zero,
	# which is what stops a long name widening its row — but it also means the
	# identity block will happily shrink to nothing when it shares a row with
	# anything greedy. This is the width below which a name stops being a name.
	box.custom_minimum_size.x = IDENTITY_MIN_WIDTH

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 7)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if not op.callsign.is_empty():
		line.add_child(text('"%s"' % op.callsign, SIZE_SMALL, OCHRE))

	var below := text(secondary, SIZE_SMALL, TEXT_3)
	below.clip_text = true
	below.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	below.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(below)
	box.add_child(line)

	grow(box)
	return box


# --- Bonds -------------------------------------------------------------------

## Every link between this operator and a given group, strongest first.
##
## The group is normally the squad being assembled, which makes this the answer
## to "what happens if I put this person in with these people" — the question
## the squad builder exists to ask and could not previously answer at all.
static func bonds_with(op: OperatorData, others: Array) -> Array:
	var found: Array = []
	for other in others:
		if other == op or not Bonds.has_bond(op, other):
			continue
		found.append({
			"other": other,
			"type": Bonds.bond_type(op, other),
			"strength": Bonds.strength(op, other),
		})
	found.sort_custom(func(a, b): return a["strength"] > b["strength"])
	return found


## The strongest tie this operator has to a group, as a fixed-width list column.
##
## Shaped like `stat()` and `fatigue_meter()` rather than as an extra line of
## text, for the reason those exist: a row's height is fixed, and anything that
## grows a row grows it into the one beneath. A column can be empty without
## changing anything around it, which matters here because most operators have
## no history with most squads.
##
## Rivalries outrank friendships when both are present. A friend in the squad is
## worth knowing about; somebody they cannot work with is worth stopping for.
static func bond_column(op: OperatorData, others: Array, width: int = 104) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.custom_minimum_size.x = width

	var links := bonds_with(op, others)
	if links.is_empty():
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return box

	var pick: Dictionary = links[0]
	for link in links:
		if link["type"] == GameEnums.BondType.RIVALRY:
			pick = link
			break

	var caption := text(
		"WITH SQUAD" if links.size() == 1 else "WITH SQUAD (%d)" % links.size(),
		SIZE_CAPTION, TEXT_3)
	caption.add_theme_font_override("font", display())
	caption.clip_text = true
	box.add_child(caption)

	var other: OperatorData = pick["other"]
	var value := text(
		"%s · %s" % [Bonds.short_word(pick["type"]), other.short_label()],
		SIZE_SMALL,
		Bonds.color_for(pick["type"]))
	value.clip_text = true
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(value)

	# The cause lives in the tooltip rather than the row. It is a whole sentence
	# — "They got each other out alive on Salt the Wells" — and the row has no
	# width for it, but it is the part that makes the link a story instead of a
	# modifier, so it must be reachable from where the decision is made.
	var lines: PackedStringArray = []
	for link in links:
		var reason: String = Bonds.reason_for(op, link["other"])
		lines.append("%s · %s%s" % [
			Bonds.describe(link["type"], link["strength"]),
			link["other"].display_label(),
			("\n    " + reason) if not reason.is_empty() else ""])
	box.tooltip_text = "\n".join(lines)
	return box


## Every link inside one group, each listed once, with what caused it.
##
## This is the squad builder's story surface. The column above answers "should I
## add them"; this answers "who are these people to each other", which is the
## question the player is meant to start asking somewhere around week six.
static func bond_ties(members: Array) -> Array:
	var seen := {}
	var ties: Array = []
	for a in members:
		for b in members:
			if a == b or not Bonds.has_bond(a, b):
				continue
			var key: String = "%s|%s" % ([a.id, b.id] if str(a.id) < str(b.id) else [b.id, a.id])
			if seen.has(key):
				continue
			seen[key] = true
			ties.append({
				"a": a,
				"b": b,
				"type": Bonds.bond_type(a, b),
				"strength": Bonds.strength(a, b),
				"reason": Bonds.reason_for(a, b),
			})
	ties.sort_custom(func(x, y): return x["strength"] > y["strength"])
	return ties


## Rank insignia, sized to sit inline with a name.
static func rank_icon(rank: int, size: int = SIZE_SMALL) -> Label:
	var node := text(GameEnums.rank_glyph(rank), size, GameEnums.rank_color(rank))
	node.tooltip_text = GameEnums.rank_name(rank)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## Insignia plus the rank's name, for anywhere a rank is being reported.
static func rank_tag(rank: int, size: int = SIZE_CAPTION) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rank_icon(rank, size + 1))
	box.add_child(text(GameEnums.rank_name(rank), size, GameEnums.rank_color(rank)))
	return box


## A role icon: the glyph in the role's colour, sized to sit beside a portrait.
static func role_icon(role: int, size: int = SIZE_HEADING) -> Label:
	var node := text(GameEnums.role_glyph(role), size, GameEnums.role_color(role))
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.custom_minimum_size.x = size + 6
	node.tooltip_text = GameEnums.role_name(role)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## Icon plus name, for anywhere a role is being reported rather than chosen.
static func role_tag(role: int, size: int = SIZE_CAPTION) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(role_icon(role, size + 2))
	box.add_child(text(GameEnums.role_name(role), size, GameEnums.role_color(role)))
	return box


## Seconds an armed confirm button waits before disarming itself.
const CONFIRM_TIMEOUT := 4.0


## A button that commits only on the second press.
##
## Deploying a squad, selling kit, dismissing someone and dropping a retainer are
## all one click away from happening and none of them can be undone. Arming the
## button first turns a misclick into a harmless one, and the armed label says
## plainly what the next click will do.
##
## It disarms itself after CONFIRM_TIMEOUT, because a button left sitting in its
## armed state is a trap for whatever the player clicks next.
## Gives an existing Button the two-press behaviour. Use this for buttons that
## come from a .tscn; confirm_button() below is the same thing for code-built rows.
static func make_confirming(
	button: Button,
	label: String,
	armed_label: String,
	on_confirm: Callable
) -> Button:
	button.text = label
	button.set_meta("armed", false)

	var disarm := func():
		if not is_instance_valid(button):
			return
		button.set_meta("armed", false)
		button.text = label
		button.remove_theme_color_override("font_color")

	button.pressed.connect(func():
		if bool(button.get_meta("armed")):
			disarm.call()
			on_confirm.call()
			return

		button.set_meta("armed", true)
		button.text = armed_label
		button.add_theme_color_override("font_color", RUST)

		var timer := button.get_tree().create_timer(CONFIRM_TIMEOUT)
		timer.timeout.connect(func():
			if is_instance_valid(button) and bool(button.get_meta("armed")):
				disarm.call()
		)
	)
	return button


static func confirm_button(
	label: String,
	armed_label: String,
	on_confirm: Callable,
	width: int = 180
) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(width, 42)
	return make_confirming(button, label, armed_label, on_confirm)


## A filled chip. For the one or two facts on a panel that should be read before
## anything else — what kind of job this is, and what it pays.
static func pill(content: String, color: Color, size: int = SIZE_SMALL) -> PanelContainer:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.16)
	style.border_color = color
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	box.add_theme_stylebox_override("panel", style)
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var label := title(content.to_upper(), size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	return box


## Every mission type gets its own colour, so the board is scannable by the kind
## of work on offer rather than by reading each title.
static func mission_type_color(mission_type: int) -> Color:
	match mission_type:
		GameEnums.MissionType.ASSAULT:
			return RUST
		GameEnums.MissionType.INFILTRATION:
			return STEEL
		GameEnums.MissionType.RESCUE:
			return MINT
		GameEnums.MissionType.RECON:
			return Color(0.537, 0.694, 0.741)
		GameEnums.MissionType.SABOTAGE:
			return OCHRE
		GameEnums.MissionType.ESCORT:
			return Color(0.694, 0.639, 0.478)
		GameEnums.MissionType.ASSASSINATION:
			return Color(0.788, 0.353, 0.412)
		_:
			return TEXT_2


static func status_color(status: int) -> Color:
	match status:
		GameEnums.OperatorStatus.AVAILABLE:
			return MINT
		GameEnums.OperatorStatus.ON_MISSION:
			return STEEL
		GameEnums.OperatorStatus.INJURED:
			return RUST
		GameEnums.OperatorStatus.TRAINING:
			return OCHRE
		GameEnums.OperatorStatus.ON_INTEL:
			return STEEL
		_:
			return TEXT_3


static func status_text(op: OperatorData) -> String:
	if op.status == GameEnums.OperatorStatus.ON_INTEL:
		return "Casing"
	var content: String = GameEnums.OperatorStatus.keys()[op.status].capitalize()
	if op.days_unavailable > 0:
		content += " %dd" % op.days_unavailable
	return content


static func odds_color(percent: int) -> Color:
	if percent >= 65:
		return MINT
	if percent >= 40:
		return OCHRE
	return RUST


# --- Assessment --------------------------------------------------------------

## The company's read on a contract, said in words instead of as a percentage.
##
## The resolver still computes an exact probability, the breakdown still lists
## every term, and the list still sums to the squad score. What goes is the
## player ever being SHOWN the figure. A visible "95%" makes the decision before
## the player does: the question stops being "do I understand this job well
## enough to know who to send" and becomes "how do I get this number up", and
## every screen in front of it becomes an optimiser rather than a briefing.
##
## Six bands is coarse on purpose. There is nothing to tune toward except the
## next band, and a band is roughly a SPREAD's worth of squad score, so crossing
## one means a real change in the squad rather than a rounding win. The
## breakdown underneath still names exactly which term to act on — the player
## loses the score, not the reasons.
##
## Every band is read off the same `success_chance` the roll will use, so the
## assessment can never disagree with what actually happens.
const ASSESSMENT_STEPS := 6

## Score terms smaller than this are noise in a summary — they belong in the
## breakdown, which lists everything, not in a list of things worth acting on.
const CONCERN_FLOOR := 1.0


## 0 (desperate) through 5 (routine), from a raw probability.
##
## Anything quoting a HYPOTHETICAL reading — a field decision pricing what it
## will buy before the player takes it — goes through this, because it has a
## chance from `MissionResolver.chance_for()` and no report to hang it on.
static func assessment_band_for(chance: float) -> int:
	var percent: int = int(round(chance * 100.0))
	if percent >= 86:
		return 5
	if percent >= 72:
		return 4
	if percent >= 58:
		return 3
	if percent >= 44:
		return 2
	if percent >= 28:
		return 1
	return 0


static func assessment_band(report: MissionReport) -> int:
	return assessment_band_for(report.success_chance)


static func assessment_word_for(band: int) -> String:
	match band:
		5:
			return "Routine"
		4:
			return "Favourable"
		3:
			return "Workable"
		2:
			return "Even"
		1:
			return "Against us"
		_:
			return "Desperate"


static func assessment_word(report: MissionReport) -> String:
	return assessment_word_for(assessment_band(report))


## The band said as a sentence. Carries the part a single word cannot: whether
## the squad is ahead or behind, and how much room that leaves.
static func assessment_note(report: MissionReport) -> String:
	match assessment_band(report):
		5:
			return "Nothing here they have not handled before."
		4:
			return "Comfortably ahead of what this asks for."
		3:
			return "Ahead, but not by enough to be careless."
		2:
			return "This could go either way."
		1:
			return "Behind on this. Somebody will pay for it."
		_:
			return "This is not a contract. It is a gamble."


static func assessment_color_for(band: int) -> Color:
	match band:
		5, 4:
			return MINT
		3, 2:
			return OCHRE
		_:
			return RUST


static func assessment_color(report: MissionReport) -> Color:
	return assessment_color_for(assessment_band(report))


## A gauge, and deliberately not a bar.
##
## Fatigue and condition are drawn as continuous bars because those genuinely
## ARE percentages the player is meant to read. This one fills in whole steps,
## so two contracts can be compared against each other without the shape ever
## resolving back into the figure this whole change exists to withhold.
static func band_gauge(band: int, color: Color, cell_width: int = 22, expand: bool = false) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in ASSESSMENT_STEPS:
		var cell := ColorRect.new()
		cell.custom_minimum_size = Vector2(cell_width, 7)
		cell.color = color if i <= band else RULE
		if expand:
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cell)
	if expand:
		grow(row)
	return row


## The headline block: what the company thinks of this job, and why in one line.
static func assessment_block(report: MissionReport, caption: String = "Our assessment") -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var label := text(caption.to_upper(), SIZE_CAPTION, TEXT_3)
	label.add_theme_font_override("font", display())
	box.add_child(label)

	var color := assessment_color(report)
	box.add_child(title(assessment_word(report), SIZE_TITLE, color))
	box.add_child(band_gauge(assessment_band(report), color))

	var note := text(assessment_note(report), SIZE_SMALL, TEXT_2)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	return box


## Whose line this is, for a term the resolver charged to one person. The
## callsign rather than the legal name — it is shorter, and it is what the
## company actually calls them.
static func _modifier_owner(report: MissionReport, modifier: Modifier) -> String:
	if modifier.operator_id == &"" or report.squad == null:
		return ""
	for op in report.squad.members():
		if op.id == modifier.operator_id:
			return op.short_label()
	return ""


## The terms costing this squad the most, worst first, named.
##
## Read straight off the breakdown rather than restated, so a concern the player
## is shown is one the resolver genuinely charged them for — and fixing it moves
## the same number. This is what replaces the percentage as the thing the player
## acts on: not "get it to 95" but "they are two people over strength and one of
## them is exhausted".
static func assessment_concerns(report: MissionReport, limit: int = 4) -> Array:
	var found: Array = []
	for modifier in report.modifiers:
		if modifier.value > -CONCERN_FLOOR:
			continue
		var owner := _modifier_owner(report, modifier)
		found.append({
			"label": ("%s — %s" % [owner, modifier.label]) if not owner.is_empty()
				else modifier.label,
			"value": modifier.value,
		})
	found.sort_custom(func(a, b): return a["value"] < b["value"])
	return found.slice(0, limit)


## The concern list as a column of lines. No figures: on the board there is no
## breakdown to check them against, and a bare "-24.0" with nothing to compare
## it to is the percentage wearing a different hat.
static func concerns_readout(report: MissionReport, limit: int = 4) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)

	var concerns := assessment_concerns(report, limit)
	if concerns.is_empty():
		var clear := text(
			"Nothing standing against them.", SIZE_SMALL, TEXT_3)
		clear.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(clear)
		return box

	for concern in concerns:
		var line := text("·   %s" % concern["label"], SIZE_SMALL, TEXT_2)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(line)
	return box


## Risk climbs the same ramp everywhere: quiet, then ochre, then rust.
## Difficulty as a skull rating rather than a bare number. A player reads
## "three of five" instantly and has to think about "68.4".
static func difficulty_skulls(difficulty: float) -> int:
	if difficulty >= 88.0:
		return 5
	if difficulty >= 74.0:
		return 4
	if difficulty >= 58.0:
		return 3
	if difficulty >= 46.0:
		return 2
	return 1


static func skull_text(difficulty: float) -> String:
	var filled := difficulty_skulls(difficulty)
	return "%s%s" % ["☠".repeat(filled), "·".repeat(5 - filled)]


static func skull_color(difficulty: float) -> Color:
	match difficulty_skulls(difficulty):
		5, 4:
			return RUST
		3:
			return OCHRE
		_:
			return TEXT


## The skull count said in words.
##
## "Threat 3 skulls" and "Risk 64" sat side by side reading as two versions of
## the same number. They are not: threat is how hard the job is, danger is how
## likely the people you send get hurt, and a quiet job in a lethal place scores
## low on one and high on the other. Naming the threat band makes the pair read
## as two different questions.
static func threat_word(difficulty: float) -> String:
	match difficulty_skulls(difficulty):
		5:
			return "Extreme"
		4:
			return "Severe"
		3:
			return "Hard"
		2:
			return "Moderate"
		_:
			return "Light"


## The headline block on a contract: what kind of fight this is, in words and in
## skulls, sized so it is read first.
static func threat_block(difficulty: float) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.tooltip_text = "How hard the opposition is. Compare it against what your squad scores."

	var caption := text("THREAT", SIZE_CAPTION, TEXT_3)
	caption.add_theme_font_override("font", display())
	box.add_child(caption)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var word := title(threat_word(difficulty), SIZE_TITLE, skull_color(difficulty))
	line.add_child(word)
	var skulls := text(skull_text(difficulty), SIZE_HEADING, skull_color(difficulty))
	skulls.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(skulls)
	box.add_child(line)
	return box


static func risk_color(risk: float) -> Color:
	if risk >= 70.0:
		return RUST
	if risk >= 45.0:
		return OCHRE
	return TEXT


# --- Rating ------------------------------------------------------------------

## Label, bar, figure. The one row shape for anything measured out of 100 — a
## skill, a temperament axis, what a squad brings in stealth, what an operator
## rates on sabotage work. The figure is monospace so a column of them stays
## straight whether the value is 7 or 97.
##
## `shown_value` is for the one case where the bar and the number are honestly
## different: a starred skill's bar shows progress toward the NEXT star while the
## figure shows what the operator is actually worth.
static func meter_row(
	caption: String,
	value: int,
	color: Color = OCHRE,
	shown_value: int = -1,
	caption_width: int = 108,
	value_width: int = 38
) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var name_label := text(caption, SIZE_SMALL, TEXT_2)
	name_label.custom_minimum_size.x = caption_width
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_label)

	# The bar styles itself rather than sitting inside a PanelContainer — a
	# container squeezes it back down to a hairline.
	var bar := ProgressBar.new()
	bar.max_value = 100
	bar.value = clampi(value, 0, 100)
	bar.show_percentage = false
	bar.custom_minimum_size.y = 10
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grow(bar)

	var track := StyleBoxFlat.new()
	track.bg_color = INK
	track.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)

	var value_label := data(
		str(value if shown_value < 0 else shown_value), SIZE_SMALL, TEXT)
	value_label.custom_minimum_size.x = value_width
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	return row


## What a kind of work asks for, and — when a squad is given — what that squad
## actually brings to each of those things.
##
## The tier is named on every row rather than carried by a heading above a group
## or by the bar's colour alone. Headings cost two rows on a panel that has none
## to spare, and colour on its own cannot be read by everybody — so the word
## does the work and the colour agrees with it. Both tiers come out of
## `Ovr.emphasis()`, which derives them from the profile's own weights, so this
## can never label a job in a way its own arithmetic contradicts.
##
## The bars are the squad's AVERAGE in each skill, not their rating. See
## Ovr.group_average for why those are deliberately different numbers.
static func work_emphasis_block(
	profile: MissionProfile,
	members: Array = [],
	caption_width: int = 132
) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	if profile == null:
		return box

	for entry in Ovr.emphasis(profile):
		var skill: int = int(entry["skill"])
		var primary: bool = bool(entry["primary"])
		var caption: String = "%s  ·  %s" % [
			GameEnums.skill_name(skill), "primary" if primary else "secondary"]

		if members.is_empty():
			# No squad to measure, so no bar. One drawn at zero would read as a
			# squad that is bad at this rather than as no squad.
			box.add_child(text(caption, SIZE_SMALL, TEXT_2 if primary else TEXT_3))
			continue

		box.add_child(meter_row(
			caption,
			Ovr.group_average(members, skill, profile.mission_type),
			OCHRE if primary else RULE_BRIGHT,
			-1,
			caption_width))
	return box


static func trait_color(polarity: int) -> Color:
	match polarity:
		GameEnums.TraitPolarity.POSITIVE:
			return MINT
		GameEnums.TraitPolarity.NEGATIVE:
			return RUST
		_:
			return TEXT_2
