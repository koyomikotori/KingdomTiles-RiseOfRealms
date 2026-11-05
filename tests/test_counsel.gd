extends "res://tests/test_suite.gd"
## M16i: the counselors Linh Nhi and Tử Uyên and what they say.

## Every topic the game asks for, with the placeholders it fills.
const TOPICS := {
	&"game_start": {}, &"raid_won": {}, &"raid_lost": {}, &"invasion_won": {"clan": "X"},
	&"invasion_lost": {"clan": "X"}, &"attack_won": {"clan": "X"}, &"attack_lost": {"clan": "X"},
	&"annexed": {"clan": "X"}, &"battle_won": {}, &"battle_lost": {}, &"duel_won": {"general": "Y"},
	&"duel_lost": {"general": "Y"}, &"commander_fallen": {"general": "Y"}, &"expedition_stage_won": {},
	&"expedition_cleared": {}, &"expedition_failed": {}, &"news_war": {"clan": "X"}, &"news_agent": {},
	&"news_officer": {}, &"news_deserted": {}, &"news_ally_left": {}, &"news_uprising": {},
	&"news_castle_danger": {}, &"black_market": {}, &"victory": {}, &"defeat": {},
}


func _state(settings: Dictionary = {}) -> KingdomState:
	var terrains := TerrainLibrary.load_all()
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.setup_new_game(settings)
	state.start()
	return state


func test_every_topic_has_lines_for_both() -> void:
	for topic: StringName in TOPICS:
		check(Counsel.has_topic(topic), "%s exists" % topic)
		var context: Dictionary = TOPICS[topic].duplicate()
		context["kingdom"] = "Z"
		for speaker in Counselor.IDS:
			check(Counsel.topics()[String(topic)].get(String(speaker), []).size() >= 2,
					"%s: %s has a few lines" % [topic, speaker])
			# Many picks: every variant gets a turn.
			for i in 30:
				var lines := Counsel.lines(topic, speaker, context)
				check_eq(lines.size(), 1, "%s: one line" % topic)
				check(lines[0].speaker == speaker, "%s: only %s speaks" % [topic, speaker])
				check(lines[0].expression in Counselor.EXPRESSIONS, "%s: known expression %s" % [topic, lines[0].expression])
				check(not "{" in lines[0].text and not lines[0].text.is_empty(), "%s: filled text: %s" % [topic, lines[0].text])
				var other: String = Counselor.NAMES[Counselor.TU_UYEN if speaker == Counselor.LINH_NHI else Counselor.LINH_NHI]
				check(not other in lines[0].text, "%s: %s never answers the other one" % [topic, speaker])
	for topic: String in Counsel.topics():
		check(TOPICS.has(StringName(topic)), "%s is used by the game" % topic)
	check(Counsel.lines(&"no_such_topic", Counselor.LINH_NHI).is_empty(), "Unknown topic: silence")


func test_leader_is_chosen_and_saved() -> void:
	check_eq(_state().counselor, Counselor.LINH_NHI, "Linh Nhi by default")
	var state := _state({"counselor": Counselor.TU_UYEN})
	check_eq(state.counselor, Counselor.TU_UYEN, "Chosen on the new game screen")
	check_eq(_state({"counselor": &"nobody"}).counselor, Counselor.LINH_NHI, "Unknown id: Linh Nhi")
	var copy := _state()
	copy.load_save(JSON.parse_string(JSON.stringify(state.to_save())))
	check_eq(copy.counselor, Counselor.TU_UYEN, "Saved")
	var old := state.to_save()
	old.erase("counselor")
	copy.load_save(JSON.parse_string(JSON.stringify(old)))
	check_eq(copy.counselor, Counselor.LINH_NHI, "Older saves: Linh Nhi")


func test_news_picks_the_worst_topic() -> void:
	var news: Array[Dictionary] = [{"title": "a", "lines": ["x"], "topic": &"news_deserted", "context": {}},
			{"title": "b", "lines": ["y"], "topic": &"news_war", "context": {"clan": "X"}}]
	check_eq(ImportantNews.counsel_topic(news), [&"news_war", {"clan": "X"}], "War before deserters")
	check_eq(ImportantNews.counsel_topic([] as Array[Dictionary]), [&"", {}], "No news: nothing to say")
	for topic in ImportantNews.COUNSEL_ORDER:
		check(Counsel.has_topic(topic), "%s has lines" % topic)


func test_portraits_fall_back_to_generated_parts() -> void:
	for id in Counselor.IDS:
		var officer := Counselor.fallback_officer(id)
		check_eq(officer.name, Counselor.NAMES[id], "%s's fallback face" % id)
		for entry: Array in PortraitView.layers(officer, Color.WHITE):
			check(GameArt.portrait_part(entry[0]) != null, "%s: part %s" % [id, entry[0]])
