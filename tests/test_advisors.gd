extends "res://tests/test_suite.gd"
## M11f: advisors, posts and stratagems (GDD §8).

var terrains := TerrainLibrary.load_all()


func _state() -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.start()
	return state


func _rich(state: KingdomState) -> void:
	state.stockpile.add({&"food": 999, &"wood": 999, &"stone": 999, &"ore": 999, &"hardwood": 999, &"horses": 999})


func _advisor(state: KingdomState, admin: int, diplomacy: int, strategy: int, stars: int = 3) -> Advisor:
	var advisor := state.advisors.generate(stars)
	advisor.admin = admin
	advisor.diplomacy = diplomacy
	advisor.strategy = strategy
	return advisor


func _run(simulator: BattleSimulator) -> BattleRecord:
	while not simulator.finished:
		simulator.step()
	return simulator.record


func _unit(unit_id: StringName) -> UnitData:
	return UnitData.load_all().filter(func(u: UnitData) -> bool: return u.unit_id == unit_id)[0]


func test_data_loads() -> void:
	var advisors := Advisors.new()
	check_eq(advisors.stratagems.size(), 8, "Eight stratagems")
	check_eq(advisors.stratagems[&"fire_attack"].target, StratagemData.Target.ENEMY_LARGEST, "Fire attack hits the largest unit")


func test_generated_advisors_follow_the_stars() -> void:
	var advisors := Advisors.new()
	advisors.rng.seed = 3
	for stars in range(1, 7):
		var rank := advisors.ranks[stars]
		for i in 20:
			var advisor := advisors.generate(stars)
			var total := advisor.admin + advisor.diplomacy + advisor.strategy
			check(total >= roundi(rank.total_min * 1.5) and total <= roundi(rank.total_max * 1.5), "%d★ total %d" % [stars, total])
			for stat in [advisor.admin, advisor.diplomacy, advisor.strategy]:
				check(stat >= 1 and stat <= 10, "Stats 1-10")
			check_eq(advisor.stratagems.size(), stars, "%d★: %d stratagems" % [stars, stars])
			var unique := {}
			for id in advisor.stratagems:
				unique[id] = true
			check_eq(unique.size(), stars, "All different")


func test_posts_fill_and_swap() -> void:
	var state := _state()
	var a := _advisor(state, 5, 5, 5)
	var b := _advisor(state, 5, 5, 5)
	var c := _advisor(state, 5, 5, 5)
	for advisor in [a, b, c]:
		check(state.advisors.add(advisor), "Room for three")
	check(not state.advisors.add(_advisor(state, 1, 1, 1)), "No fourth advisor")
	check_eq([a.post, b.post, c.post], [&"admin", &"diplomacy", &"military"], "New advisors take the free posts")
	state.advisors.assign(c, &"admin")
	check_eq([a.post, c.post], [&"military", &"admin"], "Taking a held post swaps")
	state.advisors.dismiss(c)
	check(state.advisors.holder(&"admin") == null, "A dismissed advisor leaves the post empty")


func test_candidates_mix_generals_and_advisors() -> void:
	var state := _state()
	_rich(state)
	var kinds := {}
	for i in 20:
		state.generals.refresh_candidates(3, state.turn)
		for officer in state.generals.candidates:
			kinds[officer is Advisor] = true
	check(kinds.has(true) and kinds.has(false), "Both generals and advisors show up")
	check_eq(state.generals.candidates.size(), 3, "Still three candidates")
	# Recruit an advisor candidate.
	while not state.generals.candidates.any(func(o: Officer) -> bool: return o is Advisor):
		state.generals.refresh_candidates(3, state.turn)
	var index := 0
	while not state.generals.candidates[index] is Advisor:
		index += 1
	var advisor: Advisor = state.generals.candidates[index]
	check_eq(state.generals.recruit(state.stockpile, index), Generals.RecruitResult.OK, "Recruited")
	check(state.advisors.advisors.has(advisor) and state.generals.generals.is_empty(), "Joined the advisors")
	check_eq(advisor.post, &"admin", "Took the first free post")


