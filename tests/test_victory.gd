extends "res://tests/test_suite.gd"

var terrains := TerrainLibrary.load_all()


func _state() -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.start()
	return state


func _annex(state: KingdomState, clan_ids: Array[StringName]) -> void:
	for clan_id in clan_ids:
		state.wars.fronts[clan_id].annexed = true
		state.diplomacy.clans[clan_id].annexed = true


func _ally(state: KingdomState, clan_ids: Array[StringName]) -> void:
	for clan_id in clan_ids:
		state.diplomacy.clans[clan_id].alliance_turns = 99


func _all_clans(state: KingdomState) -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(state.diplomacy.clans.keys())
	ids.sort()
	return ids


func test_uniting_every_clan_wins_and_allies_count() -> void:
	var state := _state()
	var ids := _all_clans(state)
	check_eq(ids.size(), 24, "24 clans on the map")
	_annex(state, ids.slice(0, 20))
	_ally(state, ids.slice(20, 23))
	check_eq(state.victory.check(state), Victory.NO_PATH, "23 of 24")
	check_eq(state.victory.progress(state), {"united": 23, "total": 24}, "Progress")
	_ally(state, ids.slice(23))
	check_eq(state.victory.check(state), Victory.Path.CONQUEST, "Every clan annexed or allied")
	check_eq(state.victory.check(state), Victory.NO_PATH, "Reported only once")
	check_eq(state.victory.won_path, Victory.Path.CONQUEST, "Remembered")


func test_castle_levels_need_united_clans() -> void:
	KingdomState.castle_needs_clans = true
	var state := _state()
	state.stockpile.add({&"food": 999, &"wood": 999, &"stone": 999, &"ore": 999, &"hardwood": 999, &"horses": 999})
	check_eq(state.check_castle_upgrade(), KingdomState.CastleResult.NEEDS_CLANS, "Level 2 needs one clan")
	_ally(state, [&"south_farmers"])
	check_eq(state.check_castle_upgrade(), KingdomState.CastleResult.OK, "An ally counts")
	state.upgrade_castle()
	check_eq(state.castle_level, 2, "Level 2")
	check_eq(state.check_castle_upgrade(), KingdomState.CastleResult.NEEDS_CLANS, "Level 3 needs three")
	_annex(state, [&"north_wolves", &"east_merchants"])
	check_eq(state.check_castle_upgrade(), KingdomState.CastleResult.OK, "1 ally + 2 annexed")
	var needed: Array[int] = []
	for level in state.castle_levels:
		needed.append(level.required_clans)
	check_eq(needed, [0, 1, 3, 6, 10, 15] as Array[int], "1 / 3 / 6 / 10 / 15 clans")
	KingdomState.castle_needs_clans = false


func test_castle_falls_when_an_invasion_wins_with_no_land_left() -> void:
	var state := _state()
	state.wars.declare_war(&"north_wolves")
	var first := state.finish_invasion(&"north_wolves", _lost_battle(state))
	check(not first.castle_fallen and not state.victory.lost, "Land left: only cells are lost")
	state.board.lose_edge_cells(Vector2i.UP, 100)
	check(state.victory.castle_in_danger(state), "Warned")
	var second := state.finish_invasion(&"north_wolves", _lost_battle(state))
	check(second.castle_fallen and state.victory.lost, "Castle falls")
	check_eq(state.victory.check(state), Victory.NO_PATH, "No victory after a loss")
	check_eq([state.stats.battles_won, state.stats.battles_lost], [0, 2], "Battles counted")


func _lost_battle(state: KingdomState) -> BattleRecord:
	var invaders := state.wars.create_clan_side(&"north_wolves", 40, state.units)
	var simulator := BattleSimulator.new(invaders, RaidSystem.create_kingdom_side(state), 1)
	while not simulator.finished:
		simulator.step()
	return simulator.record


func test_victory_state_is_saved() -> void:
	var state := _state()
	state.victory.won_path = Victory.Path.CONQUEST
	state.stats.battles_won = 3
	var data: Dictionary = JSON.parse_string(JSON.stringify(state.to_save()))
	var loaded := _state()
	loaded.load_save(data)
	check_eq(loaded.victory.won_path, Victory.Path.CONQUEST, "Won path")
	check_eq(loaded.stats.battles_won, 3, "Stats")
