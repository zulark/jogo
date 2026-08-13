class_name Balance
extends RefCounted

## Every tuning number in the game lives here. Nothing else should hardcode a
## constant. When the simulation harness says the game is too easy or too
## lethal, this is the only file that changes.


# --- Success probability -----------------------------------------------------

## How sharply squad quality converts into odds. A squad scoring SPREAD points
## above the mission difficulty sits at roughly 73% success. Lower = swingier.
const SPREAD := 14.0

## Odds are never certain in either direction. Keeps every mission a gamble.
const MIN_SUCCESS := 0.05
const MAX_SUCCESS := 0.95

## Split between "does this operator have the skills the mission needs" and
## "does this operator suit the role they were assigned". Must sum to 1.0.
const MISSION_SKILL_WEIGHT := 0.6
const ROLE_SKILL_WEIGHT := 0.4

## Flat score added per rank step above Private.
const RANK_BONUS_PER_STEP := 2.0

## How much less each additional operator contributes than the one before, once
## the squad is sorted best-first. The first person carries the job; the fifth
## helps at the margin.
##
## This replaced a flat average, which had the pathological property that adding
## anyone below the squad's current mean LOWERED the odds — so a player who
## brought more people watched the number fall. With descending weights over a
## fixed denominator (see MissionProfile.contribution_denominator) every added
## body is a non-negative gain, and "this job needs five people" falls out of the
## arithmetic instead of needing a penalty bolted on beside it.
const SQUAD_CONTRIBUTION_DECAY := 0.75


## Leader's LEADERSHIP skill is multiplied by this and added to the squad score.
## At 0.12 an elite leader (90) is worth about +11 points.
const LEADER_FACTOR := 0.12

## Cost per point of personality distance from the mission's preferred value,
## scaled by the profile's own per-axis weight.
const PERSONALITY_COST := 0.12


# --- Casualties --------------------------------------------------------------

## A failed mission is this much more dangerous than a successful one.
##
## Applied to the operator's EXPOSURE — what is left of the contract's danger
## after their own skill, kit and intel have been taken off — and not to the raw
## danger. The difference matters more than it looks. Multiplying first and
## subtracting after meant a veteran and a rookie both landed above the 95% clamp
## on any failed hard contract, so the entire top half of the survival curve did
## nothing exactly when the player needed it most: every investment in keeping
## people alive was worth the most on quiet jobs and worth nothing on the
## disasters. Mitigating first makes being good at surviving pay MORE when it
## goes wrong, which is the only version of this that reads as fair.
const FAILURE_DANGER_MULT := 1.7

## Fraction of an operator's survival score subtracted from the danger roll.
const ENDURANCE_MITIGATION := 0.35

## Survival score is a blend of ENDURANCE and COMBAT.
const SURVIVAL_ENDURANCE_WEIGHT := 0.6
const SURVIVAL_COMBAT_WEIGHT := 0.4

## Of the total harm chance, how much is death vs. wound vs. trauma.
## These are shares of the harm band, not absolute probabilities.
##
## Death was at 0.18 through v0.1-v0.4 and it was too high: an aggressive company
## buried six operators in twelve simulated weeks, and since every death costs a
## replacement's signing bonus it was quietly the largest line in the budget.
## Wounds absorbed the difference, so the pressure to rotate is unchanged — you
## still lose people from the roster constantly, you just get them back.
##
## Then DEATH_SHARE_PER_RISK and DEATH_SHARE_ON_FAILURE were bolted on beside it
## and quietly undid the whole correction: with the base at 0.11, an ordinary
## 45-risk contract already computed 0.227 and a failed hard one 0.42, both well
## past the 0.18 this comment calls too lethal. The twelve-week harness buried
## EIGHT of a seven-person company while winning eighteen of its twenty
## contracts, which is the exact death spiral the design brief forbids.
##
## The rule the three constants below now follow: THE PLAYER CHOOSES RISK, THE
## DICE CHOOSE SUCCESS, so severity is driven mostly by the number printed on the
## board and only lightly by the coin flip. A milk run that goes wrong sends
## people to the infirmary; a job the player was warned about buries them.
const DEATH_SHARE := 0.03

