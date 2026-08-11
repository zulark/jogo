# Squad Manager — Build Roadmap

Design source: `.cursorrules/rules.md`. This file tracks how we get there.

## Locked decisions

- **Calendar**: a *day* is a turn, ended by the player when they choose. A *week*
  (`Balance.DAYS_PER_WEEK`) is the upkeep cycle — salaries and fixed costs are
  charged on the week boundary. Missions, crafting, training and healing occupy
  their participants for a number of days, so the player cannot do everything in
  one day. Scarcity comes from people and facilities being tied up, not from an
  action-point pool.
- **Odds are transparent**, XCOM-style. `MissionResolver` never returns a bare
  percentage: it returns a `MissionReport` whose modifier list sums exactly to
  the squad score. If the list stops summing, the breakdown is lying and that is
  a bug.
- **Language**: all code and display strings in English.
- **Division of labour**: scripts *and* scenes can be authored outside the editor
  — `.tscn` is a text format — with UI verified visually via the screenshot
  harness. Art and sprites are the user's. Logic still lives in `RefCounted` and
  `Resource` classes with no scene-tree dependency, which is what lets the
  headless harnesses run at all.

## Layout

```
core/    pure logic, no nodes    balance, resolver, squad, factories, libraries
data/    Resource definitions    operator, trait, mission, profiles
content/ authored .tres          (from v0.2)
ui/      scene scripts           (from v0.2)
tests/   headless harnesses      sim_missions.gd
```

## Versions

### v0.1 — resolver core — **DONE**
Data model, `MissionResolver` with the full scoring formula, casualty rolls, and
a headless balance harness. No UI.

Run the harness with:

```
Godot.exe --headless --path . --import          # after adding any class_name script
Godot.exe --headless --path . --script res://tests/sim_missions.gd
```

**Main scene** is `ui/briefing_demo.tscn` — a sandbox that rolls a random squad
against a random contract so the maths can be felt rather than read off a table.
Press F5, or Space to deploy / draw a new contract. It is not the game loop; it
is a test bench, and v0.2 replaces it as the main scene.

UI can be checked without opening the editor. Both harnesses must run **without**
`--headless` — the dummy renderer produces a blank image.

```
Godot.exe --path . --script res://tests/screenshot_ui.gd     # briefing panel alone
Godot.exe --path . --script res://tests/screenshot_demo.gd   # main scene, both states
```

### v0.2 — core loop — **DONE**
`Campaign` is the rules engine and the only thing allowed to mutate `GameState`:
hire, dismiss, deploy, end day. Days tick deployments, recovery and contract
expiry; every seventh close charges payroll. Dead operators move to the
cemetery. Save/load is JSON under `user://`.

```
Godot.exe --headless --path . --script res://tests/sim_campaign.gd
```

Plays eight weeks headlessly and checks the calendar, orphaned operators, burial,
and a save round trip taken with a squad still in the field.

**Decided**: recruits are an XCOM-style pool that refreshes every week — sign
them or they move on. The mission board instead tops back up, so a contract the
player is saving for does not vanish. Swap point is `Campaign.refresh_recruits()`.

**Main scene** is `ui/hq.tscn`: a header with the numbers that matter, three
tabs (Contracts, Roster, Recruits), and End Day. Picking a contract opens the
squad builder, which is a place you came from the board rather than a fourth
tab. `ui/after_action.tscn` is a modal that queues reports one at a time — a
death should never be a line item scrolling past in a list.

`Game` (`core/game.gd`) holds the live campaign. It is a **static class, not an
autoload**, because autoloads do not exist under `--script`, which would make
every screen that touches the campaign impossible to drive from a harness.

```
Godot.exe --path . --script res://tests/screenshot_hq.gd
```

Walks all four screens plus a real deploy-and-resolve and captures each one to
`.screenshots/`. Not headless — see the note above.

`ui/briefing_demo.tscn` survives as a quick resolver sandbox but is no longer
the main scene; delete it once it stops being useful.

### Visual system
`ui/ui_style.gd` is the whole look: one palette, one type scale, one set of
builders. Screens build list rows in code rather than as tiny scenes, because a
roster row is data-shaped — it changes with the roster, not with the layout.

The direction is **the company's paperwork**, not a dashboard: service records,
contract riders, after-action reports.

- **Numbers are monospace**, right-aligned, in fixed-width `stat()` blocks. This
  is functional, not decorative — figures line up down a list so a column can be
  compared at a glance.
- **Headings are a condensed face**, the way a stencilled label would be.
- **Olive-shifted charcoal**, the colour of a field desk rather than the default
  blue-black.
- **Ochre carries structure and attention** — section eyebrows, the selected
  row's left edge. Mint and rust are reserved strictly for outcomes.
- Fonts come from the OS via `SystemFont` (Consolas / Bahnschrift with
  fallbacks), so there is nothing to import or license. Swap `_MONO_NAMES` and
  `_DISPLAY_NAMES` for real font files at the art pass.

