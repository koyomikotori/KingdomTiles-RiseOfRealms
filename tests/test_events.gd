extends "res://tests/test_suite.gd"

var terrains := TerrainLibrary.load_all()


func _state() -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.start()
	state.turn = 5
	return state


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## Answers `event_id` (about `clan_id`) with choice `index`.
func _resolve(state: KingdomState, event_id: StringName, index: int, clan_id: StringName = &"",
		rng: RandomNumberGenerator = _rng()) -> Dictionary:
	var entry := {"event_id": event_id, "clan_id": clan_id}
	var event: EventData = state.events.events[event_id]
	if event.choices.any(func(choice: EventChoiceData) -> bool: return not choice.cost_share.is_empty()):
		entry["costs"] = state.events._fixed_costs(state, event)
	state.events.pending = [entry] as Array[Dictionary]
	return state.events.resolve(state, rng, index)


func _can(state: KingdomState, event_id: StringName) -> bool:
	return state.events.can_happen(state, state.events.events[event_id])


# --- Data ---------------------------------------------------------------------------------

func test_every_event_is_complete() -> void:
	var events := EventData.load_all()
	var resources := ResourceTypeData.load_all().map(func(t: ResourceTypeData) -> StringName: return t.resource_id)
	var units := UnitData.load_all().map(func(u: UnitData) -> StringName: return u.unit_id)
	check(events.size() >= 16, "First event set loaded (%d)" % events.size())
	for event_id in events:
		var event := events[event_id]
		check(not event.title.is_empty() and not event.text.is_empty(), "%s has text" % event_id)
		check(event.choices.size() >= 1 and event.choices.size() <= 4, "%s has 1-4 choices" % event_id)
		for choice in event.choices:
			check(not choice.outcomes.is_empty(), "%s: '%s' has an outcome" % [event_id, choice.text])
			for resource_id in choice.cost:
				check(resources.has(resource_id), "%s: cost %s exists" % [event_id, resource_id])
			for outcome in choice.outcomes:
				check(outcome.weight > 0.0 and not outcome.text.is_empty(), "%s: outcome has weight and text" % event_id)
				check(outcome.add_unit == &"" or units.has(outcome.add_unit), "%s: unit %s exists" % [event_id, outcome.add_unit])
				for resource_id in outcome.resources:
					check(resources.has(resource_id), "%s: resource %s exists" % [event_id, resource_id])
					# A fixed price belongs in the cost, which locks the choice when it cannot be paid.
					check(outcome.resources[resource_id] > 0 or choice.outcomes.size() > 1,
							"%s: '%s' takes %s outside its cost" % [event_id, choice.text, resource_id])
				for resource_id in outcome.random_resources:
					check(resources.has(resource_id), "%s: resource %s exists" % [event_id, resource_id])
					check(not outcome.random_resources[resource_id].is_empty(), "%s: %s has amounts" % [event_id, resource_id])
				if outcome.relation != 0 or outcome.declare_war or outcome.clan_strength != 0:
					check(event.needs_clan, "%s: clan effects need a clan" % event_id)


# --- When events happen -------------------------------------------------------------------

func test_turn_start_rolls_zero_to_three_events_with_the_chosen_odds() -> void:
	var counts := [0, 0, 0, 0]
	var rng := _rng(7)
	for i in 400:
		var state := _state()
		state.stockpile.add({&"food": 100, &"wood": 100, &"stone": 100})
		state.events.pending.clear()
		counts[state.events.roll(state, rng).size()] += 1
	check(counts[0] > 160 and counts[0] < 240, "About 50%% none (%d/400)" % counts[0])
	check(counts[1] > 90 and counts[1] < 150, "About 30%% one (%d/400)" % counts[1])
	check(counts[2] > 35 and counts[2] < 85, "About 15%% two (%d/400)" % counts[2])
	check(counts[3] > 5 and counts[3] < 40, "About 5%% three (%d/400)" % counts[3])


