extends SceneTree

## Enforces .docs/prose_style_guide.md against every generated-text pool.
##
##   Godot.exe --headless --path . --script res://tests/prose_rules.gd
##
## sim_prose.gd dumps the prose so a person can read it as prose; this checks the
## structural rules nobody can be expected to re-verify by eye on every edit —
## that a new kill-feed method still carries no comma, that a briefing opening
## still has exactly one "%s", that nothing in a noun-phrase list has quietly
## grown a capital letter and a full stop.
##
## The two are complements, not alternatives. This file cannot tell you that a
## sentence is ugly or that it contradicts the line above it; only reading can.
## What it can do is guarantee that every string in every pool still PLUGS IN.

var _failures: Array[String] = []
var _checked := 0


func _initialize() -> void:
	_check_enemy_kinds()
	_check_methods()
	_check_briefings()
	_check_titles()
	_check_after_action()
	_check_bond_reasons()
	_check_resume()
	_check_descriptions()
	_check_coverage()

	print("")
	if _failures.is_empty():
		print("PROSE RULES: %d strings checked, all conform." % _checked)
	else:
		print("PROSE RULES: %d strings checked, %d violations." % [
			_checked, _failures.size()])
		for line in _failures:
			print("  %s" % line)
	print("")
	quit(0 if _failures.is_empty() else 1)


func _fail(where: String, text: String, why: String) -> void:
	_failures.append("%s — %s\n      %s" % [where, why, JSON.stringify(text)])


const _STOPS := [".", "!", "?"]


func _ends_in_stop(text: String) -> bool:
	return _STOPS.has(text.substr(text.length() - 1))


## A fragment that slots into a template: lower case, no terminal punctuation,
## no internal comma, no format placeholder of its own.
func _require_noun_phrase(where: String, text: String) -> void:
	_checked += 1
	if text.strip_edges() != text or text.is_empty():
		_fail(where, text, "empty, or padded with whitespace")
		return
	if text.substr(0, 1) != text.substr(0, 1).to_lower():
		_fail(where, text, "opens with a capital; it is a phrase, not a sentence")
	if _ends_in_stop(text):
		_fail(where, text, "ends in a stop; it is a phrase, not a sentence")
	if text.contains(",") or text.contains(";"):
		_fail(where, text, "contains a comma or semicolon, which the column separator already implies")
	if text.contains("%"):
		_fail(where, text, "contains '%', which nothing substitutes here")
	if text.begins_with("the "):
		_fail(where, text, "is definite; these lists name things the player has never met")


## A standalone sentence: capitalised, closed with a stop.
func _require_sentence(where: String, text: String) -> void:
	_checked += 1
	if text.strip_edges() != text or text.is_empty():
		_fail(where, text, "empty, or padded with whitespace")
		return
	if text.substr(0, 1) != text.substr(0, 1).to_upper():
		_fail(where, text, "does not open with a capital")
	if not _ends_in_stop(text):
		_fail(where, text, "does not close with a stop")


## "a"/"an" must agree with the SOUND of what follows — TextUtil owns that call,
## so this only asks whether the hand-written article matches what TextUtil would
## have chosen. Phrases with no article are left alone: a mass or plural head
## ("sustained fire", "two bursts") correctly takes none.
func _require_article_agrees(where: String, text: String) -> void:
	var article := ""
	if text.begins_with("a "):
		article = "a"
	elif text.begins_with("an "):
		article = "an"
	else:
		return

	var rest: String = text.substr(article.length() + 1)
	_checked += 1
	if TextUtil.article(rest) != article:
		_fail(where, text, "should read '%s %s'" % [TextUtil.article(rest), rest])


## Exactly one placeholder, and it is "%s". A stray per-cent sign anywhere in one
## of these crashes the format call at runtime rather than merely reading badly.
func _require_single_placeholder(where: String, text: String) -> void:
	_checked += 1
	if text.count("%") != 1 or not text.contains("%s"):
		_fail(where, text, "must contain exactly one placeholder, and it must be '%s'")