func test_admin_post_helps_the_economy() -> void:
	var state := _state()
	_rich(state)
	# A row of 10 farms: 40 food a turn (5 - 1 each), so +15% is visible.
	for x in 10:
		state.board.set_land(Vector2i(1 + x, 1), &"farmland", false)
		state.board.place_building(&"farm", Vector2i(1 + x, 1), Vector2i.ONE)
	state.army.add_squad(&"swordsman", 20)
	var barracks := state.buildings[&"barracks"]
	var before_yield := state.get_turn_yield()
	var before_upkeep := state.get_army_upkeep()
	var admin := _advisor(state, 10, 1, 1)
	state.advisors.add(admin)
	var advisor_upkeep := state.advisors.get_upkeep()
	var cost := state.building_cost(barracks)
	for resource_id in barracks.cost:
		check_eq(cost[resource_id], barracks.cost[resource_id] - roundi(barracks.cost[resource_id] * 0.15), "−15%% %s" % resource_id)
	var after_yield := state.get_turn_yield()
	check_eq(before_yield.get(&"food", 0), 40, "10 farms")
	check(after_yield.get(&"food", 0) > before_yield.get(&"food", 0), "+15% production")
	check_eq(after_yield.get(&"food", 0) - before_yield.get(&"food", 0), roundi(before_yield.get(&"food", 0) * 0.15), "Exactly 15%")
	# Upkeep: squads (and generals) get cheaper, the advisor adds their own.
	var after_upkeep := state.get_army_upkeep()
	check_eq(after_upkeep.get(&"food", 0), before_upkeep.get(&"food", 0) - roundi(before_upkeep.get(&"food", 0) * 0.15)
			+ advisor_upkeep.get(&"food", 0), "Upkeep: discount, then the advisor's pay")
	check_eq(state.get_net_income(), _net_from_parts(state), "Income breakdown still adds up")
	var food := state.stockpile.get_amount(&"food")
	check_eq(state.build(&"barracks", Vector2i(4, 4)), BuildRules.Result.OK, "Built")
	check_eq(food - state.stockpile.get_amount(&"food"), cost.get(&"food", 0), "Paid the discounted cost")


func _net_from_parts(state: KingdomState) -> Dictionary[StringName, int]:
	var net := state.get_turn_yield()
	for resource_id in state.get_upkeep():
		net[resource_id] = net.get(resource_id, 0) - state.get_upkeep()[resource_id]
	for resource_id in net.keys():
		if net[resource_id] == 0:
			net.erase(resource_id)
	return net


func test_a_wounded_or_missing_advisor_does_nothing() -> void:
	var state := _state()
	var admin := _advisor(state, 10, 1, 1)
	state.advisors.add(admin)
	check_eq(state.advisors.post_stat(&"admin"), 10, "Working")
	admin.wounded_turns = 2
	check_eq(state.advisors.post_stat(&"admin"), 0, "Wounded: no effect")
	check_eq(state.advisors.post_stat(&"diplomacy"), 0, "Nobody in the post")


func test_diplomacy_post_helps_diplomacy() -> void:
	var state := _state()
	var clan: StringName = state.diplomacy.clans.keys()[0]
	var price := state.diplomacy.price_factor(clan, &"food", &"wood")
	var alliance := state.alliances.alliance_chance(clan)
	state.diplomacy.threat = 40
	var wariness := state.diplomacy.wariness_target(clan)
	var envoy := _advisor(state, 1, 10, 1)
	state.advisors.add(envoy)
	state.advisors.assign(envoy, &"diplomacy")
	check_eq(state.diplomacy.envoy, 10, "Diplomacy knows the envoy's skill")
	check(is_equal_approx(state.diplomacy.price_factor(clan, &"food", &"wood"), price * 1.15), "+15% trade price")
	check(state.alliances.alliance_chance(clan) >= alliance, "Alliance at least as likely")
	check(state.diplomacy.wariness_target(clan) < wariness, "Less wariness")
	state.advisors.dismiss(envoy)
	check_eq(state.diplomacy.envoy, 0, "Gone: no bonus")


func test_admin_and_diplomacy_learn_each_turn() -> void:
	var state := _state()
	_rich(state)
	var admin := _advisor(state, 3, 3, 3)
	var envoy := _advisor(state, 3, 3, 3)
	var strategist := _advisor(state, 3, 3, 3)
	for advisor in [admin, envoy, strategist]:
		state.advisors.add(advisor)
	for i in 3:
		state.end_turn()
	check_eq([admin.xp, envoy.xp], [30, 30], "+10 per turn in the admin and diplomacy posts")
	check_eq(strategist.xp, 0, "The military post learns only in battle")


