extends "res://tests/test_suite.gd"
## M18b: achievements kept across games (GDD §30).

const FILE := "user://test_achievements.cfg"


func _state() -> KingdomState:
	AchievementStore.use_file(FILE)
	AchievementStore.clear()
	var terrains := TerrainLibrary.load_all()
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.setup_new_game({"tutorial": false})
	state.give_starting_resources()
	state.start()
	return state


func _ids(entries: Array[Dictionary]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in entries:
		ids.append(entry.id)
	return ids


func test_every_achievement_is_complete() -> void:
	var state := _state()
	var seen := {}
	check(Achievements.all().size() >= 40, "About forty achievements")
	for entry in Achievements.all():
		check(not seen.has(entry.id), "%s is listed once" % entry.id)
		seen[entry.id] = true
		check(Achievements.CATEGORIES.has(entry.category), "%s has a known category" % entry.id)
		check(not String(entry.title).is_empty() and not String(entry.description).is_empty(), "%s has words" % entry.id)
		check(entry.target >= 1, "%s has a target" % entry.id)
		check(GameArt.icon(StringName("achievement_" + String(entry.category))) != null, "%s has a medal" % entry.id)
		check(not String(entry.description).contains("bạn"), "%s never calls the ruler bạn" % entry.id)
		# Every measure is known (an unknown one warns and gives 0).
		Achievements.measure(entry.measure, state)
		var reward: Dictionary = entry.reward
		if reward.has("frame"):
			check(GameArt.portrait_part("frame_ruler_" + String(reward.frame)) != null, "%s frame drawn" % entry.id)
	check(GameArt.icon(Achievements.SECRET_ICON) != null, "Secret medal drawn")


## The board shows the file's order: easy to hard, every hidden one at the bottom.
func test_hidden_ones_come_last() -> void:
	var hidden_seen := false
	for entry in Achievements.all():
		if entry.hidden:
			hidden_seen = true
		else:
			check(not hidden_seen, "%s is listed before the hidden ones" % entry.id)
	check(hidden_seen, "Some achievements are hidden")


func test_measures_follow_the_game() -> void:
	var state := _state()
	check_eq(Achievements.measure(&"turn", state), state.turn, "Turn")
	check_eq(Achievements.measure(&"squads", state), state.army.count_squads(), "Squads")
	check_eq(Achievements.measure(&"castle_level", state), 1, "Castle level")
	check_eq(Achievements.measure(&"won", state), 0, "Not won yet")
	state.victory.won_path = Victory.Path.CONQUEST
	state.difficulty = Difficulty.Level.HARD
	check_eq(Achievements.measure(&"won_difficulty", state), 3, "Won on Hard")
	check_eq(Achievements.measure(&"won_fast", state), 1, "Won early")


func test_check_unlocks_once_and_keeps_progress() -> void:
	var state := _state()
	var first := _ids(Achievements.check(state))
	check(first.has(&"first_officer") == false, "No officer yet")
	check(not first.has(&"first_win"), "No battle won yet")
	state.stats["battles_won"] = 1
	var second := _ids(Achievements.check(state))
	check(second.has(&"first_win"), "A won battle unlocks it")
	check(AchievementStore.is_unlocked(&"first_win"), "Kept in the store")
	check(not _ids(Achievements.check(state)).has(&"first_win"), "Only once")
	check_eq(AchievementStore.progress(&"wins_25"), 1, "Progress toward 25 wins")
	state.stats["battles_won"] = 0
	Achievements.check(state)
	check_eq(AchievementStore.progress(&"wins_25"), 1, "The best progress stays")
	# Another game (or after a restart) still knows it.
	AchievementStore.use_file(FILE)
	check(AchievementStore.is_unlocked(&"first_win"), "Read back from the file")


func test_stats_are_counted() -> void:
	var state := _state()
	var general := state.generals.generate(3)
	state.generals.add(general)
	state.finish_spar(general, true)
	check_eq(int(state.stats.spars_won), 1, "A won spar")
	state.tutorial.start(state)
	state.tutorial.skip()
	check_eq(int(state.stats.tutorial_finished), 0, "A skipped tutorial does not count")
	state.tutorial.start(state)
	state.tutorial.step = Tutorial.STEPS.size() - 1
	state.tutorial.next(state)
	check_eq(int(state.stats.tutorial_finished), 1, "A finished tutorial counts")
	var data := state.to_save()
	var loaded := _state()
	loaded.load_save(data)
	check_eq(int(loaded.stats.spars_won), 1, "Saved")
	var old := data.duplicate(true)
	old.stats = {"battles_won": 2, "battles_lost": 1}
	loaded.load_save(old)
	check_eq(int(loaded.stats.market_buys), 0, "Older saves start at 0")


func test_rewards_unlock_looks() -> void:
	_state()
	check(Achievements.unlocked_rewards("color").is_empty(), "No colors yet")
	check_eq(Achievements.with_reward("frame").size(), 3, "Three ruler frames")
	AchievementStore.unlock(&"land_100")
	AchievementStore.unlock(&"victory")
	check_eq(Achievements.unlocked_rewards("color").size(), 1, "One color")
	check_eq(Achievements.unlocked_rewards("honor"), ["Bá Chủ Thiên Hạ"], "One honor")
	var ruler := Ruler.from_preset(1, "Lan")
	ruler.honor = "Minh Chủ"
	ruler.frame = "jade"
	check_eq(PortraitView.frame_part(ruler), "frame_ruler_jade", "The ruler's frame")
	var back := Ruler.from_save(ruler.to_save())
	check_eq([back.honor, back.frame], ["Minh Chủ", "jade"], "Saved with the ruler")
	check_eq(back.full_name(), "Lan · Minh Chủ", "Name with the honor")
	check_eq(Ruler.from_save({"preset": 0}).frame, "", "Older saves: the gold frame")
