extends "res://tests/test_suite.gd"
## M16j: sparring with a wandering fighter (Spar, GDD §26).


func _state() -> KingdomState:
	var terrains := TerrainLibrary.load_all()
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.start()
	state.turn = 10
	return state


func _general(stars: int, might: int = 5, command: int = 5) -> General:
	var general := General.new()
	general.name = "Thử"
	general.stars = stars
	general.might = might
	general.command = command
	general.look = OfficerLook.from_seed("Thử")
	return general


func test_who_may_spar() -> void:
	var state := _state()
	var low := _general(2)
	check_eq(Spar.check(low, 10), Spar.Result.LOW_STARS, "2★ may not")
	var general := _general(3)
	check_eq(Spar.check(general, 10), Spar.Result.OK, "3★ may")
	general.away = true
	check_eq(Spar.check(general, 10), Spar.Result.AWAY, "Not while away")
	general.away = false
	general.wounded_turns = 2
	check_eq(Spar.check(general, 10), Spar.Result.WOUNDED, "Not while wounded")
	general.wounded_turns = 0
	general.level = general.max_level()
	check_eq(Spar.check(general, 10), Spar.Result.MAX_LEVEL, "Nothing to learn at the top")
	general.level = 1
	general.last_spar_turn = 8
	check_eq(Spar.check(general, 10), Spar.Result.COOLDOWN, "Rests 5 turns")
	check_eq(Spar.turns_left(general, 10), 3, "3 turns left")
	check(Spar.describe(Spar.Result.COOLDOWN, general, 10).contains("3"), "Says how long")
	check_eq(Spar.check(general, 13), Spar.Result.OK, "Ready again on turn 13")
	check_eq(state.check_spar(general), Spar.Result.AWAY, "Not one of the kingdom's generals")


func test_needle_and_zones_follow_the_stars() -> void:
	var easy := Spar.new(_general(3), 1)
	var hard := Spar.new(_general(6), 1)
	check(easy.sweep_time() > hard.sweep_time(), "The needle is faster for 6★")
	check(easy.perfect_half() > hard.perfect_half() and easy.good_half() > hard.good_half(), "Zones narrower")
	check(easy.dodge_open_share() < hard.dodge_open_share(), "The green ring is smaller")
	for i in Spar.SWEEP_TIME.size() - 1:
		check(Spar.PERFECT_HALF[i] > Spar.PERFECT_HALF[i + 1] and Spar.GOOD_HALF[i] > Spar.GOOD_HALF[i + 1]
				and Spar.DODGE_OPEN[i] < Spar.DODGE_OPEN[i + 1], "Every star is harder: %d" % i)
	check_eq(easy.needle_at(0.0), 0.0, "Starts on the left")
	check(is_equal_approx(easy.needle_at(easy.sweep_time()), 1.0), "Right edge after one sweep")
	check(is_equal_approx(easy.needle_at(easy.sweep_time() * 1.5), 0.5), "And back")
	check_eq(easy.grade(0.5), Spar.Grade.PERFECT, "Middle")
	check_eq(easy.grade(0.5 + easy.perfect_half() + 0.01), Spar.Grade.GOOD, "Beside it")
	check_eq(easy.grade(0.95), Spar.Grade.MISS, "Far off")
	var commander := Spar.new(_general(6, 5, 10), 1)
	check(is_equal_approx(commander.dodge_time() - hard.dodge_time(), 0.1), "Command lengthens the ring")
	var huge := Spar.new(_general(6, 5, 40), 1)
	check(is_equal_approx(huge.dodge_time() - Spar.DODGE_TIME[3], Spar.COMMAND_DODGE_MAX), "Up to the cap")


func test_damage_grows_with_might() -> void:
	var weak := Spar.new(_general(3, 0), 1)
	var strong := Spar.new(_general(3, 10), 1)
	check_eq(weak.damage_of(Spar.Grade.PERFECT), Spar.PERFECT_DAMAGE, "No might: base damage")
	check_eq(strong.damage_of(Spar.Grade.PERFECT), 28, "Might 10: +40%")
	check_eq(strong.damage_of(Spar.Grade.GOOD), 17, "Good hit, rounded")
	check_eq(strong.damage_of(Spar.Grade.MISS), 0, "A miss does nothing")