func test_no_events_before_turn_three_and_no_repeats_in_a_turn() -> void:
	var state := _state()
	state.turn = 2
	state.stockpile.add({&"food": 100, &"wood": 100, &"stone": 100})
	for event_id in state.events.events:
		if event_id != &"bandit_mercy":
			check(not _can(state, event_id), "%s waits for turn 3" % event_id)
	state.turn = 5
	state.stockpile.add({&"food": 100, &"wood": 100, &"stone": 100})
	for seed_value in 50:
		var picked := state.events.roll(state, _rng(seed_value)).map(func(e: Dictionary) -> StringName: return e.event_id)
		for event_id in picked:
			check_eq(picked.count(event_id), 1, "No repeat in one turn")
		state.events.last_turn.clear()


func test_conditions_and_cooldowns() -> void:
	var state := _state()
	check(not _can(state, &"crop_blight"), "No farmland")
	for x in 4:
		state.board.set_land(Vector2i(x, 0), &"farmland", false)
	state.stockpile.add({&"food": 30})
	check(_can(state, &"crop_blight"), "Farmland and food")
	state.events.last_turn[&"crop_blight"] = 5
	state.turn = 12
	check(not _can(state, &"crop_blight"), "Cooldown of 8 turns")
	state.turn = 13
	check(_can(state, &"crop_blight"), "Cooldown over")
	check(not _can(state, &"camp_plague"), "No barracks")


func test_bandits_beg_only_after_a_raid_was_beaten_last_turn() -> void:
	var state := _state()
	check(not _can(state, &"bandit_mercy"), "No raid")
	state.events.raid_won_turn = 4
	check(_can(state, &"bandit_mercy"), "Raid beaten last turn")
	state.turn = 6
	check(not _can(state, &"bandit_mercy"), "Too late")


## M18c: a tribute demand comes only from a bordering clan with 1.5× the kingdom's soldiers, no
## friendlier than Neutral, under no pact or tribute peace, at most once per clan in 15 turns.
func test_clan_events_pick_a_matching_clan() -> void:
	var state := _state()
	var tribute: EventData = state.events.events[&"tribute_demand"]
	for i in 4:
		state.army.add_squad(&"swordsman", 20)
	for front in state.wars.fronts.values():
		front.strength = 10
	check(not _can(state, &"tribute_demand"), "No clan is strong enough")
	state.wars.fronts[&"north_wolves"].strength = 119
	check(not _can(state, &"tribute_demand"), "Below 1.5 × 80 soldiers")
	state.wars.fronts[&"north_wolves"].strength = 120
	check(_can(state, &"tribute_demand"), "Wolves border us with 1.5 × our soldiers")
	check_eq(state.events.pick_clan(state, tribute, _rng()), &"north_wolves", "Only the wolves match")
	state.diplomacy.change_relation(&"north_wolves", 80)
	check(not _can(state, &"tribute_demand"), "Not from a friendly clan")
	state.diplomacy.change_relation(&"north_wolves", -80)
	state.diplomacy.clans[&"north_wolves"].pact_turns = 5
	check(not _can(state, &"tribute_demand"), "Not under a pact")
	state.diplomacy.clans[&"north_wolves"].pact_turns = 0
	state.diplomacy.clans[&"north_wolves"].tribute_peace = 3
	check(not _can(state, &"tribute_demand"), "Not while keeping the peace for a tribute")
	state.diplomacy.clans[&"north_wolves"].tribute_peace = 0
	state.events.clan_last_turn["tribute_demand|north_wolves"] = state.turn - 14
	check(not _can(state, &"tribute_demand"), "Once per clan in 15 turns")
	state.events.clan_last_turn["tribute_demand|north_wolves"] = state.turn - 15
	check(_can(state, &"tribute_demand"), "Cooldown over")
	# Aid requests need a friendly clan and enough in store.
	var request: EventData = state.events.events[&"ally_request"]
	state.stockpile.add({&"wood": 40, &"stone": 40})
	state.diplomacy.change_relation(&"south_farmers", 100)
	var matching := state.events._matching_clans(state, request)
	check(matching.has(&"south_farmers"), "A friendly clan asks")
	for clan_id in matching:
		check(state.diplomacy.get_tier(clan_id) >= Diplomacy.Tier.FRIENDLY, "%s is friendly" % clan_id)


# --- Answers ------------------------------------------------------------------------------