## Added to the death share by how lethal the contract was. A 90-risk job that
## goes wrong should bury people; a 20-risk one mostly should not. This is what
## makes the RISK column on the board mean something concrete — and it is now the
## DOMINANT term, so that column is the lethality dial the player actually reads.
const DEATH_SHARE_PER_RISK := 0.0022

## Added again when the contract actually failed. Losing is when people die —
## but the failure roll is the part the player does not control, so it leans on
## the scales rather than doubling them.
const DEATH_SHARE_ON_FAILURE := 0.06

## Hard ceiling on the three terms above, after the medic. Nothing the dice can
## arrange makes more than this fraction of a squad's casualties fatal: the
## worst contract in the game losing a third of its wounded is a catastrophe, and
## a catastrophe the player can still rebuild from is the difference between hard
## and unfair.
const DEATH_SHARE_MAX := 0.30

const WOUND_SHARE := 0.55

## A medic in the squad reduces every operator's harm chance by this fraction.
const MEDIC_HARM_REDUCTION := 0.25

## And this fraction of what is left of the death share — which is the thing a
## medic actually does. Stopping a wound from becoming a body is their whole job,
## and until now the role bought a flat cut to getting hit at all, which is the
## one thing a medic cannot help with. Together with the line above, taking a
## medic is the clearest survivability decision on the squad screen.
const MEDIC_DEATH_SHARE_RELIEF := 0.30

const WOUND_DAYS_MIN := 2
const WOUND_DAYS_MAX := 14
const TRAUMA_DAYS_MIN := 3
const TRAUMA_DAYS_MAX := 10


## Extra harm chance, in percentage points, for an operator who goes into a
## hazardous region without the kit that cancels it. Cheap to counter, painful
## to ignore — which is the whole point of counter-kit existing.
const HAZARD_HARM := 13.0

## And what it costs the squad's odds, per uncovered operator.
const HAZARD_SCORE := 2.4

## Morale for an operator who pulled a squadmate out. Keeping people alive
## should feel as good as killing people does.
const SAVE_MORALE := 9

## And for the person who was saved.
const SAVED_MORALE := 6

## Morale an operator gains from a heavy day's work, per kill, capped.
const KILL_MORALE_PER := 2
const KILL_MORALE_CAP := 10

## Morale a whole company gains when one of theirs kills someone important.
const TROPHY_MORALE_COMPANY := 6

## And what it does for the operator who actually did it.
const TROPHY_MORALE_KILLER := 22

## Extra morale for the killer of a named target, on top of the trophy award —
## a legend is made in one afternoon.
const TROPHY_MORALE_LEGEND := 12

## Reputation for a named kill. This is what the company becomes known for.
const TROPHY_REPUTATION := 6


# --- Rewards and progression -------------------------------------------------

## Fraction of the full reward paid out when the mission fails.
const FAILURE_REWARD_RATIO := 0.2

const XP_ON_SUCCESS := 100
const XP_ON_FAILURE := 40

## Bonus XP fraction for surviving a mission above your rank's usual difficulty.
const XP_DIFFICULTY_FACTOR := 0.01

## Cumulative XP for each Rank, indexed by the enum. The first six are reached
## by working contracts; the last four only by teaching.
const RANK_XP := [0, 300, 750, 1400, 2300, 3500, 5200, 7400, 10200, 13600]

## XP an instructor earns for seeing one trainee through.
const XP_PER_TRAINING := 320


# --- Skill growth ------------------------------------------------------------

## Points a skill gains at zero, before diminishing returns. The actual gain is
## scaled by how heavily the mission leaned on that skill and by how much room
## is left — going from 20 to 25 is easy, 90 to 95 is not.
const SKILL_GAIN_BASE := 5.0

## Failure still teaches, just less.
const SKILL_GAIN_FAILURE_RATIO := 0.45

## Nobody self-improves past this in the field; the rest comes from training.
const SKILL_FIELD_CEILING := 88

