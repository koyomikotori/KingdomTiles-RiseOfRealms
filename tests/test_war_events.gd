extends "res://tests/test_suite.gd"
## M16b: war and bandit events (chances by stars, officers leaving or joining, idle buildings,
## raids called in, peasant squads, assassinations).

var terrains := TerrainLibrary.load_all()


func _state() -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.start()
	state.turn = 12
	state.stockpile.add({&"food": 500, &"wood": 500, &"stone": 500, &"ore": 500, &"hardwood": 500, &"horses": 500})
	return state


## An RNG whose first randf() satisfies `predicate`.
func _rng_where(predicate: Callable) -> RandomNumberGenerator:
	for seed_value in 10000:
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_value
		if predicate.call(probe.randf()):
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			return rng
	return RandomNumberGenerator.new()


func _low_rng() -> RandomNumberGenerator:
	return _rng_where(func(value: float) -> bool: return value < 0.01)


func _high_rng() -> RandomNumberGenerator:
	return _rng_where(func(value: float) -> bool: return value > 0.99)


func _resolve(state: KingdomState, event_id: StringName, index: int, clan_id: StringName = &"",
		rng: RandomNumberGenerator = _low_rng()) -> Dictionary:
	state.events.pending = [{"event_id": event_id, "clan_id": clan_id}] as Array[Dictionary]
	return state.events.resolve(state, rng, index)


func _can(state: KingdomState, event_id: StringName) -> bool:
	return state.events.can_happen(state, state.events.events[event_id])


func _choice(state: KingdomState, event_id: StringName, index: int) -> EventChoiceData:
	return state.events.events[event_id].choices[index]


## A finished farm at `origin`.
func _farm(state: KingdomState, origin: Vector2i) -> void:
	state.board.set_land(origin, &"farmland", false)
	check_eq(state.build(&"farm", origin), BuildRules.Result.OK, "Farm built")


func _agent_on(state: KingdomState, clan_id: StringName, stars: int) -> Agent:
	var agent := state.agents.generate(stars)
	state.agents.agents.append(agent)
	check_eq(state.start_agent_mission(agent, Agent.RELATIONS, clan_id), Agents.Result.OK, "Agent sent")
	return agent


func test_war_events_load() -> void:
	var events := EventData.load_all()
	for id: StringName in [&"granary_raid", &"agent_assassin", &"general_discontent", &"war_refugees",
			&"important_prisoner", &"suspicious_group", &"bandit_surrender", &"enemy_offer"]:
		check(events.has(id), "%s loaded" % id)


func test_granary_raid_needs_a_war() -> void:
	var state := _state()
	check(not _can(state, &"granary_raid"), "No war: no raid on the granary")
	state.wars.declare_war(&"north_wolves")
	check(_can(state, &"granary_raid"), "At war: may happen")
	check_eq(state.events.pick_clan(state, state.events.events[&"granary_raid"], _low_rng()), &"north_wolves",
			"About the enemy")
	var food := state.stockpile.get_amount(&"food")
	_resolve(state, &"granary_raid", 0, &"north_wolves")
	check_eq(state.stockpile.get_amount(&"food"), food - floori(food * 0.1), "Fighting back: 10% lost")


func test_prisoner_chance_grows_with_the_envoy() -> void:
	var state := _state()
	state.wars.declare_war(&"north_wolves")
	var choice := _choice(state, &"important_prisoner", 0)
	check(is_equal_approx(state.events.choice_chance(state, choice, &"north_wolves"), 0.5), "No envoy: 50%")
	var envoy := state.advisors.generate(4)
	state.advisors.add(envoy)
	state.advisors.assign(envoy, &"diplomacy")
	check(is_equal_approx(state.events.choice_chance(state, choice, &"north_wolves"), 0.7), "4-star envoy: +20%")
	var ore := state.stockpile.get_amount(&"ore")
	_resolve(state, &"important_prisoner", 0, &"north_wolves", _low_rng())
	check_eq(state.stockpile.get_amount(&"ore"), ore + 15, "Ransom paid")


func test_prisoner_may_join_unless_full() -> void:
	var state := _state()
	state.wars.declare_war(&"north_wolves")
	var officers := state.generals.generals.size() + state.advisors.advisors.size()
	_resolve(state, &"important_prisoner", 1, &"north_wolves", _low_rng())
	check_eq(state.generals.generals.size() + state.advisors.advisors.size(), officers + 1, "One officer joined")
	while state.generals.generals.size() < Generals.MAX_GENERALS:
		state.generals.add(state.generals.generate(1))
	while not state.advisors.is_full():
		state.advisors.add(state.advisors.generate(1))
	check(not state.events.can_choose(state, _choice(state, &"important_prisoner", 1), &"north_wolves"),
			"No room: cannot recruit")
	check(state.events.can_choose(state, _choice(state, &"important_prisoner", 0), &"north_wolves"), "Ransom still fine")


