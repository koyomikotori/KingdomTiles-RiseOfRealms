extends "res://tests/test_suite.gd"
## M18f-a balance: barracks training by level, town squad slots, a stand-in commander at home,
## agents and the Sở cảnh sát removed.

var terrains := TerrainLibrary.load_all()


func _state(seed_value: int = 3) -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), seed_value)
	state.start()
	state.stockpile.add({&"food": 9000, &"wood": 9000, &"stone": 9000, &"ore": 9000, &"hardwood": 9000, &"horses": 9000})
	return state


func _barracks(state: KingdomState, at: Vector2i, level: int) -> void:
	state.board.set_land(at, &"grass", false)
	check_eq(state.build(&"barracks", at), BuildRules.Result.OK, "Barracks built")
	state.board.set_building_level(at, level)


func test_training_grows_with_barracks_levels() -> void:
	var state := _state()
	check_eq(state.training_xp(), 0.0, "No barracks: no training")
	_barracks(state, Vector2i(4, 4), 1)
	check_eq(state.training_xp(), Experience.TRAINING_XP, "Level 1: the old 10")
	state.board.set_building_level(Vector2i(4, 4), 4)
	check_eq(state.training_xp(), Experience.TRAINING_XP + 3.0, "Level 4: +3")
	_barracks(state, Vector2i(6, 4), 3)
	check_eq(state.training_xp(), Experience.TRAINING_XP + 5.0, "Every barracks adds its levels")
	check(not state.elite_training(), "No level 6 barracks yet")


func test_level_six_barracks_train_to_elite_at_half_speed() -> void:
	var state := _state()
	state.army.add_squad(&"swordsman", 10)
	var squad: Army.Squad = state.army.squads.back()
	state.army.train(50.0)
	state.army.train(50.0)
	state.army.train(50.0)
	check_eq(squad.xp, Experience.SQUAD_LEVEL_XP[1], "Without elite training it stops at Cựu binh")
	state.army.train(50.0, true)
	check_eq(squad.xp, Experience.SQUAD_LEVEL_XP[1] + 25.0, "Past Cựu binh at half speed")
	for i in 20:
		state.army.train(50.0, true)
	check_eq(squad.xp, Experience.SQUAD_LEVEL_XP[2], "Never past Tinh nhuệ")
	_barracks(state, Vector2i(4, 4), Experience.ELITE_TRAINING_LEVEL)
	check(state.elite_training(), "A level 6 barracks trains to Tinh nhuệ")


func test_every_town_of_ours_holds_five_squads() -> void:
	var state := _state()
	var before := state.get_squad_capacity()
	var ids: Array = state.diplomacy.clans.keys()
	for clan_id in ids:
		state.wars.fronts[clan_id].annexed = true
		state.diplomacy.clans[clan_id].annexed = true
	state.victory.check(state)
	state.start_realm()
	check_eq(state.get_squad_capacity(), before + 5 * Realm.TOWN_SQUADS, "The five home towns: +25 at once")
	var town := state.realm.towns[RealmMap.town_id(1, RealmMap.Slot.NORTH)]
	state.realm.capture(state, town)
	check_eq(state.get_squad_capacity(), before + 6 * Realm.TOWN_SQUADS, "A captured town: +5 more")


func test_a_general_stands_in_for_an_absent_commander() -> void:
	var state := _state()
	var commander := state.generals.generate(5)
	state.generals.add(commander)
	var low := state.generals.generate(2)
	state.generals.add(low)
	var high := state.generals.generate(4)
	state.generals.add(high)
	check_eq(state.generals.commander, commander, "The first general commands")
	check_eq(state.generals.home_leader(), commander, "Leads at home")
	check(state.generals.stand_in() == null, "No stand-in needed")
	commander.away = true
	check_eq(state.generals.home_leader(), high, "The most stars at home stands in")
	check_eq(state.generals.stand_in(), high, "Shown as the stand-in")
	check(state.generals.active_commander() == null, "Events still see no commander")
	var side := BattleSide.new("Ta")
	state.generals.lead(side, state.board, true)
	check_eq(side.general_name, high.name, "The stand-in leads the home battle")
	high.wounded_turns = 3
	check_eq(state.generals.home_leader(), low, "Then the next one")
	low.away = true
	check(state.generals.home_leader() == null, "Nobody left: no general")
	commander.away = false
	check_eq(state.generals.home_leader(), commander, "The commander takes over again")


func test_old_police_stations_are_refunded() -> void:
	var state := _state()
	var at := Vector2i(4, 4)
	state.board.set_land(at, &"grass", false)
	check(state.board.place_building(KingdomState.POLICE_ID, at, Vector2i.ONE), "An old save's police station")
	state.board.set_building_level(at, 3)
	var wood := state.stockpile.get_amount(&"wood")
	var refund := state._remove_police()
	check_eq(state.board.get_cell(at).building_id, CellData.NO_BUILDING, "Demolished")
	var expected_wood: int = KingdomState.POLICE_COST[&"wood"] * 6 + BuildingData.UPGRADE_EXTRA.get(&"wood", 0)
	check_eq(refund.get(&"wood", 0), expected_wood, "Levels 1 + 2 + 3 paid back")
	check_eq(state.stockpile.get_amount(&"wood"), wood + expected_wood, "Into the stockpile")
	check(state._remove_police().is_empty(), "Nothing more to refund")
	check(not state.buildings.has(KingdomState.POLICE_ID), "No police station to build any more")