Three traps, all already paid for:

- `UiStyle.identity()` clips its labels. Without that a long name widens its row
  past the column and pushes the stat block off the edge — it cost a render on
  the Training screen's three-column layout.

- A `Button`'s minimum size **ignores its children**. Row content is anchored, so
  a row shorter than its content silently overlaps the row below. Use
  `UiStyle.ROW_HEIGHT` / `ROW_HEIGHT_COMPACT`; do not invent a height.
- A `ProgressBar` inside a `PanelContainer` gets squeezed to a hairline. Style
  the bar's own `background` and `fill` instead of wrapping it.

Content is capped at `HQ.MAX_CONTENT_WIDTH` and centred. Full-width rows force
the eye from a title on the far left to its figures on the far right.

### Nationality and languages
Operators carry a nationality (`NationLibrary`) and a language→fluency map.
Two independent resolver terms come out of it: internal cohesion (a squad that
cannot brief itself coordinates badly) and the local tongue (a speaker earns a
bonus; nobody speaking it is a small nudge, deliberately not a tax). Regions
live in `RegionLibrary` and carry the local language until v0.6 expands them.

Names come from `NameLibrary`, keyed by **culture** rather than nation so
several nations can share one pool. Nationality is rolled before the name, since
it decides both the name and the languages. Korean and Japanese pools render
family-name-first. Callsigns stay culture-agnostic — the company assigns those —
but are unique across the roster and cemetery.

Given-name pools mix masculine and feminine names because operators have no
modelled gender, which is also why the Slavic pools use only surnames that do
not inflect (`-enko`, `-ykh`, `-czyk` rather than `-ov/-ova`, `-ski/-ska`). If
portraits later make gender matter, split the pools then.

### v0.3 — operators become people — **DONE**
`core/progression.gd` owns everything that changes an operator, and every
function returns a plain-English change log. That log is not decoration: a
management game where people quietly improve behind the scenes gives the player
nothing to feel, so the after-action screen shows "Stealth 32 → 33" and
"Left with: Glory Hound" or the whole layer is invisible.

- **Rank** comes from XP against `Balance.RANK_XP`. The field track stops at
  Warrant Officer.
- **The instructor fork** is the design doc's Subtenente decision. Past the field
  cap an operator either stays at that ceiling or leaves the field *permanently*
  for the four instructor ranks, which are earned only by teaching. Instructors
  cannot deploy — `GameState.deployable_operators()` is the filter.
- **Skills** grow at what the contract actually tested, with diminishing returns
  and a field ceiling (`SKILL_FIELD_CEILING`). The last stretch only comes from
  being taught, which is what makes the academy worth its cost.
- **Traits** are earned from outcomes. Trauma always leaves a mark, and it leaves
  a *specific* one: `TraitLibrary.fear_of(type)` generates "Fears Infiltration",
  so one bad night in a tunnel turns an operator into a roster puzzle.
- **Training** costs two operators for a week. The trainee closes part of the
  gap on every skill the mentor beats them at, and may inherit one of the
  mentor's traits — including a bad one.
- **The cemetery** keeps the record: rank reached, contracts, who trained them,
  who they taught, and where they died.

Both factories now seed XP and service record from starting rank. A Sergeant who
arrives with 0 XP would show "0 / 300 toward Corporal" under the word "Sergeant",
and their headstone would read "0 contracts completed".

### v0.4 — pressure — **DONE**
The rotation pressure from the design doc, plus the social layer.

- **Fatigue** accrues per deployed day and with mission risk, and recovers only
  at base — deployed and training operators do not rest, so a class is not a
  free rest cure. It costs score *and* raises harm chance, so running the same
  four people into the ground raises the body count, not just the odds.
- **Morale** swings either side of `MORALE_NEUTRAL`, so a happy squad is worth
  building rather than merely "not broken". It falls on failures, wounds, missed
  payroll, and hardest of all on losing someone they were close to. Below
  `MORALE_DESERTION_THRESHOLD` the roster flags them as considering leaving, and
  each week there is a chance they walk — the warning always arrives with time
  to act on it.
- **Bonds** (`core/bonds.gd`) form between survivors of the same contract.
  Temperament tilts which way: sociable pairs make friends, aggressive ones
  grate, and a failed contract can sour a pairing that would have gone the other
  way. Romance is ~1% per pair per contract, per the doc.

Bonds live on the operators (mirrored on both sides) rather than in a registry,
so `MissionResolver` reads them straight off a Squad without being handed extra
state. **Nothing outside `Bonds` may touch `op.bonds` directly.** On death the
link is stripped one-sidedly: the living stop being scored for a friendship with
a corpse, but the headstone still says who they were close to.

Bond terms are divided by **pair count**, not summed. A squad has n(n-1)/2 pairs,
so summing made bonds scale quadratically with squad size — a squad of six
friends won on arithmetic alone. Caught by the isolated harness, which measured
an 84-point swing between friends and rivals; it is 19 now.