## Mastery. Once a skill is filled, further learning converts into a star and the
## bar starts again — the operator never gets worse for it, because a starred
## skill is read as maxed PLUS a bonus per star. Five is the ceiling.
const MAX_SKILL_STARS := 5

## What each star is worth on top of a filled skill.
const STAR_BONUS := 6

## How much an operator's own role counts toward what they practise, on top of
## what the contract tested. A scout learns stealth on any job.
const ROLE_SKILL_GROWTH := 0.5


# --- Traits earned in the field ----------------------------------------------

## Trauma always leaves a mark. That is the point of it.
const TRAIT_CHANCE_ON_TRAUMA := 1.0

## A contract won by a wide margin can leave someone better than it found them.
const TRAIT_CHANCE_ON_TRIUMPH := 0.20

## Coming home from a failure, unhurt but shaken.
const TRAIT_CHANCE_ON_DISASTER := 0.22

## Success margin (percentage points over the odds) that counts as a triumph.
const TRIUMPH_MARGIN := 25.0

## An operator carrying more than this is a character, not a stat block. Past it
## they stop collecting.
const MAX_TRAITS := 5


# --- Training ----------------------------------------------------------------

## Days both mentor and trainee are off the board. Training costs the company
## two people, which is what makes it a decision rather than free upside.
const TRAINING_DAYS := 7

## Fraction of the gap between mentor and trainee closed per session, per skill.
const TRAINING_TRANSFER := 0.30

## Training is the only route to a filled skill, and therefore to stars.
const TRAINING_SKILL_CEILING := 100

## Chance the trainee picks up one of the mentor's traits — good or bad. A hard
## veteran teaches their flinches along with their marksmanship.
const TRAINING_TRAIT_CHANCE := 0.30

## Minimum rank gap for one operator to teach another anything.
const TRAINING_MIN_RANK_GAP := 2


# --- Fatigue -----------------------------------------------------------------
#
# The design doc's rotation pressure. Running the same four people back to back
# should degrade them, so the answer to "who do I send" changes week to week and
# the rookies eventually have to go out. Fatigue is the mechanism.

const FATIGUE_PER_DEPLOYED_DAY := 9.0

## Dangerous work is more tiring than long work.
const FATIGUE_RISK_FACTOR := 0.10

## Recovered per day spent at base, not deployed and not in a class.
const FATIGUE_RECOVERY_PER_DAY := 7

## Score lost by a completely spent operator.
const FATIGUE_PENALTY_MAX := 18.0

## Extra harm chance, in percentage points, at full fatigue. Tired people get hurt.
const FATIGUE_HARM_MAX := 14.0

## Above this the roster screen flags them as needing rest.
const FATIGUE_WARNING := 60

## At this point no contract will take them. Standing work and training still
## will, so an exhausted operator is not useless — just not deployable.
const FATIGUE_EXHAUSTED := 100


# --- Age ---------------------------------------------------------------------

## A year of game time. Operators have a birthday every this many days.
const DAYS_PER_YEAR := 364

## Physical skills begin to slip from here.
const AGE_DECLINE_START := 38

## Points lost per year past that, on COMBAT, STEALTH and ENDURANCE only.
## Judgement does not decay, which is what makes an old operator worth keeping
## as an instructor instead of worth firing.
const AGE_DECLINE_PER_YEAR := 2


# --- Morale ------------------------------------------------------------------

const MORALE_START := 65

const MORALE_ON_SUCCESS := 9
const MORALE_ON_FAILURE := -13
const MORALE_ON_WOUND := -7

## Losing someone you were close to is the heaviest thing in the game.
const MORALE_ON_FRIEND_DEATH := -22
const MORALE_ON_PARTNER_DEATH := -38
const MORALE_ON_RIVAL_DEATH := -4

## Morale drifts back toward this each week — nothing stays raw forever.
const MORALE_NEUTRAL := 55
const MORALE_DRIFT_PER_WEEK := 3

## Missing payroll is felt by everyone, immediately.
const MORALE_UNPAID := -16

