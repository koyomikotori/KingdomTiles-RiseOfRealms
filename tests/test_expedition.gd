extends "res://tests/test_suite.gd"
## M14i: the uprising zone (start, spread, locked cells) and the expedition against it (away
## officers and squads, stages, rewards, defeat, save).

var terrains := TerrainLibrary.load_all()


func _state() -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.start()
	# The whole board is owned grass, so zones have room.
	for cell in state.board.get_all_cells():
		cell.owned = true
		if cell.building_id != BoardData.CASTLE_ID:
			cell.terrain_id = &"grass"
	return state


func _castle_cells(state: KingdomState) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in state.board.get_all_cells():
		if cell.building_id == BoardData.CASTLE_ID:
			result.append(cell.coord)
	return result


## Adds `count` full squads of `unit_id` and returns them.
func _squads(state: KingdomState, unit_id: StringName, count: int) -> Array[Army.Squad]:
	var result: Array[Army.Squad] = []
	for i in count:
		state.army.add_squad(unit_id, state.units[unit_id].squad_size)
		result.append(state.army.squads.back())
	return result


func test_a_zone_starts_on_the_edge_and_locks_its_cells() -> void:
	var state := _state()
	var uprising := state.uprising
	for turn in range(1, Uprising.FIRST_TURN):
		uprising.rng.seed = turn
		check_eq(uprising.end_turn(state.board, turn, false), &"", "Nothing before turn %d" % Uprising.FIRST_TURN)
	check(uprising.start(state.board), "Started")
	check_eq(uprising.cells.size(), 9, "A 3×3 block")
	var castle := _castle_cells(state)
	var on_edge := false
	for coord in uprising.cells:
		check(not castle.has(coord), "Never the castle")
		check(state.board.get_cell(coord).occupied, "Cells marked")
		on_edge = on_edge or coord.x == 0 or coord.y == 0 or coord.x == 11 or coord.y == 11
	check(on_edge, "Next to the territory's edge")
	var coord := uprising.cells[4]
	state.board.set_land(coord, &"grass", false)
	check_eq(BuildRules.check(state.board, state.stockpile, state.buildings[&"barracks"], coord), BuildRules.Result.REBELS,
			"Nothing built there")
	var piece := LandPiece.new(&"one", [Vector2i.ZERO] as Array[Vector2i], [&"grass"] as Array[StringName])
	check_eq(PlacementRules.check(state.board, piece, coord), PlacementRules.Result.REBELS, "No land placed there")


func test_buildings_in_the_zone_do_nothing() -> void:
	var state := _state()
	var uprising := state.uprising
	uprising.start(state.board)
	var coord := uprising.cells[4]
	var cell := state.board.get_cell(coord)
	cell.terrain_id = &"farmland"
	uprising.apply(state.board)
	state.stockpile.add({&"food": 500, &"wood": 500, &"stone": 500})
	cell.occupied = false
	check_eq(state.build(&"farm", coord), BuildRules.Result.OK, "A farm (before the zone took it)")
	check(not Economy.buildings_yield(state.board, state.buildings).is_empty(), "It produces")
	uprising.apply(state.board)
	check(Economy.buildings_yield(state.board, state.buildings).is_empty(), "Not in the zone")
	check_eq(state.board.count_buildings(&"farm"), 0, "Not counted as working")
	check_eq(state.board.count_buildings(&"farm", true), 1, "Still counted against the limit")
	check_eq(state.check_building_upgrade(coord), KingdomState.UpgradeResult.REBELS, "No upgrade")


func test_the_zone_spreads_every_two_turns_until_the_castle() -> void:
	var state := _state()
	var uprising := state.uprising
	uprising.start(state.board)
	check_eq(uprising.end_turn(state.board, 10, false), &"", "Not after one turn")
	check_eq(uprising.end_turn(state.board, 11, false), &"spread", "After two")
	check(uprising.cells.size() > 9, "Bigger")
	var size := uprising.cells.size()
	uprising.end_turn(state.board, 12, true)
	uprising.end_turn(state.board, 13, true)
	check_eq(uprising.cells.size(), size, "Not while an expedition is on the way")
	for i in 30:
		uprising.end_turn(state.board, 14 + i, false)
	check(uprising.touches_castle(state.board), "Reaches the castle")
	size = uprising.cells.size()
	uprising.end_turn(state.board, 50, false)
	uprising.end_turn(state.board, 51, false)
	check_eq(uprising.cells.size(), size, "And stops there")
	for coord in _castle_cells(state):
		check(not uprising.covers(coord), "The castle is never taken")
	check(uprising.size_factor() > 1.0, "A bigger zone is worth more")
	# Land lost meanwhile leaves the zone; growing the board moves it.
	var lost := uprising.cells[0]
	state.board.get_cell(lost).owned = false
	uprising.end_turn(state.board, 52, true)
	check(not uprising.covers(lost), "Lost land is dropped")
	var before := uprising.cells[0]
	uprising.shift(state.board, Vector2i(2, 0))
	check(uprising.covers(before + Vector2i(2, 0)), "Shifted with the board")