### v0.5 — money — **DONE** (except crafting)
- **Eight facilities**, three levels each, every one wired into a system that
  already existed: the Infirmary shortens recovery days, the Psychologist lowers
  the chance a scar forms (never removes one — the doc is explicit), the Canteen
  pushes morale up weekly, the Academy shortens classes and deepens transfer,
  the Intelligence Centre is flat score on every contract, the Armoury and
  Quartermaster unlock shop tiers, the Warehouse raises storage.
- **The budget sheet** (`core/economy.gd`): salaries, rations, ammunition,
  medical and facility upkeep, itemised, plus weeks of runway. Every line is
  something the player chose.
- **Equipment** in two slots. Almost everything has a downside — plate armour
  costs stealth, a long rifle is useless up close — because a loadout that is
  strictly better than another is not a choice.
- **Reputation** moves contract fees and gates the blackmarket, which ignores
  facilities entirely.

Deferred: repair, durability and blueprint crafting. Everything else in the
doc's economic layer is in.

**Tuning done here, with the reasoning:**
- Contract fees up ~60%. At the old rates the weekly bill ate everything and the
  entire facility layer was unreachable.
- `DEATH_SHARE` 0.18 → 0.10, with wounds absorbing the difference. Deaths were
  quietly the largest line in the budget — every one costs a replacement's
  signing bonus — and an aggressive company buried six operators in twelve
  weeks. Rotation pressure is unchanged because the wound rate is unchanged.
  **This is the single lethality dial; raise it if the game should be harsher.**
- Reputation gain roughly halved. The company used to be famous inside three
  months, which made the blackmarket gate and the fee bonus meaningless.

`sim_campaign.gd` now runs 12 weeks — long enough for the economy to show a
trend rather than one good week — and `_check_market()` tests the shop rules
directly rather than hoping emergent play reaches the Armoury.

### Export
Works. The one catch: **the destination folder must already exist** — Godot will
not create it, and the failure reads only "The given export path doesn't exist."

```
mkdir -p build
Godot.exe --headless --path . --export-release "Windows Desktop" ./build/blackwater.exe
```

### v0.6 — world — **DONE**
- **Regions are places.** Each has its own language, a difficulty and risk shift
  baked into contracts generated there, travel days added to every duration, and
  one skill the ground itself tests. A squad is measured against the middle of
  that skill's range, so bad terrain for these people genuinely costs instead of
  good terrain being free upside. The three dials are independent — somewhere can
  be close and lethal, or far and gentle.
- **Five clients**, each with a preference the resolver scores openly: the Cartel
  punishes numbers, Meridian pays for them, Halberd audits your ranks, the Relief
  Directorate is judged after the fact and drops you savagely when someone dies.
  Standing is per-client and separate from company reputation — you can be famous
  and still be the last people the Cartel would call. Standing also skews who
  turns up on the board.
- **Scouting is an action, not a buff.** The Intelligence Centre is worth nothing
  until a specific contract has been cased, which costs money now and days the
  contract may not have. `Campaign.preview_mission()` only folds in the intel
  bonus once `mission.scouted` is true.
- **Events are consequences.** Every entry in `EventLibrary` is gated on
  something the player did: informants need low morale, brawls need two people
  who already hate each other, prodigies need reputation. Low morale raises both
  the chance of an event and the odds it is a bad one; the Intelligence Centre
  shifts the mix back. Measured over 400 weeks: a miserable company draws 199 bad
  events, a contented one 72, and a miserable one with a maxed Intelligence
  Centre 91.

Contract grades are now **weighted** (34/36/22/8) rather than uniform. With
region shifts stacked on top, uniform rolling produced boards where the easiest
job was difficulty 52 — nothing a new company could take.

Fees go through `MissionData.fee_for()` everywhere. The board was quoting the
reputation-adjusted fee while the briefing quoted the raw one, which is worse
than either being wrong.

### v0.6 — world (original plan)
Regions with modifiers, faction reputation affecting price and availability,
intelligence/scouting, random events.

### v0.7 — idle income and balance — **DONE**
- **Standing work.** Small, safe, badly paid jobs that take one operator and
  resolve themselves. Pay scales with how suited the person sent was, floored so
  even a bad fit earns something. It shares the Contracts screen rather than
  getting its own tab, because the trade-off between a contract and a side job
  is the decision and splitting them would hide it. Deliberately worse money
  than the softest contract — asserted in the harness, because if standing work
  ever competes with contracts the mission layer becomes optional.
- **Retainers.** A client at 45+ standing pays weekly to keep the company on
  call. Free money right up until they call: a call-up lands on the board with a
  five-day fuse, and letting it rot costs a fine plus a great deal of goodwill.
- **Passive production.** An Armoury or Quartermaster at level 2+ turns out
  surplus kit to sell.

The Base screen's budget now shows income against costs and a **net weekly**
figure, and runway is computed from the net — retainers were otherwise invisible
in the one number that decides whether the company is alive.

