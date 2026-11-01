extends "res://tests/test_suite.gd"
## M13: barracks levels, the four military buildings, the new unit rules (GDD §8 "Lính và công
## trình quân sự mới").

var terrains := TerrainLibrary.load_all()
var buildings := BuildingData.load_all()
var unit_list := UnitData.load_all()

const MILITARY: Array[StringName] = [&"war_stable", &"archery_range", &"martial_hall", &"military_academy"]


func _state(castle_level: int = 6) -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains, buildings, unit_list)
	state.start()
	state.castle_level = castle_level
	state.stockpile.add({&"food": 2000, &"wood": 2000, &"stone": 2000, &"ore": 900, &"hardwood": 900, &"horses": 900})
	for x in range(2, 10):
		state.board.set_land(Vector2i(x, 2), &"grass", false)
	return state


func _upgrade_to(state: KingdomState, origin: Vector2i, level: int) -> void:
	while state.board.get_building_level(origin) < level:
		var result := state.upgrade_building(origin)
		if result != KingdomState.UpgradeResult.OK:
			check(false, "Upgrade at %s failed (%d)" % [origin, result])
			return


func test_data() -> void:
	for id in MILITARY:
		var building: BuildingData = buildings.get(id)
		check(building != null, "%s loads" % id)
		if building == null:
			continue
		check_eq([building.max_level(), building.max_count, building.fixed_count, building.required_castle_level,
				building.castle_level_gap, building.category], [3, 1, true, 3, 2, BuildingData.Category.MILITARY],
				"%s: 3 levels, one, castle 3, castle − 2" % id)
		check_eq(building.allowed_terrains, [&"grass"] as Array[StringName], "%s on grass" % id)
		check(GameArt.building(id) != null, "%s has art" % id)
	for unit in unit_list:
		check(not unit.required_buildings.is_empty() and unit.required_buildings.has(&"barracks"),
				"%s needs a barracks" % unit.unit_id)
		check(unit.required_terrain.is_empty(), "%s needs no terrain" % unit.unit_id)
		check(ResourceLoader.exists("res://assets/units/%s.png" % unit.unit_id), "%s has a sprite" % unit.unit_id)
	var rows := {}
	for unit in unit_list:
		rows[unit.row] = rows.get(unit.row, 0) + 1
	check_eq([rows.get(0), rows.get(1), rows.get(2)], [9, 3, 9], "9 front, 3 middle, 9 back")
	check_eq(UnitData.load_all().filter(func(u: UnitData) -> bool: return u.unit_id == &"spearman")[0].row,
			UnitData.Row.FRONT, "Spearmen stand in the front row with the swordsmen")


func test_barracks_level_unlocks_tiers() -> void:
	var state := _state()
	state.build(&"barracks", Vector2i(2, 2))
	check_eq(state.recruit(&"swordsman"), RecruitmentRules.Result.OK, "Peasants at level 1")
	check_eq(state.recruit(&"elite_swordsman"), RecruitmentRules.Result.NEEDS_BUILDING, "Elites need level 3")
	var reason := RecruitmentRules.describe(RecruitmentRules.Result.NEEDS_BUILDING, state.units[&"elite_swordsman"],
			buildings, terrains)
	check(reason.contains("Doanh trại cấp 3"), "Reason names the level (got '%s')" % reason)
	_upgrade_to(state, Vector2i(2, 2), 3)
	check_eq(state.recruit(&"elite_archer"), RecruitmentRules.Result.OK, "Elites at level 3")
	check_eq(state.recruit(&"royal_pikeguard"), RecruitmentRules.Result.NEEDS_BUILDING, "Royal guards need level 6")
	_upgrade_to(state, Vector2i(2, 2), 6)
	check_eq(state.recruit(&"royal_pikeguard"), RecruitmentRules.Result.OK, "Royal guards at level 6")
	check_eq(state.check_building_upgrade(Vector2i(2, 2)), KingdomState.UpgradeResult.MAX_LEVEL, "6 is the top")


func test_barracks_level_is_capped_by_the_castle() -> void:
	var state := _state(2)
	state.build(&"barracks", Vector2i(2, 2))
	_upgrade_to(state, Vector2i(2, 2), 2)
	check_eq(state.check_building_upgrade(Vector2i(2, 2)), KingdomState.UpgradeResult.CASTLE_TOO_LOW,
			"Barracks level stays at or below the castle's")


func test_a_barracks_being_upgraded_does_not_count() -> void:
	KingdomState.instant_construction = false
	var state := _state()
	state.build(&"barracks", Vector2i(2, 2))
	state.finish_construction(Vector2i(2, 2))
	check_eq(state.board.highest_building_level(&"barracks"), 1, "Level 1 once finished")
	state.upgrade_building(Vector2i(2, 2))
	check_eq(state.board.highest_building_level(&"barracks"), 0, "Not working while upgrading")
	KingdomState.instant_construction = true


