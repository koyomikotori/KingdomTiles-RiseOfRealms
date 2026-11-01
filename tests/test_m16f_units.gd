extends "res://tests/test_suite.gd"
## Horse archers, monks, the temple, market levels, advisor numbers and agreement renewal (GDD §22,
## M16f).

var terrains := TerrainLibrary.load_all()
var resource_types := ResourceTypeData.load_all()


func _state() -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.start()
	state.stockpile.add({&"food": 900, &"wood": 900, &"stone": 900, &"ore": 900, &"hardwood": 900, &"horses": 900})
	return state


func _build(state: KingdomState, building_id: StringName, at: Vector2i) -> BuildRules.Result:
	state.board.set_land(at, &"grass", false)
	return state.build(building_id, at)


func _unit(id: StringName) -> UnitData:
	return load("res://data/units/%s.tres" % id)


func _side(units: Array) -> BattleSide:
	var side := BattleSide.new("Test")
	for entry in units:
		side.add_unit(_unit(entry[0]), entry[1])
	return side


func _rng_where(predicate: Callable) -> RandomNumberGenerator:
	for seed_value in 10000:
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_value
		if predicate.call(probe.randf()):
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			return rng
	return RandomNumberGenerator.new()


func test_new_unit_lines() -> void:
	var ids: Array[StringName] = [&"horse_archer", &"elite_horse_archer", &"royal_horse_archer"]
	for i in ids.size():
		var unit := _unit(ids[i])
		check_eq([unit.unit_type, unit.row, unit.attack_kind, unit.is_cavalry, unit.charge_after_volleys, unit.tier()],
				[UnitData.Type.HORSE_ARCHER, UnitData.Row.BACK, UnitData.AttackKind.BOW, true, 3, i + 1],
				"%s: back-row mounted bowmen, charge after 3 volleys" % ids[i])
		check_eq([unit.required_buildings.get(&"archery_range"), unit.required_buildings.get(&"war_stable"),
				unit.required_buildings.get(&"barracks")], [i + 1, i + 1, [1, 3, 6][i]], "%s buildings" % ids[i])
		var archer := _unit([&"archer", &"elite_archer", &"marksman_archer"][i])
		check(unit.range_attack < archer.range_attack, "%s shoots weaker than archers of its tier" % ids[i])
		check(unit.recruit_cost.has(&"horses"), "%s needs horses" % ids[i])
	var monks: Array[StringName] = [&"monk", &"elite_monk", &"royal_monk"]
	for i in monks.size():
		var unit := _unit(monks[i])
		check_eq([unit.unit_type, unit.row, unit.steadfast, unit.tier()], [UnitData.Type.MONK, UnitData.Row.FRONT,
				true, i + 1], "%s: front-row steadfast monks" % monks[i])
		check_eq([unit.required_buildings.get(&"martial_hall"), unit.required_buildings.get(&"temple")],
				[i + 1, [1, 3, 5][i]], "%s buildings" % monks[i])
		var sword := _unit([&"swordsman", &"elite_swordsman", &"royal_swordguard"][i])
		check(unit.armor < sword.armor and unit.melee_attack > sword.melee_attack and unit.morale > sword.morale,
				"%s: less armor, harder blows, higher morale than swordsmen" % monks[i])
	check_eq(UnitData.TYPE_NAMES.size(), UnitData.Type.size(), "A name per unit type")


func test_horse_archers_shoot_three_volleys_then_charge() -> void:
	# Swordsmen hold the line meanwhile (alone, the riders are the front line from the clash on).
	var simulator := BattleSimulator.new(_side([[&"elite_swordsman", 60], [&"horse_archer", 12]]),
			_side([[&"swordsman", 40]]), 1)
	var volleys := 0
	var charged_at := -1.0
	while not simulator.finished and simulator.time < 30.0:
		simulator.step()
	for event in simulator.record.events:
		if event.side != 0 or event.unit != 1:
			continue
		if event.type == &"arrow_volley":
			volleys += 1
			check(charged_at < 0.0, "No arrows after the charge")
		elif event.type == &"charge" and charged_at < 0.0:
			charged_at = event.time
	check_eq(volleys, 3, "Three volleys")
	check(charged_at > 0.0, "Then they charge")
	var unit := simulator.record.sides[0].units[1]
	check_eq(unit.row, UnitData.Row.FRONT, "Riding in the front row")
	check(unit.has_closed_in(), "Closed in")