**Balance pass.** v0.6 quietly broke the economy: region travel days cut contract
throughput and region difficulty shifts cut the success rate, without fees being
re-tuned for either. A twelve-week run ended at **−7368 with the roster down from
seven to three** — and only one of those was a death. The rest deserted, because
one missed payroll crushes morale, which shrinks the roster, which cuts income.
A death spiral with a single entry point.

Fixed by raising fees ~20% and easing the salary curve (3.2 → 2.9 per skill
point). The same run now ends solvent at 3426 with the roster intact and two
facilities built.

Two of those numbers were **agent artifacts, not balance**, and worth separating:
the sim only invested at six weeks of runway (which it never reached, reporting
the base layer as unreachable when it was merely expensive) and never used
standing work at all. Both fixed; the remaining shortfall was the real one.

`sim_campaign.gd` now also generates 200 starting companies and asserts almost
all of them have a contract under difficulty 55. Region shifts stack on top of
grades, and a board with no approachable work is a dead end for a new company —
194 of 200 pass, so the occasional hard board is variance rather than a bug.

### v0.7 — idle income and balance (original plan)
Retainer contracts, passive facility production, auto-resolved low-risk
missions. Full balance pass driven by the harness.

### v0.8 — intel, and a UI that holds its shape — **DONE**

**Intel teams.** The second way to case a contract, and the one that costs people
instead of money. `Campaign.scout()` stays as the desk answer — the Intelligence
Centre buys a look, instantly arranged and only as good as the facility. An
`IntelOp` is the other: one or two operators tied up for days, coming back with
more than the desk could get, and occasionally coming back having been *seen*,
which raises the contract's difficulty and halves what they learned.

- Casing rating is stealth-led, tech-second, with a partner adding a fraction of
  a share rather than averaging in — two mediocre scouts should not out-read one
  excellent one, but they should beat them working alone.
- Exhausted operators **can** be sent. Casing is the one job the field will not
  take them off, which finally gives the player something to do with people no
  contract will have.
- What a case was worth is stored on the contract as `intel_bonus` when it
  finishes, so `MissionResolver` reads one number and never has to know whether
  a desk or a team produced it.
- `IntelOp` serialises a **mission id**, not a mission. Deserialising its own
  copy would have applied `scouted`, `intel_bonus` and the spotted-difficulty
  penalty to an object no squad could ever be sent against. It re-links to the
  live board on load, and returns null if the contract expired while the team
  was out — a real outcome, not an error.

**UI: declared widths are now contracts.** `stat()` and `fatigue_meter()` clip
their labels, which drops their minimum width to zero and leaves the declared
width as the only thing setting the size. Before this a "FATIGUE 71%" caption in
a 52-pixel column silently widened it and took the difference out of whatever
shared the row — so a row changed shape depending on how tired somebody was, and
operator names were the half that lost. `IDENTITY_MIN_WIDTH` is the floor below
which a name stops being a name.

Callsigns moved to the **second line** in list rows. Side by side, the name and
the callsign competed for one row and the name always lost: `Matthias Neumann`
fitted while the shorter `Yamamoto Mizuki` clipped, purely because "Ember" is one
character longer than "Nail".

**Two overflow bugs of the same shape.** The after-action card and the contract
side panel both grew downward without limit — the card until it left the screen,
the panel until it pushed the HQ header off the top *and* the dock off the
bottom, because the shell grows from its centre. An assassination contract did
it with one extra TARGET block. Both now cap their height and scroll internally,
and the screenshot harness asserts on every capture that the header and dock are
still where they belong.

Godot trap worth keeping, and the reason the card was mis-sized twice: a `Label`
with autowrap reports its **minimum** height as though wrapping at one character
per line. A six-line column claimed to need 7966 pixels. Size containers from
laid-out rects after two frames, never from `get_combined_minimum_size()`.

**Confirmation on anything that commits.** Deploying, selling kit, sending an
intel team, sending someone on standing work and dropping a retainer were all one
click from happening and none can be undone. `UiStyle.make_confirming()` arms on
the first press, states what the second will do, and disarms itself after four
seconds so an armed button is never a trap for the next click.

**Contracts say what they want.** Squad size, the roles the job will not go
without, and the skills it tests, all read straight off `MissionProfile` so they
cannot drift from what the resolver does. Mission type and fee are chips at the
top. Finding out that escort work wants five people and a medic by assembling
four and watching the score drop is a puzzle with the pieces face down.

The harness mirrors `hq.gd`'s `Tab` enum by hand and it had already drifted:
`TAB_CEMETERY` pointed at Clients, so a screenshot named "cemetery" was of
another screen and nothing complained. `_check_tabs_match()` reads the real enum
off the script and asserts the mirror.

### v0.9 — full-bleed, and three numbers that meant different things — **DONE**

Screens run edge to edge with a 16-pixel gutter. The centred 1180 column went
because the base is going to be a drawn place behind this UI, and a column
floating in the middle of a painted hangar reads as a website laid over a game.
The cost is real — a very wide row makes the eye travel — and the answer is
**fixed panel widths and wrapping text**, not a narrower page:

