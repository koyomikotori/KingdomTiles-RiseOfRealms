extends "res://tests/test_suite.gd"

var terrains := TerrainLibrary.load_all()
var buildings := BuildingData.load_all()
var units := UnitData.load_all()


func _state() -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 5)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains, buildings, units)
	state.start()
	return state


func _rich_state() -> KingdomState:
	var state := _state()
	state.stockpile.add({&"food": 50, &"wood": 50, &"stone": 50})
	return state


func _paint(board: BoardData, terrain: StringName, coords: Array[Vector2i]) -> void:
	for coord in coords:
		board.set_land(coord, terrain, false)


func test_data_loads() -> void:
	check(buildings.has(&"barracks"), "Barracks is loaded")
	check_eq(units.size(), 21, "21 unit types (M13)")
	check_eq(units.slice(0, 3).map(func(u: UnitData) -> StringName: return u.unit_id),
			[&"swordsman", &"elite_swordsman", &"royal_swordguard"], "Units in sort order")
	for unit in units:
		check(not unit.recruit_cost.is_empty(), "%s has a recruit cost" % unit.unit_id)
		check(unit.squad_size > 0 and unit.melee_attack > 0 and unit.morale > 0, "%s has combat stats" % unit.unit_id)


func test_build_barracks_pays_cost() -> void:
	var state := _rich_state()
	check_eq(state.build(&"barracks", Vector2i(4, 4)), BuildRules.Result.OK, "Barracks on own grass")
	check_eq(state.board.get_cell(Vector2i(4, 4)).building_id, &"barracks", "Cell holds the barracks")
	check_eq([state.stockpile.get_amount(&"wood"), state.stockpile.get_amount(&"stone")], [44, 48], "Paid 6 wood, 2 stone")
	check_eq(state.build(&"barracks", Vector2i(7, 7)), BuildRules.Result.OK, "Second barracks")
	check_eq(state.build(&"barracks", Vector2i(4, 7)), BuildRules.Result.OK, "Third barracks")
	check_eq(state.build(&"barracks", Vector2i(7, 4)), BuildRules.Result.LIMIT_REACHED, "At most three barracks")


func test_build_rejections_change_nothing() -> void:
	var state := _state()
	check_eq(state.build(&"barracks", Vector2i(4, 4)), BuildRules.Result.CANNOT_AFFORD, "Empty stockpile")
	state.stockpile.add({&"wood": 6, &"stone": 2})
	check_eq(state.build(&"barracks", Vector2i(0, 0)), BuildRules.Result.NOT_OWNED, "Outside territory")
	check_eq(state.build(&"barracks", Vector2i(5, 5)), BuildRules.Result.OCCUPIED, "On the castle")
	check_eq(state.build(&"barracks", Vector2i(-1, 0)), BuildRules.Result.OUT_OF_BOUNDS, "Off the board")
	_paint(state.board, &"forest", [Vector2i(4, 4)])
	check_eq(state.build(&"barracks", Vector2i(4, 4)), BuildRules.Result.WRONG_TERRAIN, "Barracks needs grass")
	check_eq(state.board.count_buildings(&"barracks"), 0, "Nothing was built")
	check_eq([state.stockpile.get_amount(&"wood"), state.stockpile.get_amount(&"stone")], [6, 2], "Nothing was paid")


func test_pieces_cannot_cover_buildings() -> void:
	var state := _rich_state()
	state.build(&"barracks", Vector2i(4, 4))
	var piece := LandPiece.new(&"t", [Vector2i.ZERO] as Array[Vector2i], [&"forest"] as Array[StringName])
	check_eq(PlacementRules.check(state.board, piece, Vector2i(4, 4)), PlacementRules.Result.ON_BUILDING, "Barracks is protected")