func test_horse_archers_keep_shooting_while_others_fight() -> void:
	var simulator := BattleSimulator.new(_side([[&"swordsman", 20], [&"horse_archer", 12]]),
			_side([[&"swordsman", 20]]), 3)
	while not simulator.finished and simulator.time < BattleSimulator.CONTACT_TIME + 1.0:
		simulator.step()
	var unit := simulator.record.sides[0].units[1]
	check_eq(unit.row, UnitData.Row.BACK, "Still on the wing right after contact")
	check(unit.volleys >= 1 and unit.volleys < 3, "Shooting while the swordsmen fight")


func test_steadfast_monks_keep_morale_when_the_general_falls() -> void:
	var side := _side([[&"monk", 20], [&"swordsman", 20]])
	side.add_unit(load("res://data/general_units/general_guard.tres"), 5)
	side.units[2].is_general_guard = true
	side.units[2].soldiers = 0.0
	var simulator := BattleSimulator.new(_side([[&"swordsman", 20]]), side, 1)
	simulator.step()
	check(side.general_fallen, "The general fell")
	check_eq(side.units[0].morale, float(_unit(&"monk").morale), "Monks keep their morale")
	check_eq(side.units[1].morale, float(_unit(&"swordsman").morale - Generals.FALL_MORALE_LOSS),
			"Swordsmen lose theirs")


func test_steadfast_monks_ignore_enemy_stratagem_morale() -> void:
	var stratagem := StratagemData.new()
	stratagem.stratagem_id = &"test_fear"
	stratagem.target = StratagemData.Target.ENEMY_ALL
	stratagem.morale_base = -3.0
	stratagem.attack_base = -0.1
	var schemers := _side([[&"swordsman", 20]])
	schemers.stratagems = [stratagem]
	schemers.stratagem_bonus = 1.0
	var targets := _side([[&"monk", 20], [&"swordsman", 20]])
	var simulator := BattleSimulator.new(schemers, targets, 1)
	simulator.step()
	check_eq(targets.units[0].morale, float(_unit(&"monk").morale), "Monks shrug off the morale blow")
	check(is_equal_approx(targets.units[0].attack_mult, 0.9), "Other stratagem effects still land")
	check_eq(targets.units[1].morale, float(_unit(&"swordsman").morale) - 3.0, "Swordsmen lose morale")


func test_temple_morale_and_production() -> void:
	var state := _state()
	var temple := state.buildings[&"temple"]
	check_eq([temple.category, temple.max_level(), temple.fixed_count, temple.required_castle_level],
			[BuildingData.Category.ADMIN, 5, true, 2], "Admin, 5 levels, one, castle 2")
	check_eq(_build(state, &"temple", Vector2i(4, 4)), BuildRules.Result.CASTLE_TOO_LOW, "Temples from castle level 2")
	state.castle_level = 6
	check_eq(_build(state, &"temple", Vector2i(4, 4)), BuildRules.Result.OK, "Built")
	var morale: Array[float] = []
	var production: Array[int] = []
	for level in range(1, 6):
		state.board.set_building_level(Vector2i(4, 4), level)
		morale.append(state.building_effect(&"army_morale"))
		production.append(roundi(state.building_effect(&"production_bonus") * 100))
	check_eq(morale, [1.0, 1.5, 2.0, 2.5, 3.0] as Array[float], "+1 / 1.5 / 2 / 2.5 / 3 morale")
	check_eq(production, [5, 6, 7, 8, 10] as Array[int], "+5 / 6 / 7 / 8 / 10% production")
	check(temple.effect_lines(2).has("+1.5 nhuệ khí cho quân ta"), "Half points shown")
	state.army.add_squad(&"swordsman", 20)
	var side := state.create_kingdom_side(&"")
	check_eq(side.units[0].morale, float(_unit(&"swordsman").morale) + 3.0, "Own squads get the temple's morale")