func test_stratagems_fire_at_the_start() -> void:
	var stratagems := StratagemData.load_all()
	var worked := 0
	for seed_value in 40:
		var mine := BattleSide.new("Mine")
		mine.add_unit(_unit(&"swordsman"), 20)
		mine.advisor_name = "Test"
		mine.strategy = 10
		mine.stratagems.append(stratagems[&"fire_attack"])
		var enemy := BattleSide.new("Enemy")
		enemy.add_unit(_unit(&"spearman"), 20)
		enemy.add_unit(_unit(&"swordsman"), 10)
		var simulator := BattleSimulator.new(mine, enemy, seed_value)
		simulator.step()
		var used := simulator.record.events.filter(func(e: Dictionary) -> bool: return e.type == &"stratagem")
		if used.is_empty():
			check_eq(enemy.units[0].soldiers, 20.0, "Failed: nothing happened")
			continue
		worked += 1
		check_eq(used[0].stratagem, &"fire_attack", "Event names the stratagem")
		check(is_equal_approx(enemy.units[0].soldiers, 20.0 * (1.0 - 0.085)), "Largest unit lost 4% + 0.45% × 10")
		check_eq(enemy.units[1].soldiers, 10.0, "Other units untouched")
	# 25% + 30% = 55%.
	check(worked > 12 and worked < 32, "Works about half the time (%d/40)" % worked)


func test_stratagem_effects_by_target() -> void:
	var stratagems := StratagemData.load_all()
	var mine := BattleSide.new("Mine")
	mine.add_unit(_unit(&"swordsman"), 20)
	mine.add_unit(_unit(&"archer"), 15)
	mine.advisor_name = "Test"
	mine.strategy = 10
	var enemy := BattleSide.new("Enemy")
	enemy.add_unit(_unit(&"spearman"), 20)
	enemy.add_unit(_unit(&"archer"), 15)
	for id in [&"war_drums", &"ambush", &"formation", &"provoke", &"feint"]:
		mine.stratagems.append(stratagems[id])
	var morale_mine := mine.units[0].morale
	var morale_enemy := enemy.units[0].morale
	# Retry seeds until every stratagem worked.
	for seed_value in 500:
		var sides := _copy_sides(mine, enemy)
		var simulator := BattleSimulator.new(sides[0], sides[1], seed_value)
		simulator.step()
		if simulator.record.events.filter(func(e: Dictionary) -> bool: return e.type == &"stratagem").size() < 5:
			continue
		var own: BattleSide = sides[0]
		var foe: BattleSide = sides[1]
		check(is_equal_approx(own.units[0].morale, morale_mine + 3.0), "Drums: +1 + 0.2 × 10 morale")
		check(is_equal_approx(foe.units[0].morale, morale_enemy - 3.0), "Ambush: −1 − 0.2 × 10 morale")
		check(is_equal_approx(own.units[0].defense_mult, 1.15), "Formation: front row +15% defense")
		check(is_equal_approx(own.units[1].defense_mult, 1.0), "…not the archers behind")
		check(is_equal_approx(own.units[1].attack_mult, 1.15), "Provoke: everyone +15% melee attack")
		check(is_equal_approx(foe.units[1].range_mult, 0.7), "Feint: enemy archers −30% range attack")
		check(is_equal_approx(foe.units[0].range_mult, 1.0), "…not the spearmen")
		return
	check(false, "Some seed should make all five work")


func _copy_sides(mine: BattleSide, enemy: BattleSide) -> Array[BattleSide]:
	var result: Array[BattleSide] = []
	for side in [mine, enemy]:
		var copy := BattleSide.new(side.display_name)
		for unit in side.units:
			copy.add_unit(unit.data, unit.start_soldiers)
		copy.advisor_name = side.advisor_name
		copy.strategy = side.strategy
		copy.stratagems = side.stratagems.duplicate()
		result.append(copy)
	return result


func test_no_advisor_no_change() -> void:
	var a := BattleSide.new("A")
	a.add_unit(_unit(&"swordsman"), 20)
	var b := BattleSide.new("B")
	b.add_unit(_unit(&"spearman"), 20)
	var record := BattleSimulator.simulate(a, b, 7)
	check(not record.events.any(func(e: Dictionary) -> bool: return e.type == &"stratagem"), "No stratagems without an advisor")


