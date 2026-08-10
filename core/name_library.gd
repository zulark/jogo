class_name NameLibrary
extends RefCounted

## Names drawn from the operator's own culture, so an Afghan scout is not called
## Bexley Marchetti.
##
## Keyed by CULTURE rather than by nation, because naming conventions cross
## borders — Mexico and Colombia share one pool, Russia and Ukraine share
## another. Adding a nation usually means pointing it at a culture that already
## exists rather than writing twenty more names.
##
## Given-name pools mix masculine and feminine names. Operators have no modelled
## gender, so any name in the pool is valid for any operator; if portraits later
## make that matter, split the pools then rather than inventing a field now.

enum Order { GIVEN_FIRST, FAMILY_FIRST }

const CULTURES := {
	&"anglo": {
		"order": Order.GIVEN_FIRST,
		"given": ["James", "Ruth", "Marcus", "Eleanor", "Gareth", "Nora", "Desmond", "Iris", "Owen", "Clara"],
		"family": ["Whitfield", "Hargrove", "Bennett", "Sinclair", "Kavanagh", "Ashcroft", "Merrill", "Doyle", "Prescott", "Vaughn"],
	},
	&"lusophone": {
		"order": Order.GIVEN_FIRST,
		"given": ["Rafael", "Beatriz", "Thiago", "Larissa", "Mateus", "Camila", "Bruno", "Fernanda", "Diogo", "Renata"],
		"family": ["Ferreira", "Almeida", "Barbosa", "Cardoso", "Nogueira", "Ribeiro", "Moreira", "Pacheco", "Teixeira", "Andrade"],
	},
	&"hispanic": {
		"order": Order.GIVEN_FIRST,
		"given": ["Andres", "Lucia", "Emilio", "Valentina", "Joaquin", "Marisol", "Rodrigo", "Ximena", "Tomas", "Paloma"],
		"family": ["Salazar", "Ibarra", "Montoya", "Vergara", "Escobedo", "Quintero", "Arreola", "Bustamante", "Carranza", "Peralta"],
	},
	&"francophone": {
		"order": Order.GIVEN_FIRST,
		"given": ["Julien", "Celine", "Mathieu", "Amelie", "Olivier", "Camille", "Thibault", "Sylvie", "Remy", "Oceane"],
		"family": ["Lefebvre", "Marchand", "Boucher", "Rousseau", "Devereaux", "Chevalier", "Fontaine", "Girard", "Lambert", "Renaud"],
	},
	&"germanic": {
		"order": Order.GIVEN_FIRST,
		"given": ["Lukas", "Annika", "Tobias", "Heike", "Sebastian", "Franziska", "Jonas", "Ingrid", "Matthias", "Katrin"],
		"family": ["Brandt", "Hoffmann", "Keller", "Neumann", "Schreiber", "Vogel", "Wendt", "Kaufmann", "Lindner", "Reinhardt"],
	},
	# Slavic surnames inflect for gender (-ski/-ska, -ov/-ova). Operators have no
	# modelled gender, so both pools below deliberately use only forms that do
	# NOT inflect — otherwise a mixed given-name pool produces "Yuri Sokolova",
	# which reads as broken to anyone who speaks the language.
	&"slavic_west": {
		"order": Order.GIVEN_FIRST,
		"given": ["Jakub", "Agnieszka", "Marcin", "Zofia", "Piotr", "Halina", "Tomasz", "Ewa", "Krzysztof", "Marta"],
		"family": ["Kowalczyk", "Nowak", "Kaczmarek", "Mazur", "Baran", "Szymczak", "Sikora", "Wojcik", "Adamczyk", "Pawlak"],
	},
	&"slavic_east": {
		"order": Order.GIVEN_FIRST,
		"given": ["Dmitri", "Yelena", "Anatoly", "Oksana", "Grigori", "Nadiya", "Vasily", "Larisa", "Yuri", "Marina"],
		"family": ["Petrenko", "Kravchenko", "Shevchenko", "Tkachenko", "Bondarenko", "Chernykh", "Sedykh", "Dolgikh", "Koval", "Moroz"],
	},
	&"balkan": {
		"order": Order.GIVEN_FIRST,
		"given": ["Nikola", "Jelena", "Milos", "Danica", "Vuk", "Snezana", "Dragan", "Milica", "Zoran", "Vesna"],
		"family": ["Jovanovic", "Petrovic", "Markovic", "Ilic", "Stankovic", "Popovic", "Radovanovic", "Djuric", "Nikolic", "Savic"],
	},
	&"arabic": {
		"order": Order.GIVEN_FIRST,
		"given": ["Karim", "Nadia", "Hisham", "Yasmin", "Tarek", "Layla", "Sameh", "Rania", "Fouad", "Amira"],
		"family": ["El-Masri", "Hassan", "Farouk", "Abdelrahman", "Zaki", "Mansour", "Khalil", "Saleh", "Nasr", "Badawi"],
	},
	&"afghan": {
		"order": Order.GIVEN_FIRST,
		"given": ["Rashid", "Parwana", "Najib", "Shakila", "Wali", "Zarmina", "Hameed", "Nasrin", "Daud", "Gulalai"],
		"family": ["Noorzai", "Stanikzai", "Wardak", "Popalzai", "Achakzai", "Barakzai", "Safi", "Alokozai", "Sherzai", "Hotak"],
	},
	&"west_african": {
		"order": Order.GIVEN_FIRST,
		"given": ["Chukwuemeka", "Amara", "Babatunde", "Ngozi", "Ibrahim", "Halima", "Olumide", "Folake", "Sani", "Zainab"],
		"family": ["Okonkwo", "Adeyemi", "Balogun", "Chukwu", "Danjuma", "Eze", "Ogunleye", "Abubakar", "Nwosu", "Oyelaran"],
	},
	&"east_african": {
		"order": Order.GIVEN_FIRST,
		"given": ["Juma", "Wanjiru", "Otieno", "Akinyi", "Kipchoge", "Nyambura", "Mwangi", "Zawadi", "Baraka", "Amani"],
		"family": ["Kimani", "Ochieng", "Wekesa", "Mutiso", "Kariuki", "Njoroge", "Omondi", "Chebet", "Wanjala", "Muthoni"],
	},
	&"korean": {
		"order": Order.FAMILY_FIRST,
		"given": ["Ji-ho", "Seo-yeon", "Min-jun", "Ha-eun", "Dong-hyun", "Soo-ah", "Jae-won", "Yu-jin", "Tae-yang", "Eun-bi"],
		"family": ["Kim", "Lee", "Park", "Choi", "Jung", "Kang", "Cho", "Yoon", "Jang", "Lim"],
	},
	&"japanese": {
		"order": Order.FAMILY_FIRST,
		"given": ["Haruki", "Ayano", "Kenji", "Mizuki", "Souta", "Rina", "Takeshi", "Nanami", "Riku", "Sachiko"],
		"family": ["Ishikawa", "Tanaka", "Yamamoto", "Kobayashi", "Fujimoto", "Nakamura", "Saito", "Watanabe", "Morita", "Hasegawa"],
	},
	&"indian": {
		"order": Order.GIVEN_FIRST,
		"given": ["Arjun", "Priya", "Vikram", "Ananya", "Rohit", "Meera", "Sandeep", "Kavita", "Nikhil", "Divya"],
		"family": ["Sharma", "Iyer", "Chauhan", "Reddy", "Banerjee", "Nair", "Malhotra", "Deshpande", "Rao", "Gupta"],
	},
}