func test_recruit_requires_barracks_and_resources() -> void:
	var state := _state()
	state.stockpile.add({&"food": 3, &"stone": 1, &"wood": 6})
	check_eq(state.recruit(&"swordsman"), RecruitmentRules.Result.NEEDS_BUILDING, "No barracks yet")
	state.stockpile.add({&"stone": 2})
	state.build(&"barracks", Vector2i(4, 4))
	check_eq(state.recruit(&"swordsman"), RecruitmentRules.Result.OK, "Recruit with barracks")
	check_eq(state.army.count_squads(&"swordsman"), 1, "One swordsman squad")
	check_eq(state.army.count_soldiers(&"swordsman"), 20, "A squad brings 20 swordsmen")
	# Stone: 1 + 2 added, 2 for the barracks, 1 for the swordsman.
	check_eq([state.stockpile.get_amount(&"food"), state.stockpile.get_amount(&"stone")], [0, 0], "Paid 3 food, 1 stone")
	check_eq(state.recruit(&"swordsman"), RecruitmentRules.Result.CANNOT_AFFORD, "Out of food")
	check_eq(state.army.count_squads(), 1, "Failed recruit adds nobody")


func test_archers_need_no_forest() -> void:
	var state := _rich_state()
	state.build(&"barracks", Vector2i(4, 4))
	check_eq(state.recruit(&"archer"), RecruitmentRules.Result.OK, "Archers need only a barracks (M13)")


func test_upkeep_is_paid_each_turn() -> void:
	var state := _rich_state()
	state.build(&"barracks", Vector2i(4, 4))
	state.recruit(&"swordsman")
	state.recruit(&"spearman")
	check_eq(state.get_upkeep(), {&"food": 2}, "2 squads eat 2 food")
	_paint(state.board, &"farmland", [Vector2i(7, 4)])
	state.build(&"farm", Vector2i(7, 4))
	check_eq(state.get_net_income().get(&"food"), 2, "Net food = 4 from the farm (5 - 1 on its own cell) - 2 upkeep")
	var food_before := state.stockpile.get_amount(&"food")
	var report := state.end_turn()
	check_eq(report.upkeep, {&"food": 2}, "Report shows upkeep")
	check(report.deserted.is_empty(), "Nobody deserts when fed")
	check_eq(state.stockpile.get_amount(&"food"), food_before + 4 - 2, "Stock = before + yield - upkeep")


func test_squads_desert_when_food_runs_out() -> void:
	var state := _state()
	state.army.add_squad(&"swordsman", 20)
	state.army.add_squad(&"spearman", 20)
	state.army.add_squad(&"swordsman", 7)
	state.army.add_squad(&"archer", 15)
	state.stockpile.add({&"food": 2})
	var report := state.end_turn()
	check_eq(report.deserted, {&"archer": 15, &"swordsman": 7}, "Most recently recruited squads leave first")
	check_eq(state.army.count_squads(), 2, "2 squads remain")
	check_eq(state.army.count_soldiers(), 40, "The two full squads stay")
	check_eq(state.stockpile.get_amount(&"food"), 0, "All food went to upkeep")


func test_army_squads() -> void:
	var army := Army.new()
	army.add_squad(&"swordsman", 20)
	army.add_squad(&"swordsman", 12)
	army.add_squad(&"archer", 0)
	check_eq([army.count_squads(), army.count_soldiers(&"swordsman")], [2, 32], "Empty squads are ignored")
	army.set_soldiers(army.squads[1], 0)
	check_eq(army.count_squads(), 1, "A squad reduced to 0 is removed")


func test_squad_capacity_from_castle_and_barracks() -> void:
	var state := _rich_state()
	check_eq(state.get_squad_capacity(), 3, "Castle garrison: 3 squads")
	state.build(&"barracks", Vector2i(4, 4))
	check_eq(state.get_squad_capacity(), 7, "Barracks adds 4")
	state.build(&"barracks", Vector2i(7, 7))
	check_eq(state.get_squad_capacity(), 11, "Second barracks adds 4 more")
	var garrison: Array[int] = []
	for level in range(1, 7):
		state.castle_level = level
		garrison.append(state.get_squad_capacity() - 8)
	check_eq(garrison, [3, 4, 5, 6, 7, 8] as Array[int], "The castle holds 3 → 8 squads by its level (M14d)")