func test_a_round_is_a_strike_then_a_dodge() -> void:
	var spar := Spar.new(_general(3, 0), 7)
	check(spar.defend(&"up", 0.9).is_empty(), "No dodging before striking")
	var hit := spar.strike(0.5)
	check_eq(hit.damage, 20, "Perfect strike")
	check_eq(spar.rival_hp, 80, "Rival hurt")
	check_eq(spar.phase, Spar.Phase.DEFEND, "Now the rival strikes")
	check(spar.strike(0.5).is_empty(), "No second strike")
	var open := spar.dodge_time() * spar.dodge_open_share()
	check(not spar.dodges(spar.direction, open * 0.5), "Too early")
	check(not spar.dodges(&"" if spar.direction != &"" else &"up", open + 0.01), "No key")
	var wrong: StringName = Spar.DIRECTIONS[(Spar.DIRECTIONS.find(spar.direction) + 1) % 4]
	check(not spar.dodges(wrong, open + 0.01), "Wrong way")
	check(not spar.dodges(spar.direction, spar.dodge_time() + 0.01), "Too late")
	var dodge := spar.defend(spar.direction, open + 0.01)
	check(dodge.dodged and dodge.damage == 0, "Dodged")
	check_eq(spar.round_number, 2, "Next round")
	check_eq(spar.phase, Spar.Phase.ATTACK, "Our turn again")
	spar.strike(0.0)
	var taken := spar.defend(&"", spar.dodge_time() + 0.1)
	check(not taken.dodged and taken.damage == Spar.RIVAL_DAMAGE, "The ring closed")
	check_eq(spar.hp, 80, "General hurt")


func test_the_match_ends_by_knockout_or_after_five_rounds() -> void:
	var strong := Spar.new(_general(3, 10), 3)
	for i in 4:
		strong.strike(0.5)
		if not strong.is_over():
			strong.defend(&"", 9.0)
	check(strong.is_over() and strong.rival_hp == 0, "Four perfect strikes of 28 knock the rival down")
	check(strong.won(), "A win")
	var even := Spar.new(_general(3, 0), 3)
	for i in Spar.ROUNDS:
		even.strike(0.5 + even.perfect_half() + 0.01)  # good: 12
		even.defend(even.direction, even.dodge_time() * 0.75)
	check(even.is_over() and even.round_number == Spar.ROUNDS, "Five rounds")
	check_eq(even.rival_hp, 40, "5 × 12 taken")
	check(even.won(), "More health left wins")
	var poor := Spar.new(_general(3, 0), 3)
	for i in Spar.ROUNDS:
		poor.strike(0.0)
		poor.defend(&"", 9.0)
	check(poor.is_over() and poor.hp == 0 and not poor.won(), "Knocked down")
	var tie := Spar.new(_general(3, 0), 3)
	tie.hp = 60
	tie.rival_hp = 60
	tie.phase = Spar.Phase.DONE
	check(not tie.won(), "A tie goes to the rival")


func test_finishing_pays_xp_and_starts_the_cooldown() -> void:
	var state := _state()
	var general := _general(4)
	state.generals.add(general)
	check_eq(Spar.xp_reward(general, true), ceili(general.xp_to_next() * 0.4), "40% of the level")
	check_eq(Spar.xp_reward(general, false), ceili(general.xp_to_next() * 0.15), "15% on a loss")
	var before := general.xp
	var reward := state.finish_spar(general, true)
	check_eq(reward.xp, Spar.xp_reward(general, true) if general.level == 1 else reward.xp, "Reported")
	check(general.xp > before or general.level > 1, "XP gained")
	check_eq(general.last_spar_turn, 10, "Cooldown starts")
	check(state.finish_spar(general, true).is_empty(), "Not twice in 5 turns")
	var data: Dictionary = JSON.parse_string(JSON.stringify(general.to_save()))
	check_eq(General.from_save(data).last_spar_turn, 10, "Saved")
	data.erase("last_spar_turn")
	check_eq(Spar.check(General.from_save(data), 0), Spar.Result.OK, "Older saves: never sparred")


func test_the_rival_is_a_random_wandering_fighter() -> void:
	var kinds := {}
	for seed_value in range(1, 60):
		var spar := Spar.new(_general(3), seed_value)
		var rival := spar.rival
		kinds[rival.kind] = true
		var sprite: StringName = rival.sprite
		for layer in GameArt.LAYERS:
			check(ResourceLoader.exists(GameArt.UNIT_DIR + String(sprite) + layer + ".png"), "%s%s" % [sprite, layer])
		check_eq(GameArt.frames_of(sprite), GameArt.OFFICER_FRAMES, "%s has 4 frames" % sprite)
		check_eq(spar.rival_label(), rival.title, "Known by the title only")
	check_eq(kinds.size(), Spar.RIVALS.size(), "Every kind of rival turns up")
	check_eq(Spar.new(_general(3), 5).rival, Spar.new(_general(3), 5).rival, "Same seed, same rival")
