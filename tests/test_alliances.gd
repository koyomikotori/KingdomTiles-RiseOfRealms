extends "res://tests/test_suite.gd"

var terrains := TerrainLibrary.load_all()


func _state() -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.start()
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


func _run(simulator: BattleSimulator) -> BattleRecord:
	while not simulator.finished:
		simulator.step()
	return simulator.record


func _set_relation(state: KingdomState, clan_id: StringName, relation: int) -> void:
	state.diplomacy.change_relation(clan_id, relation - state.diplomacy.clans[clan_id].relation)


## Allies `clan_id` right away: relation 60 (Close), then 90 with the alliance's +30.
func _ally(state: KingdomState, clan_id: StringName) -> void:
	_set_relation(state, clan_id, 60)
	check_eq(state.alliances.propose_alliance(_low_rng(), clan_id), Alliances.AllianceResult.OK, "%s allied" % clan_id)


func _lent_soldiers(side: BattleSide) -> Dictionary:
	var result := {}
	for unit in side.units:
		if unit.ally != null:
			result[unit.ally.clan_id] = result.get(unit.ally.clan_id, 0) + unit.start_soldiers
	return result


# --- Data -----------------------------------------------------------------------------------

func test_clan_friendships_are_mutual() -> void:
	var clans := ClanData.load_all()
	var by_id := {}
	for clan in clans:
		by_id[clan.clan_id] = clan
	for clan in clans:
		check(not clan.friends.is_empty(), "%s has a friend" % clan.clan_id)
		for friend in clan.friends:
			check(by_id.has(friend), "%s: friend %s exists" % [clan.clan_id, friend])
			if by_id.has(friend):
				check((by_id[friend] as ClanData).friends.has(clan.clan_id), "%s <-> %s" % [clan.clan_id, friend])


# --- Alliance -------------------------------------------------------------------------------

func test_alliance_needs_a_close_relation() -> void:
	var state := _state()
	check_eq(state.alliances.check_alliance(&"south_farmers"), Alliances.AllianceResult.NOT_CLOSE, "Friendly is not enough")
	_set_relation(state, &"south_farmers", 60)
	check_eq(state.alliances.check_alliance(&"south_farmers"), Alliances.AllianceResult.OK, "Close")
	state.wars.declare_war(&"north_wolves")
	_set_relation(state, &"north_wolves", 80)
	check_eq(state.alliances.check_alliance(&"north_wolves"), Alliances.AllianceResult.AT_WAR, "Not while at war")


func test_alliance_chance_by_relation_personality_and_threat() -> void:
	var state := _state()
	_set_relation(state, &"east_merchants", 60)
	check(is_equal_approx(state.alliances.alliance_chance(&"east_merchants"), 0.45), "Merchants at 60: 0.3 + 0.15")
	_set_relation(state, &"east_merchants", 100)
	check(is_equal_approx(state.alliances.alliance_chance(&"east_merchants"), 0.95), "Capped at 95%")
	_set_relation(state, &"north_wolves", 60)
	check(is_equal_approx(state.alliances.alliance_chance(&"north_wolves"), 0.2), "Aggressive: 0.3 - 0.1")
	state.diplomacy.threat = 20
	check(is_equal_approx(state.alliances.alliance_chance(&"north_wolves"), 0.1), "Threat 20: -0.1")


func test_refused_alliance_waits_three_turns() -> void:
	var state := _state()
	_set_relation(state, &"south_farmers", 60)
	check_eq(state.alliances.propose_alliance(_high_rng(), &"south_farmers"), Alliances.AllianceResult.DECLINED, "Refused")
	check(not state.diplomacy.clans[&"south_farmers"].is_allied(), "Not allied")
	for i in 2:
		state.alliances.end_turn()
		check_eq(state.alliances.check_alliance(&"south_farmers"), Alliances.AllianceResult.COOLDOWN, "Still waiting")
	state.alliances.end_turn()
	check_eq(state.alliances.check_alliance(&"south_farmers"), Alliances.AllianceResult.OK, "Can ask again")


func test_alliance_raises_the_drift_target_and_expires() -> void:
	var state := _state()
	var before := state.diplomacy.target_relation(&"south_farmers")
	_ally(state, &"south_farmers")
	check_eq(state.diplomacy.target_relation(&"south_farmers"), before + 30, "+30 while allied")
	check_eq(state.alliances.allies(), [&"south_farmers"] as Array[StringName], "Listed as ally")
	var events: Array[Dictionary] = []
	for i in Alliances.ALLIANCE_TURNS:
		events = state.alliances.end_turn()
	check(not state.diplomacy.clans[&"south_farmers"].is_allied(), "Ended after 20 turns")
	check_eq(events, [{"clan_id": &"south_farmers", "event": &"alliance_expired"}], "Reported as expired")
	check_eq(state.alliances.check_alliance(&"south_farmers"), Alliances.AllianceResult.OK, "Can be signed again")