func test_away_officers_and_squads_stay_out_of_home_affairs() -> void:
	var state := _state()
	state.uprising.start(state.board)
	var general := state.generals.generate(2)
	state.generals.add(general)
	state.generals.set_commander(general)
	var advisor := state.advisors.generate(2)
	state.advisors.add(advisor)
	var post := advisor.post
	var home := _squads(state, &"swordsman", 1)
	var sent := _squads(state, &"spearman", 2)
	var none: Array[Army.Squad] = []
	check_eq(state.check_expedition(general, advisor, none), KingdomState.ExpeditionResult.NO_SQUADS, "Needs soldiers")
	var too_many := _squads(state, &"archer", Expedition.MAX_SQUADS + 1)
	check_eq(state.check_expedition(null, null, too_many), KingdomState.ExpeditionResult.TOO_MANY_SQUADS, "At most 10")
	for squad in too_many:
		state.army.remove_squad(squad)
	check_eq(state.start_expedition(general, advisor, sent), KingdomState.ExpeditionResult.OK, "Sent")
	check_eq(state.start_expedition(general, advisor, sent), KingdomState.ExpeditionResult.ALREADY_ON_THE_WAY, "Once")
	check(general.away and advisor.away and sent[0].away, "Away")
	check(state.generals.active_commander() == null, "No commander at home")
	check_eq(state.advisors.post_stat(post), 0, "The post does nothing meanwhile")
	var side := state.create_kingdom_side(&"")
	check_eq(side.units.size(), home.size(), "Only the squads at home fight there")
	state.dismiss_officer(general)
	check(state.generals.generals.has(general), "Cannot be dismissed")
	state.disband(sent[0])
	check(state.army.squads.has(sent[0]), "Cannot be disbanded")
	sent[0].soldiers = 1
	state._replenish()
	check_eq(sent[0].soldiers, 1, "Not replenished while away")


func test_a_won_expedition_clears_the_zone_and_pays() -> void:
	var state := _state()
	state.castle_level = 3
	state.uprising.start(state.board)
	var general := state.generals.generate(4)
	state.generals.add(general)
	var team := _squads(state, &"royal_swordguard", Expedition.MAX_SQUADS)
	for squad in team:
		squad.xp = 400.0
	state.start_expedition(general, null, team)
	var stages := Expedition.stages_for(3)
	check_eq(stages, 2, "Castle 3: two stages")
	var food_before := state.stockpile.get_amount(&"food")
	var reports: Array[Dictionary] = []
	for i in stages:
		reports.append(state.end_turn().expedition)
	check_eq(reports.size(), stages, "One stage a turn")
	check(reports[0].won and not reports[0].finished, "First stage won, more to go")
	check(reports[0].battles.size() >= Expedition.ambushes_for(3), "Every ambush fought")
	var last: Dictionary = reports.back()
	check(last.finished and last.cleared, "Done and cleared")
	check(state.expedition == null and not state.uprising.is_active(), "Zone gone")
	check(not general.away and general.xp > 0, "Home with XP")
	check(state.stockpile.get_amount(&"food") > food_before - 200, "Resources paid (net of upkeep)")
	check_eq(last.rewards.items.size(), stages, "An item per stage")
	check(state.uprising.next_allowed_turn > state.turn, "A pause before the next zone")
	check_eq(last.relation, KingdomState.EXPEDITION_RELATION, "Every clan is grateful (M16a)")
	check_eq(last.rewards.scrolls, 1, "Two stages: one scroll (M16c)")
	check_eq(state.scrolls, 1, "Scroll kept")
	check_eq(state.diplomacy.clans[&"north_wolves"].memories.get(Diplomacy.MEMORY_EXPEDITION),
			KingdomState.EXPEDITION_RELATION, "+5 remembered as the expedition")


func test_a_lost_expedition_loses_its_squads_and_keeps_the_zone() -> void:
	var state := _state()
	state.castle_level = 6
	state.uprising.start(state.board)
	for i in 20:
		state.uprising.spread(state.board)
	state.uprising.cleared = 10
	var team := _squads(state, &"swordsman", 1)
	team[0].soldiers = 2
	state.start_expedition(null, null, team)
	var report: Dictionary = state.end_turn().expedition
	check(not report.won and report.finished, "Beaten")
	check(not report.cleared, "The zone stays")
	check(not report.has("relation"), "No thanks for a lost expedition")
	check_eq(state.scrolls, 0, "No scroll for a lost expedition")
	check(state.uprising.is_active(), "Still there")
	check(not state.army.squads.has(team[0]), "The squad is lost")
	check(state.expedition == null, "Can send another")


