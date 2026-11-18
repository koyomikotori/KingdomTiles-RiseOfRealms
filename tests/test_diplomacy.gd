extends "res://tests/test_suite.gd"

var resource_types := ResourceTypeData.load_all()


func _diplomacy() -> Diplomacy:
	return Diplomacy.new(ClanData.load_all(), resource_types)


func _stock(amounts: Dictionary[StringName, int]) -> Stockpile:
	var stockpile := Stockpile.new()
	stockpile.add(amounts)
	return stockpile


func test_campaign_map_has_35_clans_on_a_6x6_grid() -> void:
	var clans := ClanData.load_all()
	check_eq(ClanData.GRID_SIZE, 6, "6×6 (M18e)")
	check_eq(clans.size(), 35, "35 clans")
	var by_grid := {}
	for clan in clans:
		check(clan.grid != ClanData.HOME, "%s is not on the kingdom's square" % clan.clan_id)
		check(Rect2i(0, 0, ClanData.GRID_SIZE, ClanData.GRID_SIZE).has_point(clan.grid), "%s is on the map" % clan.clan_id)
		by_grid[clan.grid] = clan
	check_eq(by_grid.size(), 35, "One clan per square")
	var ids := clans.map(func(c: ClanData) -> StringName: return c.clan_id)
	for clan in clans:
		for friend in clan.friends:
			check(ids.has(friend), "%s -> %s exists" % [clan.clan_id, friend])
			var other: ClanData = clans[ids.find(friend)] if ids.has(friend) else null
			if other != null:
				check(other.friends.has(clan.clan_id), "%s <-> %s goes both ways" % [clan.clan_id, friend])
				check_eq(ClanData.grid_distance(clan.grid, other.grid), 1, "%s and %s are neighbours" % [clan.clan_id, friend])
	# Farther clans are stronger: the far corner beats the kingdom's neighbours.
	check(by_grid[Vector2i(5, 5)].military_strength > 3 * by_grid[Vector2i(1, 0)].military_strength, "The far corner is strongest")
	check(by_grid[Vector2i(5, 5)].army_units.has(&"heavy_cavalry"), "…and fields the best units")
	check(by_grid[Vector2i(1, 0)].army_units.keys().all(func(id: StringName) -> bool:
			return id in [&"swordsman", &"spearman", &"archer"]), "Neighbours field peasants")


func test_distance_and_reach_follow_the_territory() -> void:
	var diplomacy := _diplomacy()
	check_eq(diplomacy.distance(&"north_wolves"), 1, "Wolves border the corner")
	check(diplomacy.borders(&"north_wolves") and diplomacy.in_reach(&"north_wolves"), "…so they border and are in reach")
	check_eq(diplomacy.distance(&"east_merchants"), 2, "Merchants are two steps away")
	check(not diplomacy.borders(&"east_merchants") and diplomacy.in_reach(&"east_merchants"), "In reach, not bordering")
	check_eq(diplomacy.distance(&"golden_eagle"), 8, "The far corner")
	check(not diplomacy.in_reach(&"golden_eagle"), "Out of reach")
	check_eq(diplomacy.check_gift(_stock({&"food": 50}), &"golden_eagle", {&"food": 50} as Dictionary[StringName, int]),
			Diplomacy.GiftResult.TOO_FAR, "No gifts that far")
	check_eq(diplomacy.check_trade(_stock({&"food": 50}), &"golden_eagle", &"food", 10, &"wood"),
			Diplomacy.TradeResult.TOO_FAR, "No trade that far")
	check_eq(diplomacy.direction_to(&"north_wolves"), ClanData.Direction.EAST, "Wolves are east of the corner")
	check_eq(diplomacy.direction_to(&"south_farmers"), ClanData.Direction.SOUTH, "Farmers are south")
	diplomacy.clans[&"north_wolves"].annexed = true
	check_eq(diplomacy.distance(&"north_wolves"), 0, "Annexed: part of the territory")
	check(not diplomacy.in_reach(&"north_wolves"), "No more diplomacy with it")
	check_eq(diplomacy.distance(&"east_merchants"), 1, "The merchants border the kingdom now")
	check_eq(diplomacy.count_united(), 1, "One clan united")