- `DisplayServer.window_set_min_size()` sets a floor, so a layout that fits once
  fits always.
- The contract side panel is pinned at 430 and does not expand.
- **Every label in a panel wraps or clips.** This is the rule that makes fixed
  widths work: an unwrapped label's natural width becomes its panel's minimum
  width, and the panel takes it out of whatever shares the row. One unwrapped
  hazard sentence — "Heat country. Without the kit that cancels it…" — was
  enough to squeeze the world map beside it.

**Threat, Risk and Readiness read as three versions of the same number.** They
are three different questions:

- **Threat** — how hard the opposition is. Now the headline: in words *and*
  skulls (`Hard ☠☠☠··`), on its own line, because it is what the squad score is
  measured against.
- **Danger** (was Risk) — how likely the people you send come home hurt. A quiet
  job in a lethal place is low threat and high danger; the old naming made that
  pair unreadable.
- **Chance of success** (was Readiness) — the only one the player acts on
  directly, so it says what it is.

**Standing work works like Contracts now.** Every row used to carry its own
operator dropdown and Send button while the side panel showed a title and a
description — the list was where you acted and the panel was decoration, the
reverse of Contracts mode two clicks away. Selecting a job now fills the panel
and the panel is where it gets staffed, candidates sorted by suitability.

### v0.10 — the day became a decision — **DONE**

**The problem this fixes.** A day was a turn, but on most days there was exactly
one action worth taking — deploy or don't — and then End Day was pressed
repeatedly while timers ran down. Contracts take 4–7 days, training a week,
intel 3–5. The real play pattern was *one decision, then five presses of a
button*. Standing work, intel and the market all added decisions **around** the
loop rather than **inside** it.

**Daily incidents** (`core/incident_library.gd`). Something lands on the desk on
roughly a quarter of days, with a two-day cooldown, and stops the player. Three
rules, and they are the design:

- **Gated on something true about the company.** Nobody asks for leave who is
  not unhappy; no informant turns up for a contract that is already cased; no
  creditor calls unless the books are red. An incident that could fire on day
  one of any save is weather, not consequence — the same standard `EventLibrary`
  is held to.
- **Every option states its price before it is taken.** The odds screen makes
  that bargain with the player everywhere else; an incident that hid its cost
  would be the one place it is broken. The harness asserts every option of every
  incident carries a non-empty detail line.
- **No free option.** Refusing leave costs morale, granting it costs days.
  An incident where one choice dominates is a message box in a decision's
  clothes.

Eight to start: leave requests, barracks fights, rush jobs from a client who
likes you, a walk-in recruit, an early discharge from the infirmary, an
informant selling intel, worn kit, and a creditor at the door.

The modal resolves in two beats — choose, then read what the choice did —
because applying and closing in one motion makes it feel like a message box that
happened to have buttons. Incidents queue *behind* the debrief: a squad coming
home is the bigger news.

**A base you can lose.** Facilities were a one-way ratchet — once bought, no
decision left in them for the rest of the run, so money stopped mattering after
the buying phase. Two consecutive weeks closing in debt now cuts the most
expensive facility down a level, refunding 40% of that level's cost. One bad
week is a warning with a week to trade out of it, which the harness asserts
separately: a single unlucky contract must not wreck a run.

### v0.11 — nothing happens without a reason — **DONE**

The rule was always stated and only half kept. An audit found six of the eight
bad events gated on *presence* rather than *cause*:

| event | was | now |
| --- | --- | --- |
| theft | `inventory.size() > 0` | somebody unhappy enough to have a motive |
| gear failure | `inventory.size() >= 2` | kit that was actually carried last week |
| illness | `roster_size() >= 3` | worn-out people, or no infirmary |
| client dispute | `not faction_standing.is_empty()` | a client already disappointed |
| supply shortage | `reputation < 90` | `reputation < 35` — nobody deals with unknowns |
| generator failure | has a base and money | a base running on a week's runway or less |

"You own something" is not a reason. A player who loses a suppressed pistol out
of a clear sky has no way to connect it to anything they did, and unattributable
misfortune is noise rather than difficulty. The good events got the same
treatment: salvage, caches and commendations now require a squad to have
actually been out, and a "quiet week" cannot fire in a week somebody deployed.

Two supporting changes made those conditions expressible:
`GameState.deployed_last_week` (the activity counter is reset before events roll,
so nothing could ask "was anyone in the field?"), plus `average_fatigue()` and
`lowest_morale()`.

**Every event that destroys kit now goes through `_spare_item()`** — only
something nobody is carrying can be lost — **and every one names its cause in
the text.** "X went missing overnight. Nobody saw anything, and morale here has
been bad for weeks" is a consequence; "X went missing from storage overnight" is
a dice roll.