## Callsigns stay culture-agnostic on purpose: they are assigned by the company,
## in the company's working language, not inherited from where someone was born.
const CALLSIGNS := [
	"Ash", "Bishop", "Cinder", "Dial", "Ember", "Flint", "Gable", "Husk",
	"Ivory", "Jackal", "Kite", "Lark", "Mirth", "Nail", "Onyx", "Pike",
	"Quill", "Rook", "Static", "Tally", "Vellum", "Wick", "Anvil", "Brine",
	"Crow", "Dusk", "Etch", "Fable", "Grit", "Hollow", "Inkwell", "Junco",
]


static func full_name(rng: RandomNumberGenerator, culture: StringName) -> String:
	var entry: Dictionary = CULTURES.get(culture, CULTURES[&"anglo"])
	var given: Array = entry["given"]
	var family: Array = entry["family"]

	var given_name: String = given[rng.randi() % given.size()]
	var family_name: String = family[rng.randi() % family.size()]

	if int(entry["order"]) == Order.FAMILY_FIRST:
		return "%s %s" % [family_name, given_name]
	return "%s %s" % [given_name, family_name]


## Prefers a callsign nobody on the roster is already using. Two operators
## answering to "Ivory" in the same squad reads as a bug even when it is not.
static func callsign(rng: RandomNumberGenerator, taken: Array = []) -> String:
	var free: Array = []
	for name in CALLSIGNS:
		if not taken.has(name):
			free.append(name)
	if free.is_empty():
		free = CALLSIGNS
	return free[rng.randi() % free.size()]