func test_military_buildings() -> void:
	var low := _state(2)
	check_eq(low.build(&"war_stable", Vector2i(2, 2)), BuildRules.Result.CASTLE_TOO_LOW, "Needs castle level 3")
	var state := _state(3)
	state.build(&"barracks", Vector2i(2, 2))
	check_eq(state.recruit(&"light_cavalry"), RecruitmentRules.Result.NEEDS_BUILDING, "Cavalry needs the stable")
	check_eq(state.build(&"war_stable", Vector2i(3, 2)), BuildRules.Result.OK, "Stable on grass")
	check_eq(state.build(&"war_stable", Vector2i(4, 2)), BuildRules.Result.LIMIT_REACHED, "Only one stable")
	var horses := state.stockpile.get_amount(&"horses")
	check_eq(state.recruit(&"light_cavalry"), RecruitmentRules.Result.OK, "Light cavalry at stable 1")
	check_eq(state.stockpile.get_amount(&"horses"), horses - 3, "Cavalry costs horses")
	check_eq(state.check_building_upgrade(Vector2i(3, 2)), KingdomState.UpgradeResult.CASTLE_TOO_LOW,
			"Castle 3 → stable level 1 only")
	state.castle_level = 5
	_upgrade_to(state, Vector2i(3, 2), 3)
	check_eq(state.recruit(&"heavy_cavalry"), RecruitmentRules.Result.NEEDS_BUILDING, "Heavy cavalry also needs barracks 6")
	_upgrade_to(state, Vector2i(2, 2), 5)
	state.castle_level = 6
	_upgrade_to(state, Vector2i(2, 2), 6)
	check_eq(state.recruit(&"heavy_cavalry"), RecruitmentRules.Result.OK, "Stable 3 + barracks 6")


func test_musketeers_need_the_martial_hall_too() -> void:
	var state := _state()
	state.build(&"barracks", Vector2i(2, 2))
	_upgrade_to(state, Vector2i(2, 2), 6)
	state.build(&"military_academy", Vector2i(3, 2))
	_upgrade_to(state, Vector2i(3, 2), 3)
	check_eq(state.recruit(&"heavy_artillery"), RecruitmentRules.Result.OK, "Heavy guns at academy 2+")
	check_eq(state.recruit(&"elite_musketeer"), RecruitmentRules.Result.NEEDS_BUILDING, "Musketeers need the martial hall")
	check_eq(RecruitmentRules.missing_buildings(state.board, state.units[&"elite_musketeer"]),
			{&"martial_hall": 3} as Dictionary[StringName, int], "Only the hall is missing")
	state.build(&"martial_hall", Vector2i(4, 2))
	_upgrade_to(state, Vector2i(4, 2), 3)
	check_eq(state.recruit(&"elite_musketeer"), RecruitmentRules.Result.OK, "Academy 3 + barracks 6 + hall 3")


func test_old_saves_keep_their_units_and_barracks() -> void:
	var state := _state()
	state.build(&"barracks", Vector2i(2, 2))
	state.recruit(&"spearman")
	var data := state.to_save()
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var loaded := KingdomState.new(BoardData.from_save(data.board), PieceHand.new(gen), terrains, buildings, unit_list)
	loaded.load_save(data)
	check_eq(loaded.army.count_squads(&"spearman"), 1, "Old unit ids are the peasant tier")
	check_eq(loaded.board.get_building_level(Vector2i(2, 2)), 1, "Existing barracks are level 1")
	check_eq(loaded.units[&"spearman"].display_name, "Thương binh nông dân", "…renamed")


# --- Battle rules ---------------------------------------------------------------------------

func _unit(row: UnitData.Row, kind: UnitData.AttackKind = UnitData.AttackKind.MELEE) -> UnitData:
	var unit := UnitData.new()
	unit.unit_id = &"test"
	unit.row = row
	unit.attack_kind = kind
	unit.melee_attack = 8
	unit.melee_defense = 8
	unit.armor = 8
	unit.morale = 99
	return unit


func _losses_after(attacker: UnitData, defender: UnitData, seconds: float, extra_defender: UnitData = null) -> float:
	var a := BattleSide.new("a")
	a.add_unit(attacker, 20)
	var d := BattleSide.new("d")
	d.add_unit(defender, 20)
	if extra_defender != null:
		d.add_unit(extra_defender, 20)
	var simulator := BattleSimulator.new(a, d, 7)
	while not simulator.finished and simulator.time < seconds - 0.0001:
		simulator.step()
	return 20.0 - d.units[0].soldiers


