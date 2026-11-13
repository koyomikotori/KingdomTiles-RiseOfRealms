extends "res://tests/test_suite.gd"
## M14b: the campaign map rules not covered in test_diplomacy / test_war / test_victory: land
## added clockwise, only neighbours invade, bandits growing over time, the notice column, old
## saves refused.

var terrains := TerrainLibrary.load_all()


func _state() -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.start()
	return state


func test_every_second_annexation_adds_land_clockwise_eight_times() -> void:
	var sides: Array[Vector2i] = []
	for i in 5:
		sides.append(Wars.expansion_side(i))
	check_eq(sides, [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP] as Array[Vector2i],
			"Top, right, bottom, left, then round again")
	check_eq(Wars.expansion_side(7), Vector2i.LEFT, "The 8th still adds land")
	check_eq(Wars.expansion_side(8), Vector2i.ZERO, "Then the board stops growing")
	var state := _state()
	var got: Array[Vector2i] = []
	var needed: Array[int] = []
	for clan_id: StringName in [&"north_wolves", &"south_farmers", &"east_merchants", &"west_fortress"]:
		var side := state.wars.annex(clan_id)
		got.append(side)
		needed.append(state.wars.annexations_to_expand())
		state.board.expand(side, Wars.ANNEX_EXPANSION)
	check_eq(got, [Vector2i.ZERO, Vector2i.UP, Vector2i.ZERO, Vector2i.RIGHT] as Array[Vector2i], "Land every second annexation")
	check_eq(needed, [1, 2, 1, 2] as Array[int], "Annexations still needed")
	check_eq([state.board.width, state.board.height], [14, 14], "Four annexations: 12×12 → 14×14")
	var ids := state.wars.fronts.keys()
	var count := 4
	for clan_id: StringName in ids:
		if not state.wars.fronts[clan_id].annexed and count < 16:
			state.board.expand(state.wars.annex(clan_id), Wars.ANNEX_EXPANSION)
			count += 1
	check_eq([state.board.width, state.board.height], [20, 20], "Sixteen annexations: 20×20")
	check_eq(state.wars.annexations_to_expand(), 0, "Full size")
	for clan_id: StringName in ids:
		if not state.wars.fronts[clan_id].annexed:
			check_eq(state.wars.annex(clan_id), Vector2i.ZERO, "No more land after that")


func test_winning_a_defense_never_adds_land() -> void:
	var state := _state()
	for i in 6:
		state.army.add_squad(&"swordsman", 20)
	state.wars.declare_war(&"north_wolves")
	state.wars.fronts[&"north_wolves"].strength = 6
	var simulator := BattleSimulator.new(state.wars.create_clan_side(&"north_wolves", 6, state.units),
			state.create_kingdom_side(&"north_wolves", true), 3)
	while not simulator.finished:
		simulator.step()
	var result := state.finish_invasion(&"north_wolves", simulator.record)
	check(result.won, "Repelled")
	check(not state.wars.fronts[&"north_wolves"].annexed, "Not annexed by defending")
	check_eq([state.board.width, state.board.height], [12, 12], "No land from a defense")


func test_only_bordering_clans_invade() -> void:
	var state := _state()
	state.wars.fronts[&"east_merchants"].at_war = true  # two steps away (an event could do this)
	state.wars.fronts[&"east_merchants"].turns_since_invasion = 100
	var rng := RandomNumberGenerator.new()
	for i in 50:
		check_eq(state.wars.pick_invader(rng), &"", "A clan two steps away never invades")
	state.wars.annex(&"north_wolves")
	state.wars.fronts[&"east_merchants"].turns_since_invasion = 100
	var invaded := false
	for i in 50:
		invaded = invaded or state.wars.pick_invader(rng) == &"east_merchants"
	check(invaded, "Once the wolves are annexed the merchants border the kingdom and can invade")


func test_bandits_grow_more_frequent_and_bring_riders() -> void:
	var state := _state()
	var raid := RaidData.load_bandits()
	state.turn = 10
	var early := RaidSystem.get_raid_chance(state, raid)
	state.turn = 40
	var later := RaidSystem.get_raid_chance(state, raid)
	check(is_equal_approx(later - early, raid.chance_per_ten_turns * 3), "+%.2f every 10 turns" % raid.chance_per_ten_turns)
	state.turn = 500
	check(is_equal_approx(RaidSystem.get_raid_chance(state, raid), raid.max_chance), "Capped")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var riders_early := 0
	var riders_late := 0
	for i in 20:
		for unit in RaidSystem.create_bandit_side(raid, state.enemy_units, 10, rng).units:
			riders_early += 1 if unit.data.unit_id == &"bandit_rider" else 0
		for unit in RaidSystem.create_bandit_side(raid, state.enemy_units, 40, rng).units:
			riders_late += 1 if unit.data.unit_id == &"bandit_rider" else 0
	check_eq(riders_early, 0, "No riders on turn 10")
	check(riders_late > 0, "Riders join later")


