extends "res://tests/test_suite.gd"
## M16k: the memory card match between the Chúa công and an advisor (MemoryMatch, GDD §27).


func _state() -> KingdomState:
	var terrains := TerrainLibrary.load_all()
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.start()
	state.turn = 10
	return state


func _advisor(stars: int) -> Advisor:
	var advisor := Advisor.new()
	advisor.name = "Thử"
	advisor.stars = stars
	advisor.look = OfficerLook.from_seed("Thử")
	return advisor


## The other card with the same face as `card`.
func _twin(game: MemoryMatch, card: int) -> int:
	for other in game.cards.size():
		if other != card and game.cards[other] == game.cards[card]:
			return other
	return -1


## A card in play that is not `card`'s twin (and not `card`).
func _stranger(game: MemoryMatch, card: int) -> int:
	for other in game.cards.size():
		if other != card and game.taken[other] == MemoryMatch.NOBODY and game.cards[other] != game.cards[card]:
			return other
	return -1


func test_who_may_play() -> void:
	var state := _state()
	check_eq(MemoryMatch.check(_advisor(2), 10), MemoryMatch.Result.LOW_STARS, "2★ may not")
	var advisor := _advisor(3)
	check_eq(MemoryMatch.check(advisor, 10), MemoryMatch.Result.OK, "3★ may")
	advisor.away = true
	check_eq(MemoryMatch.check(advisor, 10), MemoryMatch.Result.AWAY, "Not while away")
	advisor.away = false
	advisor.wounded_turns = 1
	check_eq(MemoryMatch.check(advisor, 10), MemoryMatch.Result.WOUNDED, "Not while wounded")
	advisor.wounded_turns = 0
	advisor.level = advisor.max_level()
	check_eq(MemoryMatch.check(advisor, 10), MemoryMatch.Result.MAX_LEVEL, "Nothing to learn at the top")
	advisor.level = 1
	advisor.last_memory_turn = 7
	check_eq(MemoryMatch.check(advisor, 10), MemoryMatch.Result.COOLDOWN, "Rests 5 turns")
	check(MemoryMatch.describe(MemoryMatch.Result.COOLDOWN, advisor, 10).contains("2"), "Says how long")
	check_eq(MemoryMatch.check(advisor, 12), MemoryMatch.Result.OK, "Ready again on turn 12")
	check_eq(state.check_memory(advisor), MemoryMatch.Result.AWAY, "Not one of the kingdom's advisors")


func test_the_board_grows_with_the_stars() -> void:
	var sizes := {3: Vector2i(4, 4), 4: Vector2i(5, 4), 5: Vector2i(6, 5), 6: Vector2i(6, 6)}
	for stars: int in sizes:
		var game := MemoryMatch.new(_advisor(stars), 3)
		check_eq(Vector2i(game.columns, game.rows), sizes[stars], "%d★ board" % stars)
		check_eq(game.cards.size(), game.columns * game.rows, "%d★: a card per cell" % stars)
		var counts := {}
		for face in game.cards:
			counts[face] = counts.get(face, 0) + 1
		check_eq(counts.size(), game.pair_count(), "%d★: every face in play" % stars)
		check(counts.values().all(func(n: int) -> bool: return n == 2), "%d★: exactly two of each" % stars)
	check(MemoryMatch.new(_advisor(3), 1).remember_chance() < MemoryMatch.new(_advisor(6), 1).remember_chance(),
			"A 6★ advisor remembers better")
	check(MemoryMatch.FACES.size() >= 18, "Faces for the 6×6 board")
	for face in MemoryMatch.FACES.size():
		check(MemoryScreen.face_texture(face) != null, "Face %d has a picture" % face)
	check_eq(MemoryMatch.new(_advisor(4), 9).cards, MemoryMatch.new(_advisor(4), 9).cards, "Same seed, same deal")


