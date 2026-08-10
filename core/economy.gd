class_name Economy
extends RefCounted

## The weekly bill, itemised.
##
## The design doc asks for running costs managed like a budget sheet — the
## Cities: Skylines comparison. The point is that the player should be able to
## look at one screen and see exactly where the money goes, because every line
## on it is something they chose: how many people they employ, how hurt those
## people are, and how much base they decided to run.
##
## Pure functions over GameState, so the campaign harness can print the same
## sheet the base screen renders.


## Every cost line for the coming week. Returns
## { "lines": [{caption, amount, detail}], "total": int }.
static func weekly_costs(state: GameState) -> Dictionary:
	var lines: Array = []

	var payroll := state.weekly_payroll()
	lines.append({
		"caption": "Salaries",
		"amount": payroll,
		"detail": "%d on the books" % state.living_roster_size(),
	})

	var rations := ration_cost(state)
	lines.append({
		"caption": "Rations",
		"amount": rations,
		"detail": "%d per head" % Balance.COST_RATIONS_PER_OPERATOR,
	})

	var ammunition := ammunition_cost(state)
	lines.append({
		"caption": "Ammunition",
		"amount": ammunition,
		"detail": "%d deployed this week" % state.deployed_headcount(),
	})

	var medical := medical_cost(state)
	lines.append({
		"caption": "Medical",
		"amount": medical,
		"detail": "%d in the infirmary" % state.injured_headcount(),
	})

	var upkeep := facility_upkeep(state)
	lines.append({
		"caption": "Facility upkeep",
		"amount": upkeep,
		"detail": "%d built" % state.built_facility_count(),
	})

	var total := 0
	for line in lines:
		total += int(line["amount"])

	return {"lines": lines, "total": total}


## Money that arrives without anyone being sent anywhere. Shown against the bill
## so the player can see how much of the week is already covered.
static func weekly_income(state: GameState) -> Dictionary:
	var lines: Array = []
	var retainers := state.retainer_income()
	if retainers > 0:
		lines.append({
			"caption": "Retainers",
			"amount": retainers,
			"detail": "%s on call" % TextUtil.count(state.retainers.size(), "client"),
		})

	var total := 0
	for line in lines:
		total += int(line["amount"])
	return {"lines": lines, "total": total}


## What the week actually costs after passive income. This is the number that
## decides whether the company is alive.
static func net_weekly(state: GameState) -> int:
	return weekly_total(state) - int(weekly_income(state)["total"])


## Everyone eats, every week, whether they work or not.
static func ration_cost(state: GameState) -> int:
	return state.living_roster_size() * Balance.COST_RATIONS_PER_OPERATOR


## Only the people who actually went out burn through ammunition.
static func ammunition_cost(state: GameState) -> int:
	return state.deployed_headcount() * Balance.COST_AMMUNITION_PER_DEPLOYED


## The wounded are the expensive ones, which is its own argument for rotation.
static func medical_cost(state: GameState) -> int:
	return state.injured_headcount() * Balance.COST_MEDICAL_PER_INJURED


static func facility_upkeep(state: GameState) -> int:
	var total := 0
	for id in state.facilities:
		var facility := FacilityLibrary.get_facility(id)
		if facility != null:
			total += facility.upkeep_at(int(state.facilities[id]))
	return total


static func weekly_total(state: GameState) -> int:
	return int(weekly_costs(state)["total"])


## Weeks of runway at the current burn. -1 means the company is already under.
static func weeks_of_runway(state: GameState) -> int:
	if state.diamonds < 0:
		return -1
	var burn := net_weekly(state)
	if burn <= 0:
		return 99
	return int(floor(float(state.diamonds) / float(burn)))
