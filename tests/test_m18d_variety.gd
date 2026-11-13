extends "res://tests/test_suite.gd"
## M18d (GDD §31): the ruler's background and the clans shuffled every game.


func _state(settings: Dictionary = {}, seed_value: int = 3) -> KingdomState:
	var terrains := TerrainLibrary.load_all()
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), seed_value)
	var chosen := {"tutorial": false}
	chosen.merge(settings, true)
	state.setup_new_game(chosen)
	state.start()
	return state


## Runs `body` with backgrounds and shuffling on, then puts the test settings back.
func _with(origins: bool, shuffle: bool, body: Callable) -> void:
	KingdomState.origins_on = origins
	KingdomState.shuffle_clans = shuffle
	body.call()
	KingdomState.origins_on = false
	KingdomState.shuffle_clans = false


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# --- Backgrounds --------------------------------------------------------------------------

func test_backgrounds_follow_the_outfit() -> void:
	var expected: Array[StringName] = [RulerOrigin.EMPEROR, RulerOrigin.EMPEROR, RulerOrigin.WARLORD,
			RulerOrigin.WARLORD, RulerOrigin.STRATEGIST, RulerOrigin.STRATEGIST]
	for i in Ruler.PRESETS.size():
		check_eq(Ruler.from_preset(i).origin(), expected[i], "Preset %d" % i)
		check_eq(RulerOrigin.lines(expected[i]).size(), 3, "Preset %d: three advantages" % i)
	check(RulerOrigin.describe(RulerOrigin.WARLORD).begins_with("Xuất thân: Võ tướng"), "Described")
	check_eq(_state({"ruler_preset": 0}).origin(), &"", "Off in tests unless turned on")


func test_emperor() -> void:
	_with(true, false, func() -> void:
		var plain := _state({"ruler_preset": 2})
		var state := _state({"ruler_preset": 1})
		check_eq(state.origin(), RulerOrigin.EMPEROR, "Nữ hoàng is a Thiên tử")
		check(is_equal_approx(state.alliances.pact_chance(&"south_farmers"),
				plain.alliances.pact_chance(&"south_farmers") + RulerOrigin.DIPLOMACY_CHANCE), "Pact chance +10%")
		check(is_equal_approx(state.diplomacy.price_factor(&"south_farmers", &"food", &"wood"),
				plain.diplomacy.price_factor(&"south_farmers", &"food", &"wood") * 1.1), "Trade prices ×1.1")
		state.give_starting_resources()
		check_eq(state.stockpile.get_amount(&"food"), 120, "Starting resources +50%")
		check_eq(state.stockpile.get_amount(&"ore"), 15, "Others too")
		var general := state.generals.generate(2)
		state.generals.add(general)
		general.gain_xp(50)
		check_eq(general.xp, 55, "Officers gain 10% more XP")
		var copy := _state({"ruler_preset": 3})
		copy.load_save(JSON.parse_string(JSON.stringify(state.to_save())))
		check(is_equal_approx(copy.diplomacy.origin_chance, RulerOrigin.DIPLOMACY_CHANCE), "Back after loading")
		check_eq(copy.generals.generals[0].xp_rate, 1.1, "Loaded officers too"))


func test_warlord() -> void:
	_with(true, false, func() -> void:
		var state := _state({"ruler_preset": 2})
		state.give_starting_army()
		check_eq(state.generals.generals.size(), 1, "A starting general")
		check_eq(state.generals.generals[0].stars, RulerOrigin.START_STARS, "3★")
		check_eq(state.generals.commander, state.generals.generals[0], "Who leads the army")
		check_eq(state.advisors.advisors.size(), 0, "No advisor")
		check_eq(state.generals.generals[0].xp_rate, 1.0, "Officers' XP unchanged")
		var unit := state.units[&"swordsman"]
		var cost := state.recruit_cost(&"swordsman")
		for resource_id in unit.recruit_cost:
			check_eq(cost[resource_id], unit.recruit_cost[resource_id]
					- roundi(unit.recruit_cost[resource_id] * RulerOrigin.RECRUIT_DISCOUNT), "Cheaper %s" % resource_id)
		var squad := state.army.squads[0]
		state.army.add_xp(squad, 20.0)
		check(is_equal_approx(squad.xp, 22.0), "Squads gain 10% more XP")
		state.army.train()
		check(is_equal_approx(squad.xp, 22.0 + Experience.TRAINING_XP * 1.1), "Training too")
		check(state.origin_yield_bonus().is_empty(), "No production bonus"))