func test_a_pair_keeps_the_turn_and_a_miss_passes_it() -> void:
	var game := MemoryMatch.new(_advisor(3), 5)
	var twin := _twin(game, 0)
	check(game.flip(0).second == false, "First card")
	check(game.flip(0).is_empty(), "Not the same card twice")
	var pair := game.flip(twin)
	check(pair.pair, "A pair")
	check_eq(game.scores[MemoryMatch.Side.RULER], 1, "Scored")
	check_eq(game.side, MemoryMatch.Side.RULER, "Flips again")
	check(game.flip(0).is_empty(), "Taken cards stay")
	var card := _stranger(game, 0)
	var other := _stranger(game, card)
	game.flip(card)
	var miss := game.flip(other)
	check(miss.second and not miss.pair and game.waiting(), "No pair: both stay up")
	check(game.flip(_stranger(game, other)).is_empty(), "No third card")
	game.end_turn()
	check_eq(game.side, MemoryMatch.Side.ADVISOR, "The advisor's turn")
	check(game.picked.is_empty(), "Turned down")


func test_the_advisor_uses_what_they_remember() -> void:
	var game := MemoryMatch.new(_advisor(6), 2)
	game.memory.clear()
	var card := 0
	var twin := _twin(game, card)
	game.memory[card] = game.cards[card]
	game.memory[twin] = game.cards[twin]
	game.side = MemoryMatch.Side.ADVISOR
	var first := game.ai_pick()
	check(first == card or first == twin, "Goes for the remembered pair")
	game.flip(first)
	check_eq(game.ai_pick(), twin if first == card else card, "Then its twin")
	game.flip(twin if first == card else card)
	check_eq(game.scores[MemoryMatch.Side.ADVISOR], 1, "The advisor scores")
	check(not game.memory.has(card) and not game.memory.has(twin), "Forgets taken cards")
	game.memory.clear()
	var pick := game.ai_pick()
	check(game.taken[pick] == MemoryMatch.NOBODY, "Otherwise an unknown card in play")
	game.flip(pick)
	var known := _twin(game, pick)
	game.memory[known] = game.cards[known]
	check_eq(game.ai_pick(), known, "Finds the twin of the card just turned up")


func test_a_whole_match_ends_with_a_winner() -> void:
	for stars in [3, 6]:
		var game := MemoryMatch.new(_advisor(stars), 11)
		var steps := 0
		while not game.is_over() and steps < 2000:
			steps += 1
			if game.waiting():
				game.end_turn()
			elif game.side == MemoryMatch.Side.ADVISOR:
				game.flip(game.ai_pick())
			else:  # a forgetful player: always the first two cards in play
				var free := range(game.cards.size()).filter(func(c: int) -> bool:
					return game.taken[c] == MemoryMatch.NOBODY and not game.picked.has(c))
				game.flip(free[0])
		check(game.is_over(), "%d★: over" % stars)
		check_eq(game.scores[0] + game.scores[1], game.pair_count(), "%d★: every pair taken" % stars)
		check_eq(game.ruler_won(), game.scores[0] > game.scores[1], "%d★: more pairs win" % stars)
	var tie := MemoryMatch.new(_advisor(3), 1)
	tie.scores = [4, 4]
	check(tie.is_over() and not tie.ruler_won(), "A tie goes to the advisor")


func test_finishing_pays_the_advisor_and_starts_the_cooldown() -> void:
	var state := _state()
	var advisor := _advisor(4)
	state.advisors.add(advisor)
	check_eq(MemoryMatch.xp_reward(advisor, true), ceili(advisor.xp_to_next() * 0.4), "40% when the Chúa công wins")
	check_eq(MemoryMatch.xp_reward(advisor, false), ceili(advisor.xp_to_next() * 0.15), "15% otherwise")
	var expected := MemoryMatch.xp_reward(advisor, true)
	var reward := state.finish_memory(advisor, true)
	check_eq(reward.xp, expected, "Reported")
	check_eq(advisor.last_memory_turn, 10, "Cooldown starts")
	check(state.finish_memory(advisor, true).is_empty(), "Not twice in 5 turns")
	var data: Dictionary = JSON.parse_string(JSON.stringify(advisor.to_save()))
	check_eq(Advisor.from_save(data).last_memory_turn, 10, "Saved")
	data.erase("last_memory_turn")
	check_eq(MemoryMatch.check(Advisor.from_save(data), 0), MemoryMatch.Result.OK, "Older saves: never played")