func test_alliance_breaks_below_friendly_and_cancelling_costs_30() -> void:
	var state := _state()
	_ally(state, &"south_farmers")
	_set_relation(state, &"south_farmers", 19)
	var events := state.alliances.end_turn()
	check_eq(events, [{"clan_id": &"south_farmers", "event": &"alliance_broken"}], "Fell apart")
	check(not state.diplomacy.clans[&"south_farmers"].is_allied(), "No longer allied")
	_ally(state, &"east_merchants")
	state.alliances.cancel_alliance(&"east_merchants")
	check(not state.diplomacy.clans[&"east_merchants"].is_allied(), "Cancelled")
	check_eq(state.diplomacy.clans[&"east_merchants"].relation, 30, "90 - 30 penalty - 30 alliance bonus")


# --- Declaring war on friends and treaty partners -------------------------------------------

func test_declaring_war_angers_the_targets_friends_most() -> void:
	var state := _state()
	var merchants := state.diplomacy.clans[&"east_merchants"].relation
	var farmers := state.diplomacy.clans[&"south_farmers"].relation
	state.wars.declare_war(&"north_wolves")
	check_eq(state.diplomacy.clans[&"east_merchants"].relation, merchants - 15, "Friend of the wolves: -15")
	check_eq(state.diplomacy.clans[&"south_farmers"].relation, farmers - 5, "Others: -5")


func test_betraying_an_ally_costs_everyone_and_ends_the_alliance() -> void:
	var state := _state()
	_ally(state, &"south_farmers")
	var steppe := state.diplomacy.clans[&"steppe_tribes"].relation
	var wolves := state.diplomacy.clans[&"north_wolves"].relation
	check_eq(state.wars.declare_penalty(&"south_farmers", &"north_wolves"), -5 - 20, "Preview")
	state.wars.declare_war(&"south_farmers")
	check(not state.diplomacy.clans[&"south_farmers"].is_allied(), "The alliance is gone")
	check_eq(state.diplomacy.clans[&"north_wolves"].relation, wolves - 25, "Others: -5 - 20 (ally)")
	check_eq(state.diplomacy.clans[&"steppe_tribes"].relation, steppe - 35, "Their friend: -15 - 20")


# --- Lent soldiers --------------------------------------------------------------------------

func test_allies_send_thirty_percent_unless_weak_or_friends_with_the_enemy() -> void:
	var state := _state()
	_ally(state, &"east_merchants")  # 65 soldiers, friend of north_wolves
	_ally(state, &"south_farmers")  # 40 soldiers
	check_eq(_lent_soldiers(state.create_kingdom_side(&"")), {&"east_merchants": 20, &"south_farmers": 12},
			"Both help against bandits")
	check_eq(_lent_soldiers(state.create_kingdom_side(&"north_wolves")), {&"south_farmers": 12},
			"Merchants will not fight their friend")
	state.wars.fronts[&"south_farmers"].strength = 11  # below 30% of 40
	check_eq(_lent_soldiers(state.create_kingdom_side(&"")), {&"east_merchants": 20}, "Weak allies stay home")


func test_shared_victory_costs_the_ally_soldiers_and_raises_relation() -> void:
	var state := _state()
	_ally(state, &"south_farmers")
	state.army.add_squad(&"swordsman", 20)
	state.army.add_squad(&"swordsman", 20)
	state.wars.declare_war(&"north_wolves")
	var relation := state.diplomacy.clans[&"south_farmers"].relation
	var invaders := state.wars.create_clan_side(&"north_wolves", 6, state.units)
	var record := _run(BattleSimulator.new(invaders, state.create_kingdom_side(&"north_wolves"), 1))
	var result := state.finish_invasion(&"north_wolves", record)
	check(result.won, "Invasion beaten")
	var sent: int = result.allies[&"south_farmers"].sent
	var lost: int = result.allies[&"south_farmers"].lost
	check_eq(sent, 12, "Farmers sent 12")
	check_eq(state.wars.fronts[&"south_farmers"].strength, 40 - lost, "Their losses come out of their army")
	check_eq(state.diplomacy.clans[&"south_farmers"].relation, relation + 5, "Shared win: +5")
	check_eq(result.allies[&"south_farmers"].relation, 5, "Reported")
	check_eq(state.army.count_squads(), 2, "Ally units never touch the kingdom's squads")


