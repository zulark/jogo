# Prose style guide

Every sentence in this game is assembled at runtime from small pieces. Nobody
writes "Lucia Vergara killed a sentry with a single shot at 12 metres" — the
game writes it, out of a name, a noun phrase, another noun phrase and an integer,
and it has to come out grammatical for every combination of those it can produce.

This document is the contract each of those pieces signs. A string that keeps it
plugs into the templates that consume it, in every combination, forever. A string
that breaks it produces "a Antimalarials", "the knife · 102m", or "41 kills
confirmed. Brought on by Reyes." in the middle of a paragraph.

## How this is enforced

Two tools, and they check different things.

```
Godot.exe --headless --path . --import
Godot.exe --headless --path . --script res://tests/prose_rules.gd   # structure
Godot.exe --headless --path . --script res://tests/sim_prose.gd     # readability
```

`prose_rules.gd` is a checker. It walks every pool in the game and asserts the
mechanical rules below — article agreement, placeholder counts, capitalisation,
stray commas, range bands. It exits non-zero on a violation and names the string.
**Run it after touching any list in this document.**

`sim_prose.gd` asserts nothing. It dumps a few hundred generated lines so a
person can read them as prose. It is the only thing that finds a line that is
grammatical and still wrong: a contradiction between two sentences, a register
that does not match, a fact the systems never produced. **Read its output after
touching any list in this document.**

Neither replaces the other. The checker cannot tell you a sentence is a lie.

## Rule 0 — never build grammar by hand

Before writing a template, check whether the grammar you need already exists.
Writing `"a %s"` by hand is how `"a Antimalarials & Field Antiseptics"` shipped.

| You need | Call | Never write |
|---|---|---|
| "a" / "an" | `TextUtil.article(word)` | a first-letter vowel test |
| "a sentry" | `TextUtil.with_article(word)` | `"a %s" % word` |
| "3 contracts" | `TextUtil.count(n, "contract")` | `"%d contracts" % n` |
| "contracts" | `TextUtil.noun(n, "contract")` | `singular + "s"` |
| "three contracts" | `TextUtil.spelled(n, "contract")` | a hand-rolled number word |
| "Three" opening a sentence | `TextUtil.number_capitalised(n)` | `str(n).capitalize()` |
| "A, B and C" | `TextUtil.join_names(names)` | `", ".join(names)` |
| "Reyes's" / "Vasquez'" | `TextUtil.possessive(label)` | `"%s's" % label` |
| joining fragments into a paragraph | `TextUtil.sentences(parts)` | `" ".join(parts)` |
| "the Kunar Valley" | `RegionData.place()` | `display_name` |
| "a set of night optics" | `ItemData.indefinite()` | `"a %s" % display_name` |
| "the night optics **are**" | `ItemData.verb_is()` | `"is"` |
| "a decision on **them**" | `ItemData.object_pronoun()` | `"it"` |
| "the wet" / "the heat" | `GameEnums.hazard_phrase()` | the enum key |
| "assaulter", not "assault" | `GameEnums.role_person_name()` | `role_name()` |

If the grammar you need is not there, **add it to `TextUtil` and call it** — do
not solve it inline. `TextUtil.spelled(n, "of them", "of them")` was somebody
defeating the pluraliser with a fake noun to get a phrase out of it, and it
produced "one contract completed, one of them gone wrong".

## The two shapes

Almost every mistake in this codebase has been mixing these two inside one list.

**A PHRASE** is a fragment that a template will insert into a sentence, or that
a UI column will print on its own. It is lower case, it has no closing stop, and
it contains no comma.

> `a machine gunner` · `a single shot` · `sustained fire` · `cartel accountant`

**A SENTENCE** is complete and stands alone. It has a subject and a finite verb,
it opens with a capital, and it closes with a stop.

> `They got each other out alive on Salt the Wells.`
> `Expect organised opposition.`

**A list holds one shape or the other, never both.** Which one a list holds is
fixed by how it is consumed, and is stated for every list below. When you add to
a list, match the shape of what is already in it — and if what is already in it
disagrees with itself, that is a bug to fix, not a precedent to follow.

---

## 1. Kill feed

`MissionResolver._ENEMY_KINDS`, `._METHODS`, `._METHODS_DEFAULT`