func test_tiers() -> void:
	var expected := {-100: Diplomacy.Tier.HOSTILE, -60: Diplomacy.Tier.HOSTILE, -59: Diplomacy.Tier.TENSE,
			-20: Diplomacy.Tier.TENSE, -19: Diplomacy.Tier.NEUTRAL, 19: Diplomacy.Tier.NEUTRAL,
			20: Diplomacy.Tier.FRIENDLY, 59: Diplomacy.Tier.FRIENDLY, 60: Diplomacy.Tier.CLOSE, 100: Diplomacy.Tier.CLOSE}
	for relation in expected:
		check_eq(Diplomacy.tier_for(relation), expected[relation], "Tier at %d" % relation)


func test_recent_events_fade_by_personality() -> void:
	var diplomacy := _diplomacy()
	# Farmers: base 30, first impression -10 (start 20), peaceful: each memory fades 2 per turn.
	diplomacy.change_relation(&"south_farmers", -40, Diplomacy.MEMORY_GIFT)  # 20 -> -20
	# Fortress: base 0, first impression -5, isolated: 1 per turn.
	diplomacy.change_relation(&"west_fortress", 30, Diplomacy.MEMORY_GIFT)  # -5 -> 25
	diplomacy.end_turn()
	check_eq(diplomacy.clans[&"south_farmers"].memories, {&"first_impression": -8, &"gift": -38}, "Each fades by 2")
	check_eq(diplomacy.clans[&"south_farmers"].relation, -16, "30 - 8 - 38")
	check_eq(diplomacy.clans[&"west_fortress"].memories, {&"first_impression": -4, &"gift": 29}, "Each fades by 1")
	check_eq(diplomacy.clans[&"west_fortress"].relation, 25, "0 - 4 + 29")
	for i in 60:
		diplomacy.end_turn()
	check_eq(diplomacy.clans[&"south_farmers"].relation, 30, "Ends at its base")
	check_eq(diplomacy.clans[&"west_fortress"].relation, 0, "Ends at its base")


func test_relation_is_clamped() -> void:
	var diplomacy := _diplomacy()
	diplomacy.change_relation(&"north_wolves", -500)
	check_eq(diplomacy.clans[&"north_wolves"].relation, Diplomacy.MIN_RELATION, "Clamped at -100")
	diplomacy.change_relation(&"north_wolves", 500)
	check_eq(diplomacy.clans[&"north_wolves"].relation, Diplomacy.MAX_RELATION, "Clamped at 100")


func test_gift_raises_relation_by_value_and_personality() -> void:
	var diplomacy := _diplomacy()
	var stockpile := _stock({&"food": 50, &"stone": 50})
	# 10 food = value 10 -> 2 points x1.5 (peaceful) = 3
	check_eq(diplomacy.give_gift(stockpile, &"south_farmers", {&"food": 10}), Diplomacy.GiftResult.OK, "Gift accepted")
	check_eq(diplomacy.clans[&"south_farmers"].relation, 23, "Peaceful: +3")
	check_eq(stockpile.get_amount(&"food"), 40, "Gift paid")
	# 10 stone = value 20 -> 4 points x0.6 (aggressive) = 2
	diplomacy.give_gift(stockpile, &"north_wolves", {&"stone": 10})
	check_eq(diplomacy.clans[&"north_wolves"].relation, -8, "Aggressive: +2")


func test_gift_limit_per_turn() -> void:
	var diplomacy := _diplomacy()
	var stockpile := _stock({&"stone": 200})
	diplomacy.give_gift(stockpile, &"south_farmers", {&"stone": 100})
	check_eq(diplomacy.clans[&"south_farmers"].relation, 35, "Capped at +15 this turn")
	check_eq(diplomacy.check_gift(stockpile, &"south_farmers", {&"stone": 1}), Diplomacy.GiftResult.LIMIT_REACHED, "No more this turn")
	diplomacy.end_turn()
	check_eq(diplomacy.check_gift(stockpile, &"south_farmers", {&"stone": 10}), Diplomacy.GiftResult.OK, "Limit resets next turn")