func test_shared_defeat_lowers_relation_and_counts_only_own_losses() -> void:
	var state := _state()
	_ally(state, &"south_farmers")
	state.army.add_squad(&"swordsman", 10)
	state.wars.declare_war(&"north_wolves")
	var relation := state.diplomacy.clans[&"south_farmers"].relation
	var invaders := state.wars.create_clan_side(&"north_wolves", 70, state.units)
	var record := _run(BattleSimulator.new(invaders, state.create_kingdom_side(&"north_wolves"), 1))
	var result := state.finish_invasion(&"north_wolves", record)
	check(not result.won, "Overrun")
	check_eq(state.diplomacy.clans[&"south_farmers"].relation, relation - 10, "Shared defeat: -10")
	var own_lost := 0
	for bucket in [result.casualties, result.scattered, result.retreat_losses]:
		for unit_id in bucket:
			own_lost += bucket[unit_id]
	check(own_lost <= 10, "Kingdom losses only count its own 10 soldiers (got %d)" % own_lost)


func test_friends_defend_the_attacked_clan_unless_allied() -> void:
	var state := _state()
	state.army.add_squad(&"swordsman", 20)
	state.wars.declare_war(&"north_wolves")  # friends: east_merchants (65), west_fortress (75)
	var simulator := state.start_attack(&"north_wolves")
	check_eq(_lent_soldiers(simulator.record.sides[BattleRecord.DEFENDER]), {&"east_merchants": 20, &"west_fortress": 23},
			"Both friends help")
	var state2 := _state()
	state2.army.add_squad(&"swordsman", 20)
	_ally(state2, &"east_merchants")
	state2.wars.declare_war(&"north_wolves")
	var sim2 := state2.start_attack(&"north_wolves")
	check_eq(_lent_soldiers(sim2.record.sides[BattleRecord.DEFENDER]), {&"west_fortress": 23}, "An ally does not defend them")
	check(_lent_soldiers(sim2.record.sides[BattleRecord.ATTACKER]).is_empty(), "…nor attack its own friend")


func test_helpers_lose_their_own_soldiers_not_the_targets() -> void:
	var state := _state()
	state.army.add_squad(&"swordsman", 20)
	state.wars.declare_war(&"north_wolves")
	var record := _run(state.start_attack(&"north_wolves"))
	var result := state.finish_attack(&"north_wolves", record)
	var helper_lost: int = result.helpers[&"east_merchants"].lost
	check_eq(state.wars.fronts[&"east_merchants"].strength, 65 - helper_lost, "The merchants pay for their own losses")
	check_eq(state.wars.fronts[&"north_wolves"].strength, 50 - result.enemy_lost, "The wolves only lose their own")
	check(result.enemy_lost <= 50, "enemy_lost excludes the helpers")


func test_alliance_needs_the_clan_in_reach() -> void:
	var state := _state()
	_set_relation(state, &"golden_eagle", 80)
	check_eq(state.alliances.check_alliance(&"golden_eagle"), Alliances.AllianceResult.TOO_FAR, "The far corner is out of reach")
	_set_relation(state, &"east_merchants", 80)
	check_eq(state.alliances.check_alliance(&"east_merchants"), Alliances.AllianceResult.OK, "Two steps away is fine")


func test_alliance_can_be_renewed_in_its_last_turns() -> void:
	var state := _state()
	_ally(state, &"south_farmers")
	check_eq(state.alliances.check_alliance(&"south_farmers"), Alliances.AllianceResult.ALREADY_ALLIED, "Not yet")
	for i in Alliances.ALLIANCE_TURNS - Alliances.ALLIANCE_RENEW_TURNS:
		state.alliances.end_turn()
	check_eq(state.diplomacy.clans[&"south_farmers"].alliance_turns, 5, "5 turns left")
	check_eq(state.alliances.check_alliance(&"south_farmers"), Alliances.AllianceResult.OK, "Renewable")
	check_eq(state.alliances.propose_alliance(_low_rng(), &"south_farmers"), Alliances.AllianceResult.OK, "Renewed")
	check_eq(state.diplomacy.clans[&"south_farmers"].alliance_turns, Alliances.ALLIANCE_TURNS, "Another 20 turns")


func test_alliance_bonus_is_part_of_the_relation_at_once() -> void:
	var state := _state()
	_set_relation(state, &"south_farmers", 60)
	state.alliances.propose_alliance(_low_rng(), &"south_farmers")
	check_eq(state.diplomacy.clans[&"south_farmers"].relation, 90, "+30 as soon as it is signed")
	state.diplomacy.clans[&"south_farmers"].alliance_turns = 1
	state.alliances.end_turn()
	check_eq(state.diplomacy.clans[&"south_farmers"].relation, 60, "…and gone when it expires")