func test_recruit_stops_at_capacity() -> void:
	var state := _rich_state()
	state.stockpile.add({&"food": 100, &"stone": 100})
	state.build(&"barracks", Vector2i(4, 4))
	for i in 7:
		check_eq(state.recruit(&"spearman"), RecruitmentRules.Result.OK, "Recruit squad %d of 7" % (i + 1))
	var food := state.stockpile.get_amount(&"food")
	check_eq(state.recruit(&"spearman"), RecruitmentRules.Result.ARMY_FULL, "Eighth squad refused")
	check_eq([state.army.count_squads(), state.stockpile.get_amount(&"food")], [7, food], "Refusal adds and charges nothing")
	state.disband(state.army.squads[0])
	check_eq(state.recruit(&"spearman"), RecruitmentRules.Result.OK, "Disbanding frees a slot")


func test_replenish_is_free_and_needs_barracks() -> void:
	var state := _state()
	state.army.add_squad(&"swordsman", 5)
	state.army.add_squad(&"archer", 14)
	state.stockpile.add({&"food": 10})
	var report := state.end_turn()
	check(report.replenished.is_empty(), "No barracks: no replenishment")
	check_eq(state.army.squads[0].soldiers, 5, "Squad unchanged")
	state.stockpile.add({&"wood": 6, &"stone": 2})
	state.build(&"barracks", Vector2i(4, 4))
	var food_before := state.stockpile.get_amount(&"food")
	report = state.end_turn()
	check_eq(report.replenished, {&"swordsman": 2, &"archer": 1}, "5% + 0.5% (level-1 barracks) of 20 = +2; archer only needs 1")
	check_eq([state.army.squads[0].soldiers, state.army.squads[1].soldiers], [7, 15], "Squads grew, never past full size")
	check_eq(state.stockpile.get_amount(&"food"), food_before - 2, "Only the usual upkeep was paid")
	for i in 7:
		state.stockpile.add({&"food": 2})
		state.end_turn()
	check_eq(state.army.squads[0].soldiers, 20, "Back to full strength after a few turns")


func test_disband_removes_squad_and_its_upkeep() -> void:
	var state := _state()
	state.army.add_squad(&"swordsman", 3)
	state.army.add_squad(&"spearman", 20)
	state.disband(state.army.squads[0])
	check_eq(state.army.count_squads(), 1, "One squad left")
	check_eq(state.army.squads[0].unit_id, &"spearman", "The right squad was removed")
	check_eq(state.get_army_upkeep(), {&"food": 1}, "Upkeep drops with it")


func test_barracks_levels_speed_up_replenishment() -> void:
	var state := _rich_state()
	check_eq(state.replenish_fraction(), 0.0, "No barracks: none")
	state.build(&"barracks", Vector2i(4, 4))
	check(is_equal_approx(state.replenish_fraction(), 0.055), "5% + 0.5% for a level-1 barracks (M16a)")
	state.board.set_building_level(Vector2i(4, 4), 5)
	check(is_equal_approx(state.replenish_fraction(), 0.075), "Level 5: +2.5%")
	state.build(&"barracks", Vector2i(7, 7))
	state.board.set_building_level(Vector2i(7, 7), 5)
	check(is_equal_approx(state.replenish_fraction(), 0.10), "Two level-5 barracks: +5%")
	state.board.set_construction(Vector2i(7, 7), 3, true)
	check(is_equal_approx(state.replenish_fraction(), 0.075), "One being upgraded does not count")


func test_new_games_start_with_three_peasant_squads() -> void:
	var state := _state()
	check_eq(state.army.count_squads(), 0, "Tests start without an army")
	state.give_starting_army()
	var ids := state.army.squads.map(func(s: Army.Squad) -> StringName: return s.unit_id)
	check_eq(ids, [&"swordsman", &"spearman", &"archer"], "A sword, spear and bow squad")
	check(state.army.squads.all(func(s: Army.Squad) -> bool: return s.soldiers == state.units[s.unit_id].squad_size),
			"At full strength")
	check(state.army.count_squads() <= state.get_squad_capacity(), "They fit in the castle")