const MORALE_BONUS_MAX := 10.0
const MORALE_PENALTY_MAX := 15.0

## Below this an operator is considering walking, and the roster says so.
const MORALE_DESERTION_THRESHOLD := 20

## Weeks of pay owed to someone you let go.
const SEVERANCE_WEEKS := 2

## Weekly chance an operator that unhappy actually leaves. Low on purpose: the
## warning needs to arrive with enough time to do something about it.
const DESERTION_CHANCE := 0.20


# --- Bonds -------------------------------------------------------------------

## Chance any given pair on a contract forms or deepens a bond.
const BOND_FORM_CHANCE := 0.28

## Of the bonds that form, how many are romances. The doc is explicit that this
## must stay very low, so the effective rate is about 1% per pair per contract.
const BOND_ROMANCE_SHARE := 0.04

## Chance a pairing that would have become friends instead sours, when the
## contract failed. Blame gets assigned after a bad night — but most people who
## survive something together do not come out of it hating each other, so this
## is deliberately low.
const BOND_BLAME_ON_FAILURE := 0.16

## Baseline odds a new bond is friendly rather than hostile, before temperament
## pushes it either way. Above half on purpose: rivalry should be the exception
## that makes a roster interesting, not the default state of the company.
const BOND_FRIENDLY_BASE := 0.66

const BOND_STRENGTH_GAIN := 18
const BOND_STRENGTH_MAX := 100

## Score effect at full strength, for a squad where EVERY pair has this bond.
## The resolver divides by pair count, so these are the ceiling rather than a
## per-pair sum — a lone rivalry in a big squad is diluted, which is right.
const BOND_FRIENDSHIP_BONUS := 8.0
const BOND_ROMANCE_BONUS := 12.0
const BOND_RIVALRY_PENALTY := 11.0


# --- The world ---------------------------------------------------------------

## Score per point of the region's emphasis skill above (or below) the middle of
## the range. At 0.18 a squad averaging 80 in the right skill gains ~5.4, and one
## averaging 25 loses ~4.5.
const REGION_EMPHASIS_FACTOR := 0.18

## Client preferences.
const CLIENT_DISCREET_IDEAL := 3
const CLIENT_DISCREET_PENALTY := 5.0
const CLIENT_OVERWHELMING_IDEAL := 4
const CLIENT_OVERWHELMING_BONUS := 3.0

## How far past their ideal a show of force keeps paying. Uncapped, this was the
## one term in the game that rewarded stacking bodies without limit: on an
## assault contract eight operators cost -4 to squad size and earned +12 here, so
## the answer to a client who likes numbers was always "bring everyone", which is
## the opposite of a composition decision.
const CLIENT_OVERWHELMING_MAX_OVER := 2
const CLIENT_EXPECTED_RANK := 2.0
const CLIENT_RANK_FACTOR := 3.5

## Standing lost with a no-casualties client for every operator who does not
## come home. Deliberately brutal — it is the whole personality of that client.
const CLIENT_CLEAN_HANDS_CASUALTY := -18

## Standing lost with any client when a contract fails.
const CLIENT_STANDING_ON_FAILURE := -7


# --- Scouting ----------------------------------------------------------------

## Days a contract takes to case, before the Intelligence Centre speeds it up.
const SCOUT_BASE_DAYS := 4

## Score a scouted contract is worth, per point of Intelligence Centre effect.
const SCOUT_BONUS_FACTOR := 1.0

## Threat, in percentage points, taken off every operator on a cased contract,
## per point of intel the case was worth.
##
## Intel deliberately does NOT touch mission.difficulty. Difficulty is what pays
## the company — XP scales off it (XP_DIFFICULTY_FACTOR), so does reputation
## (REPUTATION_DIFFICULTY_FACTOR) and so does salvage (SALVAGE_PER_DIFFICULTY) —
## so a system that "made the job easier" by writing the number down would have
## quietly cut the fee, the promotion and the parts for the privilege of knowing
## what you were walking into. Casing a contract instead adds SCORE, which moves
## the odds by exactly the same arithmetic through the logistic curve and leaves
## every payout untouched.
##
## This is the other half, and the half that was missing: knowing where the
## patrols are should keep people alive, not merely make the objective likelier.
## At 0.75 a good team's case (~9 points) is worth about -7 threat to everyone
## who goes in, which is two thirds of a plate carrier — a fair price for a week
## of somebody's time, and never enough to make a dangerous contract safe.
const INTEL_HARM_FACTOR := 0.75