Rendered as a four-column row, joined with a middle dot:

```
Bruno Cardoso "Crow"  ·  a courier  ·  a sidearm fired at contact range  ·  10m
```

### 1a. Enemies — `_ENEMY_KINDS`

**Shape: PHRASE. A singular, indefinite noun phrase naming exactly one person,
carrying its own article.**

* **Opens with `a` or `an`,** agreeing with the *sound* of the next word
  (`an officer`, `an entrenched shooter`, but `a union enforcer`). The checker
  verifies this against `TextUtil.article()`.
* **Never `the`.** The feed lists strangers. `"the last man standing"` claimed a
  fact about the whole engagement that nothing computes, and printed twice in the
  same feed the moment one operator got two kills.
* **Exactly one body.** `"a patrol element"` was a group; the feed then showed
  five lines under a heading that said nine. If the phrase can be more than one
  person, it does not belong here. A crew is fine as long as the phrase names one
  member of it — `a mortar crewman`, not `a mortar crew`.
* No comma, no stop, no `%`.

> ✓ `a radioman calling for fire` — one person, indefinite, postmodified by a
> participle rather than a clause.
> ✗ `a patrol element` — a unit, so the tally stops matching the feed.
> ✗ `the last man standing` — definite, and asserts something unrepeatable.
> ✗ `two men at the gate` — plural.

### 1b. Methods — `_METHODS` and `_METHODS_DEFAULT`

Each entry is `[phrase, min_metres, max_metres]`.

**Shape: PHRASE. An indefinite noun phrase naming the means of the kill.**

* **The article follows countability, and that is a real grammatical test, not a
  style preference.** A countable head takes `a`/`an` (`a short burst`,
  `a knife thrust`). A mass or plural head takes no determiner at all
  (`sustained fire`, `blunt force trauma`, `two bursts`, `three rounds before a
  malfunction`). Ask: *could I say "two of these"?* If yes, it needs an article.
* **Never `the`.**
* **No finite verb.** A noun phrase may be postmodified by a prepositional phrase
  (`a shot from the shadows`) or a participle (`a burst cut short by a jam`), but
  the moment it grows a clause it stops being a phrase and reads as half a
  sentence dropped into a table cell. The checker rejects ` that `, ` which `,
  ` who `, ` they `, ` it `, ` nobody `.
* No comma. The `·` separator already does that work, and a comma inside a cell
  makes the row ambiguous. `"a single round, no follow-up"` became
  `"a single round with no follow-up"`.
* **British spelling**, matching the rest of the codebase: *armour*, *calibre*,
  *centre*, *metre*.
* **The range band must be true of the phrase, not of the weapon.** The same rifle
  kills at 400 metres and at arm's length; the phrase is what says which. A knife
  is `1, 2`. `min >= 1` and `max >= min`, both checked.
* **The phrase must be consistent with the pool it is in.** `_METHODS_DEFAULT` is
  standard issue — a sidearm and whatever is to hand — so nobody in it swings a
  rifle butt they were never issued. A pool keyed to a weapon id may only describe
  that weapon.

> ✓ `a heavy-calibre round through light armour` — countable head, prepositional
> postmodifier, hyphenated compound modifier, British spelling.
> ✓ `spalling from a collapsed wall` — mass head, so correctly no article.
> ✗ `suppressive fire that found a mark` — finite clause.
> ✗ `directed lethal shrapnel` — stacked loose adjectives, and *lethal* is
> redundant: every entry in this list killed somebody.
> ✗ `the shockwave of a close-proximity detonation` — definite.

---

## 2. Mission briefings

A briefing is assembled by `MissionFactory._write_briefing()` in a fixed order
and joined by `TextUtil.sentences()`, which supplies missing stops and single
spaces and nothing else:

```
<opening>  <ground>  [<target>]  <caution>
```

Because every part is joined into one paragraph, **every part is a SENTENCE**,
and each must read correctly with an arbitrary sibling on either side.

### 2a. Openings — `MissionFactory.BRIEFING_OPENINGS`

**Shape: SENTENCE (one or more).**

* **Exactly one `%s`, and it is the place.** The checker enforces the count. Any
  other per-cent sign must be doubled or the format call fails at runtime.