# --- M16a: capped wariness, non-aggression pacts ------------------------------------------

func test_late_threat_is_capped() -> void:
	var state := _state()
	state.diplomacy.threat = 300
	check_eq(state.diplomacy.wariness_target(&"north_wolves"), Diplomacy.MAX_WARINESS, "Wariness stops at 40")
	_set_relation(state, &"north_wolves", 100)
	check(is_equal_approx(state.alliances.alliance_chance(&"north_wolves"), 0.3 + 0.5 - 0.1 - 0.25),
			"Threat takes at most 25% off the alliance chance")
	state.diplomacy.clans[&"north_wolves"].wariness = 200
	state.diplomacy.end_turn()
	check(state.diplomacy.clans[&"north_wolves"].wariness <= Diplomacy.MAX_WARINESS, "Old high wariness drops to the cap")


func test_allies_feel_no_threat() -> void:
	var state := _state()
	state.diplomacy.threat = 100
	_ally(state, &"east_merchants")
	check_eq(state.diplomacy.wariness_target(&"east_merchants"), 0, "No wariness toward an ally")


func test_pact_from_neutral_with_a_chance() -> void:
	var state := _state()
	_set_relation(state, &"north_wolves", -30)
	check_eq(state.alliances.check_pact(&"north_wolves"), Alliances.PactResult.NOT_NEUTRAL, "Tense: no pact")
	_set_relation(state, &"north_wolves", -19)
	check_eq(state.alliances.check_pact(&"north_wolves"), Alliances.PactResult.OK, "Neutral: can ask")
	check(is_equal_approx(state.alliances.pact_chance(&"north_wolves"), 0.4 - 0.1), "Aggressive, just Neutral: 0.4 - 0.1")
	_set_relation(state, &"north_wolves", 31)
	check(is_equal_approx(state.alliances.pact_chance(&"north_wolves"), 0.4 + 0.5 - 0.1), "+1% per relation point")
	check_eq(state.alliances.propose_pact(_high_rng(), &"north_wolves"), Alliances.PactResult.DECLINED, "Refused")
	check_eq(state.alliances.check_pact(&"north_wolves"), Alliances.PactResult.COOLDOWN, "Waits after a refusal")
	for i in Alliances.PACT_RETRY_TURNS:
		state.alliances.end_turn()
	var before := state.diplomacy.clans[&"north_wolves"].relation
	check_eq(state.alliances.propose_pact(_low_rng(), &"north_wolves"), Alliances.PactResult.OK, "Signed")
	check_eq(state.diplomacy.clans[&"north_wolves"].relation, before + Diplomacy.PACT_BASE_BONUS, "+10 while it runs")
	check_eq(state.alliances.check_pact(&"north_wolves"), Alliances.PactResult.ALREADY_HAS, "Only one at a time")


func test_pact_stops_war_declarations_and_expires() -> void:
	var state := _state()
	_set_relation(state, &"north_wolves", 20)
	state.alliances.propose_pact(_low_rng(), &"north_wolves")
	_set_relation(state, &"north_wolves", -100)
	check_eq(state.wars._declare_chance(&"north_wolves"), 0.0, "Hostile but bound by the pact")
	check(not state.wars.clan_declares_war(&"north_wolves"), "No war from events either")
	var events: Array[Dictionary] = []
	for i in Alliances.PACT_TURNS:
		events = state.alliances.end_turn()
	check(not state.diplomacy.clans[&"north_wolves"].has_pact(), "Ran out")
	check(events.any(func(e: Dictionary) -> bool: return e.event == &"pact_expired"), "Reported")
	check(state.wars._declare_chance(&"north_wolves") > 0.0, "May declare war again")


func test_breaking_a_pact_costs_everyone() -> void:
	var state := _state()
	_set_relation(state, &"north_wolves", 20)
	state.alliances.propose_pact(_low_rng(), &"north_wolves")
	check_eq(state.wars.declare_penalty(&"north_wolves", &"south_farmers"),
			Wars.DECLARE_OTHERS_PENALTY + Wars.BREAK_PACT_PENALTY, "Breaking the pact: -20 more")
	state.wars.declare_war(&"north_wolves")
	check(not state.diplomacy.clans[&"north_wolves"].has_pact(), "The pact is gone")


func test_pact_is_saved() -> void:
	var state := _state()
	_set_relation(state, &"north_wolves", 20)
	state.alliances.propose_pact(_low_rng(), &"north_wolves")
	var copy := _state()
	copy.diplomacy.load_save(JSON.parse_string(JSON.stringify(state.diplomacy.to_save())))
	check_eq(copy.diplomacy.clans[&"north_wolves"].pact_turns, Alliances.PACT_TURNS, "Turns left saved")