func test_notices_list_what_is_going_on() -> void:
	var state := _state()
	check(Notices.build(state, {}).is_empty(), "A new kingdom has nothing to report")
	KingdomState.instant_construction = false
	state.stockpile.add({&"wood": 50, &"stone": 50, &"food": 50})
	state.build(&"barracks", Vector2i(4, 7))
	KingdomState.instant_construction = true
	state.wars.declare_war(&"north_wolves")
	state.diplomacy.clans[&"south_farmers"].alliance_turns = 7
	var report := {"completed": [{"name": "Nông trại", "level": 2, "upgrade": true}],
			"war_declared": [&"north_wolves"] as Array[StringName], "replenished": {&"swordsman": 3},
			"deserted": {}, "castle_in_danger": false}
	var sections := Notices.build(state, report)
	var ids := sections.map(func(s: Dictionary) -> StringName: return s.id)
	check_eq(ids, [&"buildings", &"diplomacy", &"army"], "Three sections, in order")
	var lines := {}
	for section: Dictionary in sections:
		for item: Dictionary in section.items:
			lines[Notices.key(section.id, item.id)] = item.lines
	check_eq(lines.get("buildings/constructing"), ["Doanh trại: còn 2 lượt"] as Array[String], "Construction with turns left")
	check_eq(lines.get("buildings/completed"), ["Nông trại lên cấp 2"] as Array[String], "Finished this turn")
	check(lines.get("diplomacy/wars", [""])[0].begins_with("Lang Tộc Bạch Nha: quân"), "At war, with their army")
	check_eq(lines.get("diplomacy/allies"), ["Điền Trang Thanh Lâm: còn 7 lượt"] as Array[String], "Allies with turns left")
	check_eq(lines.get("army/replenished"), ["+3 Kiếm binh nông dân"] as Array[String], "Replenished soldiers")
	check(not lines.has("army/deserted"), "Empty items are left out")
	for key: String in lines:
		check(not key.contains("collect"), "Resources collected are never listed")



func test_important_news_only_for_what_cannot_wait() -> void:
	var state := _state()
	var calm := {"completed": [{"name": "Nông trại", "level": 2, "upgrade": true}], "replenished": {&"swordsman": 3},
			"deserted": {}, "castle_in_danger": false, "agents": [{"name": "A", "clan_id": &"north_wolves",
			"mission": Agent.RELATIONS, "event": &"done", "levels": 0}]}
	check(ImportantNews.build(state, calm).is_empty(), "Building, replenishing, missions done: nothing important")
	check(ImportantNews.build(state, {}, {"general": {"fate": &"none"}}).is_empty(), "A battle nobody was hurt in")
	var report := {"war_declared": [&"north_wolves"] as Array[StringName], "deserted": {&"swordsman": 4},
			"castle_in_danger": true, "treaties": [{"clan_id": &"south_farmers", "event": &"alliance_broken"},
			{"clan_id": &"south_farmers", "event": &"alliance_ended"}],
			"agents": [{"name": "Bảo", "clan_id": &"north_wolves", "mission": Agent.SABOTAGE, "event": &"killed", "levels": 0}]}
	var battle := {"general": {"name": "Khải", "fate": &"dead"}, "advisor": {"name": "Phong", "fate": &"wounded"}}
	var news := ImportantNews.build(state, report, battle)
	var titles := news.map(func(n: Dictionary) -> String: return n.title)
	check_eq(titles, ["Bị tuyên chiến", "Đặc vụ bị lộ", "Tướng sĩ", "Lính đào ngũ", "Đồng minh rời bỏ",
			"Thành chính nguy hiểm"], "Every kind, in order")
	check_eq(news[2].lines.size(), 2, "The commander and the advisor")
	check(news[2].lines[0].contains("tử trận"), "The commander died")
	check_eq(news[4].lines.size(), 1, "An alliance running out is not important")

func test_old_saves_are_refused() -> void:
	var folder := "user://test_campaign_saves"
	var system := SaveSystem.new(folder)
	var state := _state()
	check_eq(system.save(state, "slot_1"), OK, "Saved")
	var path := system.path("slot_1")
	var file := FileAccess.open(path, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	data.save_version = 3
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	check(system.load_slot("slot_1").has("error"), "A v3 save (6 clans) is refused")
	data.save_version = SaveSystem.SAVE_VERSION
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	check(system.load_slot("slot_1").has("game"), "A current save loads")
	system.delete("slot_1")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