## Charged up front, per level of the facility.
const SCOUT_COST_PER_LEVEL := 220


# --- Intel teams -------------------------------------------------------------
#
# The other way to case a contract: people on the ground instead of the desk.
# It costs no money and a great deal of time, which is the trade — the desk
# answer is instant to arrange and weaker, the team answer ties up operators the
# squad might have wanted.

## Days a team takes, before the Intelligence Centre and a sharp team shorten it.
const INTEL_BASE_DAYS := 5

## Most people who can usefully work one contract. Past two they trip over
## each other, and a third body is a body missing from the squad.
const INTEL_MAX_TEAM := 2

## Score a perfect team could bring back, before the facility adds its own.
## Sits above the level 1 Intelligence Centre (3.0) and below level 3 (11.0), so
## sending good people beats buying the cheap desk answer without making the
## facility pointless.
const INTEL_TEAM_MAX_BONUS := 9.0

## Stealth carries casing work; tech is the other half (cameras, comms, locks).
const INTEL_STEALTH_WEIGHT := 0.6

## A second pair of eyes is worth something, but not a second full share.
const INTEL_PARTNER_BONUS := 0.12

## No amount of intel turns a bad contract into a good one.
const INTEL_BONUS_CEILING := 18.0

const INTEL_FATIGUE_PER_DAY := 3
const INTEL_XP := 70

## Chance per operation of being noticed, before the team's quality lowers it.
const INTEL_MISHAP_BASE := 0.16

## Being noticed puts the ground on alert, and the contract gets harder.
const INTEL_MISHAP_DIFFICULTY := 5.0


# --- Losing the base ---------------------------------------------------------
#
# Facilities were a one-way ratchet: buy one and there is no decision left in it
# for the rest of the run. Making them losable keeps money scarce after the
# buying phase, and turns "can I afford the upkeep" into a live question rather
# than a line on a sheet.

## Consecutive weeks in debt before something in the base is let go. Two, not
## one — a single bad week is a setback, not a collapse, and the player gets a
## warning week to trade their way out of it.
const UPKEEP_GRACE_WEEKS := 2


# --- Daily incidents ---------------------------------------------------------
#
# Tuned so a week of five days carries roughly one or two decisions. Much more
# and ending a day becomes a chore; much less and it goes back to being a button
# with nothing behind it.

## Chance per day that something lands on the desk.
const INCIDENT_CHANCE := 0.26

## Days that must pass after one before another can fire. Two incidents on
## consecutive days reads as harassment rather than as a company running.
const INCIDENT_COOLDOWN := 2


# --- Field events ------------------------------------------------------------
#
# The decision inside a contract rather than around it. A squad is gone for four
# to seven days and until now the player agreed the odds at the door and then
# watched a timer; this is the radio call that asks them to spend something.

## Chance per deployed day that the squad calls in with a situation. Over a
## four-day contract that lands one about two thirds of the time, which is often
## enough to be part of a contract and rare enough to still be an event.
const FIELD_EVENT_CHANCE := 0.28

## How many a single contract may raise. One: a second call would be answered
## with the first one's consequences still unread, and the point is that the
## decision is the contract's turning point rather than its weather.
const FIELD_EVENTS_PER_DEPLOYMENT := 1

## Fraction of the contract's danger that still applies when the player pulls
## the squad out. Breaking contact is the safe option, not a free one.
const WITHDRAWAL_DANGER_MULT := 0.45

## What an operator who sat out the rest of the contract at the extraction point
## learns from it. Not nothing — they were there — and not what the people who
## finished it earned.
const WITHDRAWN_XP_RATIO := 0.5