func test_gift_rejections_change_nothing() -> void:
	var diplomacy := _diplomacy()
	var stockpile := _stock({&"food": 3})
	check_eq(diplomacy.give_gift(stockpile, &"south_farmers", {&"food": 0}), Diplomacy.GiftResult.EMPTY, "Empty gift")
	check_eq(diplomacy.give_gift(stockpile, &"south_farmers", {&"food": 10}), Diplomacy.GiftResult.CANNOT_AFFORD, "Too much")
	check_eq([diplomacy.clans[&"south_farmers"].relation, stockpile.get_amount(&"food")], [20, 3], "Unchanged")


func test_trade_price_follows_the_formula() -> void:
	var diplomacy := _diplomacy()
	# East merchants: relation 10, merchant, lack wood, plenty of food, two steps away (×0.85).
	# factor = (0.6 + 0.1 * 0.2 + 0.15) * 1.4 * 1.3 * 0.85 = 1.191 -> 10 wood (value 10) buys 11 food.
	check_eq(diplomacy.trade_quote(&"east_merchants", &"wood", 10, &"food"), 11, "Good deal: they need wood")
	# Same clan, stone for wood: 0.77 * 0.85 -> 10 stone (value 20) buys 13 wood.
	check_eq(diplomacy.trade_quote(&"east_merchants", &"stone", 10, &"wood"), 13, "Ordinary deal")
	# Distant clans pay less than they would as neighbours.
	var steppe := diplomacy.price_factor(&"steppe_tribes", &"stone", &"food")
	check(is_equal_approx(steppe, 0.6 * 1.4 * 1.3 * 0.85), "Distant penalty applied (got %.3f)" % steppe)


func test_trade_swaps_goods_and_improves_relation() -> void:
	var diplomacy := _diplomacy()
	var stockpile := _stock({&"wood": 30})
	check_eq(diplomacy.trade(stockpile, &"east_merchants", &"wood", 10, &"food"), Diplomacy.TradeResult.OK, "Trade done")
	check_eq([stockpile.get_amount(&"wood"), stockpile.get_amount(&"food")], [20, 11], "Goods swapped")
	check_eq(diplomacy.clans[&"east_merchants"].relation, 11, "+1 relation")
	diplomacy.trade(stockpile, &"east_merchants", &"wood", 5, &"food")
	diplomacy.trade(stockpile, &"east_merchants", &"wood", 5, &"food")
	diplomacy.trade(stockpile, &"east_merchants", &"wood", 5, &"food")
	check_eq(diplomacy.clans[&"east_merchants"].relation, 13, "Trade relation gain capped at +3 per turn")


func test_trade_capacity_per_turn() -> void:
	var diplomacy := _diplomacy()
	var stockpile := _stock({&"stone": 100})
	check_eq(diplomacy.check_trade(stockpile, &"east_merchants", &"stone", 21, &"food"),
			Diplomacy.TradeResult.OVER_CAPACITY, "42 value is more than 40 per turn")
	diplomacy.trade(stockpile, &"east_merchants", &"stone", 15, &"food")
	check_eq(diplomacy.remaining_capacity(&"east_merchants"), 10, "30 of 40 used")
	check_eq(diplomacy.check_trade(stockpile, &"east_merchants", &"stone", 6, &"food"),
			Diplomacy.TradeResult.OVER_CAPACITY, "Only 10 value left")
	diplomacy.end_turn()
	check_eq(diplomacy.remaining_capacity(&"east_merchants"), Diplomacy.TRADE_CAPACITY_PER_TURN, "Resets next turn")