func test_a_choice_pays_its_cost_and_applies_the_outcome() -> void:
	var state := _state()
	state.stockpile.add({&"food": 200})
	var relation := state.diplomacy.clans[&"south_farmers"].relation
	var result := _resolve(state, &"famine_aid", 0, &"south_farmers")
	check_eq(state.stockpile.get_amount(&"food"), 180, "Paid 10% of the food")
	check_eq(state.diplomacy.clans[&"south_farmers"].relation, relation + 12, "+12")
	check_eq(state.diplomacy.clans[&"south_farmers"].memories.get(Diplomacy.MEMORY_EVENT), 12, "Remembered as an event")
	check(result.text.contains("Điền Trang Nam Lâm"), "Clan name filled in")
	check(state.events.pending.is_empty(), "Answered")


func test_unaffordable_choices_change_nothing() -> void:
	var state := _state()
	state.stockpile.add({&"food": 5})
	check(_resolve(state, &"famine_aid", 0, &"south_farmers").is_empty(), "Refused (at least 10 food)")
	check_eq(state.stockpile.get_amount(&"food"), 5, "Nothing paid")
	check_eq(state.events.pending.size(), 1, "Still waiting for an answer")


func test_outcomes_roll_by_weight() -> void:
	# The merchant (M16i): pay food, then rare goods 40%, an even swap 30%, a loss 20%, nothing 10%.
	var kinds := {&"rare": 0, &"even": 0, &"loss": 0, &"nothing": 0}
	for seed_value in 1000:
		var state := _state()
		state.stockpile.add({&"food": 20})
		_resolve(state, &"traveling_merchant", 0, &"", _rng(seed_value))
		check_eq(state.stockpile.get_amount(&"food"), 0, "Paid 20 food")
		var rare := state.stockpile.get_amount(&"ore") + state.stockpile.get_amount(&"hardwood") 				+ state.stockpile.get_amount(&"horses")
		var wood := state.stockpile.get_amount(&"wood")
		var stone := state.stockpile.get_amount(&"stone")
		if rare > 0:
			kinds[&"rare"] += 1
		elif wood == 20 or stone == 10:
			kinds[&"even"] += 1
		elif wood == 10:
			kinds[&"loss"] += 1
		else:
			kinds[&"nothing"] += 1
	for kind: StringName in {&"rare": 0.4, &"even": 0.3, &"loss": 0.2, &"nothing": 0.1}:
		var share: float = {&"rare": 0.4, &"even": 0.3, &"loss": 0.2, &"nothing": 0.1}[kind]
		check(absf(kinds[kind] / 1000.0 - share) < 0.05, "%s about %d%%: %s" % [kind, share * 100, kinds])


func test_the_merchant_takes_food_wood_or_stone() -> void:
	var paid := {0: [&"food", 20], 1: [&"wood", 20], 2: [&"stone", 10]}
	for index: int in paid:
		var state := _state()
		var amounts: Dictionary[StringName, int] = {paid[index][0]: paid[index][1]}
		state.stockpile.add(amounts)
		check(not _resolve(state, &"traveling_merchant", index).is_empty(), "Choice %d taken" % index)
		check_eq(state.stockpile.get_amount(paid[index][0]), 0, "Paid %s" % paid[index][0])
	var poor := _state()
	check(_resolve(poor, &"traveling_merchant", 1).is_empty(), "No wood: refused")
	check(not _resolve(poor, &"traveling_merchant", 3).is_empty(), "Turning them away is free")


## Answers `event_id` with `choice` 1000 times; {resource: {amount: times}}.
func _rolled(event_id: StringName, choice: int, pay: Dictionary, resources: Array[StringName]) -> Dictionary:
	var seen := {}
	for resource_id in resources:
		seen[resource_id] = {}
	var amounts: Dictionary[StringName, int] = {}
	amounts.assign(pay)
	for seed_value in 1000:
		var state := _state()
		state.stockpile.add(amounts)
		_resolve(state, event_id, choice, &"", _rng(seed_value))
		for resource_id in resources:
			var amount := state.stockpile.get_amount(resource_id)
			seen[resource_id][amount] = seen[resource_id].get(amount, 0) + 1
	return seen


## `seen` (from _rolled) matches {amount: share} within 5%.
func _check_odds(seen: Dictionary, odds: Dictionary, label: String) -> void:
	check_eq(seen.keys().size(), odds.size(), "%s: amounts %s" % [label, seen])
	for amount: int in odds:
		check(absf(seen.get(amount, 0) / 1000.0 - odds[amount]) < 0.05, "%s: %d about %d%%: %s" % [label, amount, odds[amount] * 100, seen])