# --- Unexpected events -------------------------------------------------------

## Base weekly chance that something happens at all.
const EVENT_BASE_CHANCE := 0.30

## Added to the chance for every point of average morale below neutral, so an
## unhappy company is a company things happen to.
const EVENT_MORALE_FACTOR := 0.006

## Each level of the Intelligence Centre removes this much of the chance that an
## event, when one fires, turns out to be a bad one.
const EVENT_INTEL_SHIELD := 0.14


# --- Standing work -----------------------------------------------------------
#
# Deliberately poor money. This exists so the bench is not dead weight, not as a
# way to fund the company — if standing work ever competes with contracts, the
# whole mission layer becomes optional.

const SIDE_JOB_PAY_PER_DAY := 95.0

## Floor on the pay multiplier, so even a bad fit comes back with something.
const SIDE_JOB_MIN_RATIO := 0.45

const SIDE_JOB_XP := 45
const SIDE_JOB_FATIGUE_PER_DAY := 4

## Dull work is not risk-free, but it is close.
const SIDE_JOB_MISHAP_BASE := 0.07

const SIDE_JOB_BOARD_SIZE := 4


## Chance a successful contract turns up something worth keeping.
const LOOT_CHANCE := 0.34

## Kit found in the field has already had a life. It arrives usable and worn,
## which is what makes the workshop worth walking to rather than a chore bolted
## onto a free gift.
const LOOT_CONDITION_MIN := 38.0
const LOOT_CONDITION_MAX := 74.0


# --- Kit condition -----------------------------------------------------------
#
# Durability is the last system in the design doc, and the one most likely to
# turn into an inventory chore. It earns its place by being a slider on numbers
# the player already reads: a worn rifle is not "a rifle at 61 durability", it is
# "Combat +8 instead of +13" on the same breakdown the odds screen has always
# shown. The rule is that BENEFITS scale with condition and DRAWBACKS do not, so
# neglected kit is eventually worse than no kit.

const CONDITION_NEW := 100.0

## At or below this an item gives nothing and cannot be issued. A discrete
## broken state rather than a smooth fade to zero, because the workshop screen
## and the loadout picker both need to say plainly whether a thing works.
const CONDITION_UNSERVICEABLE := 20.0

## Condition lost per day in the field, per item carried.
##
## Tuned down hard from a first pass at 3.1. At that rate the twelve-week sim
## swung from +6892 solvent to −4493 bankrupt on wear alone, and the reason was
## not the repair bills: weaker kit lowered the odds, which cost contracts,
## which killed people, which is the same single-entry death spiral v0.7 had to
## dig out of. Kit should be a running cost, not a second lethality dial. At 1.7
## a five-day contract at middling danger takes about eleven points off, so a
## piece of kit is good for six or seven jobs before it needs the bench.
const WEAR_PER_CONTRACT_DAY := 1.7

## And per point of the contract's danger, per day. Kit comes back from a lethal
## job in a worse state than from a long quiet one.
const WEAR_PER_RISK_DAY := 0.012

## Multiplier when the contract failed. Losing is hard on equipment.
const WEAR_ON_FAILURE := 1.5

## Extra wear on kit recovered from somebody who did not come home. It is not
## lost with them — a rifle outliving the person who earned its reputation is
## the whole point of the item histories this is groundwork for — but it comes
## back in the state that implies.
const WEAR_ON_DEATH := 30.0


# --- Repair, scrap and crafting ----------------------------------------------
#
# The Armoury and Quartermaster stop being pure shopfronts here. Each runs a
# bench per facility level, and a bench is the scarce thing: repairing before a
# contract means the item is not on the contract.

## Fraction of the item's price a full restoration costs.
const REPAIR_COST_RATIO := 0.26

## Days a full restoration takes at facility level 1. Level 2 and 3 take a day
## less each, floored at one.
const REPAIR_DAYS_MAX := 5