func test_trade_rejections_change_nothing() -> void:
	var diplomacy := _diplomacy()
	var stockpile := _stock({&"food": 5, &"wood": 1})
	check_eq(diplomacy.trade(stockpile, &"east_merchants", &"food", 5, &"food"), Diplomacy.TradeResult.SAME_RESOURCE, "Same resource")
	check_eq(diplomacy.trade(stockpile, &"east_merchants", &"food", 0, &"wood"), Diplomacy.TradeResult.EMPTY, "Nothing offered")
	check_eq(diplomacy.trade(stockpile, &"east_merchants", &"food", 9, &"wood"), Diplomacy.TradeResult.CANNOT_AFFORD, "Not enough food")
	check_eq(diplomacy.trade(stockpile, &"west_fortress", &"wood", 1, &"stone"), Diplomacy.TradeResult.TOO_SMALL, "1 wood buys no stone")
	diplomacy.change_relation(&"north_wolves", -20)  # -10 -> -30: tense
	check_eq(diplomacy.trade(stockpile, &"north_wolves", &"food", 5, &"stone"), Diplomacy.TradeResult.REFUSED, "Tense clans refuse")
	check_eq([stockpile.get_amount(&"food"), stockpile.get_amount(&"wood")], [5, 1], "Stockpile unchanged")


func test_kingdom_end_turn_advances_diplomacy() -> void:
	var terrains := TerrainLibrary.load_all()
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains)
	state.start()
	state.diplomacy.change_relation(&"south_farmers", -10)  # 20 -> 10: base 30, memories -10 and -10
	state.end_turn()
	check_eq(state.diplomacy.clans[&"south_farmers"].relation, 14, "Both memories fade by 2 at the end of the turn")


## An RNG whose first randf() satisfies `predicate` (to force an acceptance or a refusal).
func _rng_where(predicate: Callable) -> RandomNumberGenerator:
	for seed_value in 10000:
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_value
		if predicate.call(probe.randf()):
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			return rng
	return RandomNumberGenerator.new()


func _accepting_rng() -> RandomNumberGenerator:
	return _rng_where(func(value: float) -> bool: return value < 0.05)


func _declining_rng() -> RandomNumberGenerator:
	return _rng_where(func(value: float) -> bool: return value > 0.99)


func test_agreement_chance_depends_on_price_relation_and_personality() -> void:
	var diplomacy := _diplomacy()
	var fair := diplomacy.trade_quote(&"east_merchants", &"wood", 10, &"food")
	var modest := diplomacy.agreement_chance(&"east_merchants", &"wood", 10, &"food", fair - 4)
	var greedy := diplomacy.agreement_chance(&"east_merchants", &"wood", 10, &"food", fair + 4)
	check(modest > greedy, "Asking for less is likelier to be accepted")
	check(modest <= Diplomacy.AGREEMENT_MAX_CHANCE, "Never certain")
	diplomacy.change_relation(&"west_fortress", 15)  # -5 -> 10, same relation as the merchants
	var isolated := diplomacy.agreement_chance(&"west_fortress", &"stone", 5, &"wood",
			diplomacy.trade_quote(&"west_fortress", &"stone", 5, &"wood"))
	var merchant := diplomacy.agreement_chance(&"east_merchants", &"stone", 5, &"wood",
			diplomacy.trade_quote(&"east_merchants", &"stone", 5, &"wood"))
	check(isolated < merchant, "At a fair price, isolated clans are harder to convince than merchants")
	check_eq(diplomacy.agreement_chance(&"east_merchants", &"wood", 1, &"stone", 1), 0.0, "No chance when the fair amount is 0")
	check_eq(Diplomacy.chance_name(0.0), "Không thể", "Chance names")
	check_eq(Diplomacy.chance_name(0.85), "Rất có thể", "Chance names")