func test_stone_vein_rolls_stone_and_ore_on_their_own() -> void:
	var seen := _rolled(&"stone_vein", 0, {&"food": 10}, [&"stone", &"ore"] as Array[StringName])
	_check_odds(seen[&"stone"], {10: 0.5, 30: 0.3, 50: 0.2}, "Stone")
	_check_odds(seen[&"ore"], {0: 0.5, 20: 0.3, 30: 0.2}, "Ore")
	var state := _state()
	state.stockpile.add({&"food": 10})
	var result := _resolve(state, &"stone_vein", 0)
	check(result.changes.any(func(line: String) -> bool: return line.begins_with("Nhận:")), "Gain line: %s" % [result.changes])


func test_hardwood_grove_rolls_wood_and_hardwood() -> void:
	var seen := _rolled(&"hardwood_grove", 0, {&"food": 10}, [&"wood", &"hardwood"] as Array[StringName])
	_check_odds(seen[&"wood"], {10: 0.5, 30: 0.3, 50: 0.2}, "Wood")
	_check_odds(seen[&"hardwood"], {0: 0.5, 20: 0.3, 30: 0.2}, "Hardwood")
	check_eq(_state().events.events[&"hardwood_grove"].min_terrain, {&"forest": 2} as Dictionary[StringName, int], "Needs forest")
	check_eq(_state().events.events[&"wild_horses"].min_terrain, {&"grass": 3} as Dictionary[StringName, int], "Horses need grass")


func test_wild_horses_trade_food_or_send_soldiers() -> void:
	_check_odds(_rolled(&"wild_horses", 0, {&"food": 30}, [&"horses"] as Array[StringName])[&"horses"],
			{10: 0.5, 15: 0.3, 20: 0.2}, "Villagers")
	_check_odds(_rolled(&"wild_horses", 1, {}, [&"horses"] as Array[StringName])[&"horses"],
			{0: 0.5, 10: 0.3, 15: 0.2}, "Soldiers")
	for seed_value in 50:
		var state := _state()
		var result := _resolve(state, &"wild_horses", 1, &"", _rng(seed_value))
		if state.stockpile.get_amount(&"horses") == 0:
			check(&"Không thu được gì." in result.changes, "Empty-handed is said: %s" % [result.changes])
			break


func test_marriage_needs_an_ally_and_a_rich_gift() -> void:
	var state := _state()
	check(not _can(state, &"marriage_alliance"), "No ally yet")
	state.diplomacy.clans[&"south_farmers"].alliance_turns = 10
	state.turn = 6
	check(_can(state, &"marriage_alliance"), "An ally")
	check(not state.events.block_reason(state, state.events.events[&"marriage_alliance"].choices[0]).is_empty(),
			"Locked without the gift")
	state.stockpile.add({&"ore": 15 - state.stockpile.get_amount(&"ore"), &"hardwood": 15 - state.stockpile.get_amount(&"hardwood"),
			&"food": 30})
	var relation := state.diplomacy.clans[&"south_farmers"].relation
	_resolve(state, &"marriage_alliance", 0, &"south_farmers")
	check_eq(state.diplomacy.clans[&"south_farmers"].relation, relation + 20, "+20 for the wedding")
	check_eq(state.stockpile.get_amount(&"hardwood"), 0, "Gift paid")
	check_eq(state.stockpile.get_amount(&"ore"), 0, "Ore too")
	_resolve(state, &"marriage_alliance", 1, &"south_farmers")
	check_eq(state.diplomacy.clans[&"south_farmers"].relation, relation + 12, "-8 for refusing")