## Condition ceiling lost permanently by a repair that puts back a full 100
## points, scaled down for anything less.
##
## Proportional rather than flat, deliberately. A flat charge per visit would
## mean topping something up at 90% cost the same ceiling as rebuilding it from
## 20%, which makes careful maintenance strictly worse than neglect — a gotcha
## rather than a decision. Priced by the damage put right, the question stops
## being *when* to repair and goes back to being whether to spend the money and
## the bench at all.
const REPAIR_CEILING_LOSS := 7.5

## Ceiling below which the bench will not take it back. Past here a repair buys
## so little that replacing it is the honest answer, and the parts are worth
## more than the item.
const CONDITION_BEYOND_REPAIR := 40.0

## Salvage recovered per diamond of an item's price, when stripped at full
## condition. A 2600-diamond rifle is worth about 26 parts; a worn one, less.
const SCRAP_PER_PRICE := 0.010

## Fraction of the scrap value that survives regardless of condition. Even a
## write-off has a barrel and a stock in it.
const SCRAP_CONDITION_FLOOR := 0.45

## Salvage a successful contract brings home, per point of difficulty. Gated on
## success: parts come off work that got finished.
const SALVAGE_PER_DIFFICULTY := 0.11

## Chance a successful contract turns up plans for something the shops do not
## sell. Only on hard work, and only for a blueprint the company does not
## already hold — see Campaign._award_blueprint.
const BLUEPRINT_CHANCE := 0.22

## Difficulty a contract must reach before plans are worth finding on it.
const BLUEPRINT_MIN_DIFFICULTY := 52.0


# --- Retainers ---------------------------------------------------------------
#
# A client pays to keep the company on call. Free money until they call.

## Standing a client wants before they will put you on retainer.
const RETAINER_MIN_STANDING := 45

const RETAINER_BASE_WEEKLY := 420

## Weekly chance an active retainer turns into a priority contract on the board.
const RETAINER_CALLUP_CHANCE := 0.25

## Days a call-up sits there before the client takes offence.
const RETAINER_CALLUP_DAYS := 5

## What ignoring a call-up costs, in cash and in their opinion of you.
const RETAINER_REFUSAL_FINE := 1800
const RETAINER_REFUSAL_STANDING := -22

## Walking away from a retainer is cheaper than failing one, but not free.
const RETAINER_CANCEL_STANDING := -12


# --- Passive production ------------------------------------------------------

## Facility level at which the Armoury and Quartermaster start turning out
## surplus kit of their own.
const PRODUCTION_MIN_LEVEL := 2

## Weekly chance of producing something, per level above the minimum.
const PRODUCTION_CHANCE_PER_LEVEL := 0.30


# --- Running costs -----------------------------------------------------------
#
# The design doc's budget sheet. Split into lines the player can act on rather
# than one lump: rations scale with how many people you employ, ammunition with
# how hard you work them, medical with how badly that went.

const COST_RATIONS_PER_OPERATOR := 45
const COST_AMMUNITION_PER_DEPLOYED := 130
const COST_MEDICAL_PER_INJURED := 180


# --- Reputation --------------------------------------------------------------

const REPUTATION_START := 25

## Gained per success, scaled by how hard the contract was. Deliberately slow —
## at the first rates the company was famous inside three months, which made the
## blackmarket gate and the fee bonus meaningless by mid-game.
const REPUTATION_ON_SUCCESS := 1.4
const REPUTATION_DIFFICULTY_FACTOR := 0.028

## Failing in front of a client costs more than succeeding earns.
const REPUTATION_ON_FAILURE := -5.0

## Losing people looks bad regardless of the outcome.
const REPUTATION_PER_CASUALTY := -2.0

## Contracts pay more when the company is worth hiring. At full reputation a
## contract is worth this much more than at zero.
const REPUTATION_PAY_BONUS_MAX := 0.35

## Fraction of the purchase price recovered when selling kit back.
const RESALE_RATIO := 0.55


# --- Calendar ----------------------------------------------------------------

## The player ends a day when they choose; upkeep is charged every DAYS_PER_WEEK.
const DAYS_PER_WEEK := 7