func test_proposal_rejections() -> void:
	var diplomacy := _diplomacy()
	check_eq(diplomacy.check_proposal(&"east_merchants", &"wood", 5, &"wood", 5, 10), Diplomacy.ProposalResult.SAME_RESOURCE, "Same resource")
	check_eq(diplomacy.check_proposal(&"east_merchants", &"wood", 0, &"food", 5, 10), Diplomacy.ProposalResult.EMPTY, "Nothing given")
	check_eq(diplomacy.check_proposal(&"east_merchants", &"stone", 16, &"food", 5, 10), Diplomacy.ProposalResult.TOO_LARGE, "32 value > 30")
	check_eq(diplomacy.check_proposal(&"east_merchants", &"wood", 5, &"food", 5, 4), Diplomacy.ProposalResult.BAD_DURATION, "Too short")
	check_eq(diplomacy.check_proposal(&"east_merchants", &"wood", 5, &"food", 5, 31), Diplomacy.ProposalResult.BAD_DURATION, "Too long")
	diplomacy.change_relation(&"north_wolves", -20)
	check_eq(diplomacy.check_proposal(&"north_wolves", &"food", 5, &"stone", 2, 10), Diplomacy.ProposalResult.REFUSED, "Tense clans refuse")


func test_accepted_agreement_signs_and_raises_relation() -> void:
	var diplomacy := _diplomacy()
	var result := diplomacy.propose(_accepting_rng(), &"east_merchants", &"wood", 10, &"food", 12, 10)
	check_eq(result, Diplomacy.ProposalResult.OK, "Signed")
	check_eq(diplomacy.clans[&"east_merchants"].relation, 10 + 8 + 15, "+8 on signing, +15 while it runs")
	var agreement := diplomacy.get_agreement(&"east_merchants")
	check(agreement != null, "Agreement stored")
	if agreement != null:
		check_eq([agreement.give_amount, agreement.get_amount, agreement.turns_left], [10, 12, 10], "Terms kept")
	check_eq(diplomacy.check_proposal(&"east_merchants", &"stone", 2, &"food", 2, 10), Diplomacy.ProposalResult.ALREADY_HAS, "One per clan")


func test_declined_offer_waits_until_next_turn() -> void:
	var diplomacy := _diplomacy()
	check_eq(diplomacy.propose(_declining_rng(), &"east_merchants", &"wood", 10, &"food", 12, 10),
			Diplomacy.ProposalResult.DECLINED, "Declined")
	check(diplomacy.get_agreement(&"east_merchants") == null, "No agreement")
	check_eq(diplomacy.clans[&"east_merchants"].relation, 10, "Relation unchanged")
	check_eq(diplomacy.check_proposal(&"east_merchants", &"wood", 10, &"food", 12, 10),
			Diplomacy.ProposalResult.ASKED_THIS_TURN, "Cannot ask again this turn")
	diplomacy.end_turn()
	check_eq(diplomacy.check_proposal(&"east_merchants", &"wood", 10, &"food", 12, 10),
			Diplomacy.ProposalResult.OK, "Can ask again next turn")


func test_agreement_runs_each_turn_and_completes() -> void:
	var diplomacy := _diplomacy()
	var stockpile := _stock({&"wood": 100})
	diplomacy.propose(_accepting_rng(), &"south_farmers", &"wood", 5, &"food", 4, 5)
	var relation := diplomacy.clans[&"south_farmers"].relation
	var report := diplomacy.run_agreements(stockpile)
	check_eq(report[0].event, &"delivered", "Delivered")
	check_eq([stockpile.get_amount(&"wood"), stockpile.get_amount(&"food")], [95, 4], "Goods exchanged")
	check_eq(diplomacy.clans[&"south_farmers"].relation, relation + 1, "+1 per turn")
	for i in 4:
		report = diplomacy.run_agreements(stockpile)
	check(report[0].completed, "Completed after 5 turns")
	check(diplomacy.get_agreement(&"south_farmers") == null, "Removed when done")
	check_eq(stockpile.get_amount(&"food"), 20, "Five deliveries")
	check_eq(diplomacy.clans[&"south_farmers"].relation,
			relation + 5 + Diplomacy.AGREEMENT_COMPLETE_GAIN - Diplomacy.AGREEMENT_BASE_BONUS, "+3 on completion, the +15 ends")


