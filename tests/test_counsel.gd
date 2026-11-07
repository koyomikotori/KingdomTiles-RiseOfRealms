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
	&"event_good": {}, &"event_bad": {}, &"event_mixed": {}, &"event_neutral": {},
	&"spar_won": {"general": "Y", "rival": "Z"}, &"spar_lost": {"general": "Y", "rival": "Z"}, &"memory_won": {"advisor": "Y"}, &"memory_lost": {"advisor": "Y"},
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


# --- M16i-b: the counselor tells every event --------------------------------------------------

func test_every_event_is_told_by_both() -> void:
	var events := EventData.load_all()
	for event_id in events:
		var event := events[event_id]
		check(Counsel.events().has(String(event_id)), "%s has lines" % event_id)
		var context := {"kingdom": "Z", "clan": "X", "officer": "W"}
		for speaker in Counselor.IDS:
			var options: Array = Counsel.events().get(String(event_id), {}).get(String(speaker), [])
			check(options.size() >= 2, "%s: %s has two lines" % [event_id, speaker])
			for line: Array in options:
				var text := String(line[1])
				check(StringName(line[0]) in Counselor.EXPRESSIONS, "%s: expression %s" % [event_id, line[0]])
				check(not "{clan}" in text or event.needs_clan, "%s: {clan} only for clan events" % event_id)
				check(not "{officer}" in text or event.officer_request != &"", "%s: {officer} only for requests" % event_id)
				check(not text.format(context).contains("{"), "%s: every placeholder is known" % event_id)
				check(not _calls_ruler_ban(text), "%s: %s calls the ruler Chúa công: %s" % [event_id, speaker, text])
			var lines := Counsel.event_lines(event_id, speaker, context)
			check(lines.size() == 1 and lines[0].speaker == speaker, "%s: one line of %s" % [event_id, speaker])
	for event_id: String in Counsel.events():
		check(events.has(StringName(event_id)), "%s is a real event" % event_id)
	check(Counsel.event_lines(&"no_such_event", Counselor.LINH_NHI).is_empty(), "Unknown event: own text")


func test_no_line_calls_the_ruler_ban() -> void:
	for source: Dictionary in [Counsel.topics(), Counsel.events()]:
		for key: String in source:
			for speaker: String in source[key]:
				for line: Array in source[key][speaker]:
					check(not _calls_ruler_ban(String(line[1])), "%s / %s: %s" % [key, speaker, line[1]])


## "bạn" as a word addressing the ruler (not "bạn bè": friends).
func _calls_ruler_ban(text: String) -> bool:
	var lower := text.to_lower().replace("bạn bè", "")
	var regex := RegEx.create_from_string("(^|[^\\p{L}])bạn([^\\p{L}]|$)")
	return regex.search(lower) != null


func test_the_default_kingdom_name_is_never_said() -> void:
	var state := _state()
	check_eq(state.kingdom_name, KingdomState.DEFAULT_KINGDOM_NAME, "Default name")
	check_eq(Counsel.context(state).kingdom, "vương quốc ta", "Said as 'vương quốc ta'")
	check_eq(Counsel.context(state, {"clan": "X"}).clan, "X", "Extra context kept")
	var named := _state({"name": "Đại Nam"})
	check_eq(Counsel.context(named).kingdom, "Đại Nam", "A chosen name is said as it is")
	for speaker in Counselor.IDS:
		for i in 20:
			check(not Counsel.lines(&"game_start", speaker, Counsel.context(state))[0].text.contains("của bạn"),
					"No 'của bạn' in the welcome")


func test_result_tone_follows_what_really_happened() -> void:
	var outcome := EventOutcomeData.new()
	var none: Array[String] = []
	check_eq(EventSystem.tone(outcome, none), &"event_neutral", "Nothing happened")
	var gain: Array[String] = ["Nhận: Gỗ 20"]
	check_eq(EventSystem.tone(outcome, gain), &"event_good", "A gain")
	var empty: Array[String] = ["Đã trả: Lương thực 10", "Không thu được gì."]
	check_eq(EventSystem.tone(outcome, empty), &"event_neutral", "An empty roll after paying is not a gain or a loss")
	var loss: Array[String] = ["Mất: Lương thực 15"]
	check_eq(EventSystem.tone(outcome, loss), &"event_bad", "A loss")
	outcome.relation = -20
	check_eq(EventSystem.tone(outcome, gain), &"event_mixed", "Seized goods: gain and anger")
	outcome.relation = 10
	check_eq(EventSystem.tone(outcome, none), &"event_good", "Friendship")
	var enemy := EventOutcomeData.new()
	enemy.morale_amount = -2
	enemy.morale_enemy = true
	check_eq(EventSystem.tone(enemy, none), &"event_good", "The enemy loses heart")
	enemy.morale_enemy = false
	check_eq(EventSystem.tone(enemy, none), &"event_bad", "Our army loses heart")
	var uprising := EventOutcomeData.new()
	uprising.force_uprising = true
	check_eq(EventSystem.tone(uprising, none), &"event_bad", "Rebels")


func test_resolve_reports_the_tone() -> void:
	var state := _state()
	state.events.pending = [{"event_id": &"bumper_harvest", "clan_id": &""}] as Array[Dictionary]
	var result := state.events.resolve(state, RandomNumberGenerator.new(), 0)
	check_eq(result.tone, &"event_good", "A harvest stored is good")
	state.events.pending = [{"event_id": &"settlers", "clan_id": &""}] as Array[Dictionary]
	check_eq(state.events.resolve(state, RandomNumberGenerator.new(), 1).tone, &"event_neutral", "Refusing settlers")