func test_monks_need_the_temple() -> void:
	var state := _state()
	state.castle_level = 6
	_build(state, &"martial_hall", Vector2i(2, 2))
	check_eq(state.recruit(&"monk"), RecruitmentRules.Result.NEEDS_BUILDING, "No temple, no monks")
	_build(state, &"temple", Vector2i(4, 4))
	check_eq(state.recruit(&"monk"), RecruitmentRules.Result.OK, "Martial hall + temple")


func test_markets_level_up() -> void:
	var state := _state()
	state.castle_level = 6
	var market := state.buildings[&"market"]
	check_eq(market.max_level(), 6, "6 levels")
	var capacity: Array[int] = []
	for level in range(1, 7):
		capacity.append(roundi(market.effect_at(&"trade_capacity", level)))
	check_eq(capacity, [10, 12, 14, 16, 18, 20] as Array[int], "+2 trade value per level")
	for level in [1, 6]:
		check(is_equal_approx(market.effect_at(&"production_bonus", level), 0.01), "+1% production at any level")
	var spots: Array[Vector2i] = [Vector2i(2, 2), Vector2i(4, 2), Vector2i(7, 2), Vector2i(2, 7), Vector2i(7, 7)]
	for at in spots:
		check_eq(_build(state, &"market", at), BuildRules.Result.OK, "Market at %s" % at)
	check(is_equal_approx(state.building_effect(&"production_bonus"), 0.05), "5 markets: +5% production")


func test_advisors_are_weaker() -> void:
	check_eq([Advisors.ADMIN_YIELD, Advisors.ADMIN_COST, Advisors.ADMIN_UPKEEP], [0.015, 0.015, 0.015], "Nội chính −25%")
	check_eq([Diplomacy.ENVOY_PRICE, Diplomacy.ENVOY_CHANCE, Diplomacy.ENVOY_WARINESS, Diplomacy.ENVOY_GIFT],
			[0.015, 0.0225, 0.03, 0.0225], "Ngoại giao −25%")
	check_eq([Advisors.STRATAGEM_CHANCE_PER_POINT, Advisors.MILITARY_MORALE], [0.025, 0.25], "Quân sư weaker")


func test_agreements_renew_in_their_last_turns() -> void:
	var diplomacy := Diplomacy.new(ClanData.load_all(), resource_types)
	var clan := &"east_merchants"
	var accepting := _rng_where(func(value: float) -> bool: return value < 0.05)
	check_eq(diplomacy.check_renewal(clan, 10), Diplomacy.ProposalResult.EMPTY, "Nothing to renew")
	check_eq(diplomacy.propose(accepting, clan, &"wood", 10, &"food", 12, 10), Diplomacy.ProposalResult.OK, "Signed")
	diplomacy.clans[clan].proposed_this_turn = false
	var agreement := diplomacy.get_agreement(clan)
	check_eq(diplomacy.check_renewal(clan, 10), Diplomacy.ProposalResult.NOT_YET, "Too early with 10 turns left")
	agreement.turns_left = Diplomacy.AGREEMENT_RENEW_TURNS
	check_eq(diplomacy.check_renewal(clan, 3), Diplomacy.ProposalResult.BAD_DURATION, "At least 5 more turns")
	var declining := _rng_where(func(value: float) -> bool: return value > 0.99)
	check_eq(diplomacy.renew_agreement(declining, clan, 10), Diplomacy.ProposalResult.DECLINED, "They can say no")
	check_eq(agreement.turns_left, Diplomacy.AGREEMENT_RENEW_TURNS, "A refusal changes nothing")
	check_eq(diplomacy.check_renewal(clan, 10), Diplomacy.ProposalResult.ASKED_THIS_TURN, "One offer a turn")
	diplomacy.clans[clan].proposed_this_turn = false
	accepting = _rng_where(func(value: float) -> bool: return value < 0.05)
	check_eq(diplomacy.renew_agreement(accepting, clan, 10), Diplomacy.ProposalResult.OK, "Renewed")
	check_eq([agreement.turns_left, agreement.total_turns], [15, 15], "10 more turns on top of the 5 left")
	check_eq([agreement.give_amount, agreement.get_amount], [10, 12], "Same terms")