* The place arrives already carrying its lower-case article — "the Donbas
  Corridor", from `RegionData.place()` — so `%s` **must not open a sentence**, and
  the template must never write its own "the" in front of it.
* Ends with a stop. Multiple sentences are fine; the *last* one must end with a
  stop, and so must each one before it.
* Says what the client wants. It must not describe the terrain (that is the next
  sentence's job) or the opposition (that is the caution's).

> ✓ `There is a safe in %s the client would like the contents of, and no story attached.`
> ✗ `%s is where the client wants a door taken off.` — place opens the sentence,
> so it prints "the Donbas Corridor is where…" with a lower-case *the*.
> ✗ `The client wants the %s cleared.` — doubles the article.

### 2b. Ground — `RegionData.description`

**Shape: SENTENCE (one or more), no placeholder.** It lands between two sentences
that both already name the region, so it must not name it again, and must not
open with a connective that assumes what came before.

### 2c. Target job title — `MissionFactory.TARGET_TITLES`

**Shape: PHRASE — a bare singular noun phrase with NO article of its own.**

It is consumed as `"The target is %s, %s" % [name, TextUtil.with_article(title)]`.
The article is supplied for you, and supplied *correctly* — which is why
`union enforcer` prints as "a union enforcer" and not "an". Writing the article
into the entry both duplicates it and defeats the sound test.

It must be a **job**, never a rank used as a name and never a plural: it has to
read after a person's name and a comma.

> ✓ `mine security chief` · `recruiter for somebody else's war`
> ✗ `a customs inspector` — brings its own article.
> ✗ `the Bondarenko brothers` — plural, and definite.

### 2d. Caution — `MissionFactory.CAUTIONS`

**Shape: SENTENCE (one or more), and NO placeholder at all** — this is the only
briefing part that is never substituted, so a `%s` here would print raw.

It always lands last, so it must not open with a connective that expects the
terrain sentence in front of it. It describes the opposition and nothing else.

### 2e. Contract titles — `MissionFactory.TITLES`

**Shape: LABEL.** Title Case, **no closing stop**, no `%`.

* A title is never format-substituted, but it *is* pasted into sentences that are
  — bond reasons say "on Nobody Was There". So it must read as **the name of a
  job**, not of a place: "Got each other out of Nobody Was There" falls apart,
  which is why every bond template frames it with "on" or "how … went".
* **No gendered pronoun.** The title is drawn independently of the target, whose
  name is rolled separately, so `"He Will Be at the Villa"` spent a while sitting
  directly above "The target is Clara Ashcroft". Use they/them or, better, no
  pronoun at all. The checker rejects He/She/Him/Her/His.
* Prefer titles that survive any region and any client, because they get both.

---

## 3. After-action feed

`MissionStory.OPENINGS`, `OPENING_FALLBACK`, and the inline `wins` / `losses`.

**Shape: SENTENCE.** The openings take **exactly one `%s`**, the place, under the
same rules as briefing openings (§2a). The win and loss pools take no placeholder.

The hard rule here is not grammatical, it is factual: **the feed may never assert
something the resolver did not produce.** Every line in `MissionStory.write()`
is guarded by the state that makes it true — a medic line requires a medic and a
wounded operator; a withdrawal gets the withdrawal ending rather than a defeat
line, because the company chose it. When adding a line, find the state that
makes it true and guard on it. If nothing in `MissionReport` makes it true, it
does not go in the feed.

Related: `.docs` aside, this is the same standard as *no unmotivated randomness*
applied to sentences instead of to causes.

---

## 4. Operator descriptions — `OperatorData.resume()`

The one that is read most and broke most often. It builds an `Array` of parts and
hands them to `TextUtil.sentences()`.

**`TextUtil.sentences()` supplies the stops. It does not supply subjects, verbs,
or sense.** A fragment put into `parts` comes out of the paragraph as a fragment.

**Shape: every element of `parts` is a COMPLETE SENTENCE with an explicit
subject** — the operator's label, or "They", or "Their file". This is not a
stylistic preference: `IncidentLibrary._walk_in()` pastes the whole résumé
directly after a sentence of its own, so a run of headings reads as a form rather
than as a person.

