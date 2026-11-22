extends "res://tests/test_suite.gd"
## Administrative buildings (GDD §8 M14e).

var terrains := TerrainLibrary.load_all()


func _state() -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.start()
	state.stockpile.add({&"food": 900, &"wood": 900, &"stone": 900, &"ore": 900, &"hardwood": 900, &"horses": 900})
	return state


## Builds on a grass cell made for it.
func _build(state: KingdomState, building_id: StringName, at: Vector2i) -> BuildRules.Result:
	state.board.set_land(at, &"grass", false)
	return state.build(building_id, at)


func test_admin_buildings_unlock_with_the_castle() -> void:
	var state := _state()
	var buildings := state.buildings
	for id: StringName in [&"market", &"granary", &"academy", &"infirmary", &"magistrate"]:
		check_eq(buildings[id].category, BuildingData.Category.ADMIN, "%s is administrative" % id)
	check_eq(_build(state, &"market", Vector2i(4, 4)), BuildRules.Result.CASTLE_TOO_LOW, "Markets from castle level 2")
	var markets: Array[int] = []
	var academies: Array[int] = []
	for level in range(2, 7):
		markets.append(BuildRules.limit(buildings[&"market"], level))
		academies.append(BuildRules.limit(buildings[&"academy"], level))
	check_eq(markets, [1, 2, 3, 4, 5] as Array[int], "1 market at castle level 2, +1 per level")
	check_eq(academies, [1, 1, 1, 1, 1] as Array[int], "One academy")
	check_eq(BuildRules.limit(buildings[&"barracks"], 1), 3, "Others still count from level 1")


func test_markets_trade_more_and_better() -> void:
	var state := _state()
	state.castle_level = 6
	var clan := &"east_merchants"
	var capacity := state.diplomacy.remaining_capacity(clan)
	var price := state.diplomacy.price_factor(clan, &"wood", &"food")
	_build(state, &"market", Vector2i(4, 4))
	check_eq(state.diplomacy.remaining_capacity(clan), capacity + 10, "+10 trade value a turn")
	check(is_equal_approx(state.diplomacy.price_factor(clan, &"wood", &"food"), price * 1.03), "3% better prices")
	for at: Vector2i in [Vector2i(7, 4), Vector2i(4, 7), Vector2i(7, 7), Vector2i(2, 2)]:
		_build(state, &"market", at)
	check(is_equal_approx(state.diplomacy.price_factor(clan, &"wood", &"food"), price * 1.15), "15% at most")
	state.buildings_supplied = false
	check_eq(state.diplomacy.remaining_capacity(clan), capacity, "Unpaid markets do nothing")


func test_granaries_keep_plunder_and_feed_the_army() -> void:
	var state := _state()
	state.castle_level = 6
	for i in 10:
		state.army.add_squad(&"swordsman", 20)
	var upkeep: int = state.get_army_upkeep()[&"food"]
	_build(state, &"granary", Vector2i(4, 4))
	check(is_equal_approx(state.plunder_protection(), 0.1), "One granary keeps 10%")
	check_eq(state.get_army_upkeep()[&"food"], upkeep - roundi(upkeep * 0.02), "−2% army food")
	check_eq(state.get_net_income(), _net_from_parts(state), "Income breakdown adds up")
	for at: Vector2i in [Vector2i(7, 4), Vector2i(4, 7), Vector2i(7, 7), Vector2i(2, 2)]:
		_build(state, &"granary", at)
	check(is_equal_approx(state.plunder_protection(), 0.5), "Five granaries: 50%")
	# A lost raid takes 30% less half of it.
	var raid := RaidData.load_bandits()
	var food := state.stockpile.get_amount(&"food")
	state.army.squads.clear()
	var bandits := BattleSide.new("Quân cướp")
	bandits.add_unit(UnitData.load_enemies()[&"bandit_thug"], 16)
	var result := RaidSystem.resolve(state, raid, bandits, 1)
	check(not result.won, "No army: the raid is lost")
	check_eq(result.resources_lost[&"food"], floori(food * raid.resource_loss_on_defeat * 0.5), "Half kept from plunder")


func test_magistrate_adds_production() -> void:
	var state := _state()
	state.castle_level = 6
	state.board.set_land(Vector2i(2, 2), &"farmland", false)
	state.build(&"farm", Vector2i(2, 2))
	state.board.set_building_level(Vector2i(2, 2), 6)
	var food: int = state.get_turn_yield()[&"food"]
	_build(state, &"magistrate", Vector2i(4, 4))
	state.board.set_building_level(Vector2i(4, 4), 5)
	check_eq(state.get_turn_yield()[&"food"], food + roundi(food * 0.2), "Level 5: +20% production")
	check_eq(state.get_net_income(), _net_from_parts(state), "Income breakdown adds up")


func test_academy_teaches_and_infirmary_heals() -> void:
	var state := _state()
	state.castle_level = 6
	var general := state.generals.generate(3)
	state.generals.generals.append(general)
	general.wounded_turns = 3
	_build(state, &"academy", Vector2i(4, 4))
	state.board.set_building_level(Vector2i(4, 4), 2)
	state.stockpile.add({&"food": 500})
	state.end_turn()
	check_eq(general.xp, 10, "Level-2 academy: +10 XP a turn")
	check_eq(general.wounded_turns, 2, "Without an infirmary: one turn a turn")
	_build(state, &"infirmary", Vector2i(7, 4))
	state.board.set_building_level(Vector2i(7, 4), 5)
	state.end_turn()
	check_eq(general.wounded_turns, 0, "Infirmary: twice as fast")
	check(is_equal_approx(state.building_effect(&"commander_survival"), 0.2), "Level 5: −20% death chance")
	check(Generals.death_chance(general, 0.2) < Generals.death_chance(general), "…used by the death chance")
	var unit := BattleSide.Unit.new(state.units[&"swordsman"], 20, null)
	unit.soldiers = 10.0
	check_eq(BattleOutcome.soldiers_kept(unit, false, true), 5, "Lost battle: 50% kept")
	check_eq(BattleOutcome.soldiers_kept(unit, false, true, false, state.building_effect(&"retreat_keep")), 7,
			"Level-5 infirmary: 70% kept")


func _net_from_parts(state: KingdomState) -> Dictionary[StringName, int]:
	var net: Dictionary[StringName, int] = {}
	for resource_id in state.get_income_breakdown():
		for entry: Dictionary in state.get_income_breakdown()[resource_id]:
			net[resource_id] = net.get(resource_id, 0) + entry.amount
	for resource_id in net.keys():
		if net[resource_id] == 0:
			net.erase(resource_id)
	return net