func test_strategist() -> void:
	_with(true, false, func() -> void:
		var state := _state({"ruler_preset": 4})
		state.give_starting_army()
		check_eq(state.advisors.advisors.size(), 1, "A starting advisor")
		check_eq(state.advisors.advisors[0].stars, RulerOrigin.START_STARS, "3★")
		check_eq(state.advisors.advisors[0].post, &"admin", "In the first post")
		check_eq(state.generals.generals.size(), 0, "No general")
		var unit := state.units[&"swordsman"]
		check_eq(state.recruit_cost(&"swordsman"), unit.recruit_cost, "Full price")
		for i in 12:
			state.army.add_squad(&"swordsman", 10)
		var food_upkeep: int = state.army.get_upkeep(state.units).get(&"food", 0)
		check(food_upkeep >= 10, "A big army eats")
		check_eq(state.origin_upkeep_discount(), {&"food": roundi(food_upkeep * RulerOrigin.FOOD_UPKEEP_CUT)},
				"10% off the army's food")
		# A farm: production +10%.
		state.stockpile.add({&"food": 500, &"wood": 500, &"stone": 500})
		# Farmland all around feeds the farm (fields), enough for a 10% share to show.
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				state.board.set_land(Vector2i(5 + dx, 3 + dy), &"farmland", false)
		check_eq(state.build(&"farm", Vector2i(5, 3)), BuildRules.Result.OK, "Farm built")
		var made := Economy.buildings_yield(state.board, state.buildings)
		check(made.get(&"food", 0) >= 15, "The farm produces (%s)" % made)
		check_eq(state.origin_yield_bonus(), Advisors.share_of(made, RulerOrigin.PRODUCTION), "Production +10%")
		var sources := []
		for entries in state.get_income_breakdown().values():
			for entry in entries:
				sources.append(entry.source)
		check(sources.has(&"origin_yield") and sources.has(&"origin_upkeep"), "Shown in the income breakdown"))


func test_no_background_without_origins() -> void:
	var state := _state({"ruler_preset": 2})
	state.give_starting_resources()
	state.give_starting_army()
	check_eq(state.generals.generals.size(), 0, "No general in other tests")
	check_eq(state.stockpile.get_amount(&"food"), 80, "Usual starting resources")
	check_eq(state.recruit_cost(&"swordsman"), state.units[&"swordsman"].recruit_cost, "Usual price")


# --- Shuffled clans -----------------------------------------------------------------------

func test_layout_keeps_the_map_fair() -> void:
	var clans := ClanData.load_all()
	var by_square := {}
	var personalities := {}
	var pairs := 0
	for clan in clans:
		by_square[clan.grid] = clan
		personalities[clan.personality] = personalities.get(clan.personality, 0) + 1
		pairs += clan.friends.size()
	for seed_value in [1, 2, 3, 4, 5, 6, 7, 8]:
		var layout := ClanLayout.roll(clans, _rng(seed_value))
		check_eq(layout.size(), clans.size(), "Seed %d: every clan placed" % seed_value)
		var squares := {}
		var counts := {}
		var peaceful_near := false
		var made := 0
		for clan_id in layout:
			var entry: Dictionary = layout[clan_id]
			var square := Vector2i(entry.grid[0], entry.grid[1])
			squares[square] = true
			var slot: ClanData = by_square[square]
			counts[entry.personality] = counts.get(entry.personality, 0) + 1
			if slot.ring() == 1 and entry.personality == ClanData.Personality.PEACEFUL:
				peaceful_near = true
			check(entry.strength >= slot.military_strength * 0.8 - 3 and entry.strength <= slot.military_strength * 1.2 + 3,
					"Seed %d %s: strength near its square's" % [seed_value, clan_id])
			check_eq(entry.strength % ClanLayout.STRENGTH_STEP, 0, "Rounded")
			check_eq(entry.army.size(), slot.army_units.size(), "Army of its square")
			check(entry.surplus[0] != entry.deficit[0], "Surplus and deficit differ")
			check(entry.friends.size() <= ClanLayout.MAX_FRIENDS, "At most two friends")
			for friend in entry.friends:
				var other: Dictionary = layout[friend]
				check(other.friends.has(clan_id), "Friends both ways")
				check(absi(other.grid[0] - entry.grid[0]) + absi(other.grid[1] - entry.grid[1]) == 1, "Friends border")
				check(entry.personality != ClanData.Personality.ISOLATED, "No isolated friends")
			made += entry.friends.size()
		check_eq(squares.size(), clans.size(), "Seed %d: one clan per square" % seed_value)
		check(not squares.has(ClanData.HOME), "Home stays the kingdom's")
		check_eq(counts, personalities, "Seed %d: same personalities" % seed_value)
		check(peaceful_near, "Seed %d: a peaceful neighbor" % seed_value)
		check(made <= pairs and made >= pairs - 6, "Seed %d: about as many friends (%d of %d)" % [seed_value, made, pairs])
	check(ClanLayout.roll(clans, _rng(1)) != ClanLayout.roll(clans, _rng(2)), "Different games, different maps")


