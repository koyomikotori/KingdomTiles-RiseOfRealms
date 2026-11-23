extends "res://tests/test_suite.gd"
## M18g quality of life: the build check, the end-turn reminder, batch recruiting, the remembered
## battle speed, completed buildings report where they are.

const TEST_SETTINGS := "user://test_m18g_settings.cfg"

var terrains := TerrainLibrary.load_all()


func _state(seed_value: int = 3) -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), seed_value)
	state.start()
	return state


func _rich(state: KingdomState) -> void:
	state.stockpile.add({&"food": 9000, &"wood": 9000, &"stone": 9000, &"ore": 9000, &"hardwood": 9000, &"horses": 9000})


func test_check_build_matches_build() -> void:
	var state := _state()
	var at := Vector2i(4, 4)
	state.board.set_land(at, &"grass", false)
	check_eq(state.check_build(&"barracks", at), BuildRules.Result.CANNOT_AFFORD, "Nothing in the stockpile")
	_rich(state)
	var wood := state.stockpile.get_amount(&"wood")
	check_eq(state.check_build(&"barracks", at), BuildRules.Result.OK, "Now it fits")
	check_eq(state.stockpile.get_amount(&"wood"), wood, "Checking costs nothing")
	check_eq(state.build(&"barracks", at), BuildRules.Result.OK, "And it builds")


func test_the_reminder_lists_unfinished_business() -> void:
	var state := _state()
	var keys := EndTurnReminder.items(state).map(func(item: Dictionary) -> StringName: return item.key)
	check(keys.has(EndTurnReminder.PIECES), "Pieces in hand")
	check(keys.has(EndTurnReminder.BUILDERS), "Idle builders")
	check(not keys.has(EndTurnReminder.RECRUIT), "Nothing to recruit with")
	check(not keys.has(EndTurnReminder.ARMIES), "No realm yet")
	_rich(state)
	state.board.set_land(Vector2i(4, 4), &"grass", false)
	state.build(&"barracks", Vector2i(4, 4))
	keys = EndTurnReminder.items(state).map(func(item: Dictionary) -> StringName: return item.key)
	check(keys.has(EndTurnReminder.RECRUIT), "Room and money for soldiers")
	var general := state.generals.generate(2)
	state.generals.add(general)
	general.points = 1
	check_eq(EndTurnReminder.officer_with_points(state), general, "A general with a point to spend")
	state.hand.pieces.clear()
	keys = EndTurnReminder.items(state).map(func(item: Dictionary) -> StringName: return item.key)
	check(not keys.has(EndTurnReminder.PIECES), "No pieces left")
	check(keys.has(EndTurnReminder.POINTS), "Points listed")


func test_recruiting_several_squads() -> void:
	var state := _state()
	_rich(state)
	state.board.set_land(Vector2i(4, 4), &"grass", false)
	state.build(&"barracks", Vector2i(4, 4))
	var free := state.get_squad_capacity() - state.army.count_squads()
	check_eq(state.affordable_recruits(&"swordsman"), free, "Limited by the free slots")
	var before := state.army.count_squads()
	check_eq(state.recruit_many(&"swordsman", 2), 2, "Two squads at once")
	check_eq(state.army.count_squads(), before + 2, "Both in the army")
	check_eq(state.recruit_many(&"swordsman", 99), 0, "All or nothing")
	check_eq(state.army.count_squads(), before + 2, "Nothing changed")


func test_battle_speed_is_remembered() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	GameSettings.use_file(TEST_SETTINGS)
	check_eq(GameSettings.battle_speed(), 0, "x1 at first")
	check(GameSettings.end_turn_reminder(), "The reminder is on by default")
	GameSettings.set_battle_speed(2)
	GameSettings.set_end_turn_reminder(false)
	GameSettings.use_file(TEST_SETTINGS)
	check_eq(GameSettings.battle_speed(), 2, "Read back")
	check(not GameSettings.end_turn_reminder(), "Off stays off")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	GameSettings.use_file(GameSettings.PATH)


func test_completed_buildings_say_where() -> void:
	var state := _state()
	_rich(state)
	KingdomState.instant_construction = false
	var at := Vector2i(4, 4)
	state.board.set_land(at, &"grass", false)
	state.build(&"watchtower", at)
	var report := state.end_turn()
	KingdomState.instant_construction = true
	check_eq(report.completed.size(), 1, "The watchtower is done")
	check_eq(report.completed[0].origin, at, "With its place")
