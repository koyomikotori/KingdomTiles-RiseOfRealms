extends "res://tests/test_suite.gd"
## M16c: limit breaks for generals and advisors (conditions, cost, raised caps, scrolls, save).

var terrains := TerrainLibrary.load_all()


func _state() -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.start()
	state.stockpile.add({&"food": 1000, &"wood": 1000, &"stone": 1000, &"ore": 1000, &"hardwood": 1000,
			&"horses": 1000})
	return state


## A general of `stars` at their max level with both stats at the cap.
func _maxed_general(state: KingdomState, stars: int) -> General:
	var general := state.generals.generate(stars)
	state.generals.add(general)
	general.level = general.max_level()
	general.might = Generals.STAT_MAX
	general.command = Generals.STAT_MAX
	return general


func test_breaks_by_stars() -> void:
	var counts: Array = []
	for stars in range(1, 7):
		var officer := Officer.new()
		officer.stars = stars
		counts.append(LimitBreak.max_breaks(officer))
	check_eq(counts, [1, 1, 2, 2, 3, 3], "1-2 stars: 1, 3-4: 2, 5-6: 3")


func test_cost_grows_with_each_break() -> void:
	var officer := Officer.new()
	officer.stars = 6
	check_eq(LimitBreak.cost(officer)[&"food"], 100, "First: 100 food")
	check_eq(LimitBreak.cost(officer)[&"horses"], 20, "First: 20 horses")
	check_eq(LimitBreak.scrolls_needed(officer), 1, "First: one scroll")
	officer.breaks = 2
	check_eq(LimitBreak.cost(officer)[&"stone"], 300, "Third: x3")
	check_eq(LimitBreak.scrolls_needed(officer), 3, "Third: three scrolls")


func test_conditions() -> void:
	var state := _state()
	var general := state.generals.generate(3)
	state.generals.add(general)
	check_eq(state.check_limit_break(general), LimitBreak.Result.NOT_MAX_LEVEL, "Needs the max level")
	general.level = general.max_level()
	check_eq(state.check_limit_break(general), LimitBreak.Result.NO_SCROLLS, "Needs a scroll")
	state.scrolls = 1
	general.away = true
	check_eq(state.check_limit_break(general), LimitBreak.Result.AWAY, "Not while away")
	general.away = false
	check_eq(state.check_limit_break(general), LimitBreak.Result.OK, "Ready")
	var poor := _state()
	poor.stockpile.spend(poor.stockpile.get_all())
	poor.scrolls = 1
	var other := poor.generals.generate(3)
	poor.generals.add(other)
	other.level = other.max_level()
	check_eq(poor.check_limit_break(other), LimitBreak.Result.NO_RESOURCES, "Needs the resources")
	check_eq(poor.limit_break(other), LimitBreak.Result.NO_RESOURCES, "Refused")
	check_eq(other.breaks, 0, "Nothing changed")
	check_eq(poor.scrolls, 1, "Scroll kept")


func test_a_break_raises_caps_and_spends() -> void:
	var state := _state()
	state.scrolls = 3
	var general := _maxed_general(state, 2)
	general.points = 3
	var level := general.level
	check(not state.generals.can_spend_point(general, &"might"), "Capped at 10")
	var food := state.stockpile.get_amount(&"food")
	check_eq(state.limit_break(general), LimitBreak.Result.OK, "Broken through")
	check_eq(general.breaks, 1, "One break")
	check_eq(state.scrolls, 2, "One scroll spent")
	check_eq(state.stockpile.get_amount(&"food"), food - 100, "Resources spent")
	check_eq(general.max_level(), level + LimitBreak.LEVEL_STEP, "Max level +2")
	check_eq(general.stat_cap(Generals.STAT_MAX), 12, "Cap 12")
	check(state.generals.spend_point(general, &"might") and state.generals.spend_point(general, &"might"),
			"Leftover points spent")
	check_eq(general.might, 12, "Up to 12")
	check(not state.generals.can_spend_point(general, &"might"), "Capped at 12")
	general.gain_xp(100000)
	check_eq(general.level, level + LimitBreak.LEVEL_STEP, "Levels again up to the new cap")
	check_eq(state.check_limit_break(general), LimitBreak.Result.NO_BREAKS_LEFT, "2 stars: only once")


func test_advisors_break_too() -> void:
	var state := _state()
	state.scrolls = 1
	var advisor := state.advisors.generate(5)
	state.advisors.add(advisor)
	advisor.level = advisor.max_level()
	advisor.admin = Advisors.STAT_MAX
	advisor.points = 1
	check(not state.advisors.can_spend_point(advisor, &"admin"), "Capped")
	check_eq(state.limit_break(advisor), LimitBreak.Result.OK, "Broken through")
	check(state.advisors.spend_point(advisor, &"admin"), "Above 10 now")
	check_eq(advisor.admin, 11, "11")


func test_scrolls_by_stages() -> void:
	check_eq([1, 2, 3, 4].map(func(stages: int) -> int: return Expedition.scrolls_for(stages)), [1, 1, 2, 2],
			"One per two stages, at least one")


func test_saved() -> void:
	var state := _state()
	state.scrolls = 2
	var general := _maxed_general(state, 4)
	state.scrolls += 1
	state.limit_break(general)
	var copy := _state()
	copy.load_save(JSON.parse_string(JSON.stringify(state.to_save())))
	check_eq(copy.scrolls, 2, "Scrolls saved")
	check_eq(copy.generals.generals[0].breaks, 1, "Breaks saved")
	var old := state.to_save()
	old.erase("scrolls")
	var older := _state()
	older.load_save(JSON.parse_string(JSON.stringify(old)))
	check_eq(older.scrolls, 0, "Older saves: none")


func test_requirement_view_colors_costs() -> void:
	for id: StringName in [&"check", &"cross", &"gain", &"time", &"scroll"]:
		check(GameArt.icon(id) != null, "Icon %s drawn" % id)
	var stockpile := Stockpile.new()
	stockpile.add({&"food": 50, &"wood": 5})
	var view := RequirementView.new()
	check(view.requirement("Met", true), "Returns met")
	check(not view.requirement("Not met", false), "Returns not met")
	view.costs({&"food": 30, &"wood": 10}, stockpile, "Giá:")
	var chips := view.get_child(view.get_child_count() - 1)
	var food: Label = chips.get_child(1).get_child(1)
	var wood: Label = chips.get_child(2).get_child(1)
	check_eq(food.get_theme_color("font_color"), RequirementView.MET_COLOR, "Enough food: green")
	check_eq(wood.get_theme_color("font_color"), RequirementView.UNMET_COLOR, "Not enough wood: red")
	check_eq(chips.get_child(2).tooltip_text, "Gỗ: cần 10, đang có 5", "Tooltip says what is held")
	view.free()