func test_tables_and_save() -> void:
	check_eq([1, 2, 3, 4, 5, 6].map(func(level: int) -> int: return Expedition.stages_for(level)), [1, 1, 2, 2, 3, 4],
			"Stages by castle level")
	check_eq([1, 2, 3, 4, 5, 6].map(func(level: int) -> int: return Expedition.ambushes_for(level)), [1, 1, 2, 2, 3, 3],
			"Ambushes by castle level")
	check(Expedition.boss_chance(2, 0) > Expedition.boss_chance(0, 0), "The rebel general is likelier later")
	check(Expedition.enemy_units_for(3, 4, 2.0) <= Expedition.MAX_ENEMY_UNITS, "At most 5 units an ambush")
	var state := _state()
	state.castle_level = 6
	state.uprising.start(state.board)
	var general := state.generals.generate(3)
	state.generals.add(general)
	var team := _squads(state, &"royal_swordguard", 3)
	state.start_expedition(general, null, team)
	var copy := _state()
	copy.load_save(JSON.parse_string(JSON.stringify(state.to_save())))
	check(copy.expedition != null, "Expedition saved")
	check_eq(copy.expedition.squads.size(), 3, "With its squads")
	check(copy.expedition.general == copy.generals.generals[0] and copy.generals.generals[0].away, "And its general, away")
	check_eq(copy.uprising.cells.size(), state.uprising.cells.size(), "Zone saved")
	check(copy.board.get_cell(copy.uprising.cells[0]).occupied, "Cells marked again on load")


# --- M16e: a rebel general's challenge -------------------------------------------------------

## An expedition with a general, sent with `accept`; the RNG makes the challenge happen.
func _duel_expedition(accept: bool) -> Array:
	var state := _state()
	state.castle_level = 3
	state.uprising.start(state.board)
	var general := state.generals.generate(3)
	state.generals.add(general)
	state.start_expedition(general, null, _squads(state, &"royal_swordguard", 4), accept)
	var rng := RandomNumberGenerator.new()
	for seed_value in 1000:
		rng.seed = seed_value
		if rng.randf() < Expedition.DUEL_CHANCE:
			rng.seed = seed_value
			break
	return [state, general, state.expedition.run_stage(state, rng)]


func test_a_rebel_challenge_accepted() -> void:
	var picked := _duel_expedition(true)
	var state: KingdomState = picked[0]
	var general: General = picked[1]
	var report: Dictionary = picked[2]
	check(not report.duel.is_empty() and report.duel.accepted, "A challenge, accepted")
	check_eq(report.duel.index, 0, "The duel comes first")
	check(ExpeditionView.is_duel(report.battles[0]), "Two generals alone")
	if report.duel.won:
		check_eq(state.expedition.rebel_morale_next, -Expedition.DUEL_MORALE, "Rebels disheartened next stage")
		check(general.xp > 0, "The general learns")
	else:
		check_eq(report.general_fate, &"dead", "The general died")
		check(report.fallen == general and state.expedition.general == null, "Out of the expedition")
		check_eq(state.expedition.team_morale_next if state.expedition != null else -Expedition.DUEL_MORALE,
				-Expedition.DUEL_MORALE, "Team disheartened next stage")
	for row in ExpeditionScreen.unit_rows(report):
		check(not row.name.begins_with("Cận vệ") or report.battles.size() > 1, "The duel is not a unit row")
	check_eq(ExpeditionScreen.summary_lines(report)[0], "Trận đã đánh: %d · thắng %d." % [report.battles.size() - 1,
			report.battles.slice(1).filter(func(r: BattleRecord) -> bool: return r.winner == BattleRecord.ATTACKER).size()],
			"The duel is not counted as a battle")


func test_a_rebel_challenge_refused() -> void:
	var picked := _duel_expedition(false)
	var report: Dictionary = picked[2]
	check(not report.duel.accepted and report.duel.index == -1, "Refused, no duel fought")
	check_eq(report.team_morale, Expedition.DECLINE_MORALE, "−1 in this stage")
	check(not ExpeditionView.is_duel(report.battles[0]), "Ambushes only")


func test_morale_left_by_a_duel_is_used_next_stage() -> void:
	var state := _state()
	state.castle_level = 3
	state.uprising.start(state.board)
	state.start_expedition(null, null, _squads(state, &"royal_swordguard", 4))
	state.expedition.rebel_morale_next = -2
	var report := state.expedition.run_stage(state, RandomNumberGenerator.new())
	check_eq(report.rebel_morale, -2, "Applied in this stage")
	check_eq(state.expedition.rebel_morale_next, 0, "Then spent")


func test_unit_rows_group_by_unit() -> void:
	var state := _state()
	state.castle_level = 3
	state.uprising.start(state.board)
	state.start_expedition(null, null, _squads(state, &"royal_swordguard", 4))
	var report := state.expedition.run_stage(state, RandomNumberGenerator.new())
	var rows := ExpeditionScreen.unit_rows(report)
	check_eq(rows.size(), 1, "Four squads of one kind: one row")
	check_eq(rows[0].squads, 4, "Counted")
	check_eq(rows[0].left, "%d/4" % rows[0].left_count, "Kept / sent")
	var saved := state.expedition.to_save(state)
	state.expedition.accept_duels = false
	check(bool(saved.accept_duels), "Duel choice saved")
