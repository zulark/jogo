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


## "a" or "an", agreed with what follows. Vowel-sound approximation, which is
## right often enough for the words this game generates.
static func article(word: String) -> String:
	if word.is_empty():
		return "a"
	return "an" if "aeiou".contains(word.substr(0, 1).to_lower()) else "a"


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