func test_spears_resist_charges_and_hurt_cavalry() -> void:
	var cavalry := _unit(UnitData.Row.FRONT)
	cavalry.charge_attack = 20
	cavalry.is_cavalry = true
	var plain := _unit(UnitData.Row.FRONT)
	var spears := _unit(UnitData.Row.FRONT)
	spears.charge_resist = 0.5
	var charge_time := BattleSimulator.CONTACT_TIME + 0.05
	check(_losses_after(cavalry, spears, charge_time) < _losses_after(cavalry, plain, charge_time) * 0.8,
			"Spearmen lose fewer men to the charge")
	var horse_target := _unit(UnitData.Row.FRONT)
	horse_target.is_cavalry = true
	check(_losses_after(spears, horse_target, 20.0) > _losses_after(plain, horse_target, 20.0),
			"Spearmen hit cavalry harder")


func test_crossbows_pierce_armor() -> void:
	var bow := _unit(UnitData.Row.BACK, UnitData.AttackKind.BOW)
	bow.range_attack = 8
	var crossbow := bow.duplicate()
	crossbow.armor_pierce = 0.5
	var target := _unit(UnitData.Row.FRONT)
	target.armor = 12
	var time := BattleSimulator.FIRST_ARROW_TIME + 0.05
	check(_losses_after(crossbow, target, time) > _losses_after(bow, target, time) * 1.2,
			"Piercing bolts kill more armored men")


func test_artillery_hits_every_row_once() -> void:
	var gun := _unit(UnitData.Row.BACK, UnitData.AttackKind.GUN)
	gun.range_attack = 25
	gun.volley_all_rows = true
	gun.damage_per_soldier = 5.0
	var front := _unit(UnitData.Row.FRONT)
	var back := _unit(UnitData.Row.BACK)
	var a := BattleSide.new("a")
	a.add_unit(gun, 8)
	var d := BattleSide.new("d")
	d.add_unit(front, 20)
	d.add_unit(back, 20)
	var simulator := BattleSimulator.new(a, d, 3)
	while simulator.time < BattleSimulator.FIRST_ARROW_TIME:
		simulator.step()
	check(d.units[0].soldiers < 20.0 and d.units[1].soldiers < 20.0, "Both rows were hit")
	check_eq(simulator.record.events.filter(func(e: Dictionary) -> bool: return e.type == &"gun_volley").size(), 1,
			"One volley")


func test_musketeers_fire_then_join_the_melee() -> void:
	var musket := _unit(UnitData.Row.BACK, UnitData.AttackKind.GUN)
	musket.range_attack = 14
	musket.melee_after_volley = true
	var a := BattleSide.new("a")
	a.add_unit(_unit(UnitData.Row.FRONT), 20)
	a.add_unit(musket, 15)
	var d := BattleSide.new("d")
	d.add_unit(_unit(UnitData.Row.FRONT), 20)
	var simulator := BattleSimulator.new(a, d, 5)
	while simulator.time < BattleSimulator.CONTACT_TIME + 1.0:
		simulator.step()
	check_eq(a.units[1].row, UnitData.Row.FRONT, "Musketeers marched to the front row")
	check(a.units[1].kills > 0.0 and a.units[1].has_charged, "…and fight in melee")


# --- M13b: kinds, tiers and name colors -------------------------------------------------------

func test_every_kind_has_three_tiers() -> void:
	for type in UnitData.TYPE_NAMES.size():
		var tiers := unit_list.filter(func(u: UnitData) -> bool: return u.unit_type == type).map(
				func(u: UnitData) -> int: return u.tier())
		# Firearms start at barracks 3: light guns are elite, heavy guns and musketeers royal.
		var expected := [2, 3, 3] if type == UnitData.Type.FIREARM else [1, 2, 3]
		check_eq(tiers, expected, "%s: tiers" % UnitData.TYPE_NAMES[type])
	check(unit_list[0].tier_color(true) != unit_list[2].tier_color(true), "Tiers have their own colors")


func test_star_colors_follow_item_rarity() -> void:
	check_eq(Officer.star_color(1), Item.RARITY_COLORS[0], "1 star gray")
	check_eq(Officer.star_color(2), Item.RARITY_COLORS[0], "2 stars gray")
	check_eq(Officer.star_color(3), Item.RARITY_COLORS[1], "3 stars green")
	check_eq(Officer.star_color(6), Item.RARITY_COLORS[4], "6 stars gold")


func test_replenishment_is_five_percent() -> void:
	check_eq(KingdomState.REPLENISH_FRACTION, 0.05, "Squads regain 5% a turn (M16a, was 10%)")