func test_ignored_general_may_leave() -> void:
	var state := _state()
	var general := state.generals.generate(2)
	state.generals.add(general)
	check(_can(state, &"general_discontent"), "A general at home")
	# The 40% outcome (leaving) comes first in the list; a low roll picks it.
	_resolve(state, &"general_discontent", 1, &"", _low_rng())
	check(not state.generals.generals.has(general), "Gone")


func test_defection_depends_on_stars() -> void:
	check(is_equal_approx(EventSystem.defect_chance(Officer.new()), 0.5), "0 stars: 50%")
	var veteran := Officer.new()
	veteran.stars = 6
	check(is_equal_approx(EventSystem.defect_chance(veteran), 0.2), "6 stars: 20%")


func test_refugees_idle_production_buildings() -> void:
	var state := _state()
	_farm(state, Vector2i(2, 2))
	state.wars.declare_war(&"north_wolves")
	check(_can(state, &"war_refugees"), "At war with a farm")
	var food: int = state.get_turn_yield().get(&"food", 0)
	check(food > 0, "The farm produces")
	_resolve(state, &"war_refugees", 1, &"", _low_rng())
	check_eq(state.board.get_cell(Vector2i(2, 2)).disabled_turns, 5, "Idle 5 turns")
	check_eq(state.get_turn_yield().get(&"food", 0), 0, "Idle: nothing")
	var copy := BoardData.from_save(JSON.parse_string(JSON.stringify(state.board.to_save())))
	check_eq(copy.get_cell(Vector2i(2, 2)).disabled_turns, 5, "Saved with the board")
	for i in 5:
		state.board.tick_disabled()
	check_eq(state.get_turn_yield().get(&"food", 0), food, "Back at work")


func test_suspicious_group_can_call_in_the_bandits() -> void:
	var state := _state()
	check(_can(state, &"suspicious_group"), "Bandits raid this game")
	_resolve(state, &"suspicious_group", 0, &"", _high_rng())
	check(state.events.raid_forced, "Failed investigation: bandits come")
	var report := state.end_turn()
	check(report.has("pending_raid") or report.has("pending_invasion"), "A battle at the start of the turn")
	if report.has("pending_raid"):
		check(not state.events.raid_forced, "Used up")


func test_investigation_chance_grows_with_police() -> void:
	var state := _state()
	var choice := _choice(state, &"suspicious_group", 0)
	check(is_equal_approx(state.events.choice_chance(state, choice), 0.4), "No police: 40%")


func test_bandits_who_give_up_join_as_peasants() -> void:
	var state := _state()
	check(not _can(state, &"bandit_surrender"), "No bandits about")
	state.events.raid_won_turn = state.turn - 1
	check(_can(state, &"bandit_surrender"), "After beating a raid")
	var squads := state.army.count_squads()
	_resolve(state, &"bandit_surrender", 0)
	check(state.army.count_squads() > squads, "Peasant squads joined")
	check(EventSystem.PEASANT_UNITS.has(state.army.squads.back().unit_id), "Peasants")


func test_assassination() -> void:
	var state := _state()
	state.wars.fronts[&"north_wolves"].strength = 1000
	state.wars.fronts[&"north_wolves"].max_strength = 1000
	check(not _can(state, &"agent_assassin"), "No agent: no chance")
	var agent := _agent_on(state, &"north_wolves", 2)
	check(_can(state, &"agent_assassin"), "Agent in a clan with officers")
	var staff := state.clan_officers.staff(&"north_wolves")
	var choice := _choice(state, &"agent_assassin", 0)
	check(is_equal_approx(state.events.choice_chance(state, choice, &"north_wolves"), 0.6), "50% + 5% x 2 stars")
	var general := staff.general
	_resolve(state, &"agent_assassin", 0, &"north_wolves", _low_rng())
	check(staff.general == null or general.wounded_turns > 0, "The general is dead or wounded")
	_resolve(state, &"agent_assassin", 1, &"north_wolves", _high_rng())
	check(not agent.is_busy(), "Failed: the agent is exposed and leaves")


func test_raid_forced_is_saved() -> void:
	var state := _state()
	state.events.raid_forced = true
	var copy := _state()
	copy.events.load_save(JSON.parse_string(JSON.stringify(state.events.to_save())))
	check(copy.events.raid_forced, "Saved")