func test_caravan_tax_or_seize() -> void:
	var small := {5: 0.4, 10: 0.4, 15: 0.2}
	var taxed := _rolled(&"merchant_caravan", 1, {}, [&"food", &"wood", &"stone", &"ore"] as Array[StringName])
	for resource_id in [&"food", &"wood", &"stone"]:
		_check_odds(taxed[resource_id], small, "Tax %s" % resource_id)
	check_eq(taxed[&"ore"].keys(), [0], "Tax brings basics only")
	var seized := _rolled(&"merchant_caravan", 2, {},
			[&"food", &"wood", &"stone", &"ore", &"hardwood", &"horses"] as Array[StringName])
	_check_odds(seized[&"food"], {15: 0.4, 25: 0.4, 35: 0.2}, "Seized food")
	_check_odds(seized[&"stone"], {10: 0.4, 15: 0.4, 20: 0.2}, "Seized stone")
	for resource_id in [&"ore", &"hardwood", &"horses"]:
		_check_odds(seized[resource_id], {8: 0.4, 12: 0.4, 18: 0.2}, "Seized %s" % resource_id)
	var state := _state()
	var farmers := state.diplomacy.clans[&"south_farmers"].relation
	var wolves := state.diplomacy.clans[&"north_wolves"].relation
	_resolve(state, &"merchant_caravan", 2, &"south_farmers")
	check_eq(state.diplomacy.clans[&"south_farmers"].relation, farmers - 25, "The caravan's clan: -20 and -5")
	check_eq(state.diplomacy.clans[&"north_wolves"].relation, wolves - 5, "Every other clan -5")


func test_wild_beasts_hunt_or_lose_food() -> void:
	var state := _state()
	for i in 5:
		state.army.add_squad(&"swordsman", 20)
	check(_can(state, &"wild_beasts") == (state.board.count_owned_terrain(&"forest") >= 3), "Needs 3 forest")
	var result := _resolve(state, &"wild_beasts", 0)
	check_eq(state.army.count_soldiers(), 94, "3 squads lose 10% each")
	check_eq(state.army.squads.filter(func(squad: Army.Squad) -> bool: return squad.soldiers == 18).size(), 3, "Three hurt")
	check(state.stockpile.get_amount(&"food") in [10, 20, 30], "Meat brought home")
	check(result.changes.any(func(line: String) -> bool: return line.begins_with("Nhận:")), "Gain line")
	state = _state()
	state.stockpile.add({&"food": 100 - state.stockpile.get_amount(&"food")})
	_resolve(state, &"wild_beasts", 1)
	check_eq(state.stockpile.get_amount(&"food"), 85, "15% of the food eaten")


func test_flood_dike_or_risk_the_stores() -> void:
	var state := _state()
	check(not state.events.block_reason(state, state.events.events[&"flood"].choices[0]).is_empty(), "Locked when poor")
	state.stockpile.add({&"wood": 50, &"stone": 50, &"hardwood": 10})
	var wood := state.stockpile.get_amount(&"wood")
	var food := state.stockpile.get_amount(&"food")
	_resolve(state, &"flood", 0)
	check_eq(state.stockpile.get_amount(&"wood"), wood - 50, "Dike paid")
	check_eq(state.stockpile.get_amount(&"food"), food, "Stores kept")
	var flooded := 0
	for seed_value in 1000:
		state = _state()
		state.stockpile.add({&"food": 100 - state.stockpile.get_amount(&"food")})
		_resolve(state, &"flood", 1, &"", _rng(seed_value))
		if state.stockpile.get_amount(&"food") == 80:
			flooded += 1
	check(absf(flooded / 1000.0 - 0.7) < 0.05, "The flood comes 70%% of the time: %d" % flooded)


func test_tax_relief_costs_stores_or_squads() -> void:
	var state := _state()
	var agree: EventChoiceData = state.events.events[&"tax_relief"].choices[0]
	state.stockpile.spend({&"ore": state.stockpile.get_amount(&"ore")} as Dictionary[StringName, int])
	check(not state.events.block_reason(state, agree).is_empty(), "Locked without the ore")
	state.stockpile.add({&"food": 20, &"wood": 10, &"stone": 10, &"ore": 5, &"hardwood": 5})
	var before := state.stockpile.get_amount(&"food")
	var pieces := state.hand.pieces.size()
	_resolve(state, &"tax_relief", 0)
	check_eq(state.stockpile.get_amount(&"food"), before - 20, "20 food given up")
	check_eq(state.stockpile.get_amount(&"ore"), 0, "5 ore given up")
	check_eq(state.hand.pieces.size(), pieces + 1, "One more piece of land")
	var forced := 0
	var lost := {1: 0, 2: 0}
	for seed_value in 400:
		state = _state()
		for i in 4:
			state.army.add_squad(&"swordsman", 20)
		state.army.squads[0].away = true
		_resolve(state, &"tax_relief", 1, &"", _rng(seed_value))
		var gone := 4 - state.army.count_squads()
		lost[gone] = lost.get(gone, 0) + 1
		check(state.army.squads.any(func(squad: Army.Squad) -> bool: return squad.away), "Squads away are safe")
		if state.uprising.forced:
			forced += 1
	check_eq(lost.keys().size(), 2, "1 or 2 squads lost: %s" % lost)
	check(absf(forced / 400.0 - 0.5) < 0.08, "Rebels about half the time: %d" % forced)