func test_military_advisor_joins_battles() -> void:
	var state := _state()
	state.army.add_squad(&"archer", 15)
	var strategist := _advisor(state, 1, 1, 10)
	state.advisors.add(strategist)
	state.advisors.assign(strategist, &"military")
	var side := state.create_kingdom_side(&"")
	check_eq(side.advisor_name, strategist.name, "The advisor follows the army")
	check_eq(side.stratagems.size(), strategist.stratagems.size(), "With their stratagems")
	check(is_equal_approx(side.units[0].range_mult, 1.2), "+2% range attack per Mưu lược")
	check(is_equal_approx(side.units[0].morale, _unit(&"archer").morale + 2.5), "+0.25 morale per Mưu lược")
	strategist.wounded_turns = 1
	check_eq(state.create_kingdom_side(&"").advisor_name, "", "A wounded advisor stays home")


func test_military_advisor_after_battles() -> void:
	var wounded := 0
	for seed_value in 30:
		var state := _state()
		state.army.add_squad(&"spearman", 20)
		var strategist := _advisor(state, 1, 1, 5)
		state.advisors.add(strategist)
		state.advisors.assign(strategist, &"military")
		state.advisors.rng.seed = seed_value
		state.wars.declare_war(&"north_wolves")
		var invaders := state.wars.create_clan_side(&"north_wolves", 80, state.units)
		var record := _run(BattleSimulator.new(invaders, state.create_kingdom_side(&"north_wolves"), 1))
		var result := state.finish_invasion(&"north_wolves", record)
		check(not result.won, "Overrun")
		check_eq(result.advisor.xp, Advisors.BATTLE_XP, "A lost battle still teaches")
		check(state.advisors.advisors.has(strategist), "Never killed")
		if result.advisor.fate == &"wounded":
			wounded += 1
			check_eq(strategist.wounded_turns, Advisors.WOUND_TURNS, "Out for 3 turns")
	check(wounded > 5 and wounded < 25, "About half are wounded (%d/30)" % wounded)
	var state := _state()
	state.army.add_squad(&"swordsman", 20)
	state.army.add_squad(&"spearman", 20)
	var strategist := _advisor(state, 1, 1, 5)
	state.advisors.add(strategist)
	state.advisors.assign(strategist, &"military")
	state.wars.declare_war(&"north_wolves")
	var invaders := state.wars.create_clan_side(&"north_wolves", 8, state.units)
	var record := _run(BattleSimulator.new(invaders, state.create_kingdom_side(&"north_wolves"), 1))
	var result := state.finish_invasion(&"north_wolves", record)
	check(result.won, "An easy win")
	check_eq([result.advisor.xp, result.advisor.fate], [Advisors.BATTLE_XP + Advisors.WIN_XP, &"none"], "Win: more XP, no wound")


func test_advisor_points() -> void:
	var state := _state()
	var advisor := _advisor(state, 10, 4, 4, 1)
	state.advisors.add(advisor)
	advisor.gain_xp(100)
	check_eq(advisor.points, 1, "One point at level 2")
	check(not state.advisors.spend_point(advisor, &"admin"), "Nội chính already at 10")
	check(state.advisors.spend_point(advisor, &"strategy"), "Add to Mưu lược")
	check_eq([advisor.strategy, advisor.points], [5, 0], "Spent")


func test_advisors_are_saved() -> void:
	var state := _state()
	var a := _advisor(state, 6, 2, 3, 4)
	var b := _advisor(state, 1, 7, 2, 2)
	state.advisors.add(a)
	state.advisors.add(b)
	state.advisors.assign(a, &"military")
	a.wounded_turns = 1
	a.gain_xp(150)
	var data: Dictionary = JSON.parse_string(JSON.stringify(state.to_save()))
	var loaded := _state()
	loaded.load_save(data)
	check_eq(JSON.stringify(loaded.advisors.to_save()), JSON.stringify(state.advisors.to_save()), "Same advisors")
	check_eq(loaded.diplomacy.envoy, 7, "The envoy skill follows the loaded posts")
	check_eq(JSON.stringify(loaded.generals.to_save()), JSON.stringify(state.generals.to_save()), "Candidates (with advisors) kept")
