class_name TextUtil
extends RefCounted

## Grammar. Every generated sentence in the game goes through here.
##
## Composing prose from templates and numbers produces "1 contracts", "1 day(s)"
## and "Lucia Escobedo and a new hire" unless something is actually agreeing the
## parts. A game whose whole appeal is the story its roster writes cannot afford
## text that reads like a database dump, so pluralisation, number words and list
## joining live in one place and nothing formats a count by hand.

const _NUMBER_WORDS := [
	"no", "one", "two", "three", "four", "five", "six",
	"seven", "eight", "nine", "ten", "eleven", "twelve",
]


## "1 contract" / "3 contracts". Pass `plural` when adding an s is wrong.
static func count(n: int, singular: String, plural: String = "") -> String:
	return "%d %s" % [n, noun(n, singular, plural)]


## The noun alone, agreed with the number.
static func noun(n: int, singular: String, plural: String = "") -> String:
	if n == 1:
		return singular
	return plural if not plural.is_empty() else singular + "s"


## "three contracts" rather than "3 contracts". Small numbers read better spelled
## out inside a sentence; large ones do not.
static func spelled(n: int, singular: String, plural: String = "") -> String:
	return "%s %s" % [number(n), noun(n, singular, plural)]


## The number as a word up to twelve, as digits past that.
static func number(n: int) -> String:
	if n >= 0 and n < _NUMBER_WORDS.size():
		return _NUMBER_WORDS[n]
	return str(n)


## Sentence-case a spelled number, for when it opens a sentence.
static func number_capitalised(n: int) -> String:
	var word := number(n)
	return word.substr(0, 1).to_upper() + word.substr(1)


## "three men" with the number word capitalised, for when the count opens a
## sentence. `spelled` is the same phrase mid-sentence.
static func spelled_capitalised(n: int, singular: String, plural: String = "") -> String:
	return "%s %s" % [number_capitalised(n), noun(n, singular, plural)]


## "A", "A and B", "A, B and C" — never "A, B, C" with a dangling comma.
static func join_names(names: Array) -> String:
	var parts: Array = []
	for entry in names:
		parts.append(str(entry))

	match parts.size():
		0:
			return ""
		1:
			return parts[0]
		2:
			return "%s and %s" % [parts[0], parts[1]]
		_:
			var head: Array = parts.slice(0, parts.size() - 1)
			return "%s and %s" % [", ".join(head), parts[parts.size() - 1]]


## Words whose first SOUND disagrees with their first letter. The article follows
## the sound, so a first-letter test alone shipped "an union enforcer" and "an
## Ukrainian" — both of which start with a consonant /j/ and take "a".
##
## Listed rather than derived: no prefix rule survives contact with English here.
## "uni" would fix "a union" and break "an uninformed decision"; "h" would fix "an
## hour" and break "a house". These are the words this game actually generates,
## and the list is the right place to add more.
## Matched WHOLE, never as a prefix: "one" must not drag "onerous" with it, and
## "unit" must not drag "uninformed". Inflections are listed out for the same
## reason.
const _SOUNDS_CONSONANT := [
	"union", "unions", "unit", "units", "uniform", "uniforms", "unique",
	"universal", "university", "ukrainian", "european", "user", "users",
	"used", "useful", "utility", "one",
]

const _SOUNDS_VOWEL := ["hour", "hours", "honest", "honour", "honorary", "heir"]

const _TRAILING_PUNCTUATION := ".,;:!?\"')-"


## "a" or "an", agreed with the sound of what follows.
static func article(word: String) -> String:
	var text := word.strip_edges()
	if text.is_empty():
		return "a"

	# Only the first word decides it: "a union enforcer", not "a enforcer" — and
	# for a hyphenated first word, only the head of it: "a one-off".
	var first := text.split(" ")[0].split("-")[0].to_lower()
	while not first.is_empty() \
			and _TRAILING_PUNCTUATION.contains(first.substr(first.length() - 1)):
		first = first.substr(0, first.length() - 1)

	if _SOUNDS_CONSONANT.has(first):
		return "a"
	if _SOUNDS_VOWEL.has(first):
		return "an"

	return "an" if "aeiou".contains(text.substr(0, 1).to_lower()) else "a"


## The word with its indefinite article attached: "a Korean", "an Egyptian".
static func with_article(word: String) -> String:
	if word.is_empty():
		return ""
	return "%s %s" % [article(word), word]


## "Reyes's", "Vasquez'". Operator labels carry a quoted callsign — `Kim Ji-ho
## "Nail"` — and hanging an apostrophe off the closing quote reads as a typo, so
## those take the possessive on the name alone: `Kim Ji-ho's`.
##
## Anything that needs a possessive of a full label should call this rather than
## writing "%s's", which is how `Vuk Djuric "Junco"'s leadership` got shipped.
static func possessive(name: String) -> String:
	var text := name.strip_edges()
	if text.is_empty():
		return ""

	# Drop a trailing quoted callsign: the possessive belongs on the person.
	var quote: int = text.find(" \"")
	if quote > 0 and text.ends_with("\""):
		text = text.substr(0, quote)

	return text + ("'" if text.ends_with("s") else "'s")


## Capitalises the first letter and leaves the rest alone — unlike String's own
## capitalize(), which lowercases everything after it and would turn a callsign
## into mush.
static func sentence_case(text: String) -> String:
	if text.is_empty():
		return text
	return text.substr(0, 1).to_upper() + text.substr(1)


## Joins fragments into one paragraph, ensuring each ends in a stop and only one
## space separates them. Stops templates from producing ".." or ". ." when a
## fragment already carries its own punctuation.
static func sentences(parts: Array) -> String:
	var cleaned: Array = []
	for entry in parts:
		var text := str(entry).strip_edges()
		if text.is_empty():
			continue
		if not text.ends_with(".") and not text.ends_with("!") and not text.ends_with("?"):
			text += "."
		cleaned.append(text)
	return " ".join(cleaned)