func test_a_forced_uprising_skips_the_countdown() -> void:
	var state := _state()
	var allowed := state.uprising.next_allowed_turn
	state.uprising.forced = true
	var data: Dictionary = JSON.parse_string(JSON.stringify(state.uprising.to_save()))
	var loaded := Uprising.new()
	loaded.load_save(data, state.board)
	check(loaded.forced, "Saved")
	check_eq(state.uprising.end_turn(state.board, 5, false), &"started", "Starts before FIRST_TURN")
	check(state.uprising.is_active() and not state.uprising.forced, "Zone up, flag used")
	check_eq(state.uprising.next_allowed_turn, allowed, "Countdown untouched")


func test_army_effects() -> void:
	var state := _state()
	state.stockpile.add({&"food": 50})
	var volunteers := _resolve(state, &"volunteers", 0)
	check_eq(state.army.count_squads(), 1, "A new squad")
	check(volunteers.changes.any(func(line: String) -> bool: return line.contains("Kiếm binh")), "Reported")
	state.army.add_squad(&"swordsman", 20)
	var expected := 0
	for squad in state.army.squads:
		expected += floori(squad.soldiers * 0.75)
	_resolve(state, &"camp_plague", 1)
	check_eq(state.army.count_soldiers(), expected, "25% of each squad is lost (rounded in their favour)")
	state.stockpile.add({&"food": 10})
	var wounded := state.army.count_soldiers()
	_resolve(state, &"healer", 0)
	check(state.army.count_soldiers() > wounded, "Healer brings soldiers back")


func test_land_and_war_effects() -> void:
	var state := _state()
	state.stockpile.add({&"wood": 10})
	_resolve(state, &"settlers", 0)
	check_eq(state.hand.pieces.size(), 5, "Two extra pieces in the hand")
	state.diplomacy.change_relation(&"north_wolves", -40)
	var rng := RandomNumberGenerator.new()
	for seed_value in 1000:
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_value
		if probe.rand_weighted(PackedFloat32Array([0.5, 0.5])) == 1:
			rng.seed = seed_value
			break
	_resolve(state, &"tribute_demand", 1, &"north_wolves", rng)
	check(state.wars.at_war_with(&"north_wolves"), "Refusing tribute may start a war")


# --- Save ---------------------------------------------------------------------------------

func test_pending_events_and_cooldowns_are_saved() -> void:
	var state := _state()
	state.events.pending = [{"event_id": &"famine_aid", "clan_id": &"south_farmers"},
			{"event_id": &"no_such_event", "clan_id": &""}] as Array[Dictionary]
	state.events.last_turn[&"stone_vein"] = 4
	state.events.raid_won_turn = 3
	var data: Dictionary = JSON.parse_string(JSON.stringify(state.to_save()))
	var loaded := _state()
	loaded.load_save(data)
	check_eq(loaded.events.pending, [{"event_id": &"famine_aid", "clan_id": &"south_farmers"}] as Array[Dictionary],
			"Pending event kept, unknown one dropped")
	check_eq(loaded.events.last_turn, {&"stone_vein": 4} as Dictionary[StringName, int], "Cooldowns")
	check_eq(loaded.events.raid_won_turn, 3, "Raid flag")


# --- Officer requests (M16k-b) --------------------------------------------------------------

func _officer(general: bool, stars: int, name: String) -> Officer:
	var officer: Officer = General.new() if general else Advisor.new()
	officer.name = name
	officer.stars = stars
	officer.look = OfficerLook.from_seed(name)
	return officer