func test_missed_payment_costs_relation() -> void:
	var diplomacy := _diplomacy()
	var stockpile := _stock({&"wood": 2})
	diplomacy.propose(_accepting_rng(), &"south_farmers", &"wood", 5, &"food", 4, 10)
	var relation := diplomacy.clans[&"south_farmers"].relation
	var report := diplomacy.run_agreements(stockpile)
	check_eq(report[0].event, &"missed", "Missed")
	check_eq([stockpile.get_amount(&"wood"), stockpile.get_amount(&"food")], [2, 0], "Nothing exchanged")
	check_eq(diplomacy.clans[&"south_farmers"].relation, relation - Diplomacy.AGREEMENT_MISSED_PENALTY, "-3")


func test_cancelling_costs_a_lot_and_hostile_clans_cancel() -> void:
	var diplomacy := _diplomacy()
	diplomacy.propose(_accepting_rng(), &"south_farmers", &"wood", 5, &"food", 4, 10)
	var relation := diplomacy.clans[&"south_farmers"].relation
	diplomacy.cancel_agreement(&"south_farmers")
	check(diplomacy.get_agreement(&"south_farmers") == null, "Cancelled")
	check_eq(diplomacy.clans[&"south_farmers"].relation,
			relation - Diplomacy.AGREEMENT_CANCEL_PENALTY - Diplomacy.AGREEMENT_BASE_BONUS, "-20, and the +15 ends")
	diplomacy.propose(_accepting_rng(), &"east_merchants", &"wood", 5, &"food", 4, 10)
	diplomacy.change_relation(&"east_merchants", -100)
	var report := diplomacy.run_agreements(_stock({&"wood": 50}))
	check_eq(report[0].event, &"cancelled_by_clan", "Hostile clan walks away")
	check(diplomacy.get_agreement(&"east_merchants") == null, "Agreement gone")


func test_agreement_raises_the_drift_target() -> void:
	var diplomacy := _diplomacy()
	diplomacy.propose(_accepting_rng(), &"south_farmers", &"wood", 5, &"food", 4, 30)
	for i in 40:
		diplomacy.end_turn()
	check_eq(diplomacy.clans[&"south_farmers"].relation, 30 + Diplomacy.AGREEMENT_BASE_BONUS, "Settles 15 above base while signed")


func test_kingdom_end_turn_runs_agreements() -> void:
	var terrains := TerrainLibrary.load_all()
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains)
	state.start()
	state.stockpile.add({&"wood": 20})
	state.diplomacy.propose(_accepting_rng(), &"south_farmers", &"wood", 5, &"food", 4, 10)
	var report := state.end_turn()
	check_eq(report.agreements.size(), 1, "Turn report lists the agreement")
	check_eq([state.stockpile.get_amount(&"wood"), state.stockpile.get_amount(&"food")], [15, 4], "Exchanged at end of turn")


func test_income_breakdown_lists_every_source_and_adds_up() -> void:
	var terrains := TerrainLibrary.load_all()
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all())
	state.start()
	state.board.set_land(Vector2i(4, 4), &"farmland", true)   # farm: (5 - 1) × 2 = 8 food (key cell)
	state.board.set_land(Vector2i(5, 4), &"farmland", false)  # farm: 4 food
	state.board.set_land(Vector2i(6, 4), &"forest", false)    # land alone: nothing
	state.army.add_squad(&"swordsman", 20)                    # -1 food
	state.stockpile.add({&"wood": 30, &"stone": 10})
	state.build(&"farm", Vector2i(4, 4))
	state.build(&"farm", Vector2i(5, 4))
	state.build(&"watchtower", Vector2i(7, 7))                # -1 food
	state.diplomacy.propose(_accepting_rng(), &"east_merchants", &"wood", 5, &"food", 6, 10)  # -5 wood, +6 food
	var breakdown := state.get_income_breakdown()
	var sources := breakdown[&"food"].map(func(e: Dictionary) -> Array: return [e.source, e.amount])
	check(sources.has([&"production", 12]), "Two farms, one on a key cell = +12 food")
	check(not sources.any(func(s: Array) -> bool: return s[0] == &"terrain"), "The land itself gives nothing")
	check(sources.has([&"army", -1]), "One squad eats 1 food")
	check(sources.has([&"building", -1]), "Watchtower upkeep -1 food")
	check(sources.has([&"agreement", 6]), "Agreement delivers 6 food")
	var farm: Dictionary = breakdown[&"food"].filter(func(e: Dictionary) -> bool: return e.source == &"production")[0]
	check_eq(farm.count, 2, "Building count for the tooltip")
	check(breakdown[&"wood"].map(func(e: Dictionary) -> int: return e.amount).has(-5), "Agreement takes 5 wood")
	check_eq(state.get_net_income(), {&"food": 16, &"wood": -5}, "Net = sum of the breakdown, agreements included")