func _require_no_placeholder(where: String, text: String) -> void:
	_checked += 1
	if text.contains("%"):
		_fail(where, text, "must contain no placeholder; this string is never substituted")


# --- The pools ---------------------------------------------------------------

## Every enemy is one countable person the squad had never met, so every entry is
## a singular phrase carrying its own indefinite article.
func _check_enemy_kinds() -> void:
	for kind in MissionResolver._ENEMY_KINDS:
		var text: String = str(kind)
		var where := "kill feed / enemy"
		_require_noun_phrase(where, text)
		_require_article_agrees(where, text)
		_checked += 1
		if not (text.begins_with("a ") or text.begins_with("an ")):
			_fail(where, text, "must open with 'a' or 'an'; one entry is one body")


## Markers of a finite verb hanging off the noun. "Suppressive fire that found a
## mark" is half a sentence in a slot that holds a noun phrase.
const _CLAUSE_MARKERS := [" that ", " which ", " who ", " they ", " it ", " nobody "]


func _check_methods() -> void:
	var pools: Array = [["kill feed / method (unarmed)", MissionResolver._METHODS_DEFAULT]]
	for weapon_id in MissionResolver._METHODS:
		pools.append([
			"kill feed / method (%s)" % weapon_id, MissionResolver._METHODS[weapon_id]])

	for pool in pools:
		var where: String = pool[0]
		for entry in pool[1]:
			_checked += 1
			if entry.size() != 3:
				_fail(where, str(entry), "must be [phrase, min_metres, max_metres]")
				continue

			var text: String = str(entry[0])
			var low: int = int(entry[1])
			var high: int = int(entry[2])

			_require_noun_phrase(where, text)
			_require_article_agrees(where, text)

			_checked += 1
			if low < 1 or high < low:
				_fail(where, text, "range %d-%d is not a band of at least one metre" % [low, high])

			for marker in _CLAUSE_MARKERS:
				if text.contains(marker):
					_fail(where, text, "reads as a clause ('%s'), not a noun phrase" % marker.strip_edges())
					break


func _check_briefings() -> void:
	for mission_type in MissionFactory.BRIEFING_OPENINGS:
		var where := "briefing / opening (%s)" % GameEnums.mission_type_name(mission_type)
		for opening in MissionFactory.BRIEFING_OPENINGS[mission_type]:
			_require_sentence(where, str(opening))
			_require_single_placeholder(where, str(opening))

	for band in MissionFactory.CAUTIONS:
		var where := "briefing / caution (%s)" % band
		for caution in MissionFactory.CAUTIONS[band]:
			_require_sentence(where, str(caution))
			_require_no_placeholder(where, str(caution))

	# The article is TextUtil's job, so the entry must not bring its own.
	for title in MissionFactory.TARGET_TITLES:
		var text: String = str(title)
		var where := "briefing / target title"
		_require_noun_phrase(where, text)
		_checked += 1
		if text.begins_with("a ") or text.begins_with("an "):
			_fail(where, text, "must not carry an article; TextUtil.with_article() supplies it")

	# The ground is pasted between the opening and the caution.
	for id in RegionLibrary.ids():
		var region := RegionLibrary.get_region(id)
		var where := "briefing / ground (%s)" % region.display_name
		_require_sentence(where, region.description)
		_require_no_placeholder(where, region.description)


## A title is a label, not prose: Title Case, no stop, and no pronoun, because it
## is drawn independently of whoever the contract turns out to be about.
##
## Matched WHOLE-WORD and case-insensitively, for the same reason TextUtil's
## article lists are: a substring test flags "Out of Here" for containing "her",
## and "Whoever Is Left" for containing "he".
const _GENDERED := ["he", "she", "him", "her", "hers", "his", "himself", "herself"]