Guarded by three checks, because this is exactly the kind of rule that decays:
a company with nothing wrong with it (content, rested, well regarded, liked by
its clients, no rivalries, a doctor, out of debt, idle) must draw **no** bad
event; a company that has earned trouble must be able to draw at least four; and
kit somebody is carrying can never be taken. The first of those caught
`generator_failure` still firing on a healthy company after the first pass.

Incidents got an anti-repeat rule as well — a contented company legitimately has
few it can draw, and without it a quiet month produced the same walk-in seven
times, which reads as a bug rather than as quiet.

### v0.12 — the contract became a decision too — **DONE**

v0.10 fixed the *day*. This fixes the *contract*. Deploying was a real decision —
the odds screen is the best thing in the game — and then four to seven days
passed in which the player did nothing about the squad they had committed. The
mission was a bet placed at the door and collected at the debrief.

**Field events** (`core/field_event_library.gd`) are the squad calling in with
something the briefing did not cover. Roughly one per contract (83% of contracts
carry one, measured), never two, never on the day it resolves. Same three rules
as the desk incidents, because they are the same promise:

- **Gated on this contract and these people.** No patrol turns up in front of a
  squad that did not come to be quiet; the job is only bigger than briefed if
  the player never cased it; nobody argues on the radio who was not already
  rivals; the ground only turns on people who came without kit for it. A
  situation that could fire on any contract is weather.
- **Every option quotes its price in the units the player already reads** —
  "Odds 58% → 64%. Danger +6", "One more day in the field", "450 diamonds",
  "standing +4". Not a hint, the number.
- **No free option.** Time, danger, money, score, standing or somebody's
  condition: each choice spends one, and the interesting shape is when the two
  options spend *different* ones, because then there is no dominant answer.

**The engineering rule that keeps it honest.** Nothing edits the odds. A
decision appends a `Modifier` to the frozen report and the score is re-summed
from the list — `MissionResolver.recompute()`, which `preview()` now ends with
too, so there is one path. `chance_for()` was pulled out of it so an option can
quote what it will cost from the *same curve* that will later produce it, rather
than approximating. The harness reads the percentages back out of the button
text and asserts both halves: the left number is the odds before the click, the
right is the odds after, and the breakdown still sums to the squad score.

**Two new verbs**, both of which existed nowhere before:

- **Pull somebody out.** They walk to the extraction point and take no further
  part. It costs *exactly* what they were contributing — summed off the
  breakdown by operator id, not estimated — and it is the only thing in the game
  that makes an operator unkillable for the rest of a contract. Worth it for
  someone who should never have been sent.
- **Call the contract off.** A failure and priced as one: part fee, reputation,
  and the client told why. But it is not the same failure as being beaten —
  measured over 200 contracts, breaking contact killed 37 against 244 for losing
  outright. A contract that turns out worse than the brief is now survivable at
  a price, instead of a bet that cannot be laid off.

**The save trap, and a bug it turned up.** `Deployment.from_dict` rebuilds the
report by re-running `preview()` against the live roster — it is not serialised,
because it must point at the same operator objects the roster holds. Anything
that changed the report *after* the preview therefore has to be replayed on
load, or saving mid-contract silently undoes whatever the player decided out
there. While fixing that: the same reload was already dropping `intel_bonus`,
so a contract cased before a save came back uncased in the odds and nothing said
so.

**The modal queue is now re-entered rather than run once.** A decision can end a
contract, so calling one off produces a debrief that has to be read before
whatever was queued behind it — squads home first, then the week's news, then
the decisions still waiting.

Three small honesty fixes fell out of looking at the result:

- A called-off contract said "CONTRACT FAILED · rolled 100 against 76%". No dice
  were thrown; the player made the call. It reads "CONTRACT CALLED OFF · ended
  from the field at 76%" now.
- Against the 95% ceiling a −3 buys nothing, and "Odds 95% → 95%" reads as a
  broken label rather than as the truth it is. It says "Odds hold at 95%".
- Kills are scaled down on a withdrawal. They were leaving, not fighting
  through, and the feed should not report a battle they declined.

Eight situations to start. Three of them — a worn-out operator, two people at
each other on the radio, and a moving target — need a company that has been
played rather than a fresh one, which is exactly the point; the harness asserts
that a cased contract staffed with rested, suitable people in benign country
draws **nothing**, and that a blind one with tired mismatched rivals draws six.

### v0.13 — the kit became a decision — **DONE**

The last system in the design doc (section 4, Lojas): the Armoury and
Quartermaster repair kit and build it from blueprints found as loot. It needed
durability first, and durability needed the refactor the post-v1.0 notes below
had already flagged as blocking everything — `state.inventory` was an array of
item *ids*, which can say the company owns two carbines but never that one of
them came back from the Kivu Border at 31%.

**Kit is copies now, not types.** `ItemInstance` is one specific rifle: a uid, a
condition, a ceiling, and a count of the contracts it has been on. Operators
hold instances rather than ids, re-linked against the inventory on load the same
way a deployment's squad is re-linked against the roster. Two people can no
longer be issued the same rifle — a claim the harness could not previously even
express. A save written before this opens fine: an array of plain ids comes back
as new copies, and an operator's old `weapon_id` claims any unheld copy of that
type, because taking an upgrading player's equipment off them is the worst
possible way to find out the game gained a system.