func test_new_games_shuffle_and_save_the_map() -> void:
	_with(false, true, func() -> void:
		var state := _state({}, 11)
		check(not state.clan_layout.is_empty(), "Shuffled")
		var moved := 0
		var fixed := {}
		for clan in ClanData.load_all():
			fixed[clan.clan_id] = clan
		for clan_id in state.diplomacy.clans:
			var data := state.diplomacy.clans[clan_id].data
			if data.grid != fixed[clan_id].grid:
				moved += 1
			check_eq(state.wars.fronts[clan_id].max_strength, data.military_strength, "Wars use the new strength")
			check_eq(state.diplomacy.clans[clan_id].relation, data.start_relation, "Starts at its personality's relation")
		check(moved > 10, "Most clans moved (%d)" % moved)
		check_eq(ClanData.load_all()[0].grid, fixed[ClanData.load_all()[0].clan_id].grid, "The .tres data is untouched")
		check_eq(_state({}, 11).clan_layout, state.clan_layout, "Same seed, same map")
		var copy := _state({}, 99)
		copy.load_save(JSON.parse_string(JSON.stringify(state.to_save())))
		for clan_id in state.diplomacy.clans:
			var a := state.diplomacy.clans[clan_id].data
			var b := copy.diplomacy.clans[clan_id].data
			check(a.grid == b.grid and a.personality == b.personality and a.surplus == b.surplus
					and a.friends == b.friends and a.army_units == b.army_units, "%s loaded as saved" % clan_id)
			check_eq(copy.wars.fronts[clan_id].max_strength, state.wars.fronts[clan_id].max_strength, "Strength loaded")
		var old := state.to_save()
		old.erase("clan_layout")
		KingdomState.shuffle_clans = false
		var plain := _state({}, 5)
		plain.load_save(JSON.parse_string(JSON.stringify(old)))
		check(plain.clan_layout.is_empty(), "Older saves keep the fixed map")
		check_eq(plain.diplomacy.clans[&"north_wolves"].data.grid, Vector2i(1, 0), "Fixed squares"))


func test_renamed_clans_and_plain_descriptions() -> void:
	var names := {}
	for clan in ClanData.load_all():
		names[clan.clan_id] = clan.display_name
		for word in ["Bắc", "Nam", "Đông", "Tây", "phương", "phía", "dư ", "thiếu", "Hiền hòa", "Thiện chiến", "Khép kín"]:
			check(not clan.display_name.contains(word) and not clan.description.contains(word),
					"%s: no '%s'" % [clan.clan_id, word])
	check_eq(names[&"north_wolves"], "Lang Tộc Bạch Nha", "Renamed")
	check_eq(names[&"south_farmers"], "Điền Trang Thanh Lâm", "Renamed")
	check_eq(names[&"east_merchants"], "Thương Hội Kim Hải", "Renamed")