func _check_titles() -> void:
	for mission_type in MissionFactory.TITLES:
		var where := "contract title (%s)" % GameEnums.mission_type_name(mission_type)
		for title in MissionFactory.TITLES[mission_type]:
			var text: String = str(title)
			_checked += 1
			if text.substr(0, 1) != text.substr(0, 1).to_upper():
				_fail(where, text, "does not open with a capital")
			if _ends_in_stop(text):
				_fail(where, text, "is a label, so it takes no closing stop")
			_require_no_placeholder(where, text)
			for word in text.split(" ", false):
				if _GENDERED.has(word.to_lower().lstrip("(\"'").rstrip(",;:!?\")'")):
					_fail(where, text, "assumes the target's gender, which is rolled separately")
					break


func _check_after_action() -> void:
	for mission_type in MissionStory.OPENINGS:
		var where := "after action / opening (%s)" % GameEnums.mission_type_name(mission_type)
		for opening in MissionStory.OPENINGS[mission_type]:
			_require_sentence(where, str(opening))
			_require_single_placeholder(where, str(opening))

	for opening in MissionStory.OPENING_FALLBACK:
		_require_sentence("after action / opening (fallback)", str(opening))
		_require_single_placeholder("after action / opening (fallback)", str(opening))


## Named placeholders, so a new line cannot silently swap the job for the place.
const _BOND_KEYS := ["{title}", "{place}"]


func _check_bond_reasons() -> void:
	for type in Bonds.BOND_REASONS:
		var where := "bond reason (%s)" % GameEnums.bond_name(type)
		for reason in Bonds.BOND_REASONS[type]:
			var text: String = str(reason)
			_require_sentence(where, text)
			_require_no_placeholder(where, text)

			_checked += 1
			var stripped := text
			for key in _BOND_KEYS:
				stripped = stripped.replace(key, "")
			if stripped.contains("{") or stripped.contains("}"):
				_fail(where, text, "uses a placeholder other than {title} or {place}")


## A seniority phrase completes "<label> is <a nationality rank>, and ___." — a
## frame that already contains a comma and an "and", so the phrase may contain
## neither. A reputation line stands alone at the end of the paragraph.
func _check_resume() -> void:
	for band in OperatorData.SENIORITY:
		var where := "resume / seniority (%s)" % band
		for phrase in OperatorData.SENIORITY[band]:
			var text: String = str(phrase)
			_checked += 1
			if text.strip_edges() != text or text.is_empty():
				_fail(where, text, "empty, or padded with whitespace")
				continue
			if text.substr(0, 1) != text.substr(0, 1).to_lower():
				_fail(where, text, "opens with a capital, but it lands mid-sentence")
			if _ends_in_stop(text):
				_fail(where, text, "ends in a stop, but it lands mid-sentence")
			if text.contains(","):
				_fail(where, text, "contains a comma; the frame already supplies ', and'")
			_require_no_placeholder(where, text)

	for gate in OperatorData.REPUTATION:
		var where := "resume / reputation (%s)" % gate
		for line in OperatorData.REPUTATION[gate]:
			_require_sentence(where, str(line))
			_require_no_placeholder(where, str(line))


func _check_descriptions() -> void:
	for entry in MedalLibrary.MEDALS:
		_require_sentence("medal note (%s)" % entry["name"], str(entry["note"]))

	for id in TraitLibrary.ids():
		var t := TraitLibrary.get_trait(id)
		_require_sentence("trait description (%s)" % t.display_name, t.description)

	# The generated fear traits are not in the static table but reach the same UI.
	for mission_type in GameEnums.MissionType.values():
		var fear := TraitLibrary.fear_of(mission_type)
		_require_sentence("trait description (%s)" % fear.display_name, fear.description)


## A mission type with no title pool falls back to a contract called "Contract",
## and one with no opening falls back to "Work in %s." Both are visible bugs, and
## both appear only for the type somebody forgot.
func _check_coverage() -> void:
	for mission_type in GameEnums.MissionType.values():
		var name: String = GameEnums.mission_type_name(mission_type)
		_checked += 1
		if not MissionFactory.TITLES.has(mission_type):
			_fail("coverage", name, "has no contract titles")
		if not MissionFactory.BRIEFING_OPENINGS.has(mission_type):
			_fail("coverage", name, "has no briefing opening")
		if not MissionStory.OPENINGS.has(mission_type):
			_fail("coverage", name, "has no after-action opening")
