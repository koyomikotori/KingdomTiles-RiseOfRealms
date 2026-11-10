extends "res://tests/test_suite.gd"
## M18a: the first-game tutorial (GDD §29).


func _state(tutorial: bool = true) -> KingdomState:
	var terrains := TerrainLibrary.load_all()
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.setup_new_game({"tutorial": tutorial})
	state.give_starting_resources()
	state.start()
	return state


func _index(id: StringName) -> int:
	for i in Tutorial.STEPS.size():
		if Tutorial.STEPS[i].id == id:
			return i
	return -1


func _go_to(state: KingdomState, id: StringName) -> void:
	state.tutorial.step = _index(id)
	state.tutorial._enter(state)


func test_on_for_new_games() -> void:
	check(not _state(false).tutorial.is_active(), "Tests can turn it off")
	var state := _state()
	check(state.tutorial.is_active(), "New games: on")
	check_eq(state.tutorial.current_id(), &"welcome", "Starts at the welcome")


func test_next_only_moves_reading_steps() -> void:
	var state := _state()
	check(state.tutorial.next(state), "Tiếp moves the welcome on")
	check_eq(state.tutorial.current_id(), &"select_piece", "Then pick a piece")
	check(not state.tutorial.next(state), "A step that needs an action ignores Tiếp")
	check(not state.tutorial.notify(&"piece_placed", state), "The wrong action does nothing")
	check(state.tutorial.notify(&"piece_selected", state), "The right action moves on")
	check_eq(state.tutorial.current_id(), &"place_piece", "Then place it")


func test_state_steps_count_from_their_start() -> void:
	var state := _state()
	_go_to(state, &"end_turn")
	check(not state.tutorial.update(state), "Nothing happened yet")
	state.end_turn()
	check(state.tutorial.update(state), "A new turn ends the step")
	_go_to(state, &"recruit")
	check(not state.tutorial.update(state), "The starting squads do not count")
	state.army.add_squad(&"swordsman", 10)
	check(state.tutorial.update(state), "One more squad ends it")


func test_hire_step_passes_while_castle_upgrades() -> void:
	var state := _state()
	_go_to(state, &"hire")
	check(not state.tutorial.update(state), "Waits for the Chiêu hiền tab")
	state.castle_turns = 2
	check(state.tutorial.update(state), "Chiêu hiền is closed during an upgrade: skip it")


func test_finishing_and_skipping_end_it() -> void:
	var state := _state()
	var endings: Array[bool] = []
	state.tutorial.ended.connect(func(skipped: bool) -> void: endings.append(skipped))
	_go_to(state, &"goal")
	check(state.tutorial.next(state), "The last step closes with Hoàn tất")
	check(not state.tutorial.is_active(), "Finished")
	var other := _state()
	other.tutorial.ended.connect(func(skipped: bool) -> void: endings.append(skipped))
	other.tutorial.skip()
	check(not other.tutorial.is_active(), "Skipped")
	check_eq(endings, [false, true] as Array[bool], "Finished, then skipped")


func test_progress_is_saved() -> void:
	var state := _state()
	_go_to(state, &"recruit")
	var data := state.to_save()
	var loaded := _state(false)
	loaded.load_save(data)
	check_eq(loaded.tutorial.current_id(), &"recruit", "Same step after loading")
	check_eq(loaded.tutorial.baseline, state.tutorial.baseline, "Same starting count")
	var old := data.duplicate()
	old.erase("tutorial")
	var older := _state(false)
	older.load_save(old)
	check(not older.tutorial.is_active(), "Older saves: no tutorial")


func test_every_step_is_told_by_both() -> void:
	for step: Dictionary in Tutorial.STEPS:
		for speaker in [Counselor.LINH_NHI, Counselor.TU_UYEN]:
			var lines := Counsel.tutorial_lines(step.id, speaker, {"kingdom": "vương quốc ta"})
			check(lines.size() == 1 and not String(lines[0].text).contains("{"), "%s by %s" % [step.id, speaker])
			if not lines.is_empty():
				check(not String(lines[0].text).contains("bạn"), "%s by %s never calls the ruler bạn" % [step.id, speaker])