> ✗ `With this company: 27 contracts completed, one of them gone wrong.`
> ✗ `41 kills confirmed.` ✗ `Brought on by Reyes.` ✗ `Noted on their file: hothead.`
> ✓ `They have run 28 contracts for this company, one of them lost.`
> ✓ `They have 41 kills confirmed.` ✓ `They were brought on by Reyes.`
> ✓ `Their file carries one note: hothead.`

That last frame is deliberate: the trait names are a mixture of adjectives
(*claustrophobic*), nouns (*hothead*) and verb phrases (*fears assault*), and
"Their file carries one note: X" is the one sentence all three read correctly
inside. Prefer a frame that survives every member of the list it quotes.

### The résumé is a story, and stories may vary

Phrasing is drawn from two pools, `OperatorData.SENIORITY` and
`OperatorData.REPUTATION`, by `_pick(salt, pool)`.

**`SENIORITY` holds PHRASES, not sentences,** because each one completes a frame
that already has punctuation of its own:

> `<label> is <a nationality rank>, and ___.`

So a seniority phrase is lower case, has no closing stop, and **contains no
comma** — "no longer a liability, and not yet an asset" put a second *and* into a
sentence that already had one, and printed as "is a Korean corporal, and no
longer a liability, and not yet an asset". This is the general lesson: **a
fragment must be checked against the punctuation of the frame it lands in, not
just against itself.**

`REPUTATION` holds SENTENCES; each stands alone at the end of the paragraph.

Two further rules govern both:

**The variation must be stable.** `resume()` is called on every roster and
recruit-list redraw. `_pick` seeds a `RandomNumberGenerator` from
`String(id).hash()`, exactly as `portrait_color()` does, so the choice is a
function of *who they are* rather than of *when it was asked*. Prose that
reshuffled on every repaint would not read as a person, and it would not survive
a save/load. **Never call `randf()` or an unseeded RNG from a display function.**
Give each pool its own `salt`, or every pool lands on the same index and an
operator's whole résumé is variant 2 throughout.

**The variation must be earned.** Every pool is gated on a record the player
watched accumulate — `confirmed_kills >= 25`, `saves >= 3`, `trainees >= 2`.
An operator with nothing on their file gets no closing line rather than a
flattering guess. A sentence the player cannot trace back to something that
happened is noise wearing a story's clothes.

**Nothing may contradict a sibling sentence.** These are all real bugs this
function has shipped:

* Seniority read off *career* experience while the next sentence reported
  *company* tenure — "one of the company's old hands" above "has not yet worked a
  contract for this company". Contracts here outrank contracts anywhere else, and
  the two are checked in that order.
* "yet to find out what this job actually is" above "They have one kill
  confirmed" — because the experience total ignored failed contracts. A contract
  that went wrong still taught them something; failures count.
* "one contract completed, one of them gone wrong" — "of them" with no plural to
  point at, describing two contracts as if they were one. The record is now one
  sentence with one arithmetic, and the `of them` branch is only reachable when
  the total is at least two.
* "They worked roughly one contract elsewhere." Nobody estimates "roughly one".
  Any hedge word (*roughly*, *about*, *some*) needs a branch for n = 1.

---

## 5. Character lore

### 5a. Bond reasons — `Bonds.BOND_REASONS`

**Shape: SENTENCE with an explicit subject** — "They", "One of them", "Neither
of them", "Nobody".