**The rule that stops durability being a chore.** Benefits scale with condition;
drawbacks do not. A worn plate carrier still costs the stealth it always cost,
still weighs what it always weighed, and stops less than it used to — so
neglected kit is eventually *worse than carrying nothing*, and the odds screen
says so in the units it already uses: "Battle Rifle (poor) · Combat +5" where it
used to read +13. Below 20% an item is unserviceable: no upside, all downside,
cannot be issued, and named on its own line in the breakdown, because a cost
with no line to explain it is the one thing that screen promises never to do.

**Wear traces to the contract.** Days in the field, the contract's danger, and
whether it came off. Kit on the rack does not rot — an item that decays with the
calendar would be a tax on time passing rather than a consequence of the work
the player took, which is the standard every event and incident is held to. Kit
carried by somebody killed is *recovered*, badly damaged, not lost: burying an
operator is expensive enough, and a rifle outliving the person who earned its
reputation is the whole point of the item histories this is groundwork for.

**A bench is the scarce thing, not the money.** Each shop runs one bench per
level. Booking a repair takes the item off whoever was carrying it and hands it
straight back when the job lands, so the price is that they are without it for
three days — not a chore for the player to remember. Kit in the field cannot be
worked on at all; those people are three days away with it.

Two prices, both stated on the button: diamonds, and days. A third is stated in
the row beneath it — every repair takes a permanent slice off the item's
ceiling, so a rebuilt rifle is never a new one. That slice is **proportional to
the damage put right**, not flat per visit: a flat charge would make topping
something up at 90% cost the same ceiling as rebuilding it from 20%, which makes
careful maintenance strictly worse than neglect. That is a gotcha, not a
decision. Priced by damage, the question goes back to being whether to spend the
money and the bench at all.

**Salvage closes the loop.** Kit past rebuilding is stripped for parts rather
than being a dead row in the inventory, and parts are what the next thing gets
built out of. One integer with one source and one sink — a second full resource
economy would be exactly the inventory management this game keeps refusing.
`gear_failure` now strips rather than destroys, for the same reason.

**Blueprints are the reason to take the harder contract.** Four items nobody
sells, found only on contracts above difficulty 52 that actually came off, known
permanently once found. Each has a sharp edge, because kit that is simply better
than the shop's is the end of a loadout decision rather than one: the Shop-Built
SMG is quiet *and* good in a fight and jams (+4% harm); the Composite Harness
buys most of a plate carrier's protection for a fraction of its stealth cost and
less of its endurance; the Rebuilt Optics see in the dark and weigh like a brick.

**Tuning, and the number that mattered.** The first pass at wear swung the
twelve-week sim from **+6892 solvent to −4493 bankrupt**, and the repair bills
were not the reason: weaker kit lowered the odds, which cost contracts, which
killed people — the same single-entry death spiral v0.7 had to dig out of. Kit
is a running cost, not a second lethality dial. Wear per day 3.1 → 1.7, repair
at 26% of price rather than 42%. The run now closes at 6384 with the roster
intact, average kit condition 61%, nothing unserviceable, and six jobs on the
bench costing 686 over twelve weeks.

Two of those were **agent artifacts** and worth separating, because the pattern
is now familiar: the sim repaired anything below its ceiling, including rifles
at 95% — burning a bench and a slice of ceiling for five points — and it only
ever maintained *spare* kit, so the squad's own equipment rotted untouched while
the rack stayed pristine. Both fixed. An agent that plays worse than a player
reports a system as more expensive than it is, exactly as v0.7's sim reported
the base layer as unreachable when it was merely expensive.

**The v0.5 rule that got reversed.** Stock listed one row per item *type* with a
count, because twelve identical carbines should be one line saying twelve. Twelve
carbines at twelve different conditions are twelve things, and collapsing them
hides the only fact on the screen worth acting on — so Stock is one row per copy
now, worst first. The Market's owned column still groups by type, because that
column answers "do we already own one of these" while looking at a price tag.

`_worn_kit` was the one incident that had been describing this system before it
existed ("past its best" against an item with no condition). It now acts on the
genuinely worst thing on the rack, and what it sells is *speed* — a rush refit
tonight without tying up a bench, priced above what the bench would charge.

### v0.14 — the base became a place — **DONE**

The HUB, in 3D, which is what the post-v1.0 note below always meant. The Base
screen was eight rows in a list. The rows were correct and told you nothing: a
company that has poured nine thousand diamonds into an Academy should be able to
*see* it, and a base with an empty plot where the Infirmary belongs should look
like one. The skyline is the balance sheet — building height is facility level,
so a base that has been invested in is visibly taller than one that has not.