func test_requests_come_only_from_officers_who_may_play() -> void:
	var state := _state()
	state.turn = 10
	for officer in state.generals.generals.duplicate():
		state.generals.generals.erase(officer)
	for officer in state.advisors.advisors.duplicate():
		state.advisors.advisors.erase(officer)
	check(not _can(state, &"spar_request") and not _can(state, &"memory_request"), "Nobody to ask")
	var low := _officer(true, 2, "Thấp")
	state.generals.add(low)
	check(not _can(state, &"spar_request"), "2★ may not spar")
	var general := _officer(true, 4, "Hùng") as General
	state.generals.add(general)
	check(_can(state, &"spar_request"), "A 4★ general may ask")
	general.last_spar_turn = 8
	check(not _can(state, &"spar_request"), "Not while resting")
	general.last_spar_turn = -100
	general.away = true
	check(not _can(state, &"spar_request"), "Not while away")
	general.away = false
	general.level = general.max_level()
	check(not _can(state, &"spar_request"), "Not at the top level")
	general.level = 1
	var advisor := _officer(false, 3, "Trí") as Advisor
	state.advisors.add(advisor)
	check(_can(state, &"memory_request"), "A 3★ advisor may ask")
	advisor.last_memory_turn = 9
	check(not _can(state, &"memory_request"), "Not while resting")
	advisor.last_memory_turn = -100
	check_eq(EventSystem.request_candidates(state, &"spar"), [general] as Array[Officer], "Only the one who may")
	# Rolled: the entry names the officer and the texts use the name.
	state.events.pending.clear()
	var rolled := false
	for seed_value in range(1, 400):
		state.events.last_turn.clear()
		state.events.pending.clear()
		for entry in state.events.roll(state, _rng(seed_value)):
			if entry.event_id == &"spar_request":
				check_eq(entry.officer, "Hùng", "The asking general")
				rolled = true
		if rolled:
			break
	check(rolled, "The spar request comes up")
	state.events.pending = [{"event_id": &"spar_request", "clan_id": &"", "officer": "Hùng"}] as Array[Dictionary]
	check(state.events.fill(state, state.events.current_event().title, &"").begins_with("Hùng"), "Title names him")
	check_eq(state.events.current_officer(state), general, "Found again by name")
	general.wounded_turns = 2
	state.events.drop_stale(state)
	check(state.events.pending.is_empty(), "Dropped once he may no longer spar")


func test_accepting_a_request_opens_the_game_with_more_xp() -> void:
	var state := _state()
	state.turn = 10
	var advisor := _officer(false, 4, "Trí") as Advisor
	state.advisors.add(advisor)
	state.events.pending = [{"event_id": &"memory_request", "clan_id": &"", "officer": "Trí"}] as Array[Dictionary]
	var refused := state.events.resolve(state, _rng(), 1)
	check(state.events.pending_request.is_empty() and not refused.has("request"), "Refusing changes nothing")
	check(refused.text.contains("Trí"), "Named in the result")
	check_eq(state.check_memory(advisor), MemoryMatch.Result.OK, "May still play")
	state.events.pending = [{"event_id": &"memory_request", "clan_id": &"", "officer": "Trí"}] as Array[Dictionary]
	var accepted := state.events.resolve(state, _rng(), 0)
	check_eq(accepted.get("request"), &"memory", "The game follows")
	check_eq(accepted.tone, &"", "No reaction: the game has its own")
	check_eq(state.events.pending_request.officer, advisor, "For the asking advisor")
	check_eq(state.events.pending_request.bonus, EventSystem.REQUEST_BONUS, "With the bonus")
	check_eq(MemoryMatch.xp_reward(advisor, true, 1.5), ceili(advisor.xp_to_next() * 0.4 * 1.5), "60% on a win")
	var expected := MemoryMatch.xp_reward(advisor, false, EventSystem.REQUEST_BONUS)
	check_eq(state.finish_memory(advisor, false, EventSystem.REQUEST_BONUS).xp, expected, "Paid with the bonus")
	var general := _officer(true, 3, "Hùng") as General
	check_eq(Spar.xp_reward(general, true, 1.5), ceili(general.xp_to_next() * 0.4 * 1.5), "Spar: 60% on a win")