The relationships screen prints this on its own line under the two portraits with
no lead-in, so a subjectless fragment ("Blamed each other for how X went.") reads
as a note somebody forgot to finish, and a bare noun phrase ("A disagreement
about an order given on X.") reads as a caption for a missing picture.

**Placeholders are named, not positional:** `{title}` is the name of the job,
`{place}` is where it happened, and the pool is substituted with
`String.format()`. Positional `%s` made the two impossible to tell apart at the
point of writing. Use either, both, or neither. The checker rejects any other key.

Remember §2e: `{title}` is the name of a **job**. "on {title}" and "how {title}
went" both hold; "out of {title}" reads as a location and falls apart.

### 5b. Trait descriptions — `TraitLibrary`

**Shape: ONE sentence, a bare verb phrase in the third person with the operator
as its unstated subject.** The roster prints it directly under the trait name
with no lead-in.

> ✓ `Does not flinch when it matters.` ✓ `Keeps people breathing on the way to the truck.`
> ✗ `Something in the last contract did not come back with them.` — supplies its
> own subject, so it reads as being about somebody else.
> ✗ `Opens fire early. Every time.` — two sentences, the second a fragment.

Generated traits (`TraitLibrary.fear_of()`) reach the same UI and obey the same
rule.

### 5c. Medal notes — `MedalLibrary.MEDALS`

**Shape: SENTENCE.** Printed after an em dash in
`"Awarded the Marksman's Cross — Twenty-five confirmed kills."` It states **the
condition that was met**, in the past tense, with numbers spelled out — it is a
citation, not a description of the medal.

A medal name that already carries its own article ("The Quiet Professional") is
handled by `MedalLibrary._named()`. Do not write "the" into a name to compensate.

---

## 6. Item lore

**There is no random item-history generator yet.** This section is the contract
for the one the post-v1.0 direction calls for — items with owners, kills and a
history. `ItemInstance.contracts` is the hook that already counts, and the
grammar primitives it will need already exist and are already correct.

An item is the hardest noun in this codebase, because the kit list contains
singulars (*a service carbine*), grammatical plurals (*a set of night optics*)
and mass nouns (*supplemental oxygen*), and each takes a different article, verb
and pronoun. **Never write any of those by hand.** `ItemData` decides, from a
listed table rather than a trailing-"s" heuristic, and `ItemInstance` delegates
every one so a sentence never has to know whether it holds a type or a copy:

| Form | Call | Singular | Plural | Mass |
|---|---|---|---|---|
| in prose | `name_in_prose()` | service carbine | night optics | supplemental oxygen |
| indefinite | `indefinite()` | a service carbine | a set of night optics | supplemental oxygen |
| definite | `definite()` | the service carbine | the night optics | the supplemental oxygen |
| verb | `verb_is()` / `verb_was()` | is / was | are / were | is / was |
| subject pronoun | `pronoun()` | it | they | it |
| object pronoun | `object_pronoun()` | it | them | it |

Rules for item history strings:

* **Shape: SENTENCE**, in the past tense, with the item or its owner as subject.
  `TextUtil.sentence_case(item.definite())` opens one correctly; capitalising by
  hand does not, because `String.capitalize()` lowercases everything after the
  first letter and would turn a callsign into mush.
* **Never `"the %s" % display_name`.** Call `definite()`. `display_name` is a
  label for a card; `name_in_prose()` is what goes in a sentence.
* **Agree the verb through `verb_is()` / `verb_was()`** whenever the item is the
  subject. "The night optics **were** signed back in", "the carbine **was**".
* **Use `object_pronoun()` in object position.** `pronoun()` there produces "a
  decision on they".
* **Every line names its cause.** The existing `kit_notes` are the model: a wear
  note fires because a contract wore it past the threshold, and says so. An item
  history entry must be generated from something recorded on the `ItemInstance` —
  a contract it was carried on, an owner who died holding it — never invented.
* **A dead operator's kit comes back.** Any history line must be true of an item
  that has outlived its owner, because that is the case the feature exists for.

---

## Checklist for adding a string

1. Find the list in this document and read the shape it holds. PHRASE or SENTENCE.
2. Write it in the same shape as its neighbours. If the neighbours disagree with
   each other, fix them.
3. Check the placeholder count against the rule for that list. Double any literal
   `%`. Use named `{keys}` where the list already does.
4. Ask what else can appear next to it. Every opening meets every caution; every
   enemy meets every method; every résumé sentence meets every other one. It has
   to be true and grammatical against all of them, not against the one you had in
   mind.
5. Ask what makes it true. If no field on `MissionReport`, `OperatorData` or
   `ItemInstance` makes it true, do not add it.
6. Run `tests/prose_rules.gd`. It must exit clean.
7. Run `tests/sim_prose.gd` and **read the output**.

## What the checker cannot check

It cannot tell you that a line is a lie, that two sentences contradict each
other, that the register is wrong, or that a joke has stopped being funny at the
fortieth reading. It checks that strings *fit*. Whether they are any good is
still decided by reading `sim_prose.gd`'s output, which is why that file asserts
nothing and always will.
