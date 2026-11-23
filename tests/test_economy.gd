extends "res://tests/test_suite.gd"

var terrains := TerrainLibrary.load_all()


func _piece(offsets: Array[Vector2i], terrain: StringName, key_index: int = LandPiece.NO_KEY) -> LandPiece:
	var piece_terrains: Array[StringName] = []
	for i in offsets.size():
		piece_terrains.append(terrain)
	return LandPiece.new(&"test", offsets, piece_terrains, key_index)


func _row(length: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in length:
		result.append(Vector2i(x, 0))
	return result


func _state(seed_value: int = 3) -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, seed_value)
	return KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains, BuildingData.load_all())


## Economy v2 (GDD §8): the land yields nothing by itself, key cells included.
func test_land_yields_nothing() -> void:
	for terrain_id: StringName in [&"farmland", &"forest", &"hill", &"grass"]:
		check(Economy.cell_yield(terrains[terrain_id], false).is_empty(), "%s gives nothing" % terrain_id)
		check(Economy.cell_yield(terrains[terrain_id], true).is_empty(), "Key %s gives nothing" % terrain_id)
	check(Economy.cell_yield(null, false).is_empty(), "Empty land gives nothing")


func test_resource_types_loaded_in_order() -> void:
	var ids := ResourceTypeData.load_all().map(func(t: ResourceTypeData) -> StringName: return t.resource_id)
	check_eq(ids, [&"food", &"wood", &"stone", &"ore", &"hardwood", &"horses"], "Resource bar order")


## Testing cheat (Ctrl+Shift+M): every resource tops up to CHEAT_RESOURCES, never past it.
func test_cheat_fills_every_resource() -> void:
	var state := _state()
	state.stockpile.add({&"food": 50})
	state.cheat_fill_resources()
	state.cheat_fill_resources()
	for type in ResourceTypeData.load_all():
		check_eq(state.stockpile.get_amount(type.resource_id), KingdomState.CHEAT_RESOURCES, "%s filled" % type.resource_id)


func test_starting_board_yields_nothing() -> void:
	check(Economy.board_yield(BoardData.create_starting_board(12), terrains).is_empty(), "All-grass start yields nothing")


func test_placing_land_changes_no_yield() -> void:
	var board := BoardData.create_starting_board(12)
	var piece := _piece(_row(4), &"farmland", 1)
	check(Economy.placement_delta(board, piece, Vector2i(4, 3), terrains).is_empty(), "No yield change predicted")
	PlacementRules.apply(board, piece, Vector2i(4, 3))
	check(Economy.board_yield(board, terrains).is_empty(), "Farmland alone yields nothing")


func test_unowned_cells_do_not_yield() -> void:
	var board := BoardData.create_starting_board(12)
	board.set_terrain(Vector2i(0, 0), &"forest")
	check(Economy.board_yield(board, terrains).is_empty(), "Terrain outside the territory yields nothing")


func test_stockpile_spend_is_all_or_nothing() -> void:
	var stock := Stockpile.new()
	stock.add({&"food": 5, &"wood": 2})
	check(stock.can_afford({&"food": 5}), "Can afford exact amount")
	check(not stock.spend({&"food": 3, &"wood": 3}), "Cannot spend more wood than held")
	check_eq([stock.get_amount(&"food"), stock.get_amount(&"wood")], [5, 2], "Failed spend changes nothing")
	check(stock.spend({&"food": 3, &"wood": 2}), "Affordable spend succeeds")
	check_eq([stock.get_amount(&"food"), stock.get_amount(&"wood")], [2, 0], "Spend subtracts")
	check_eq(stock.get_amount(&"stone"), 0, "Unknown resource is 0")


func test_end_turn_collects_and_deals_new_hand() -> void:
	var state := _state()
	state.start()
	check_eq(state.turn, 1, "Game starts on turn 1")
	check_eq(state.hand.pieces.size(), 3, "First hand has 3 pieces")
	# A lumber mill on a key forest: 5 wood, doubled. Food pays its upkeep.
	PlacementRules.apply(state.board, _piece(_row(2), &"forest", 0), Vector2i(4, 3))
	state.board.place_building(&"lumber_mill", Vector2i(4, 3), Vector2i.ONE)
	state.stockpile.add({&"food": 10})
	var old_pieces := state.hand.pieces.duplicate()
	var report := state.end_turn()
	check_eq(report.collected, {&"wood": 10}, "Collected 5 wood × 2 (key)")
	check_eq(state.stockpile.get_amount(&"wood"), 10, "Stockpile received the yield")
	check_eq(state.turn, 2, "Turn advanced")
	check_eq(state.hand.pieces.size(), 3, "New hand has 3 pieces")
	for piece in state.hand.pieces:
		check(not old_pieces.has(piece), "Unplaced pieces were discarded, not kept")
	state.end_turn()
	check_eq(state.stockpile.get_amount(&"wood"), 20, "Yield is collected again every turn")


func test_new_games_get_starting_resources() -> void:
	var state := _state()
	check_eq(state.stockpile.get_amount(&"food"), 0, "Empty until given")
	state.give_starting_resources()
	check_eq(state.stockpile.get_all(), {&"food": 80, &"wood": 80, &"stone": 80, &"ore": 10, &"hardwood": 10,
			&"horses": 10}, "80 of each basic resource, 10 of each other")


func test_place_piece_consumes_only_on_success() -> void:
	var state := _state()
	state.start()
	var bad := state.place_piece(0, Vector2i(0, 0))
	check(bad != PlacementRules.Result.OK, "Far-away placement fails")
	check_eq(state.hand.pieces.size(), 3, "Failed placement keeps the piece")
	# The piece is random, so search the board for any valid origin.
	var placed := false
	for y in range(0, 12):
		for x in range(0, 12):
			if not placed and state.place_piece(0, Vector2i(x, y)) == PlacementRules.Result.OK:
				placed = true
	check(placed, "Some valid spot exists for the first piece")
	check_eq(state.hand.pieces.size(), 2, "Successful placement uses the piece")