func test_gift_too_small_to_matter_is_refused() -> void:
	var diplomacy := _diplomacy()
	var stockpile := _stock({&"food": 5})
	# 5 food = value 5 -> 1 point x0.6 (aggressive) = 0
	check_eq(diplomacy.give_gift(stockpile, &"north_wolves", {&"food": 5}), Diplomacy.GiftResult.TOO_SMALL, "No point gifting")
	check_eq(stockpile.get_amount(&"food"), 5, "Nothing spent")


# --- Relation factors (GDD §9.3) ------------------------------------------------------------

func _factor_sum(diplomacy: Diplomacy, clan_id: StringName) -> int:
	var total := 0
	for factor in diplomacy.relation_factors(clan_id):
		total += factor.amount
	return total


func test_relation_factors_name_every_point() -> void:
	var diplomacy := _diplomacy()
	diplomacy.threat = 20
	diplomacy.end_turn()  # wariness starts growing toward 0.4 x 20 = 8
	diplomacy.give_gift(_stock({&"food": 100}), &"east_merchants", {&"food": 50} as Dictionary[StringName, int])
	diplomacy.propose(_accepting_rng(), &"east_merchants", &"wood", 10, &"food", 12, 10)
	var factors := diplomacy.relation_factors(&"east_merchants")
	var by_id := {}
	for factor in factors:
		by_id[factor.id] = factor.amount
	check_eq(by_id, {&"base": 20, &"wariness": -2, &"agreement_bonus": 15, &"first_impression": -8,
			&"gift": 10, &"agreement": 8}, "Base, wariness, treaty bonus and every recent event")
	check_eq(_factor_sum(diplomacy, &"east_merchants"), diplomacy.clans[&"east_merchants"].relation, "Adds up")
	check_eq(factors[0].id, &"base", "Lasting factors first")
	check(factors[-1].fading and absi(factors[-1].amount) <= absi(factors[-2].amount), "Recent events, largest first")


func test_wariness_grows_a_little_each_turn() -> void:
	var diplomacy := _diplomacy()
	diplomacy.threat = 30
	diplomacy.end_turn()
	check_eq(diplomacy.clans[&"north_wolves"].wariness, 3, "Aggressive: 3 per turn")
	check_eq(diplomacy.target_relation(&"north_wolves"), -15 - 30, "Long-term value uses the full wariness")
	for i in 20:
		diplomacy.end_turn()
	check_eq(diplomacy.clans[&"north_wolves"].wariness, 30, "Caught up")
	diplomacy.threat = 0
	diplomacy.end_turn()
	check_eq(diplomacy.clans[&"north_wolves"].wariness, 27, "Eases off the same way")


func test_changes_move_the_shown_relation_even_past_the_limit() -> void:
	var diplomacy := _diplomacy()
	diplomacy.change_relation(&"south_farmers", 70)  # 20 -> 90
	diplomacy.clans[&"south_farmers"].alliance_turns = 5  # +30: 120 before clamping
	check_eq(diplomacy.clans[&"south_farmers"].relation, 100, "Clamped")
	check_eq(_factor_sum(diplomacy, &"south_farmers"), 100, "The limit shows up as a factor")
	diplomacy.change_relation(&"south_farmers", 5, Diplomacy.MEMORY_GIFT)
	check(not diplomacy.clans[&"south_farmers"].memories.has(&"gift"), "Nothing stored above the limit")
	diplomacy.change_relation(&"south_farmers", -10)
	check_eq(diplomacy.clans[&"south_farmers"].relation, 90, "-10 from the shown 100")