**Thirteen plots, and five of them are not facilities.** The pad, the gate, the
barracks, the front office and the memorial exist so the base is the whole of
the company rather than most of it: contracts leave from the pad, people turn up
at the gate, the dead are at the memorial. Every plot opens the screen it
belongs to, so the base is now a complete second route through the game rather
than a decorated version of one tab. The Psychologist opens nothing, because it
has no screen — a greyed-out button under it would be a promise the game does
not keep.

**Every plot says what is happening inside it.** "1 recovering", "0 of 2 benches
busy", "morale 68", "4 recruits waiting", "3 buried". That line is the whole
difference between a model of a base and a base, and it is generated from the
same function the side panel prints, so the label above a building and the panel
beside it cannot disagree. Three of those lines went out in the first version
reading "2 recoverings", "2 burieds" and "0 of 2 benchs busy" — `TextUtil.count`
pluralises by adding an s, which is invisible in code and the only thing you see
on screen.

**The art seam is the point of the blockout.** `base_world.tscn` holds a
`Marker3D` per plot and nothing else — drag them in the editor to rearrange the
base. Drop a mesh scene named `Model` under a plot and it is used instead of the
placeholder box; the collision, the label, the selection highlight and
everything the panel knows go on working, because none of them depend on the
geometry. The boxes exist to be thrown away.

**Camera input is handled by the hub, not by the viewport's physics picking.**
Left-drag orbits, right-drag pans along the ground rather than the screen, wheel
zooms, and a click only selects if the cursor moved less than five pixels —
otherwise a selection fires at the end of every camera swing. Picking is a
manual raycast for the same reason: one owner for the press means a drag and a
click can never both claim it.

The old `base_screen.gd` is gone. Its weekly bill is the hub's default panel —
nothing selected shows the company's books, because every upgrade adds a line to
that sheet and the cost of expanding should never be on another screen — and its
facility list survives underneath as a compact summary whose rows turn the camera
to the building they name. A list and a base that never agree with each other
would be worse than either alone.

`Tab.CONTRACTS` is still the landing screen. The board is where the game is
played and that felt like the user's call rather than a side effect of this
work; it is one line in `hq.gd` (`_current_tab`) if the base should be what
opens first.

**The screenshot harness is seeded now.** It asserts as well as captures, and
unseeded it started a random company — so the steps that need a squad in the
field to photograph sometimes found none and printed a check failure that meant
nothing but the dice. A visual check tool that cries wolf gets ignored, and one
whose output changes run to run cannot be compared against yesterday's.

### Remaining for v1.0

Nothing. Every system in the design doc is in.

### After v1.0 — agreed direction

- ~~**A 3D map**: the base as a navigable place.~~ Landed in v0.14. What is left
  is art: replace the placeholder boxes with models, and the operators living in
  the base rather than being counted by a label above it.
- **Items with histories**, Dwarf Fortress style: a maker, a chain of previous
  owners, a confirmed kill count, the contracts it was carried on — and kit
  handed down between operators, so a rifle outlives the person who earned its
  reputation. **The refactor this was waiting on landed in v0.13**: the
  inventory is `ItemInstance` copies now, each with a uid, and one of them
  already counts the contracts it has been carried on. What is left is the
  record — owners, kills, the maker — and a screen that reads it.

### The HUB — **DONE in v0.14**
The base as a navigable place rather than a menu, MGSV Mother Base style. Built
in 3D rather than the 2D this section originally assumed. The half still
outstanding is *"see the roster living in them"*: the facilities report what is
happening inside as a line of text, and the operators themselves are not yet
figures standing in the base. That wants art before it wants code.

### Testing pattern worth keeping
Both harnesses now follow the same shape: `sim_campaign.gd` proves the loop does
not corrupt itself over eight weeks, and `sim_missions.gd` proves each mechanic
**changes the odds in the right direction**, isolated — same operators cloned,
one variable altered. The campaign sim would have happily reported green while
bonds were 4x too strong; only the isolated comparison caught it.

## Known tuning debt

- Casualty rates out of v0.1 are high: on a STANDARD contract a 4-operator squad
  averages roughly one casualty per mission and a ~25% chance of losing someone
  outright. Knobs are `Balance.DEATH_SHARE`, `Balance.ENDURANCE_MITIGATION` and
  `MissionFactory`'s risk bands.
- A single squad cannot pay for itself. Eight simulated weeks ran only five
  contracts — injuries and mission duration leave the company idle most days —
  and the balance fell from 9000 to 1482 against a payroll of 1600 a week. The
  design doc's own answers are rotation (v0.4 fatigue) and auto-resolved
  low-risk work for idle operators (v0.7). Until one of those lands, either the
  starting roster needs to be larger or payroll needs to be smaller.
- Mission profiles currently live in `MissionProfile.defaults()` in code. They
  move to `content/mission_profiles/*.tres` in v0.2 so they are tunable in the
  inspector; `MissionResolver.set_profiles()` is the seam.
- Traits likewise live in `TraitLibrary` and move to `content/traits/*.tres`.