func test_request_officers_are_saved() -> void:
	var state := _state()
	state.events.pending = [{"event_id": &"spar_request", "clan_id": &"", "officer": "Hùng"}] as Array[Dictionary]
	var data: Dictionary = JSON.parse_string(JSON.stringify(state.events.to_save()))
	var loaded := EventSystem.new()
	loaded.load_save(data)
	check_eq(loaded.pending[0].get("officer"), "Hùng", "The asking officer is kept")


# --- M18c: shares of the stockpile, tribute peace, thanks ----------------------------------

func test_shared_costs_are_fixed_when_rolled() -> void:
	var state := _state()
	state.stockpile.add({&"food": 300, &"wood": 300, &"stone": 300})
	var event: EventData = state.events.events[&"tribute_demand"]
	var costs := state.events._fixed_costs(state, event)
	check_eq(costs[0], {&"food": 36, &"wood": 36, &"stone": 36}, "12% of each")
	check(costs[1].is_empty(), "Refusing costs nothing")
	state.events.pending = [{"event_id": &"tribute_demand", "clan_id": &"north_wolves", "costs": costs}] as Array[Dictionary]
	state.stockpile.add({&"food": 700})
	check_eq(state.events.cost_of(event.choices[0])[&"food"], 36, "Still what was asked when the envoy came")
	var saved := state.events.to_save()
	var loaded := EventSystem.new()
	loaded.load_save(JSON.parse_string(JSON.stringify(saved)))
	check_eq(loaded.pending[0].costs[0], {&"food": 36, &"wood": 36, &"stone": 36}, "Saved with the event")


func test_paying_tribute_buys_peace() -> void:
	var state := _state()
	state.stockpile.add({&"food": 100, &"wood": 100, &"stone": 100})
	var result := _resolve(state, &"tribute_demand", 0, &"north_wolves")
	check_eq(state.diplomacy.clans[&"north_wolves"].tribute_peace, 10, "10 turns of peace")
	check_eq(state.stockpile.get_amount(&"food"), 88, "Paid 12 food")
	check_eq(result.tone, &"event_good", "Peace is good news")
	state.diplomacy.change_relation(&"north_wolves", -100)
	check(not state.wars.clan_declares_war(&"north_wolves"), "No war while the peace holds")
	check_eq(state.wars._declare_chance(&"north_wolves"), 0.0, "Not even when hostile")
	for i in 10:
		state.diplomacy.end_turn()
	check(state.wars.clan_declares_war(&"north_wolves"), "War is possible again")


func test_grateful_clans_send_thanks_later() -> void:
	var state := _state()
	check(not _can(state, EventSystem.CLAN_THANKS_EVENT), "Never rolled at random")
	state.events.add_thanks(state, &"south_farmers", _rng())
	var due: int = state.events.thanks[0].turn
	check(due >= state.turn + 3 and due <= state.turn + 6, "Comes in 3 to 6 turns")
	state.turn = due - 1
	state.events.pending.clear()
	var early := state.events.roll(state, _rng())
	check(not early.any(func(e: Dictionary) -> bool: return e.event_id == EventSystem.CLAN_THANKS_EVENT), "Not yet")
	state.turn = due
	var added := state.events.roll(state, _rng())
	check(added.size() >= 1 and added[0].event_id == EventSystem.CLAN_THANKS_EVENT, "The thanks arrive")
	check_eq(added[0].clan_id, &"south_farmers", "From the clan we helped")
	check(state.events.thanks.is_empty(), "Delivered once")
	var before := state.stockpile.get_amount(&"food") + state.equipment.items.size()
	state.events.pending = [added[0]] as Array[Dictionary]
	state.events.resolve(state, _rng(), 0)
	check(state.stockpile.get_amount(&"food") + state.stockpile.get_amount(&"ore") \
			+ state.equipment.items.size() > before, "Got goods or an item")


func test_thanks_skip_clans_at_war() -> void:
	var state := _state()
	state.events.thanks = [{"clan_id": &"north_wolves", "turn": state.turn}] as Array[Dictionary]
	state.wars.declare_war(&"north_wolves")
	state.events.pending.clear()
	var added := state.events.roll(state, _rng())
	check(not added.any(func(e: Dictionary) -> bool: return e.event_id == EventSystem.CLAN_THANKS_EVENT), "No thanks in war")
	check(state.events.thanks.is_empty(), "Dropped")
